package sim8086

import "core:fmt"

Registers :: distinct [8]u16

Flag :: enum {
	Parity,
	Zero,
	Sign,
}

Flags :: bit_set[Flag;u16]

flag_letters := [Flag]string {
	.Parity = "P",
	.Zero   = "Z",
	.Sign   = "S",
}

Cpu :: struct {
	registers: Registers,
	flags:     Flags,
}

update_flags :: proc(flags: ^Flags, result: u16) {
	flags^ -= {.Zero, .Sign, .Parity}
	if result == 0 do flags^ += {.Zero, .Parity}
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

	dst := register_name(dst_reg)
	old_result := cpu.registers[dst_reg.index]
	old_flags := cpu.flags

	switch inst.op {
	case .mov:
		cpu.registers[dst_reg.index] = value
	case .add:
		result := cpu.registers[dst_reg.index] + value
		cpu.registers[dst_reg.index] = result

		update_flags(&cpu.flags, result)
	case .sub, .cmp:
		result := cpu.registers[dst_reg.index] - value
		// cmp is sub without the writeback
		if inst.op == .sub do cpu.registers[dst_reg.index] = result

		update_flags(&cpu.flags, result)
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

	new_result := cpu.registers[dst_reg.index]
	new_flags := cpu.flags

	fmt.printf(" ;")

	if old_result != new_result {
		fmt.printf(" %s:%#x->%#x", dst, old_result, new_result)
	}

	if old_flags != new_flags {
		fmt.printf(" flags:%s->%s", format_flags(old_flags), format_flags(new_flags))
	}
}
