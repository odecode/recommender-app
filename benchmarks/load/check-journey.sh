#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
out=${JOURNEY_BUILD_DIR:-target/journey}
export LOAD_PORT=${LOAD_TEST_PORT:-18994}
peer_pid=
cleanup() { if [[ -n "$peer_pid" ]]; then kill "$peer_pid" 2>/dev/null || true; wait "$peer_pid" 2>/dev/null || true; fi; }
trap cleanup EXIT
"$out/journey_oracle"
for mode in {0..7}; do
    : > "$out/peer-$mode.log"
    PEER_MODE=$mode "$out/journey_peer" > "$out/peer-$mode.log" 2>&1 & peer_pid=$!
    for step in {1..100}; do
        grep -q peer_ready "$out/peer-$mode.log" && break
        kill -0 "$peer_pid" 2>/dev/null || { cat "$out/peer-$mode.log"; exit 1; }
        sleep .02
    done
    grep -q peer_ready "$out/peer-$mode.log"
    status=0
    "$out/journey_wire" > "$out/wire-$mode.csv" || status=$?
    if [[ $mode == 0 || $mode == 1 || $mode == 6 ]]; then [[ $status == 0 ]]; else [[ $status == 2 ]]; fi
    wait "$peer_pid"; peer_pid=
    printf 'journey_wire_case_%s_ok\n' "$mode"

    : > "$out/transport-peer-$mode.log"
    PEER_MODE=$mode "$out/journey_peer" > "$out/transport-peer-$mode.log" 2>&1 & peer_pid=$!
    for step in {1..100}; do
        grep -q peer_ready "$out/transport-peer-$mode.log" && break
        kill -0 "$peer_pid" 2>/dev/null || { cat "$out/transport-peer-$mode.log"; exit 1; }
        sleep .02
    done
    grep -q peer_ready "$out/transport-peer-$mode.log"
    status=0
    "$out/journey_transport" > "$out/transport-$mode.csv" || status=$?
    if [[ $mode == 0 || $mode == 1 || $mode == 6 ]]; then [[ $status == 0 ]]; else [[ $status == 2 ]]; fi
    wait "$peer_pid"; peer_pid=
    printf 'journey_transport_case_%s_ok\n' "$mode"
done
status=0
"$out/journey_wire" > "$out/wire-refused.csv" || status=$?
[[ $status == 2 ]]
grep -q '^wire_result,false,connect$' "$out/wire-refused.csv"
printf 'journey_wire_refused_ok\n'
status=0
"$out/journey_transport" > "$out/transport-refused.csv" || status=$?
[[ $status == 2 ]]
grep -q '^transport_result,false,connect$' "$out/transport-refused.csv"
printf 'journey_transport_refused_ok\n'
