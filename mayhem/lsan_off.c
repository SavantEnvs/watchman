/* Build-time LeakSanitizer opt-out: ASan stays on, leak detection is off (fleet policy). */
int __lsan_is_turned_off(void) { return 1; }
