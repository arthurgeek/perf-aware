#+feature dynamic-literals

package sim8086

import "core:bytes"
import "core:fmt"
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

decode_rm :: proc(reader: ^bytes.Reader, mod_reg_rm: ModRegRm, w_field: byte) -> Maybe(string) {
	rm_value: string

	if mod_reg_rm.mod_field == 0b11 {
		rm_value = reg_encoding[mod_reg_rm.rm_field][w_field]
	} else if mod_reg_rm.mod_field == 0b00 {
		rm_value = fmt.tprintf("[%s]", rm_encoding[mod_reg_rm.rm_field])
	} else if mod_reg_rm.mod_field == 0b01 {
		b2, e2 := bytes.reader_read_byte(reader)
		if e2 != .None do return nil

		rm_value = fmt.tprintf("[%s + %d]", rm_encoding[mod_reg_rm.rm_field], b2)
	} else if mod_reg_rm.mod_field == 0b10 {
		b2, e2 := bytes.reader_read_byte(reader)
		if e2 != .None do return nil
		b3, e3 := bytes.reader_read_byte(reader)
		if e3 != .None do return nil

		disp := i16(b3) << 8 | i16(b2)

		rm_value = fmt.tprintf("[%s + %d]", rm_encoding[mod_reg_rm.rm_field], disp)
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
		b0, e0 := bytes.reader_read_byte(&reader)
		if e0 != .None do break
		b1, e1 := bytes.reader_read_byte(&reader)
		if e1 != .None do break

		if b0 & 0b11111100 == 0b10001000 || b0 & 0b11111100 == 0b00000000 {
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
			}

			fmt.printfln("%s %s,%s", opcode, left, right)
		} else if b0 & 0b11110000 == 0b10110000 {
			w_field := (b0 >> 3) & 1
			reg := b0 & 0b111
			data: i16

			if w_field == 0b1 {
				b2, e2 := bytes.reader_read_byte(&reader)
				if e2 != .None do break

				data = i16(b2) << 8 | i16(b1)
			} else {
				data = i16(i8(b1))
			}

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

			b4, e4 := bytes.reader_read_byte(&reader)
			if e4 != .None do break

			data: i16

			if s_field == 0b0 && w_field == 0b1 {
				b5, e5 := bytes.reader_read_byte(&reader)
				if e5 != .None do break

				data = i16(b5) << 8 | i16(b4)
			} else {
				data = i16(i8(b4))
			}

			opcode: string

			if mod_reg_rm.reg_field & 0b111 == 0b000 {
				opcode = "add"
			}

			fmt.printfln("%s %s,%d", opcode, rm_value, data)
		} else if b0 & 0b11111110 == 0b00000100 {
			w_field := b0 & 0b1
			data: i16

			if w_field == 0b1 {
				b2, e2 := bytes.reader_read_byte(&reader)
				if e2 != .None do break

				data = i16(b2) << 8 | i16(b1)
			} else {
				data = i16(i8(b1))
			}

			fmt.printfln("%s %s,%d", "add", reg_encoding[0][w_field], data)
		} else {
			fmt.printfln("unsupported first byte: %08b", b0)
		}
	}
}
