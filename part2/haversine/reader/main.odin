package reader

import haversine_lib ".."
import json_parser "../../json-parser"
import metrics "../../metrics"
import "core:flags"
import "core:fmt"
import "core:os"
import "core:slice"

Pair :: struct {
	x0, y0, x1, y1: f64,
}

parse_pair_object :: proc(parser: ^json_parser.Parser) -> (Pair, bool) {
	pair: Pair
	has_x0, has_y0, has_x1, has_y1 := false, false, false, false

	json_parser.consume(parser, .LEFT_BRACE, "Expected coordinate pair object")
	if !json_parser.check(parser, .RIGHT_BRACE) {
		for !parser.had_error {
			key, has_key := json_parser.consume_string(parser, "Expected coordinate field name")
			if !has_key {
				return {}, false
			}

			json_parser.consume(parser, .COLON, "Expected colon after coordinate field name")
			switch key {
			case "x0":
				pair.x0, has_x0 = json_parser.consume_number(parser, "Expected numeric coordinate")
			case "y0":
				pair.y0, has_y0 = json_parser.consume_number(parser, "Expected numeric coordinate")
			case "x1":
				pair.x1, has_x1 = json_parser.consume_number(parser, "Expected numeric coordinate")
			case "y1":
				pair.y1, has_y1 = json_parser.consume_number(parser, "Expected numeric coordinate")
			case:
				json_parser.skip_json_value(parser)
			}

			if !json_parser.match(parser, .COMMA) do break
		}
	}

	closing := json_parser.consume(
		parser,
		.RIGHT_BRACE,
		"Expected closing brace after coordinate pair",
	)
	if !parser.had_error && !(has_x0 && has_y0 && has_x1 && has_y1) {
		json_parser.parser_error(parser, closing, "Coordinate pair requires x0, y0, x1, and y1")
	}
	return pair, !parser.had_error
}

parse_pairs_array :: proc(parser: ^json_parser.Parser) -> (pair_count: int, total: f64) {
	json_parser.consume(parser, .LEFT_BRACKET, "Expected pairs array")
	if !json_parser.check(parser, .RIGHT_BRACKET) {
		for !parser.had_error {
			pair, ok := parse_pair_object(parser)
			if !ok do return

			total += haversine_lib.haversine(pair.x0, pair.y0, pair.x1, pair.y1)
			pair_count += 1

			if !json_parser.match(parser, .COMMA) do break
		}
	}
	json_parser.consume(parser, .RIGHT_BRACKET, "Expected closing bracket after pairs")
	return
}

parse_root_object :: proc(
	parser: ^json_parser.Parser,
) -> (
	pair_count: int,
	total: f64,
	found_pairs: bool,
) {
	json_parser.consume(parser, .LEFT_BRACE, "Expected root object")
	if !json_parser.check(parser, .RIGHT_BRACE) {
		for !parser.had_error {
			key, has_key := json_parser.consume_string(parser, "Expected root field name")
			if !has_key {
				return
			}

			json_parser.consume(parser, .COLON, "Expected colon after root field name")
			if key == "pairs" {
				pair_count, total = parse_pairs_array(parser)
				found_pairs = true
			} else {
				json_parser.skip_json_value(parser)
			}

			if !json_parser.match(parser, .COMMA) do break
		}
	}
	json_parser.consume(parser, .RIGHT_BRACE, "Expected closing brace after root object")
	return
}

parse_haversine_source :: proc(source: string) -> (pair_count: int, sum: f64, ok: bool) {
	metrics.profile_function()

	parser: json_parser.Parser
	{
		metrics.profile_block("Parser Setup")
		parser = json_parser.parser_make(source)
		if parser.had_error do return
	}

	found_pairs: bool
	{
		metrics.profile_block("Parse Root")
		pair_count, sum, found_pairs = parse_root_object(&parser)
	}
	{
		metrics.profile_block("Parser Finish")
		if !parser.had_error && !found_pairs {
			json_parser.parser_error(
				&parser,
				json_parser.parser_peek(&parser),
				"Root object requires pairs array",
			)
		}
		if !json_parser.finish(&parser) do return 0, 0, false
	}

	{
		metrics.profile_block("Average")
		if pair_count > 0 {
			sum /= f64(pair_count)
		}
	}
	return pair_count, sum, true
}

print_validation :: proc(file: ^os.File, pair_count: int, sum: f64) -> bool {
	data, read_err := os.read_entire_file(file, context.allocator)
	defer delete(data)
	if read_err != nil {
		fmt.eprintln("failed to read validator:", read_err)
		return false
	}

	f64_size := size_of(f64)
	if len(data) < f64_size || len(data) % f64_size != 0 {
		fmt.eprintln("validator must contain complete f64 values")
		return false
	}

	answers := slice.reinterpret([]f64, data)
	reference_count := len(answers) - 1
	reference_sum := answers[reference_count]

	fmt.println("\nValidation:")
	if pair_count != reference_count {
		fmt.printfln("FAILED - pair count doesn't match %d.", reference_count)
	}
	fmt.printfln("Reference sum: %.16f", reference_sum)
	fmt.printfln("Difference: %.16f", sum - reference_sum)
	fmt.println()
	return true
}

main :: proc() {
	os.exit(run())
}

run :: proc() -> int {
	metrics.begin_profile()
	defer metrics.end_and_print_profile()

	Options :: struct {
		file:      ^os.File `args:"pos=0,required,file=r" usage:"Haversine JSON file."`,
		validator: ^os.File `args:"pos=1,file=r" usage:"Haversine answers file."`,
	}

	options: Options
	{
		metrics.profile_block("Startup")
		flags.parse_or_exit(&options, os.args)
	}
	defer os.close(options.file)
	defer if options.validator != nil {
		os.close(options.validator)
	}

	data: []byte
	read_err: os.Error
	{
		metrics.profile_block("Read")
		data, read_err = os.read_entire_file(options.file, context.allocator)
	}
	defer delete(data)
	if read_err != nil {
		fmt.eprintln("failed to read input:", read_err)
		return 1
	}

	pair_count, sum, ok := parse_haversine_source(string(data))
	if !ok do return 1

	{
		metrics.profile_block("MiscOutput")
		fmt.printfln("Input size: %d", len(data))
		fmt.printfln("Pair count: %d", pair_count)
		fmt.printfln("Haversine sum: %.16f", sum)
	}

	if options.validator != nil && !print_validation(options.validator, pair_count, sum) {
		return 1
	}

	return 0
}
