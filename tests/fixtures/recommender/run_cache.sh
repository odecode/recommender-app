#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
set -eu
cd "$(dirname "$0")/../../.."
BV=${BRIEVC:-./target/debug/brievc}
: "${PGUSER:?Set PGUSER to the dedicated test role}"
: "${PGDATABASE:?Set PGDATABASE to the dedicated test database}"
export PGUSER PGDATABASE
out=$(mktemp -d /tmp/briev-cache-gates.XXXXXX)
export CACHE_PATH="$out/model.snapshot"
trap 'rm -f "$out"/*; rmdir "$out"' EXIT
for gate in cache_prepared_gate cache_snapshot_gate; do
    "$BV" build "tests/fixtures/recommender/$gate.bv" --out "$out"
    timeout 90 "$out/$gate"
done
