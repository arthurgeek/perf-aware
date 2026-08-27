package metrics

import "base:runtime"
import "core:fmt"

MAX_PROFILE_ENTRIES :: 256

@(private)
Profile_Entry :: struct {
	procedure:     string,
	elapsed_ticks: u64,
}

Profile_Block :: struct {
	entry_index: int,
	start:       u64,
}

@(private)
Profiler :: struct {
	entries:     [MAX_PROFILE_ENTRIES]Profile_Entry,
	entry_count: int,
	total_start: u64,
	active:      bool,
}

@(private)
profiler: Profiler

begin_profile :: proc() {
	assert(!profiler.active)
	profiler.active = true
	profiler.total_start = read_cpu_timer()
}

@(private)
profile_begin :: proc(name: string) -> Profile_Block {
	assert(profiler.active)
	entry_index := -1
	for entry, index in profiler.entries[:profiler.entry_count] {
		if entry.procedure == name {
			entry_index = index
			break
		}
	}
	if entry_index < 0 {
		assert(profiler.entry_count < MAX_PROFILE_ENTRIES)
		entry_index = profiler.entry_count
		profiler.entries[entry_index] = {procedure = name}
		profiler.entry_count += 1
	}
	return {entry_index = entry_index, start = read_cpu_timer()}
}

@(private)
profile_end :: proc(block: Profile_Block) {
	end := read_cpu_timer()
	entry := &profiler.entries[block.entry_index]
	entry.elapsed_ticks += end - block.start
}

@(deferred_in_out = profile_block_end)
profile_block :: proc(name: string) -> Profile_Block {
	return profile_begin(name)
}

@(private)
profile_block_end :: proc(_: string, block: Profile_Block) {
	profile_end(block)
}

@(deferred_in_out = profile_function_end)
profile_function :: proc(
	location: runtime.Source_Code_Location = #caller_location,
) -> Profile_Block {
	return profile_begin(location.procedure)
}

@(private)
profile_function_end :: proc(_: runtime.Source_Code_Location, block: Profile_Block) {
	profile_end(block)
}

end_and_print_profile :: proc() {
	assert(profiler.active)
	total_end := read_cpu_timer()
	total_elapsed := total_end - profiler.total_start
	cpu_freq := estimate_cpu_timer_freq()

	fmt.println("\nProfile:")
	if cpu_freq == 0 {
		fmt.printfln("Total: %d timer ticks", total_elapsed)
		for entry, _ in profiler.entries[:profiler.entry_count] {
			fmt.printfln("  %s: %d ticks", entry.procedure, entry.elapsed_ticks)
		}
	} else {
		total_ms := 1000.0 * f64(total_elapsed) / f64(cpu_freq)
		fmt.printfln("Total: %.4f ms (CPU freq %d)", total_ms, cpu_freq)
		for entry, _ in profiler.entries[:profiler.entry_count] {
			elapsed_ms := 1000.0 * f64(entry.elapsed_ticks) / f64(cpu_freq)
			percent := 0.0
			if total_elapsed > 0 {
				percent = 100.0 * f64(entry.elapsed_ticks) / f64(total_elapsed)
			}
			fmt.printfln(
				"  %s: %.4f ms (%.2f%%)",
				entry.procedure,
				elapsed_ms,
				percent,
			)
		}
	}

	profiler = {}
}
