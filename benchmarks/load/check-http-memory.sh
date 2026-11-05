#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
out=${LOAD_BUILD_DIR:-target/http-load}
export LOAD_PORT=${LOAD_TEST_PORT:-18991} LOAD_ITEMS=1 LOAD_TIMEOUT_MS=2000
export LOAD_HZ=10 LOAD_REQUESTS=50 LOAD_SLOTS=4
peer_pid=
cleanup() { if [[ -n "$peer_pid" ]]; then kill "$peer_pid" 2>/dev/null || true; wait "$peer_pid" 2>/dev/null || true; fi; }
trap cleanup EXIT
for mode in 0 5; do
    : > "$out/memory-peer-$mode.log"
    PEER_MODE=$mode PEER_COUNT=$LOAD_REQUESTS "$out/http_peer" > "$out/memory-peer-$mode.log" 2>&1 &
    peer_pid=$!
    for step in {1..100}; do
        grep -q peer_ready "$out/memory-peer-$mode.log" && break
        kill -0 "$peer_pid" 2>/dev/null || exit 1
        sleep .02
    done
    grep -q peer_ready "$out/memory-peer-$mode.log"
    status=0
    valgrind --error-exitcode=99 --leak-check=full --show-leak-kinds=all \
        --errors-for-leak-kinds=definite,indirect,possible --track-fds=yes \
        --log-file="$out/memory-$mode.valgrind" "$out/http_load" > "$out/memory-$mode.csv" || status=$?
    if [[ $mode == 0 ]]; then
        [[ $status == 0 ]]
        grep -q '^summary,50,0,50,50,50,0,0,0,0,' "$out/memory-$mode.csv"
    else
        [[ $status == 2 ]]
        grep -q '^summary,50,0,50,50,0,0,0,0,50,' "$out/memory-$mode.csv"
    fi
    ! grep -q 'Open AF_' "$out/memory-$mode.valgrind"
    grep -q 'ERROR SUMMARY: 0 errors' "$out/memory-$mode.valgrind"
    wait "$peer_pid"; peer_pid=
    printf 'http_memory_%s_ok\n' "$mode"
done
