#+feature dynamic-literals

package sim8086

import "core:bytes"
import "core:fmt"
import "core:io"

ModRegRm :: bit_field byte {
	rm_field:  byte | 3,
	reg_field: byte | 3,
	mod_field: byte | 2,
}

rm_encoding := [?]string{"bx+si", "bx+di", "bp+si", "bp+di", "si", "di", "bp", "bx"}

reg_encoding := [?][2]string {
	{"al", "ax"},
	{"cl", "cx"},
	{"dl", "dx"},
	{"bl", "bx"},
	{"ah", "sp"},
	{"ch", "bp"},
	{"dh", "si"},
	{"bh", "di"},
}

arith_ops := [8]Op {
	0b000 = .add,
	0b101 = .sub,
	0b111 = .cmp,
}

jump_ops := map[byte]Op {
	0b01110000 = .jo,
	0b01110001 = .jno,
	0b01110010 = .jb,
	0b01110011 = .jnb,
	0b01110100 = .je,
	0b01110101 = .jne,
	0b01110110 = .jbe,
	0b01110111 = .ja,
	0b01111000 = .js,
	0b01111001 = .jns,
	0b01111010 = .jp,
	0b01111011 = .jnp,
	0b01111100 = .jl,
	0b01111101 = .jnl,
	0b01111110 = .jle,
	0b01111111 = .jg,
	0b11100000 = .loopnz,
	0b11100001 = .loopz,
	0b11100010 = .loop,
	0b11100011 = .jcxz,
}

read_u16 :: proc(reader: ^bytes.Reader) -> (v: u16, err: io.Error) {
	lo := bytes.reader_read_byte(reader) or_return
	hi := bytes.reader_read_byte(reader) or_return

	return u16(hi) << 8 | u16(lo), .None
}

read_data :: proc(reader: ^bytes.Reader, lo: byte, wide: bool) -> (data: i16, err: io.Error) {
	if !wide do return i16(i8(lo)), .None

	hi := bytes.reader_read_byte(reader) or_return

	return i16(hi) << 8 | i16(lo), .None
}

decode_rm :: proc(
	reader: ^bytes.Reader,
	mod_reg_rm: ModRegRm,
	wide: bool,
) -> (
	op: Operand,
	err: io.Error,
) {
	switch mod_reg_rm.mod_field {
	case 0b00:
		// memory mode, no displacement
		// no [bp] without displacement: 110 means 16-bit direct address
		if mod_reg_rm.rm_field == 0b110 {
			op = DirectAddress(read_u16(reader) or_return)
		} else {
			op = EffectiveAddress{EABase(mod_reg_rm.rm_field), 0}
		}
	case 0b01:
		// memory mode, 8-bit displacement
		disp := bytes.reader_read_byte(reader) or_return

		op = EffectiveAddress{EABase(mod_reg_rm.rm_field), i16(i8(disp))}
	case 0b10:
		// memory mode, 16-bit displacement
		disp := read_u16(reader) or_return

		op = EffectiveAddress{EABase(mod_reg_rm.rm_field), transmute(i16)disp}
	case 0b11:
		// register mode
		op = Register{RegisterIndex(mod_reg_rm.rm_field), wide}
	}

	return
}

decode_instruction :: proc(reader: ^bytes.Reader) -> (inst: Instruction, err: io.Error) {
	b0 := bytes.reader_read_byte(reader) or_return
	b1 := bytes.reader_read_byte(reader) or_return

	// register/memory to/from register: 100010dw mov, 000000dw add, 001110dw cmp, 001010dw sub
	if b0 & 0b11111100 == 0b10001000 ||
	   b0 & 0b11111100 == 0b00000000 ||
	   b0 & 0b11111100 == 0b00111000 ||
	   b0 & 0b11111100 == 0b00101000 {
		mod_reg_rm := transmute(ModRegRm)b1

		wide := b0 & 0b1 == 0b1

		reg: Operand = Register{RegisterIndex(mod_reg_rm.reg_field), wide}
		rm := decode_rm(reader, mod_reg_rm, wide) or_return

		dst, src := rm, reg
		// d bit set: register is the destination
		if b0 & 0b00000010 != 0b00000000 {
			dst, src = reg, rm
		}

		// 100010dw is mov; otherwise bits 5-3 select add/sub/cmp
		op := b0 & 0b11111100 == 0b10001000 ? Op.mov : arith_ops[(b0 >> 3) & 0b111]

		inst = {op, dst, src, wide}
	} else if b0 & 0b11110000 == 0b10110000 {
		// mov: immediate to register
		wide := (b0 >> 3) & 0b1 == 0b1
		reg := Register{RegisterIndex(b0 & 0b111), wide}

		data := read_data(reader, b1, wide) or_return

		inst = {.mov, reg, Immediate(data), wide}
	} else if b0 & 0b11111100 == 0b10000000 {
		// add/sub/cmp: immediate to register/memory
		mod_reg_rm := transmute(ModRegRm)b1

		wide := b0 & 0b1 == 0b1
		sign_extend := (b0 >> 1) & 0b1 == 0b1

		rm := decode_rm(reader, mod_reg_rm, wide) or_return

		b4 := bytes.reader_read_byte(reader) or_return
		data := read_data(reader, b4, !sign_extend && wide) or_return

		// reg field selects add/sub/cmp
		inst = {arith_ops[mod_reg_rm.reg_field], rm, Immediate(data), wide}
	} else if b0 & 0b11111110 == 0b11000110 {
		// mov: immediate to register/memory
		mod_reg_rm := transmute(ModRegRm)b1

		wide := b0 & 0b1 == 0b1

		rm := decode_rm(reader, mod_reg_rm, wide) or_return

		b2 := bytes.reader_read_byte(reader) or_return
		data := read_data(reader, b2, wide) or_return

		inst = {.mov, rm, Immediate(data), wide}
	} else if b0 & 0b11111110 == 0b00000100 ||
	   b0 & 0b11111110 == 0b00101100 ||
	   b0 & 0b11111110 == 0b00111100 {
		// immediate to accumulator: 0000010w add, 0010110w sub, 0011110w cmp
		wide := b0 & 0b1 == 0b1

		data := read_data(reader, b1, wide) or_return

		// bits 5-3 select add/sub/cmp
		inst = {arith_ops[(b0 >> 3) & 0b111], Register{0, wide}, Immediate(data), wide}
	} else if b0 & 0b11111100 == 0b10100000 {
		// mov: memory to/from accumulator
		b2 := bytes.reader_read_byte(reader) or_return

		wide := b0 & 0b1 == 0b1
		addr := DirectAddress(u16(b2) << 8 | u16(b1))
		acc := Register{0, wide}

		// d bit inverted here: 0 means accumulator is the destination
		if b0 & 0b00000010 == 0b00000000 {
			inst = {.mov, acc, addr, wide}
		} else {
			inst = {.mov, addr, acc, wide}
		}
	} else if op, is_jump := jump_ops[b0]; is_jump {
		// conditional jumps and loops
		inst = {op, JumpOffset(i8(b1)), nil, false}
	} else {
		fmt.printfln("unsupported first byte: %08b", b0)
	}

	return
}
