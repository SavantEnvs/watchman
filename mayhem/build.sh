#!/usr/bin/env bash
#
# watchman/mayhem/build.sh — build the BSER decoder harness (watchman/fuzz/BserDecode.cpp) and the
# upstream BSER unit test (watchman/test/BserTest.cpp).
#
# watchman's own CMake build needs the whole fbcode dependency stack (edencommon, fbthrift, ...).
# The BSER decoder only needs its own sources plus folly (installed under /opt/folly by the
# Dockerfile), so this script compiles exactly those sources: bser.cpp, the vendored jansson,
# w_string, and the logging library bser.cpp calls into.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
FOLLY=/opt/folly
FMT=/opt/fmt
# Intermediate objects stay outside the source tree (nothing for `git clean` to miss or leave behind).
B="${MAYHEM_BUILD_DIR:-/tmp/watchman-mayhem-build}"

cd "$SRC"
rm -rf "$B"; mkdir -p "$B/gen/watchman"

# What watchman's CMake writes to watchman/config.h for a Linux/glibc build (only these are read).
cat > "$B/gen/watchman/config.h" <<'CFG'
#pragma once
#define WATCHMAN_CONFIG_FILE "/etc/watchman.json"
#define PACKAGE_VERSION "mayhem"
#define HAVE_BACKTRACE 1
#define HAVE_BACKTRACE_SYMBOLS 1
#define HAVE_BACKTRACE_SYMBOLS_FD 1
#define HAVE_FDOPENDIR 1
#define HAVE_INOTIFY_INIT 1
#define HAVE_INOTIFY_INIT1 1
#define HAVE_LOCALECONV 1
#define HAVE_MEMMEM 1
#define HAVE_OPENAT 1
#define HAVE_PIPE2 1
#define HAVE_STATFS 1
#define HAVE_STRTOLL 1
#define HAVE_EXECINFO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LOCALE_H 1
#define HAVE_SYS_INOTIFY_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_RESOURCE_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_SYS_STATFS_H 1
#define HAVE_SYS_STATVFS_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_VFS_H 1
CFG

LIB_SRCS=(
  watchman/bser.cpp
  watchman/string.cpp
  watchman/thirdparty/jansson/dump.cpp
  watchman/thirdparty/jansson/error.cpp
  watchman/thirdparty/jansson/load.cpp
  watchman/thirdparty/jansson/strconv.cpp
  watchman/thirdparty/jansson/utf.cpp
  watchman/thirdparty/jansson/value.cpp
  watchman/PubSub.cpp
  watchman/LogConfig.cpp
  watchman/Logging.cpp
  watchman/portability/Backtrace.cpp
)
INCS=(-I"$SRC" -I"$B/gen" -isystem "$FMT/include" -isystem "$FOLLY/include")
CXXSTD=(-std=gnu++17 -include cstdint -include stdexcept -include system_error)
LIBS=("$FOLLY/lib/libfolly.a" -lglog -lgflags -ldouble-conversion "$FMT/lib/libfmt.a"
      -lboost_context -lboost_filesystem -lboost_program_options -lboost_regex -lboost_system -lboost_thread
      -levent -lssl -lcrypto -lz -lunwind -lpthread -ldl)

# build_lib <outdir> <compile flags...>: compile LIB_SRCS in parallel into <outdir>/*.o
build_lib() {
  local out="$1"; shift
  mkdir -p "$out"
  printf '%s\n' "${LIB_SRCS[@]}" | xargs -P "$MAYHEM_JOBS" -I{} bash -c '
    s="$1"; shift; out="$1"; shift
    "$@" -c "$s" -o "$out/$(echo "$s" | tr / _).o"' _ {} "$out" "$CXX" "${CXXSTD[@]}" "${INCS[@]}" "$@"
}

# 1) The project, instrumented, plus the lsan hook (LeakSanitizer off at build time).
build_lib "$B/san" $SANITIZER_FLAGS $DEBUG_FLAGS -O1
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -c "$SRC/mayhem/lsan_off.c" -o "$B/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$B/standalone_main.o"

# 2) The harness: libFuzzer binary and a run-once standalone reproducer.
HARNESS="$SRC/watchman/fuzz/BserDecode.cpp"
$CXX "${CXXSTD[@]}" "${INCS[@]}" $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -c "$HARNESS" -o "$B/harness.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$B/harness.o" "$B"/san/*.o "$B/lsan_off.o" \
  "${LIBS[@]}" -o /mayhem/BserDecode
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$B/harness.o" "$B/standalone_main.o" "$B"/san/*.o "$B/lsan_off.o" \
  "${LIBS[@]}" -o /mayhem/BserDecode-standalone

# 3) The upstream BSER unit test with normal flags (no sanitizers), run by mayhem/test.sh.
build_lib "$B/plain" -O1 $COVERAGE_FLAGS
$CXX "${CXXSTD[@]}" "${INCS[@]}" -DWATCHMAN_TEST_SRC_DIR=\"$SRC\" -O1 $COVERAGE_FLAGS \
  "$SRC/watchman/test/BserTest.cpp" "$B"/plain/*.o "${LIBS[@]}" -lgmock -lgtest -lgtest_main \
  -o /mayhem/bser_test

echo "build.sh complete:"
ls -la /mayhem/BserDecode /mayhem/BserDecode-standalone /mayhem/bser_test
