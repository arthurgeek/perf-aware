package metrics

import "core:fmt"

main :: proc() {
	os_freq := get_os_timer_freq()
	fmt.printfln("    OS Freq: %d", os_freq)

	cpu_start := read_cpu_timer()
	os_start := read_os_timer()
	os_end: u64 = 0
	os_elapsed: u64 = 0

	for os_elapsed < os_freq {
		os_end = read_os_timer()
		os_elapsed = os_end - os_start
	}

	cpu_end := read_cpu_timer()
	cpu_elapsed := cpu_end - cpu_start

	fmt.printfln("   OS Timer: %d -> %d = %d", os_start, os_end, os_elapsed)
	fmt.printfln(" OS Seconds: %.4f", f64(os_elapsed) / f64(os_freq))

	fmt.printfln("  CPU Timer: %d -> %d = %d", cpu_start, cpu_end, cpu_elapsed)
	fmt.printfln("   CPU Freq: %d (guessed)", estimate_cpu_timer_freq())
}
