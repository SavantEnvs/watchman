#!/usr/bin/env bash
#
# watchman/mayhem/test.sh — RUN the pybser known-answer decode check (mayhem/bser_check.cpp, built by
# mayhem/build.sh with normal flags): valid BSER documents must decode to exact Python values. Emits CTRF.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SRC:=/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

RUNNER=/mayhem/bser_check
if [ ! -x "$RUNNER" ]; then
  echo "$RUNNER missing — mayhem/build.sh did not build it" >&2
  emit_ctrf "bser-check" 0 1 0; exit 2
fi

echo "=== $RUNNER (known-answer pybser decodes) ==="
out="$("$RUNNER" 2>&1)"; rc=$?
printf '%s\n' "$out"

PASSED=$(printf '%s\n' "$out" | grep -c '^OK ')
FAILED=$(printf '%s\n' "$out" | grep -c '^FAIL ')

if [ "$(( PASSED + FAILED ))" -eq 0 ]; then
  echo "no result lines from $RUNNER (exit $rc)" >&2
  emit_ctrf "bser-check" 0 1 0; exit 1
fi
[ "$rc" -eq 0 ] || [ "$FAILED" -gt 0 ] || FAILED=1
emit_ctrf "bser-check" "$PASSED" "$FAILED" 0
