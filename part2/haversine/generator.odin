package haversine

import "core:bufio"
import "core:flags"
import "core:fmt"
import "core:io"
import "core:math/rand"
import "core:os"
import "core:slice"

Pair :: struct {
	x0: f64,
	x1: f64,
	y0: f64,
	y1: f64,
}

write_pair :: proc(writer: io.Writer, pair: Pair) -> io.Error {
	io.write_string(writer, "{\"x0\":") or_return
	io.write_f64(writer, pair.x0) or_return
	io.write_string(writer, ",\"x1\":") or_return
	io.write_f64(writer, pair.x1) or_return
	io.write_string(writer, ",\"y0\":") or_return
	io.write_f64(writer, pair.y0) or_return
	io.write_string(writer, ",\"y1\":") or_return
	io.write_f64(writer, pair.y1) or_return
	io.write_byte(writer, '}') or_return
	return nil
}

write_binary_f64 :: proc(writer: io.Writer, value: f64) -> io.Error {
	binary_value := value
	_, err := io.write_full(writer, slice.bytes_from_ptr(&binary_value, size_of(binary_value)))
	return err
}

MethodName :: enum {
	uniform,
	cluster,
}

Options :: struct {
	method_name:    MethodName `args:"pos=0,required" usage:"coordinate distribution: uniform or cluster"`,
	seed_value:     u64 `args:"pos=1,required" usage:"seed value for random number generation"`,
	max_pair_count: u64 `args:"pos=2,required" usage:"maximum number of coordinate pairs to generate"`,
}

random_degree :: proc(center, radius, max_allowed: f64) -> f64 {
	min_value := max(center - radius, -max_allowed)
	max_value := min(center + radius, max_allowed)
	return rand.float64_range(min_value, max_value)
}

main :: proc() {
	opts: Options
	flags.parse_or_exit(&opts, os.args)
	rand.reset(opts.seed_value)

	fmt.printfln("Method: %v", opts.method_name)
	fmt.printfln("Random seed: %d", opts.seed_value)
	fmt.printfln("Pair count: %d", opts.max_pair_count)

	json_filename := fmt.tprintf("data_%d.json", opts.max_pair_count)
	json_file, open_err := os.open(
		json_filename,
		{.Write, .Create, .Trunc},
		{.Read_User, .Write_User, .Read_Group, .Read_Other},
	)
	if open_err != nil {
		fmt.eprintln("Failed to open", json_filename, "for writing:", open_err)
		return
	}
	defer os.close(json_file)

	json_buffer: [64 * 1024]byte
	json_buffered_writer: bufio.Writer
	bufio.writer_init_with_buf(&json_buffered_writer, os.to_stream(json_file), json_buffer[:])
	json_writer := bufio.writer_to_writer(&json_buffered_writer)

	answer_filename := fmt.tprintf("data_%d_haveranswer.f64", opts.max_pair_count)
	answer_file, answer_open_err := os.open(
		answer_filename,
		{.Write, .Create, .Trunc},
		{.Read_User, .Write_User, .Read_Group, .Read_Other},
	)
	if answer_open_err != nil {
		fmt.eprintln("Failed to open", answer_filename, "for writing:", answer_open_err)
		return
	}
	defer os.close(answer_file)

	answer_buffer: [64 * 1024]byte
	answer_buffered_writer: bufio.Writer
	bufio.writer_init_with_buf(&answer_buffered_writer, os.to_stream(answer_file), answer_buffer[:])
	answer_writer := bufio.writer_to_writer(&answer_buffered_writer)

	if _, write_err := io.write_string(json_writer, "{\"pairs\":["); write_err != nil {
		fmt.eprintln("Failed to write JSON:", write_err)
		return
	}

	sum := 0.0
	cluster_count_left: u64
	cluster_count_max := 1 + opts.max_pair_count / 64
	x_center, y_center := 0.0, 0.0
	x_radius, y_radius := 180.0, 90.0

	for i in 0 ..< opts.max_pair_count {
		if opts.method_name == .cluster {
			if cluster_count_left == 0 {
				cluster_count_left = cluster_count_max
				x_center = rand.float64_range(-180.0, 180.0)
				y_center = rand.float64_range(-90.0, 90.0)
				x_radius = rand.float64_range(0.0, 180.0)
				y_radius = rand.float64_range(0.0, 90.0)
			} else {
				cluster_count_left -= 1
			}
		}

		pair := Pair {
			x0 = random_degree(x_center, x_radius, 180.0),
			x1 = random_degree(x_center, x_radius, 180.0),
			y0 = random_degree(y_center, y_radius, 90.0),
			y1 = random_degree(y_center, y_radius, 90.0),
		}

		distance := haversine(
			pair.x0,
			pair.y0,
			pair.x1,
			pair.y1,
		)
		sum += distance

		if write_err := write_binary_f64(answer_writer, distance); write_err != nil {
			fmt.eprintln("Failed to write Haversine answer:", write_err)
			return
		}

		if write_err := write_pair(json_writer, pair); write_err != nil {
			fmt.eprintln("Failed to write JSON:", write_err)
			return
		}

		if i + 1 < opts.max_pair_count {
			if write_err := io.write_byte(json_writer, ','); write_err != nil {
				fmt.eprintln("Failed to write JSON:", write_err)
				return
			}
		}
	}

	if _, write_err := io.write_string(json_writer, "]}"); write_err != nil {
		fmt.eprintln("Failed to write JSON:", write_err)
		return
	}

	if flush_err := bufio.writer_flush(&json_buffered_writer); flush_err != nil {
		fmt.eprintln("Failed to flush", json_filename, ":", flush_err)
		return
	}

	sum /= f64(opts.max_pair_count)
	if write_err := write_binary_f64(answer_writer, sum); write_err != nil {
		fmt.eprintln("Failed to write final Haversine average:", write_err)
		return
	}

	if flush_err := bufio.writer_flush(&answer_buffered_writer); flush_err != nil {
		fmt.eprintln("Failed to flush", answer_filename, ":", flush_err)
		return
	}

	fmt.printfln("Expected sum: %.16f", sum)
}
