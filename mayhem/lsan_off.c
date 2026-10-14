/* Build-time LeakSanitizer opt-out for the ASan-built pybser fuzz binaries (leaks are not the bug class fuzzed for). */
int __lsan_is_turned_off(void) { return 1; }
