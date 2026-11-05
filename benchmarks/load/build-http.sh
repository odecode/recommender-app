#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${BRIEVC:?Set BRIEVC to the verified compiler executable}"
: "${BRIEV_HOME:?Set BRIEV_HOME to its matching compiler/stdlib checkout}"
out=${LOAD_BUILD_DIR:-target/http-load}
mkdir -p "$out"
for source in benchmarks/load/http_load.bv benchmarks/load/probes/catalogue.bv \
    benchmarks/load/probes/http_once.bv benchmarks/load/probes/http_peer.bv; do
    name=$(basename "$source" .bv)
    "$BRIEVC" build "$source" --stdlib-path "$BRIEV_HOME/lib" --config-dir "$BRIEV_HOME/config" \
        --out "$out" > "$out/$name.build.log" 2>&1 || { cat "$out/$name.build.log" >&2; exit 1; }
done
sha256sum "$BRIEVC" "$out/http_load" "$out/http_peer" > "$out/binaries.sha256"
"$out/catalogue"
