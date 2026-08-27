package metrics

import "core:time"

get_os_timer_freq :: proc() -> u64 {
	// nanoseconds
	return 1_000_000_000
}

read_os_timer :: proc() -> u64 {
	tick := time.tick_now()
	return u64(time.duration_nanoseconds(time.tick_diff({}, tick)))
}

read_cpu_timer :: proc() -> u64 {
	return time.read_cycle_counter()
}

estimate_cpu_timer_freq :: proc(milliseconds_to_wait: u64 = 100) -> u64 {
	os_freq := get_os_timer_freq()
	os_wait_time := os_freq * milliseconds_to_wait / 1000

	cpu_start := read_cpu_timer()
	os_start := read_os_timer()

	os_elapsed: u64
	for os_elapsed < os_wait_time {
		os_elapsed = read_os_timer() - os_start
	}

	cpu_elapsed := read_cpu_timer() - cpu_start
	if os_elapsed == 0 do return 0

	return os_freq * cpu_elapsed / os_elapsed
}
