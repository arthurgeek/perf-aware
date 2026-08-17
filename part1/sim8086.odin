#+feature dynamic-literals

package sim8086

import "core:bytes"
import "core:fmt"
import "core:io"
import "core:os"

ModRegRm :: bit_field byte {
	rm_field:  byte | 3,
	reg_field: byte | 3,
	mod_field: byte | 2,
}

rm_encoding := [?]string{"bx + si", "bx + di", "bp + si", "bp + di", "si", "di", "bp", "bx"}

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

arith_mnemonics := [8]string {
	0b000 = "add",
	0b101 = "sub",
	0b111 = "cmp",
}

jump_mnemonics := map[byte]string {
	0b01110000 = "jo",
	0b01110001 = "jno",
	0b01110010 = "jb",
	0b01110011 = "jnb",
	0b01110100 = "je",
	0b01110101 = "jne",
	0b01110110 = "jbe",
	0b01110111 = "ja",
	0b01111000 = "js",
	0b01111001 = "jns",
	0b01111010 = "jp",
	0b01111011 = "jnp",
	0b01111100 = "jl",
	0b01111101 = "jnl",
	0b01111110 = "jle",
	0b01111111 = "jg",
	0b11100000 = "loopnz",
	0b11100001 = "loopz",
	0b11100010 = "loop",
	0b11100011 = "jcxz",
}

RegisterIndex :: distinct byte
EABase :: distinct byte

Register :: struct {
	index: RegisterIndex,
	wide:  bool,
}

EffectiveAddress :: struct {
	base: EABase,
	disp: i16,
}

DirectAddress :: distinct u16
Immediate :: distinct i16
JumpOffset :: distinct i8

Operand :: union {
	Register,
	EffectiveAddress,
	DirectAddress,
	Immediate,
	JumpOffset,
}

Instruction :: struct {
	mnemonic: string,
	dst:      Operand,
	src:      Operand,
	wide:     bool,
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
		if mod_reg_rm.rm_field == 0b110 {
			op = DirectAddress(read_u16(reader) or_return)
		} else {
			op = EffectiveAddress{EABase(mod_reg_rm.rm_field), 0}
		}
	case 0b01:
		disp := bytes.reader_read_byte(reader) or_return

		op = EffectiveAddress{EABase(mod_reg_rm.rm_field), i16(i8(disp))}
	case 0b10:
		disp := read_u16(reader) or_return

		op = EffectiveAddress{EABase(mod_reg_rm.rm_field), transmute(i16)disp}
	case 0b11:
		op = Register{RegisterIndex(mod_reg_rm.rm_field), wide}
	}

	return
}

format_operand :: proc(op: Operand) -> string {
	switch v in op {
	case Register:
		return reg_encoding[v.index][v.wide ? 1 : 0]
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

print_instruction :: proc(inst: Instruction) {
	dst := format_operand(inst.dst)

	_, src_is_immediate := inst.src.(Immediate)
	_, dst_is_ea := inst.dst.(EffectiveAddress)
	_, dst_is_direct := inst.dst.(DirectAddress)

	if src_is_immediate && (dst_is_ea || dst_is_direct) {
		dst = fmt.tprintf("%s %s", inst.wide ? "word" : "byte", dst)
	}

	if inst.src == nil {
		fmt.printfln("%s %s", inst.mnemonic, dst)
	} else {
		fmt.printfln("%s %s,%s", inst.mnemonic, dst, format_operand(inst.src))
	}
}

decode_instruction :: proc(reader: ^bytes.Reader) -> (inst: Instruction, err: io.Error) {
	b0 := bytes.reader_read_byte(reader) or_return
	b1 := bytes.reader_read_byte(reader) or_return

	if b0 & 0b11111100 == 0b10001000 ||
	   b0 & 0b11111100 == 0b00000000 ||
	   b0 & 0b11111100 == 0b00111000 ||
	   b0 & 0b11111100 == 0b00101000 {
		mod_reg_rm := transmute(ModRegRm)b1

		wide := b0 & 0b1 == 0b1

		reg: Operand = Register{RegisterIndex(mod_reg_rm.reg_field), wide}
		rm := decode_rm(reader, mod_reg_rm, wide) or_return

		dst, src := rm, reg
		if b0 & 0b00000010 != 0b00000000 {
			dst, src = reg, rm
		}

		opcode := b0 & 0b11111100 == 0b10001000 ? "mov" : arith_mnemonics[(b0 >> 3) & 0b111]

		inst = {opcode, dst, src, wide}
	} else if b0 & 0b11110000 == 0b10110000 {
		wide := (b0 >> 3) & 0b1 == 0b1
		reg := Register{RegisterIndex(b0 & 0b111), wide}

		data := read_data(reader, b1, wide) or_return

		inst = {"mov", reg, Immediate(data), wide}
	} else if b0 & 0b11111100 == 0b10000000 {
		mod_reg_rm := transmute(ModRegRm)b1

		wide := b0 & 0b1 == 0b1
		sign_extend := (b0 >> 1) & 0b1 == 0b1

		rm := decode_rm(reader, mod_reg_rm, wide) or_return

		b4 := bytes.reader_read_byte(reader) or_return
		data := read_data(reader, b4, !sign_extend && wide) or_return

		inst = {arith_mnemonics[mod_reg_rm.reg_field], rm, Immediate(data), wide}
	} else if b0 & 0b11111110 == 0b11000110 {
		mod_reg_rm := transmute(ModRegRm)b1

		wide := b0 & 0b1 == 0b1

		rm := decode_rm(reader, mod_reg_rm, wide) or_return

		b2 := bytes.reader_read_byte(reader) or_return
		data := read_data(reader, b2, wide) or_return

		inst = {"mov", rm, Immediate(data), wide}
	} else if b0 & 0b11111110 == 0b00000100 ||
	   b0 & 0b11111110 == 0b00101100 ||
	   b0 & 0b11111110 == 0b00111100 {
		wide := b0 & 0b1 == 0b1

		data := read_data(reader, b1, wide) or_return

		inst = {arith_mnemonics[(b0 >> 3) & 0b111], Register{0, wide}, Immediate(data), wide}
	} else if b0 & 0b11111100 == 0b10100000 {
		b2 := bytes.reader_read_byte(reader) or_return

		wide := b0 & 0b1 == 0b1
		addr := DirectAddress(u16(b2) << 8 | u16(b1))
		acc := Register{0, wide}

		if b0 & 0b00000010 == 0b00000000 {
			inst = {"mov", acc, addr, wide}
		} else {
			inst = {"mov", addr, acc, wide}
		}
	} else if mnemonic, is_jump := jump_mnemonics[b0]; is_jump {
		inst = {mnemonic, JumpOffset(i8(b1)), nil, false}
	} else {
		fmt.printfln("unsupported first byte: %08b", b0)
	}

	return
}

main :: proc() {
	if len(os.args) <= 1 {
		fmt.println("You need to pass the binary file as the first argument")
		return
	}

	data, err := os.read_entire_file(os.args[1], context.allocator)
	defer delete(data)

	if err != nil {
		fmt.printfln("Failed to read %s: %v", os.args[1], err)
		return
	}

	fmt.printfln("bits 16")

	reader: bytes.Reader
	bytes.reader_init(&reader, data)

	for {
		inst := decode_instruction(&reader) or_break

		if inst.mnemonic != "" {
			print_instruction(inst)
		}

		free_all(context.temp_allocator)
	}
}
