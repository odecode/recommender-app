#!/usr/bin/env bash
# Build/test tooling only; scheduler and measurement logic live in Briev.
set -euo pipefail
cd "$(dirname "$0")/../.."
app_root="$PWD"
compiler_root="$(cd "${BRIEV_ROOT:-../briev-lang}" && pwd)"
compiler="${BRIEVC:-$compiler_root/target/release/brievc}"
export BRIEV_HOME="$compiler_root"
export BRIEV_CONFIG_DIR="$compiler_root/config"
output="$app_root/target/load-tests"
mkdir -p "$output"
ulimit -c 0

for source in benchmarks/load/tests/*_gate.bv; do
    name="$(basename "$source" .bv)"
    "$compiler" build "$source" --stdlib-path "$compiler_root/lib" \
        --config-dir "$compiler_root/config" --out "$output" > "$output/$name.build.log" 2>&1
    CASE=0 timeout 20s "$output/$name" > "$output/$name.actual"
    cmp "${source%.bv}.golden" "$output/$name.actual"
    printf 'PASS %s\n' "$name"
done

for scenario in 1 2 3 4 5 6 7; do
    status=0
    { CASE="$scenario" timeout 20s "$output/schedule_limits_gate" \
        > "$output/invalid-$scenario.actual"; } 2> "$output/invalid-$scenario.stderr" || status=$?
    if [ "$status" -ne 132 ]; then
        printf 'FAIL scheduler invalid case %s: exit %s\n' "$scenario" "$status" >&2
        exit 1
    fi
    test ! -s "$output/invalid-$scenario.actual"
done
printf 'PASS scheduler invalid inputs and overflow (7 cases)\n'
