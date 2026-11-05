#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${PGUSER:?Set a role for an isolated test database}"
: "${PGDATABASE:?Set an isolated test database; never use the demo database}"
: "${UDATA_PATH:?Set the MovieLens u.data path}"
: "${UITEM_PATH:?Set the matching u.item path}"
: "${LOAD_PORT:?Set an unused loopback test port}"
out=${LOAD_BUILD_DIR:-target/http-load}
server=${LOAD_SERVER:-target/http-load-server/server}
result=${LOAD_RESULT_DIR:-target/http-smoke}
mkdir -p "$result"
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
sha256sum "$server" "$out/http_load" "$UDATA_PATH" "$UITEM_PATH" > "$result/inputs.sha256"
printf 'database=%s\nrole=%s\nport=%s\n' "$PGDATABASE" "$PGUSER" "$LOAD_PORT" > "$result/environment.txt"
: > "$result/server.log"
setsid env PORT="$LOAD_PORT" MAX_CONNECTIONS=64 REFRESH_SECONDS=300 "$server" > "$result/server.log" 2>&1 &
server_pid=$!
for step in {1..1200}; do
    grep -q 'Recommender listening' "$result/server.log" && break
    kill -0 "$server_pid" 2>/dev/null || { cat "$result/server.log" >&2; exit 1; }
    sleep .1
done
grep -q 'Recommender listening' "$result/server.log"
status=0
LOAD_HZ=${LOAD_HZ:-5} LOAD_REQUESTS=${LOAD_REQUESTS:-25} LOAD_SLOTS=${LOAD_SLOTS:-4} \
    LOAD_TIMEOUT_MS=${LOAD_TIMEOUT_MS:-2000} LOAD_ITEMS=1682 "$out/http_load" > "$result/results.csv" || status=$?
cat "$result/results.csv"
exit "$status"
