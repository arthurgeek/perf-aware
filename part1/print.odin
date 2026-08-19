package sim8086

import "core:fmt"
import "core:strings"

// natural order for the final dump: ax, bx, cx, dx — not encoding order
register_print_order := [?]RegisterIndex{0b000, 0b011, 0b001, 0b010, 0b100, 0b101, 0b110, 0b111}

flag_letters := [Flag]string {
	.Carry  = "C",
	.Parity = "P",
	.Aux    = "A",
	.Zero   = "Z",
	.Sign   = "S",
}

register_name :: proc(r: Register) -> string {
	return reg_encoding[r.index][r.wide ? 1 : 0]
}

format_operand :: proc(op: Operand) -> string {
	switch v in op {
	case Register:
		return register_name(v)
	case EffectiveAddress:
		if v.disp == 0 do return fmt.tprintf("[%s]", rm_encoding[v.base])
		if v.disp < 0 do return fmt.tprintf("[%s-%d]", rm_encoding[v.base], -i32(v.disp))
		return fmt.tprintf("[%s+%d]", rm_encoding[v.base], v.disp)
	case DirectAddress:
		return fmt.tprintf("[+%d]", v)
	case Immediate:
		return fmt.tprintf("%d", v)
	case JumpOffset:
		return fmt.tprintf("$%+d", i16(v) + 2)
	}

	return ""
}

format_flags :: proc(flags: Flags) -> string {
	sb := strings.builder_make(context.temp_allocator)

	for f in Flag {
		if f in flags do strings.write_string(&sb, flag_letters[f])
	}

	return strings.to_string(sb)
}

print_trace :: proc(old, new: Cpu) {
	for value, index in new.registers {
		if old.registers[index] != value {
			fmt.printf(
				" %s:%#x->%#x",
				register_name({RegisterIndex(index), true}),
				old.registers[index],
				value,
			)
		}
	}

	if old.ip != new.ip {
		fmt.printf(" ip:%#x->%#x", old.ip, new.ip)
	}

	if old.flags != new.flags {
		fmt.printf(" flags:%s->%s", format_flags(old.flags), format_flags(new.flags))
	}
}

print_clocks :: proc(base_clock, ea_clock: u16, total: uint) {
	fmt.printf(" Clocks: +%d = %d", base_clock + ea_clock, total)

	if ea_clock != 0 do fmt.printf(" (%d + %dea)", base_clock, ea_clock)
}

print_final_registers :: proc(cpu: Cpu) {
	fmt.println("\nFinal registers:")

	for index in register_print_order {
		value := cpu.registers[index]
		if value == 0 do continue
		fmt.printfln("      %s: 0x%04x (%d)", register_name({index, true}), value, value)
	}

	fmt.printfln("      ip: 0x%04x (%d)", cpu.ip, cpu.ip)

	if cpu.flags != {} {
		fmt.printfln("   flags: %s", format_flags(cpu.flags))
	}
}

print_instruction :: proc(inst: Instruction) {
	dst := format_operand(inst.dst)

	imm, src_is_immediate := inst.src.(Immediate)
	_, dst_is_ea := inst.dst.(EffectiveAddress)
	_, dst_is_direct := inst.dst.(DirectAddress)

	if dst_is_ea || dst_is_direct {
		dst = fmt.tprintf("%s %s", inst.wide ? "word" : "byte", dst)
	}

	if inst.src == nil {
		fmt.printf("%v %s", inst.op, dst)
	} else {
		src := format_operand(inst.src)

		if src_is_immediate {
			src = fmt.tprintf("%d", inst.wide ? u16(imm) : u16(u8(imm)))
		}

		fmt.printf("%v %s, %s", inst.op, dst, src)
	}
}
