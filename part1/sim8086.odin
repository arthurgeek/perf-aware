package sim8086

import "core:bytes"
import "core:fmt"
import "core:os"

main :: proc() {
	exec := false
	filename: string

	for arg in os.args[1:] {
		switch arg {
		case "-exec":
			exec = true
		case:
			filename = arg
		}
	}

	if filename == "" {
		fmt.println("You need to pass the binary file as an argument")
		return
	}

	data, err := os.read_entire_file(filename, context.allocator)
	defer delete(data)

	if err != nil {
		fmt.printfln("Failed to read %s: %v", filename, err)
		return
	}

	if !exec do fmt.printfln("bits 16")

	reader: bytes.Reader
	bytes.reader_init(&reader, data)
	cpu: Cpu

	for {
		old := cpu
		inst := decode_instruction(&reader) or_break
		cpu.ip = u16(reader.i)

		if inst.op != .none {
			print_instruction(inst)

			if exec {
				execute_instruction(&cpu, inst)
				print_trace(old, cpu)
			}

			fmt.println()
		}

		free_all(context.temp_allocator)
	}

	if exec do print_final_registers(cpu)
}
