package sim8086

import "core:bytes"
import "core:flags"
import "core:fmt"
import "core:os"

Options :: struct {
	exec:          bool `usage:"simulate the program instead of only disassembling it"`,
	dump:          bool `usage:"write memory to sim86_memory_0.data after execution"`,
	explainclocks: bool `usage:"estimate clocks per instruction, with a breakdown"`,
	file:          string `args:"pos=0,required" usage:"8086 binary to decode"`,
}

main :: proc() {
	opts: Options
	flags.parse_or_exit(&opts, os.args)

	data, err := os.read_entire_file(opts.file, context.allocator)
	defer delete(data)

	if err != nil {
		fmt.printfln("Failed to read %s: %v", opts.file, err)
		return
	}

	if !opts.exec do fmt.printfln("bits 16")

	cpu: Cpu
	cpu.memory = make([]u8, 65536)
	defer delete(cpu.memory)

	total_clocks: uint

	// load the program into the machine's memory: code and data share the
	// address space, and fetch reads through the same bytes the program can write
	program_len := copy(cpu.memory, data)

	reader: bytes.Reader
	bytes.reader_init(&reader, cpu.memory[:program_len])

	for cpu.ip < u16(program_len) {
		reader.i = i64(cpu.ip)

		old := cpu
		inst := decode_instruction(&reader) or_break
		cpu.ip = u16(reader.i)

		if inst.op != .none {
			print_instruction(inst)

			if opts.exec {
				fmt.printf(" ;")

				if opts.explainclocks {
					base_clock, ea_clock := calculate_clocks(inst)
					total_clocks += uint(base_clock + ea_clock)

					print_clocks(base_clock, ea_clock, total_clocks)
					fmt.printf(" |")
				}

				execute_instruction(&cpu, inst)
				print_trace(old, cpu)
			}

			fmt.println()
		}

		free_all(context.temp_allocator)
	}

	if opts.exec do print_final_registers(cpu)

	if opts.dump {
		if werr := os.write_entire_file("sim86_memory_0.data", cpu.memory); werr != nil {
			fmt.printfln("Failed to write memory dump: %v", werr)
		}
	}
}
