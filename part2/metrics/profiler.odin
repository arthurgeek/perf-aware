package metrics

import "base:runtime"
import "core:fmt"

MAX_PROFILE_ENTRIES :: 256

@(private)
Profile_Entry :: struct {
	procedure:    string,
	location:     runtime.Source_Code_Location,
	parent_index: int,

	elapsed_ticks_exclusive: u64,
	elapsed_ticks_inclusive: u64,
	hit_count:               u64,
}

Profile_Block :: struct {
	entry_index:               int,
	parent_index:              int,
	start:                     u64,
	old_elapsed_ticks_inclusive: u64,
}

@(private)
Profiler :: struct {
	entries:     [MAX_PROFILE_ENTRIES]Profile_Entry,
	entry_count: int,
	current_parent_index: int,
	total_start: u64,
	active:      bool,
}

@(private)
profiler: Profiler

begin_profile :: proc() {
	assert(!profiler.active)
	profiler.active = true
	profiler.current_parent_index = -1
	profiler.total_start = read_cpu_timer()
}

@(private)
same_location :: proc(a, b: runtime.Source_Code_Location) -> bool {
	return a.line == b.line && a.column == b.column && a.file_path == b.file_path
}

@(private)
profile_begin :: proc(name: string, location: runtime.Source_Code_Location) -> Profile_Block {
	assert(profiler.active)
	parent_index := profiler.current_parent_index
	entry_index := -1
	for entry, index in profiler.entries[:profiler.entry_count] {
		if same_location(entry.location, location) {
			entry_index = index
			break
		}
	}
	if entry_index < 0 {
		assert(profiler.entry_count < MAX_PROFILE_ENTRIES)
		entry_index = profiler.entry_count
		profiler.entries[entry_index] = {
			procedure = name,
			location = location,
			parent_index = parent_index,
		}
		profiler.entry_count += 1
	}
	entry := &profiler.entries[entry_index]
	block := Profile_Block {
		entry_index = entry_index,
		parent_index = parent_index,
		old_elapsed_ticks_inclusive = entry.elapsed_ticks_inclusive,
	}
	profiler.current_parent_index = entry_index
	block.start = read_cpu_timer()
	return block
}

@(private)
profile_end :: proc(block: Profile_Block) {
	end := read_cpu_timer()
	elapsed := end - block.start
	profiler.current_parent_index = block.parent_index
	if block.parent_index >= 0 {
		profiler.entries[block.parent_index].elapsed_ticks_exclusive -= elapsed
	}

	entry := &profiler.entries[block.entry_index]
	entry.elapsed_ticks_exclusive += elapsed
	entry.elapsed_ticks_inclusive = block.old_elapsed_ticks_inclusive + elapsed
	entry.hit_count += 1
}

@(deferred_in_out = profile_block_end)
profile_block :: proc(
	name: string,
	location: runtime.Source_Code_Location = #caller_location,
) -> Profile_Block {
	return profile_begin(name, location)
}

@(private)
profile_block_end :: proc(
	_: string,
	_: runtime.Source_Code_Location,
	block: Profile_Block,
) {
	profile_end(block)
}

@(deferred_in_out = profile_function_end)
profile_function :: proc(
	location: runtime.Source_Code_Location = #caller_location,
) -> Profile_Block {
	return profile_begin(location.procedure, location)
}

@(private)
profile_function_end :: proc(_: runtime.Source_Code_Location, block: Profile_Block) {
	profile_end(block)
}

@(private)
print_profile_entries :: proc(parent_index, depth: int, total_elapsed, cpu_freq: u64) {
	for entry_index in 0 ..< profiler.entry_count {
		entry := &profiler.entries[entry_index]
		if entry.parent_index != parent_index do continue

		for _ in 0 ..< depth {
			fmt.print("  ")
		}

		elapsed_ticks := entry.elapsed_ticks_exclusive
		has_children := entry.elapsed_ticks_inclusive != elapsed_ticks
		if cpu_freq == 0 {
			if has_children {
				fmt.printfln(
					"%s[%d]: %d ticks (%d ticks w/children)",
					entry.procedure,
					entry.hit_count,
					elapsed_ticks,
					entry.elapsed_ticks_inclusive,
				)
			} else {
				fmt.printfln(
					"%s[%d]: %d ticks",
					entry.procedure,
					entry.hit_count,
					elapsed_ticks,
				)
			}
		} else {
			elapsed_ms := 1000.0 * f64(elapsed_ticks) / f64(cpu_freq)
			percent := 0.0
			if total_elapsed > 0 {
				percent = 100.0 * f64(elapsed_ticks) / f64(total_elapsed)
			}
			if has_children {
				percent_with_children := 100.0 * f64(entry.elapsed_ticks_inclusive) / f64(total_elapsed)
				fmt.printfln(
					"%s[%d]: %.4f ms (%.2f%%, %.2f%% w/children)",
					entry.procedure,
					entry.hit_count,
					elapsed_ms,
					percent,
					percent_with_children,
				)
			} else {
				fmt.printfln(
					"%s[%d]: %.4f ms (%.2f%%)",
					entry.procedure,
					entry.hit_count,
					elapsed_ms,
					percent,
				)
			}
		}

		print_profile_entries(entry_index, depth + 1, total_elapsed, cpu_freq)
	}
}

end_and_print_profile :: proc() {
	assert(profiler.active)
	total_end := read_cpu_timer()
	total_elapsed := total_end - profiler.total_start
	cpu_freq := estimate_cpu_timer_freq()

	fmt.println("\nProfile:")
	if cpu_freq == 0 {
		fmt.printfln("Total: %d timer ticks", total_elapsed)
	} else {
		total_ms := 1000.0 * f64(total_elapsed) / f64(cpu_freq)
		fmt.printfln("Total: %.4f ms (CPU freq %d)", total_ms, cpu_freq)
	}
	print_profile_entries(-1, 1, total_elapsed, cpu_freq)

	profiler = {}
}
