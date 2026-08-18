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
}

update_flags :: proc(flags: ^Flags, result: u16, carry, aux: bool) {
	flags^ = {}
	if carry do flags^ += {.Carry}
	if bits.count_ones(u8(result)) % 2 == 0 do flags^ += {.Parity}
	if aux do flags^ += {.Aux}
	if result == 0 do flags^ += {.Zero}
	if i16(result) < 0 do flags^ += {.Sign}
}

operand_value :: proc(cpu: ^Cpu, op: Operand) -> u16 {
	switch v in op {
	case Immediate:
		return u16(v)
	case Register:
		return cpu.registers[v.index]
	case EffectiveAddress, DirectAddress, JumpOffset:
		fmt.panicf("cannot read %v as a source", op)
	}
	return 0
}

binary_operands :: proc(cpu: ^Cpu, inst: Instruction) -> (dst: RegisterIndex, old, value: u16) {
	dst_reg := inst.dst.(Register)
	return dst_reg.index, cpu.registers[dst_reg.index], operand_value(cpu, inst.src)
}

execute_jump :: proc(cpu: ^Cpu, inst: Instruction, condition: bool) {
	offset := inst.dst.(JumpOffset)
	if condition do cpu.ip = u16(i16(cpu.ip) + i16(offset))
}

execute_instruction :: proc(cpu: ^Cpu, inst: Instruction) {
	switch inst.op {
	case .mov:
		dst, _, value := binary_operands(cpu, inst)
		cpu.registers[dst] = value
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
