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

for scenario in {1..11}; do
    status=0
    { CASE="$scenario" timeout 20s "$output/metrics_limits_gate" \
        > "$output/metrics-invalid-$scenario.actual"; } 2> "$output/metrics-invalid-$scenario.stderr" || status=$?
    if [ "$status" -ne 132 ]; then
        printf 'FAIL metrics invalid case %s: exit %s\n' "$scenario" "$status" >&2
        exit 1
    fi
    test ! -s "$output/metrics-invalid-$scenario.actual"
done
printf 'PASS metrics lifecycle, timestamps and overflow (11 cases)\n'

"$compiler" build benchmarks/load/collect.bv --stdlib-path "$compiler_root/lib" \
    --config-dir "$compiler_root/config" --out "$output" > "$output/collect.build.log" 2>&1
LOAD_PID=0 LOAD_HZ=100 LOAD_SAMPLES=3 timeout 20s "$output/collect" > "$output/collect-self.csv"
status=0
LOAD_PID=2147483647 LOAD_HZ=100 LOAD_SAMPLES=2 timeout 20s "$output/collect" \
    > "$output/collect-missing.csv" || status=$?
test "$status" -eq 2

check_rows() {
    awk -F, -v kind="$1" -v expected="$2" \
        -v pages="$(getconf PAGESIZE)" -v ticks="$(getconf CLK_TCK)" '
        NR == 1 { if (NF != 19 || $1 != "kind") exit 1; next }
        {
            if (NF != 19 || $1 != kind || $18 != pages || $19 != ticks) exit 1;
            if ($6 < $5 || $7 < $6 || $9 <= 0) exit 1;
            if (kind == "sample" && ($8 != 0 || $17 <= 0)) exit 1;
            if (kind == "error") {
                if ($8 != -2 || $9 != 2147483647) exit 1;
                for (column = 10; column <= 17; column++) if ($column != "") exit 1;
            }
        }
        END { if (NR != expected + 1) exit 1 }
    ' "$3"
}
check_rows sample 3 "$output/collect-self.csv"
check_rows error 2 "$output/collect-missing.csv"
printf 'PASS collector schema, units, times and failed-read status\n'
