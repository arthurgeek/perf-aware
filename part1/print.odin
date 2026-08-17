package sim8086

import "core:fmt"
import "core:strings"

// natural order for the final dump: ax, bx, cx, dx — not encoding order
register_print_order := [?]RegisterIndex{0b000, 0b011, 0b001, 0b010, 0b100, 0b101, 0b110, 0b111}

register_name :: proc(r: Register) -> string {
	return reg_encoding[r.index][r.wide ? 1 : 0]
}

format_operand :: proc(op: Operand) -> string {
	switch v in op {
	case Register:
		return register_name(v)
	case EffectiveAddress:
		if v.disp == 0 do return fmt.tprintf("[%s]", rm_encoding[v.base])
		if v.disp < 0 do return fmt.tprintf("[%s - %d]", rm_encoding[v.base], -i32(v.disp))
		return fmt.tprintf("[%s + %d]", rm_encoding[v.base], v.disp)
	case DirectAddress:
		return fmt.tprintf("[%d]", v)
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

print_instruction :: proc(inst: Instruction) {
	dst := format_operand(inst.dst)

	imm, src_is_immediate := inst.src.(Immediate)
	_, dst_is_ea := inst.dst.(EffectiveAddress)
	_, dst_is_direct := inst.dst.(DirectAddress)

	if src_is_immediate && (dst_is_ea || dst_is_direct) {
		dst = fmt.tprintf("%s %s", inst.wide ? "word" : "byte", dst)
	}

	if inst.src == nil {
		fmt.printf("%v %s", inst.op, dst)
	} else {
		src := format_operand(inst.src)

		if src_is_immediate && inst.wide {
			src = fmt.tprintf("%d", u16(imm))
		}

		fmt.printf("%v %s, %s", inst.op, dst, src)
	}
}
