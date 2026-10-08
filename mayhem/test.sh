#!/usr/bin/env bash
#
# watchman/mayhem/test.sh — RUN serde_bser's unit tests (the fuzzed crate) and emit CTRF.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
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

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not available" >&2
  emit_ctrf "cargo-test" 0 1 0; exit 2
fi

# Lockfile seed for the unit suite. Upstream gitignores watchman/rust/*/Cargo.lock, so rlenv's
# pre-build `git clean -ffdX` deletes the lockfile that the image build generated. Without a lockfile
# cargo must re-resolve against the crates.io index, which fails in the air-gapped graded build.
# mayhem/serde_bser.Cargo.lock is that generated lockfile, committed; restore it only when the tree
# has none. Not --locked: if upstream changes serde_bser's dependencies, an online build updates it.
LOCK=watchman/rust/serde_bser/Cargo.lock
[ -f "$LOCK" ] || cp mayhem/serde_bser.Cargo.lock "$LOCK"

echo "=== cargo test --manifest-path watchman/rust/serde_bser/Cargo.toml --lib (BSER serde_bser unit suite) ==="
out="$(RUSTFLAGS="" cargo test --manifest-path watchman/rust/serde_bser/Cargo.toml --lib --no-fail-fast --jobs "$MAYHEM_JOBS" 2>&1)"; rc=$?
echo "$out"

PASSED=0; FAILED=0; IGNORED=0
while read -r p f i; do
  PASSED=$(( PASSED + p )); FAILED=$(( FAILED + f )); IGNORED=$(( IGNORED + i ))
done < <(printf '%s\n' "$out" \
  | sed -n 's/^test result:.* \([0-9][0-9]*\) passed; \([0-9][0-9]*\) failed; \([0-9][0-9]*\) ignored.*/\1 \2 \3/p')

if [ "$(( PASSED + FAILED + IGNORED ))" -eq 0 ]; then
  echo "could not parse test result lines; using cargo exit code $rc" >&2
  [ "$rc" -eq 0 ] && { emit_ctrf "cargo-test" 1 0 0; exit 0; }
  emit_ctrf "cargo-test" 0 1 0; exit 1
fi

emit_ctrf "cargo-test" "$PASSED" "$FAILED" "$IGNORED"
