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

decode_rm :: proc(reader: ^bytes.Reader, mod_reg_rm: ModRegRm, w_field: byte) -> Maybe(string) {
	rm_value: string

	if mod_reg_rm.mod_field == 0b11 {
		rm_value = reg_encoding[mod_reg_rm.rm_field][w_field]
	} else if mod_reg_rm.mod_field == 0b00 {
		if mod_reg_rm.rm_field == 0b110 {
			addr, aerr := read_u16(reader)
			if aerr != .None do return nil

			rm_value = fmt.tprintf("[%d]", addr)
		} else {
			rm_value = fmt.tprintf("[%s]", rm_encoding[mod_reg_rm.rm_field])
		}
	} else if mod_reg_rm.mod_field == 0b01 {
		b2, e2 := bytes.reader_read_byte(reader)
		if e2 != .None do return nil

		rm_value = fmt.tprintf("[%s + %d]", rm_encoding[mod_reg_rm.rm_field], i16(i8(b2)))
	} else if mod_reg_rm.mod_field == 0b10 {
		disp, derr := read_u16(reader)
		if derr != .None do return nil

		rm_value = fmt.tprintf("[%s + %d]", rm_encoding[mod_reg_rm.rm_field], transmute(i16)disp)
	}

	return rm_value
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
		b0 := bytes.reader_read_byte(&reader) or_break
		b1 := bytes.reader_read_byte(&reader) or_break

		if b0 & 0b11111100 == 0b10001000 ||
		   b0 & 0b11111100 == 0b00000000 ||
		   b0 & 0b11111100 == 0b00111000 ||
		   b0 & 0b11111100 == 0b00101000 {
			mod_reg_rm := transmute(ModRegRm)b1

			w_field := b0 & 0b1
			left, right: string

			reg_value := reg_encoding[mod_reg_rm.reg_field][w_field]
			rm_value, ok := decode_rm(&reader, mod_reg_rm, w_field).?

			if !ok {
				break
			}

			if b0 & 0b00000010 == 0b00000000 {
				right = reg_value
				left = rm_value
			} else {
				right = rm_value
				left = reg_value
			}

			opcode: string

			if b0 & 0b11111100 == 0b10001000 {
				opcode = "mov"
			} else if b0 & 0b11111100 == 0b00000000 {
				opcode = "add"
			} else if b0 & 0b11111100 == 0b00101000 {
				opcode = "sub"
			} else if b0 & 0b11111100 == 0b00111000 {
				opcode = "cmp"
			}

			fmt.printfln("%s %s,%s", opcode, left, right)
		} else if b0 & 0b11110000 == 0b10110000 {
			w_field := (b0 >> 3) & 1
			reg := b0 & 0b111

			data := read_data(&reader, b1, w_field == 0b1) or_break

			fmt.printfln("%s %s,%d", "mov", reg_encoding[reg][w_field], data)
		} else if b0 & 0b11111100 == 0b10000000 {
			mod_reg_rm := transmute(ModRegRm)b1

			w_field := b0 & 0b1
			s_field := (b0 >> 1) & 0b1
			left, right: string
			rm_value: string
			ok: bool

			rm_value, ok = decode_rm(&reader, mod_reg_rm, w_field).?

			if !ok {
				break
			}

			if mod_reg_rm.mod_field != 0b11 {
				rm_value = fmt.tprintf("%s %s", w_field == 1 ? "word" : "byte", rm_value)
			}

			b4 := bytes.reader_read_byte(&reader) or_break
			data := read_data(&reader, b4, s_field == 0b0 && w_field == 0b1) or_break

			opcode: string

			if mod_reg_rm.reg_field & 0b111 == 0b000 {
				opcode = "add"
			} else if mod_reg_rm.reg_field & 0b111 == 0b101 {
				opcode = "sub"
			} else if mod_reg_rm.reg_field & 0b111 == 0b111 {
				opcode = "cmp"
			}

			fmt.printfln("%s %s,%d", opcode, rm_value, data)
		} else if b0 & 0b11111110 == 0b11000110 {
			mod_reg_rm := transmute(ModRegRm)b1

			w_field := b0 & 0b1

			rm_value, ok := decode_rm(&reader, mod_reg_rm, w_field).?

			if !ok {
				break
			}

			if mod_reg_rm.mod_field != 0b11 {
				rm_value = fmt.tprintf("%s %s", w_field == 1 ? "word" : "byte", rm_value)
			}

			b2 := bytes.reader_read_byte(&reader) or_break
			data := read_data(&reader, b2, w_field == 0b1) or_break

			fmt.printfln("mov %s,%d", rm_value, data)
		} else if b0 & 0b11111110 == 0b00000100 ||
		   b0 & 0b11111110 == 0b00101100 ||
		   b0 & 0b11111110 == 0b00111100 {
			w_field := b0 & 0b1

			data := read_data(&reader, b1, w_field == 0b1) or_break

			opcode: string

			if b0 & 0b11111110 == 0b00000100 {
				opcode = "add"
			} else if b0 & 0b11111110 == 0b00101100 {
				opcode = "sub"
			} else if b0 & 0b11111110 == 0b00111100 {
				opcode = "cmp"
			}

			fmt.printfln("%s %s,%d", opcode, reg_encoding[0][w_field], data)
		} else if b0 & 0b11111100 == 0b10100000 {
			b2 := bytes.reader_read_byte(&reader) or_break

			w_field := b0 & 0b1
			addr := u16(b2) << 8 | u16(b1)
			acc := reg_encoding[0][w_field]

			if b0 & 0b00000010 == 0b00000000 {
				fmt.printfln("mov %s,[%d]", acc, addr)
			} else {
				fmt.printfln("mov [%d],%s", addr, acc)
			}
		} else if mnemonic, is_jump := jump_mnemonics[b0]; is_jump {
			fmt.printfln("%s $%+d", mnemonic, i16(i8(b1)) + 2)
		} else {
			fmt.printfln("unsupported first byte: %08b", b0)
		}
	}
}
