#!/usr/bin/env bash
# Native memory-correctness checks. Valgrind timings are not benchmark data.
set -euo pipefail
command -v valgrind >/dev/null || { echo 'Install Valgrind to run the native memory checks.' >&2; exit 1; }
cd "$(dirname "$0")/../.."
compiler_root="$(cd "${BRIEV_ROOT:-../briev-lang}" && pwd)"
compiler="${BRIEVC:-$compiler_root/target/release/brievc}"
export BRIEV_HOME="$compiler_root" BRIEV_CONFIG_DIR="$compiler_root/config"
output="$PWD/target/load-memory"
mkdir -p "$output"
for source in benchmarks/load/probes/file_read_lifetime.bv benchmarks/load/collect.bv; do
    name="$(basename "$source" .bv)"
    "$compiler" build "$source" --stdlib-path "$compiler_root/lib" \
        --config-dir "$compiler_root/config" --out "$output" > "$output/$name.build.log" 2>&1
done

# Cross the initial 4096-byte buffer and two growth boundaries.
head -c 20000 /dev/zero > "$output/growth-input"
failed=0
memory_check() {
    local label="$1" status=0
    shift
    timeout 90s valgrind --leak-check=full --errors-for-leak-kinds=definite,indirect \
        --error-exitcode=91 --log-file="$output/$label.valgrind" "$@" \
        > "$output/$label.stdout" || status=$?
    if [[ "$status" != 0 ]]; then
        printf 'FAIL %s (exit %s): %s\n' "$label" "$status" "$output/$label.valgrind" >&2
        failed=1
    else
        printf 'PASS %s\n' "$label"
    fi
}

for mode in 0 1 2 3; do
    for reads in 1 20; do
        label="file-$mode-$reads"
        READ_MODE="$mode" READS="$reads" memory_check "$label" "$output/file_read_lifetime"
        grep -Fxq file_reads_ok "$output/$label.stdout" || failed=1
    done
done
LOAD_PID=0 LOAD_HZ=100 LOAD_SAMPLES=20 memory_check collector "$output/collect"
awk -F, 'NF != 19 || (NR > 1 && $1 != "sample") { exit 1 } END { if (NR != 21) exit 1 }' \
    "$output/collector.stdout" || failed=1
exit "$failed"
