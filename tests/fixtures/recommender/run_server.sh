#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
set -eu
cd "$(dirname "$0")/../../.."
BV=${BRIEVC:-./target/debug/brievc}
: "${PGUSER:?Set PGUSER to the dedicated test role}"
: "${PGDATABASE:?Set PGDATABASE to the dedicated test database}"
export PGUSER PGDATABASE
export PGSCHEMA=briev_server_loop_gate
out=$(mktemp -d /tmp/briev-server-gates.XXXXXX)
trap 'rm -f "$out"/*; rmdir "$out"' EXIT
"$BV" build tests/fixtures/recommender/movie_catalogue_gate.bv --out "$out"
timeout 60 "$out/movie_catalogue_gate"
"$BV" build tests/fixtures/recommender/browser_catalogue_gate.bv --out "$out"
timeout 60 "$out/browser_catalogue_gate"
for gate in reactor_gate server_json_gate server_api_gate server_io_gate server_protocol_gate server_loop_gate server_ws_protocol_gate server_property_gate; do
    "$BV" build "tests/fixtures/recommender/$gate.bv" --out "$out"
    if [ "$gate" != server_property_gate ]; then timeout 60 "$out/$gate"; fi
done

# Property probes run through the same compiled gate. Each case pins one side
# of a boundary condition, so a silent always-true helper cannot pass.
run_property_case() {
    local mode="$1" value="$2" expected="$3" fd="${4:-0}" bound="${5:-0}" row_owner="${6:-0}" query_owner="${7:-0}" closing="${8:-0}"
    local got
    got=$(PROPERTY_MODE="$mode" PROPERTY_VALUE="$value" PROPERTY_FD="${fd:-0}"         PROPERTY_BOUND_OWNER="${bound:-0}" PROPERTY_ROW_OWNER="${row_owner:-0}" PROPERTY_QUERY_OWNER="${query_owner:-0}" PROPERTY_CLOSING="${closing:-0}" timeout 60 "$out/server_property_gate")
    if [ "$got" != "$expected" ]; then
        echo "server_property_gate=$mode expected=$expected got=$got" >&2
        exit 1
    fi
    echo "server_property_gate=$mode=true"
}
run_property_case rating 3 true
run_property_case rating 0 false
run_property_case rating 6 false
run_property_case threshold 4 true
run_property_case threshold 5 false
run_property_case owner 0 true 0 1 1 1 0
run_property_case owner 0 false 0 1 1 8 0
run_property_case owner 0 false 0 1 1 1 1
run_property_case owner 0 false 0 0 7 7 0
