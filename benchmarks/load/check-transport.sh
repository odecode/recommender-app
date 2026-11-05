#!/usr/bin/env bash
# Controlled Linux transport checkpoint; no server-capacity measurement.
set -euo pipefail
cd "$(dirname "$0")/../.."
compiler_root="$(cd "${BRIEV_ROOT:-../briev-lang}" && pwd)"
compiler="$(realpath "${BRIEVC:-$compiler_root/target/release/brievc}")"
export BRIEV_HOME="$compiler_root" BRIEV_CONFIG_DIR="$compiler_root/config"
output="$PWD/target/load-transport-checkpoint"
mkdir -p "$output"
ulimit -c 0
printf 'compiler=%s\nstdlib_root=%s\n' "$compiler" "$compiler_root" > "$output/provenance.txt"
sha256sum "$compiler" "$compiler_root/lib/std/net/nonblocking.bv" \
    "$compiler_root/lib/std/os/poll.bv" >> "$output/provenance.txt"
build() {
    local source="$1" name
    name="$(basename "$source" .bv)"
    "$compiler" build "$source" --stdlib-path "$compiler_root/lib" \
        --config-dir "$compiler_root/config" --out "$output" > "$output/$name.build.log" 2>&1
    sha256sum "$source" "$output/$name" >> "$output/provenance.txt"
}
check() {
    local name="$1" expected="$2"
    CASE=0 timeout 60s valgrind --track-fds=yes --leak-check=full \
        --errors-for-leak-kinds=definite,indirect --error-exitcode=91 \
        --log-file="$output/$name.valgrind" "$output/$name" > "$output/$name.stdout"
    printf '%s\n' "$expected" > "$output/$name.expected"
    cmp "$output/$name.expected" "$output/$name.stdout"
    # Valgrind can inherit its log descriptor as well as stdin/out/err.
    # Reject any descriptor opened by the tested process, regardless of count.
    awk '/FILE DESCRIPTORS:/ { seen=1 }
         /Open / { if (pending) failed=1; pending=1 }
         /<inherited from parent>/ { pending=0 }
         END { exit (!seen || pending || failed) }' "$output/$name.valgrind"
    printf 'PASS %s (output, memory, descriptors)\n' "$name"
}
for name in nonblocking_gate nonblocking_connect_gate nonblocking_limits_gate; do
    build "$compiler_root/tests/fixtures/load/$name.bv"
done
build benchmarks/load/probes/transport_progress.bv
check nonblocking_gate nonblocking_partial_progress_backpressure_eof_ok
check nonblocking_connect_gate nonblocking_connect_success_and_refusal_ok
check nonblocking_limits_gate nonblocking_valid_lifetime_ok
check transport_progress controlled_stream_progress_ok
for scenario in {1..11}; do
    status=0
    { CASE="$scenario" timeout 20s "$output/nonblocking_limits_gate" \
        > "$output/invalid-$scenario.stdout"; } 2> "$output/invalid-$scenario.stderr" || status=$?
    if [[ "$status" != 132 ]]; then
        printf 'FAIL invalid transport case %s: exit %s\n' "$scenario" "$status" >&2
        exit 1
    fi
    test ! -s "$output/invalid-$scenario.stdout"
done
printf 'PASS transport bounds and lifetime rejection (11 cases)\n'
