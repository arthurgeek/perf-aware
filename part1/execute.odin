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

execute_instruction :: proc(cpu: ^Cpu, inst: Instruction) {
	dst_reg, is_reg := inst.dst.(Register)
	fmt.assertf(is_reg, "expected register destination, got %v in %v", inst.dst, inst)

	value: u16

	switch v in inst.src {
	case Immediate:
		value = u16(v)
	case Register:
		value = cpu.registers[v.index]
	case EffectiveAddress, DirectAddress, JumpOffset:
		fmt.panicf("expected immediate or register source, got %v in %v", inst.src, inst)
	}

	switch inst.op {
	case .mov:
		cpu.registers[dst_reg.index] = value
	case .add:
		old := cpu.registers[dst_reg.index]
		result := old + value
		cpu.registers[dst_reg.index] = result

		update_flags(
			&cpu.flags,
			result,
			carry = u32(old) + u32(value) > 0xFFFF,
			aux = (old & 0xF) + (value & 0xF) > 0xF,
		)
	case .sub, .cmp:
		old := cpu.registers[dst_reg.index]
		result := old - value
		// cmp is sub without the writeback
		if inst.op == .sub do cpu.registers[dst_reg.index] = result

		update_flags(&cpu.flags, result, carry = value > old, aux = value & 0xF > old & 0xF)
	case .none,
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
		fmt.panicf("cannot execute %v in %v", inst.op, inst)
	}
}
