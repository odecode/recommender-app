#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
out=${LOAD_BUILD_DIR:-target/http-load}
port=${LOAD_TEST_PORT:-18991}
peer_pid=
cleanup() { if [[ -n "$peer_pid" ]]; then kill "$peer_pid" 2>/dev/null || true; wait "$peer_pid" 2>/dev/null || true; fi; }
trap cleanup EXIT
export LOAD_PORT=$port LOAD_ITEMS=1 LOAD_TIMEOUT_MS=200 LOAD_HZ=5 LOAD_REQUESTS=3 LOAD_SLOTS=2
run_case() {
    local mode=$1 expected=$2
    : > "$out/peer-$mode.log"
    PEER_MODE=$mode PEER_COUNT=3 "$out/http_peer" > "$out/peer-$mode.log" 2>&1 &
    peer_pid=$!
    for step in {1..100}; do
        grep -q peer_ready "$out/peer-$mode.log" && break
        kill -0 "$peer_pid" 2>/dev/null || { cat "$out/peer-$mode.log"; return 1; }
        sleep .02
    done
    grep -q peer_ready "$out/peer-$mode.log"
    local status=0
    "$out/http_load" > "$out/case-$mode.csv" || status=$?
    if [[ $mode == 0 || $mode == 1 ]]; then [[ $status == 0 ]]; else [[ $status == 2 ]]; fi
    grep -q "^summary,3,0,3,3,$expected," "$out/case-$mode.csv"
    if [[ $mode == 6 ]]; then cleanup; else wait "$peer_pid"; fi
    peer_pid=
    printf 'http_case_%s_ok\n' "$mode"
}
run_case 0 '3,0,0,0,0'
run_case 1 '3,0,0,0,0'
run_case 2 '0,0,0,0,3'
run_case 3 '0,0,0,0,3'
run_case 4 '0,3,0,0,0'
run_case 5 '0,0,0,0,3'
run_case 6 '0,0,0,3,0'
status=0
"$out/http_load" > "$out/case-refused.csv" || status=$?
[[ $status == 2 ]]
grep -q '^summary,3,0,3,3,0,0,3,0,0,' "$out/case-refused.csv"
printf 'http_refused_ok\n'
export LOAD_HZ=1000 LOAD_REQUESTS=100 LOAD_SLOTS=1
: > "$out/peer-saturation.log"
PEER_MODE=6 PEER_COUNT=1 "$out/http_peer" > "$out/peer-saturation.log" 2>&1 &
peer_pid=$!
for step in {1..100}; do
    grep -q peer_ready "$out/peer-saturation.log" && break
    kill -0 "$peer_pid" 2>/dev/null || exit 1
    sleep .02
done
grep -q peer_ready "$out/peer-saturation.log"
status=0
"$out/http_load" > "$out/case-saturation.csv" || status=$?
[[ $status == 2 ]]
grep -q '^summary,100,99,1,1,0,0,0,1,0,' "$out/case-saturation.csv"
cleanup; peer_pid=
printf 'http_saturation_ok\n'
