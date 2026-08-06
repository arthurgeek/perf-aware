#+feature dynamic-literals

package sim8086

import "core:bytes"
import "core:fmt"
import "core:os"

Instruction :: bit_field u16 {
	// bit_field reds LSB first, ASM is MSB
	// that's why we declare them here in
	// "reverse" order
	w_field:   u16 | 1,
	d_field:   u16 | 1,
	opcode:    u16 | 6,
	rm_field:  u16 | 3,
	reg_field: u16 | 3,
	mod_field: u16 | 2,
}

mnemonics := map[u16]string {
	0b100010 = "mov",
}

registers := [?][2]string {
	{"al", "ax"},
	{"cl", "cx"},
	{"dl", "dx"},
	{"bl", "bx"},
	{"ah", "sp"},
	{"ch", "bp"},
	{"dh", "si"},
	{"bh", "di"},
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

	reader: bytes.Reader
	bytes.reader_init(&reader, data)
	buf: [2]byte

	fmt.printfln("bits 16")

	for {
		n, err := bytes.reader_read(&reader, buf[:])
		if n == 0 || err != .None {
			break
		}

		inst := transmute(Instruction)buf

		source: u16
		dest: u16

		if inst.d_field == 0 {
			source = inst.reg_field
			dest = inst.rm_field
		} else {
			dest = inst.reg_field
			source = inst.rm_field
		}

		fmt.printfln(
			"%s %s,%s",
			mnemonics[inst.opcode],
			registers[dest][inst.w_field],
			registers[source][inst.w_field],
		)
	}
}
