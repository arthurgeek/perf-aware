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

flag_letters := [Flag]string {
	.Carry  = "C",
	.Parity = "P",
	.Aux    = "A",
	.Zero   = "Z",
	.Sign   = "S",
}

Cpu :: struct {
	registers: Registers,
	flags:     Flags,
	ip:        u16,
	memory:    []u8,
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
	fmt.assertf(wide, "byte-wide memory write unimplemented at %#x", addr)

	cpu.memory[addr] = u8(value)
	cpu.memory[addr + 1] = u8(value >> 8)
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

binary_operands :: proc(cpu: ^Cpu, inst: Instruction) -> (dst: RegisterIndex, old, value: u16) {
	dst_reg := inst.dst.(Register)
	return dst_reg.index, cpu.registers[dst_reg.index], operand_value(cpu, inst.src, inst.wide)
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
		dst, old, value := binary_operands(cpu, inst)
		result := old + value
		cpu.registers[dst] = result

		update_flags(
			&cpu.flags,
			result,
			carry = u32(old) + u32(value) > 0xFFFF,
			aux = (old & 0xF) + (value & 0xF) > 0xF,
		)
	case .sub, .cmp:
		dst, old, value := binary_operands(cpu, inst)
		result := old - value
		// cmp is sub without the writeback
		if inst.op == .sub do cpu.registers[dst] = result

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
