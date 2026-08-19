package sim8086

import "core:fmt"
import "core:math/bits"

Registers :: distinct [8]u16

// declared in the order the reference prints them
Flag :: enum {
	Carry,
	Parity,
	Aux,
	Zero,
	Sign,
}

Flags :: bit_set[Flag;u16]

Cpu :: struct {
	registers:    Registers,
	flags:        Flags,
	ip:           u16,
	memory:       []u8,
}

effective_address :: proc(cpu: ^Cpu, ea: EffectiveAddress) -> u16 {
	addr := u16(ea.disp)

	for r in ea_base_registers[ea.base] {
		addr += cpu.registers[r]
	}

	return addr
}

read_memory :: proc(cpu: ^Cpu, addr: u16, wide: bool) -> u16 {
	fmt.assertf(wide, "byte-wide memory read unimplemented at %#x", addr)

	return u16(cpu.memory[addr]) | u16(cpu.memory[addr + 1]) << 8
}

write_memory :: proc(cpu: ^Cpu, addr: u16, wide: bool, value: u16) {
	cpu.memory[addr] = u8(value)
	if wide do cpu.memory[addr + 1] = u8(value >> 8)
}

update_flags :: proc(flags: ^Flags, result: u16, carry, aux: bool) {
	flags^ = {}
	if carry do flags^ += {.Carry}
	if bits.count_ones(u8(result)) % 2 == 0 do flags^ += {.Parity}
	if aux do flags^ += {.Aux}
	if result == 0 do flags^ += {.Zero}
	if i16(result) < 0 do flags^ += {.Sign}
}

operand_value :: proc(cpu: ^Cpu, op: Operand, wide: bool) -> u16 {
	switch v in op {
	case Immediate:
		return u16(v)
	case Register:
		return cpu.registers[v.index]
	case EffectiveAddress:
		return read_memory(cpu, effective_address(cpu, v), wide)
	case DirectAddress:
		return read_memory(cpu, u16(v), wide)
	case JumpOffset:
		fmt.panicf("cannot read %v as a source", op)
	}
	return 0
}

write_operand :: proc(cpu: ^Cpu, op: Operand, wide: bool, value: u16) {
	switch v in op {
	case Register:
		cpu.registers[v.index] = value
	case EffectiveAddress:
		write_memory(cpu, effective_address(cpu, v), wide, value)
	case DirectAddress:
		write_memory(cpu, u16(v), wide, value)
	case Immediate, JumpOffset:
		fmt.panicf("cannot write to %v as a destination", op)
	}
}

Operand_Kind :: enum {
	register,
	memory,
	immediate,
}

operand_kind :: proc(op: Operand) -> Operand_Kind {
	switch v in op {
	case Register:
		return .register
	case EffectiveAddress, DirectAddress:
		return .memory
	case Immediate:
		return .immediate
	case JumpOffset:
	}

	fmt.panicf("no operand kind for %v", op)
}

is_accumulator :: proc(op: Operand) -> bool {
	reg, is_reg := op.(Register)
	return is_reg && reg.index == 0
}

ea_clocks_table := [8][2]u16{{7, 11}, {8, 12}, {8, 12}, {7, 11}, {5, 9}, {5, 9}, {5, 9}, {5, 9}}

ea_clocks :: proc(op: Operand) -> u16 {
	switch v in op {
	case DirectAddress:
		return 6
	case EffectiveAddress:
		return ea_clocks_table[v.base][v.disp != 0 ? 1 : 0]
	case Register, Immediate, JumpOffset:
		return 0
	}

	return 0
}

calculate_clocks :: proc(inst: Instruction) -> (base, ea: u16) {
	switch inst.op {
	case .mov:
		dst, src := operand_kind(inst.dst), operand_kind(inst.src)

		_, dst_is_direct := inst.dst.(DirectAddress)
		_, src_is_direct := inst.src.(DirectAddress)

		switch {
		case dst_is_direct && is_accumulator(inst.src):
			return 10, 0
		case is_accumulator(inst.dst) && src_is_direct:
			return 10, 0
		case dst == .memory && src == .register:
			return 9, ea_clocks(inst.dst)
		case dst == .register && src == .memory:
			return 8, ea_clocks(inst.src)
		case dst == .register && src == .register:
			return 2, 0
		case dst == .register && src == .immediate:
			return 4, 0
		case dst == .memory && src == .immediate:
			return 10, ea_clocks(inst.dst)
		}
	case .add:
		dst, src := operand_kind(inst.dst), operand_kind(inst.src)

		switch {
		case dst == .memory && src == .register:
			return 16, ea_clocks(inst.dst)
		case dst == .register && src == .memory:
			return 9, ea_clocks(inst.src)
		case dst == .register && src == .register:
			return 3, 0
		case dst == .register && src == .immediate:
			return 4, 0
		case dst == .memory && src == .immediate:
			return 17, ea_clocks(inst.dst)
		}
	case .none,
	     .sub,
	     .cmp,
	     .jo,
	     .jno,
	     .jb,
	     .jnb,
	     .je,
	     .jne,
	     .jbe,
	     .ja,
	     .js,
	     .jns,
	     .jp,
	     .jnp,
	     .jl,
	     .jnl,
	     .jle,
	     .jg,
	     .loopnz,
	     .loopz,
	     .loop,
	     .jcxz:
		fmt.panicf("no clocks for %v in %v", inst.op, inst)
	}

	fmt.panicf("no clocks for %v with %v, %v", inst.op, inst.dst, inst.src)
}

execute_jump :: proc(cpu: ^Cpu, inst: Instruction, condition: bool) {
	offset := inst.dst.(JumpOffset)
	if condition do cpu.ip = u16(i16(cpu.ip) + i16(offset))
}

execute_instruction :: proc(cpu: ^Cpu, inst: Instruction) {
	switch inst.op {
	case .mov:
		write_operand(cpu, inst.dst, inst.wide, operand_value(cpu, inst.src, inst.wide))
	case .add:
		old := operand_value(cpu, inst.dst, inst.wide)
		value := operand_value(cpu, inst.src, inst.wide)
		result := old + value
		write_operand(cpu, inst.dst, inst.wide, result)

		update_flags(
			&cpu.flags,
			result,
			carry = u32(old) + u32(value) > 0xFFFF,
			aux = (old & 0xF) + (value & 0xF) > 0xF,
		)
	case .sub, .cmp:
		old := operand_value(cpu, inst.dst, inst.wide)
		value := operand_value(cpu, inst.src, inst.wide)
		result := old - value
		// cmp is sub without the writeback
		if inst.op == .sub do write_operand(cpu, inst.dst, inst.wide, result)

		update_flags(&cpu.flags, result, carry = value > old, aux = value & 0xF > old & 0xF)
	case .jne:
		execute_jump(cpu, inst, .Zero not_in cpu.flags)
	case .none,
	     .jo,
	     .jno,
	     .jb,
	     .jnb,
	     .je,
	     .jbe,
	     .ja,
	     .js,
	     .jns,
	     .jp,
	     .jnp,
	     .jl,
	     .jnl,
	     .jle,
	     .jg,
	     .loopnz,
	     .loopz,
	     .loop,
	     .jcxz:
		fmt.panicf("cannot execute %v in %v", inst.op, inst)
	}
}
