#!/usr/bin/env bash
#
# watchman/mayhem/build.sh — build the pybser fuzz harness (watchman/fuzz/PyBserDecode.cpp) against
# pywatchman's C BSER decoder (watchman/python/pywatchman/bser.c), plus a known-answer decode check
# (mayhem/bser_check.cpp) that mayhem/test.sh runs.
#
# Only bser.c and the harness are compiled: bser.c needs nothing but CPython's headers, so none of
# watchman's own CMake/folly dependency stack is involved.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
# Intermediate objects stay outside the source tree (nothing for `git clean` to miss or leave behind).
B="${MAYHEM_BUILD_DIR:-/tmp/watchman-mayhem-build}"

cd "$SRC"
rm -rf "$B"; mkdir -p "$B"

PYINC=$(python3-config --includes)
PYLIBS=$(python3-config --ldflags --embed)
BSER="$SRC/watchman/python/pywatchman/bser.c"
HARNESS="$SRC/watchman/fuzz/PyBserDecode.cpp"

# 1) The project (bser.c), instrumented, plus the lsan hook (LeakSanitizer off at build time).
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -O1 $PYINC -c "$BSER" -o "$B/bser_san.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -c "$SRC/mayhem/lsan_off.c" -o "$B/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$B/standalone_main.o"

# 2) The harness: libFuzzer binary and a run-once standalone reproducer.
$CXX -std=gnu++17 $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -I"$SRC" $PYINC -c "$HARNESS" -o "$B/harness.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$B/harness.o" "$B/bser_san.o" "$B/lsan_off.o" \
  $PYLIBS -o /mayhem/PyBserDecode
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$B/harness.o" "$B/standalone_main.o" "$B/bser_san.o" "$B/lsan_off.o" \
  $PYLIBS -o /mayhem/PyBserDecode-standalone

# 3) The known-answer decode check with normal flags (no sanitizers), run by mayhem/test.sh.
$CC -O1 $COVERAGE_FLAGS $PYINC -c "$BSER" -o "$B/bser_plain.o"
$CXX -std=gnu++17 -O1 $COVERAGE_FLAGS -I"$SRC" $PYINC "$SRC/mayhem/bser_check.cpp" "$B/bser_plain.o" \
  $PYLIBS -o /mayhem/bser_check

echo "build.sh complete:"
ls -la /mayhem/PyBserDecode /mayhem/PyBserDecode-standalone /mayhem/bser_check
