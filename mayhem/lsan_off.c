/*
 * Build-time LeakSanitizer opt-out for every ASan-built watchman fuzz binary.
 *
 * Leaks are not the bug class this target is fuzzed for; ASan's memory-safety checks and Rust's
 * overflow/debug assertions are. The ASan runtime that rustc's -Zsanitizer=address links in
 * references this hook weakly and asks it once at start-up whether to run leak detection.
 * mayhem/build.sh compiles this file and links the object into each cargo-fuzz binary through
 * RUSTFLAGS (-C link-arg), so the strong definition here wins. ASan itself stays fully active.
 */
int __lsan_is_turned_off(void) { return 1; }
