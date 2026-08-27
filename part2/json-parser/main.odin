package json_parser

import "core:flags"
import "core:fmt"
import "core:os"

main :: proc() {
	os.exit(run())
}

@(private)
run :: proc() -> int {
	Options :: struct {
		file: ^os.File `args:"pos=0,required,file=r" usage:"Input file."`,
	}

	opt: Options
	style: flags.Parsing_Style = .Odin

	flags.parse_or_exit(&opt, os.args, style)
	defer os.close(opt.file)

	data, read_err := os.read_entire_file(opt.file, context.allocator)
	defer delete(data)
	if read_err != nil {
		fmt.eprintln("failed to read input:", read_err)
		return 1
	}
	if !validate_source(string(data)) do return 1
	return 0
}
