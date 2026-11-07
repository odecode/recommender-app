#!/usr/bin/env bash
# Scheduled multi-user authenticated journey run. Builds nothing: it expects
# target/journey-load/journey_load from build-journey.sh. All workload,
# transport, scheduling and validation logic is Briev; this script only
# orchestrates the server process and provides independent SQL evidence.
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${PGUSER:?Set an isolated test role}"
: "${PGDATABASE:?Set an isolated test database}"
: "${UDATA_PATH:?Set MovieLens u.data}"
: "${UITEM_PATH:?Set matching u.item}"
: "${LOAD_PORT:?Set an unused loopback port}"
: "${LOAD_SERVER:?Set the server binary}"
: "${LOAD_GENERATION:?Set the installed prediction worker generation}"
: "${LOAD_USERS:?Set the number of scheduled journeys}"
: "${LOAD_HZ:?Set the arrival rate (users per second)}"
result=${JOURNEY_RESULT_DIR:-target/journey-load-smoke}
mkdir -p "$result"
export LOAD_SLOTS=${LOAD_SLOTS:-$LOAD_USERS}
export LOAD_TIMEOUT_MS=${LOAD_TIMEOUT_MS:-30000}
export LOAD_USERNAME=${LOAD_USERNAME:-load_$(date +%s)_$RANDOM}
export LOAD_PASSWORD=${LOAD_PASSWORD:-load_secret_$(date +%s)_$RANDOM}
server_pid=
cleanup() {
    if [[ -n "$server_pid" ]]; then
        local group
        group=$(ps -o pgid= -p "$server_pid" | tr -d ' ') || true
        if [[ "$group" == "$server_pid" ]]; then kill -TERM -- "-$server_pid" 2>/dev/null || true; fi
        wait "$server_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT
sha256sum "$LOAD_SERVER" target/journey-load/journey_load "$UDATA_PATH" "$UITEM_PATH" > "$result/inputs.sha256"
printf 'database=%s\nrole=%s\nport=%s\nusername_prefix=%s\nworkers=%s\nrate=%s\nworker_generation=%s\n' \
    "$PGDATABASE" "$PGUSER" "$LOAD_PORT" "$LOAD_USERNAME" "$LOAD_USERS" "$LOAD_HZ" "$LOAD_GENERATION" > "$result/environment.txt"
: > "$result/server.log"
setsid env PORT="$LOAD_PORT" MAX_CONNECTIONS=64 REFRESH_SECONDS=3600 "$LOAD_SERVER" > "$result/server.log" 2>&1 &
server_pid=$!
for step in {1..1200}; do
    grep -q 'Recommender listening' "$result/server.log" && break
    kill -0 "$server_pid" 2>/dev/null || { cat "$result/server.log" >&2; exit 1; }
    sleep .1
done
grep -q 'Recommender listening' "$result/server.log"
status=0
timeout -k 5 600 target/journey-load/journey_load > "$result/results.csv" || status=$?
cat "$result/results.csv"
[[ $status == 0 ]]
# Independent durable evidence: five ratings per generated account.
psql -X -h 127.0.0.1 -v ON_ERROR_STOP=1 -v username_prefix="$LOAD_USERNAME" -At \
    -f benchmarks/load/verify-journey-load.sql > "$result/durable.txt"
expected=$((LOAD_USERS))
read -r ratings saved receipts saved_ratings distinct_ops accounts < <(tr '|' ' ' < "$result/durable.txt")
printf 'durable ratings=%s saved=%s receipts=%s saved_ratings=%s distinct_ops=%s accounts=%s (expect %s each)\n' \
    "$ratings" "$saved" "$receipts" "$saved_ratings" "$distinct_ops" "$accounts" "$((expected*5))"
[[ "$ratings" == "$((expected*5))" && "$saved" == "$((expected*5))" && "$receipts" == "$((expected*5))" &&
   "$saved_ratings" == "$((expected*5))" && "$distinct_ops" == "$((expected*5))" && "$accounts" == "$expected" ]]
printf 'journey_load_durable_ok\n'
