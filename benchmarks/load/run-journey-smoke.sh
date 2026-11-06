#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${PGUSER:?Set an isolated test role}"
: "${PGDATABASE:?Set an isolated test database}"
: "${UDATA_PATH:?Set MovieLens u.data}"
: "${UITEM_PATH:?Set matching u.item}"
: "${LOAD_PORT:?Set an unused loopback port}"
: "${LOAD_SERVER:?Set the server binary}"
: "${LOAD_GENERATION:?Set the installed prediction worker generation}"
out=${JOURNEY_BUILD_DIR:-target/journey}
result=${JOURNEY_RESULT_DIR:-target/journey-smoke}
mkdir -p "$result"
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
sha256sum "$LOAD_SERVER" "$out/journey" "$UDATA_PATH" "$UITEM_PATH" > "$result/inputs.sha256"
printf 'database=%s\nrole=%s\nport=%s\nusername=%s\nworker_generation=%s\n' "$PGDATABASE" "$PGUSER" "$LOAD_PORT" "$LOAD_USERNAME" "$LOAD_GENERATION" > "$result/environment.txt"
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
runner=(timeout -k 5 240)
if [[ ${JOURNEY_VALGRIND:-0} == 1 ]]; then
    runner+=(valgrind --error-exitcode=99 --leak-check=full --show-leak-kinds=all
        --errors-for-leak-kinds=definite,indirect,possible --track-fds=yes --log-file="$result/valgrind.log")
fi
"${runner[@]}" "$out/journey" > "$result/results.csv" || status=$?
cat "$result/results.csv"
[[ $status == 0 ]]
# Verify persistence with a separate connection, not the server's event claims.
# psql variable quoting treats the username as a literal, never SQL syntax.
psql -X -h 127.0.0.1 -v ON_ERROR_STOP=1 -v username="$LOAD_USERNAME" -At \
    -f benchmarks/load/verify-journey.sql > "$result/durable.txt"
grep -qx '5|5|5' "$result/durable.txt"
awk -F, '$1=="operation" && $2~/^[0-9]+$/ {print $2 "," $3 "," $4 "," $5}' "$result/results.csv" > "$result/expected-receipts.csv"
[[ $(wc -l < "$result/expected-receipts.csv") == 5 ]]
: > "$result/receipt-checks.txt"
while IFS=, read -r account epoch operation revision; do
    psql -X -h 127.0.0.1 -v ON_ERROR_STOP=1 -v username="$LOAD_USERNAME" \
        -v account="$account" -v epoch="$epoch" -v operation="$operation" -v revision="$revision" -At \
        -f benchmarks/load/verify-journey-receipt.sql >> "$result/receipt-checks.txt"
done < "$result/expected-receipts.csv"
[[ $(grep -c '^1$' "$result/receipt-checks.txt") == 5 ]]
printf 'journey_durable_ok\n'
