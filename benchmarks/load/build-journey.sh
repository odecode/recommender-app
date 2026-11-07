#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${BRIEVC:?Set BRIEVC to the verified compiler executable}"
: "${BRIEV_HOME:?Set BRIEV_HOME to its matching compiler checkout}"
export BRIEV_HOME
out=${JOURNEY_BUILD_DIR:-target/journey}
mkdir -p "$out"
for source in benchmarks/load/probes/journey_oracle.bv benchmarks/load/journey.bv \
    benchmarks/load/probes/journey_wire.bv benchmarks/load/probes/journey_transport.bv \
    benchmarks/load/probes/journey_peer.bv; do
    name=$(basename "$source" .bv)
    "$BRIEVC" build "$source" --stdlib-path "$BRIEV_HOME/lib" --config-dir "$BRIEV_HOME/config" \
        --out "$out" > "$out/$name.build.log" 2>&1 || { cat "$out/$name.build.log" >&2; exit 1; }
done
"$out/journey_oracle"
sha256sum "$BRIEVC" "$out/journey" > "$out/binaries.sha256"
