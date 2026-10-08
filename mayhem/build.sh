#!/usr/bin/env bash
#
# watchman/mayhem/build.sh — build serde_bser's cargo-fuzz `roundtrip` harness as a sanitized
# libFuzzer binary (ASan via RUSTFLAGS), replicating OSS-Fuzz's Rust path.
#
# watchman's `serde_bser` crate (watchman/rust/serde_bser) implements the Watchman BSER
# encode/decode. Upstream ships NO fuzz crate at the repo top level; the old maymemheroes fork
# carried a roundtrip harness under watchman/rust/serde_bser/fuzz/. This crate preserves that
# harness ADDITIVELY under mayhem/fuzz/ (its own isolated [workspace]) and depends on the in-tree
# serde_bser crate by path. cargo-fuzz ships its own libFuzzer runtime, so each produced binary IS
# a libFuzzer target (`libfuzzer: true`). ASan is enabled the Rust way via RUSTFLAGS
# `-Zsanitizer=address` (NOT clang's $SANITIZER_FLAGS / CFLAGS — those don't apply to rustc);
# nightly is required for `-Zsanitizer`.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE. This first build (in
# CI, online) populates the cargo registry under $CARGO_HOME=/opt/toolchains/rust/cargo; the re-run
# resolves every crate from that cache. We do NOT hard-code `--offline` (it would break this online
# build); the rlenv runtime exports CARGO_NET_OFFLINE=true for the re-run.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer (kept for parity even
# though the Rust build doesn't invoke clang directly; cargo's cc-built deps might).
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SRC:=/mayhem}"
: "${MAYHEM_JOBS:=$(nproc)}"
export MAYHEM_JOBS
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

# DWARF < 4 debug-info contract (§6.2 item 10). Force DWARF version 2 so Mayhem triage / gdb can
# resolve project source lines. The rlenv runtime may export RUST_DEBUG_FLAGS before re-running
# build.sh offline; the `:-` default only applies when the variable is unset or empty.
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=--dwarf-version=2}"

cd "$SRC"

FUZZ_DIR="$SRC/mayhem/fuzz"          # our additive cargo-fuzz crate (absolute — cwd changes below)
# cargo-fuzz needs an enclosing cargo project at cwd; upstream watchman has NO root Cargo.toml, so
# we anchor on the fuzzed crate itself (serde_bser, unmodified upstream) and point --fuzz-dir at
# our external mayhem/fuzz crate. The fuzz crate depends on serde_bser by relative path.
PROJECT_DIR="$SRC/watchman/rust/serde_bser"
TRIPLE="x86_64-unknown-linux-gnu"

# ── DWARF < 4 enforcement (§6.2 item 10) ────────────────────────────────────────────────────────
# Rust's ASan runtime (librustc-nightly_rt.asan.a) is compiled with the nightly's bundled LLVM
# (defaults to DWARF 5) and is linked BEFORE the project code, so without intervention the first CU
# in .debug_info would be DWARF 5 — failing the verify-repo check. Strip the ASan archive's debug
# sections once so it contributes no debug info; our project code (DWARF 2 via RUST_DEBUG_FLAGS)
# then appears first. The stripped .a is baked into the image, so the offline re-run reproduces it.
ASAN_RT="$(find "${RUSTUP_HOME:-/opt/toolchains/rust/rustup}/toolchains" -name "librustc-nightly_rt.asan.a" 2>/dev/null | head -1)"
if [ -n "$ASAN_RT" ] && [ -f "$ASAN_RT" ]; then
    echo "Stripping debug info from Rust ASan runtime to enforce DWARF < 4: $ASAN_RT"
    objcopy --strip-debug "$ASAN_RT" || true
fi

# libfuzzer-sys compiles libFuzzer from C++ via the cc crate; force DWARF 3 so those CUs also
# satisfy the check (the cc crate respects CFLAGS/CXXFLAGS). On the re-run these are the same, so
# cargo reuses the cached libfuzzer.a (fingerprint stable).
export CFLAGS="${CFLAGS:+$CFLAGS }-gdwarf-3"
export CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }-gdwarf-3"

# Replicate OSS-Fuzz `compile` RUSTFLAGS for a libFuzzer+ASan Rust build. cargo-fuzz sets the ASan
# flag itself by default, but we set it explicitly so the behavior is pinned and visible. `--cfg
# fuzzing` matches libfuzzer-sys. RUST_DEBUG_FLAGS adds DWARF <= 2 debug info for our Rust code;
# combined with the stripped ASan runtime this keeps the first .debug_info CU < 4.
#
# No UBSan here, by necessity: rustc has no undefined-behaviour sanitizer (-Zsanitizer accepts only
# address, cfi, dataflow, hwaddress, kcfi, kernel-address, leak, memory, memtag, safestack,
# shadow-call-stack, thread). The fuzzed code is pure Rust (serde_bser and its crates.io dependencies
# compile no C/C++), so a binary-level scan finds 0 __ubsan_handle_* call sites. The Rust-native checks
# take UBSan's place and HALT: `--debug-assertions` turns on overflow checks (add/sub/shl/shr/neg
# panic, the analogue of UBSan's integer-overflow and shift checks) and core's ub_checks preconditions;
# a panic aborts the fuzz binary like a halting sanitizer report.
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address ${RUST_DEBUG_FLAGS}"

# LeakSanitizer off at BUILD time (fleet policy): compile mayhem/lsan_off.c (a strong
# __lsan_is_turned_off() returning 1) and link the object into every fuzz binary. cargo-fuzz passes
# an explicit --target, so RUSTFLAGS (and this link-arg) reach only the target crates, never build
# scripts or proc-macros. A plain object on the link line is always linked, so it overrides the ASan
# runtime's weak reference. The object is rebuilt on every run (idempotent, offline). It is compiled
# without $SANITIZER_FLAGS on purpose: the hook body is `return 1` and has nothing to instrument.
LSAN_OFF_OBJ="$SRC/mayhem/lsan_off.o"
"${CC:-clang}" -c -O1 -gdwarf-3 -fno-omit-frame-pointer "$SRC/mayhem/lsan_off.c" -o "$LSAN_OFF_OBJ"
export RUSTFLAGS="$RUSTFLAGS -C link-arg=$LSAN_OFF_OBJ"

# Discover every target from the crate's fuzz_targets/ dir (one binary per target).
FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

echo "=== cargo fuzz build (image-default nightly toolchain, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

# `-O` (release w/ opt) + `--debug-assertions` mirrors OSS-Fuzz's build.sh. Use the image's
# DEFAULT toolchain (pinned to the required nightly by the Dockerfile); a `+toolchain` override
# would make rustup try to install a different channel into the locked /opt/toolchains/rust.
for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  ( cd "$PROJECT_DIR" && cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t" )
done

# Resolve the cargo target dir robustly via `cargo metadata` (cargo-fuzz drops binaries there).
TARGET_DIR="$(cargo metadata --no-deps --format-version 1 --manifest-path "$FUZZ_DIR/Cargo.toml" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["target_directory"])')"
echo "fuzz target_directory: $TARGET_DIR"

REL="$TARGET_DIR/$TRIPLE/release"
for t in "${FUZZ_TARGETS[@]}"; do
  bin="$REL/$t"
  if [ ! -x "$bin" ]; then
    echo "ERROR: expected fuzz binary not found at $bin" >&2
    ls -la "$REL" >&2 || true
    exit 1
  fi
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

echo "build.sh complete:"
ls -la "${FUZZ_TARGETS[@]/#//mayhem/}" 2>&1 || true
