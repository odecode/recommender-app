#!/usr/bin/env bash
# Native memory-correctness checks live with the engine in tools/briev-load.
set -euo pipefail
cd "$(dirname "$0")/../.."
compiler_root="$(cd "${BRIEV_ROOT:-../briev-lang}" && pwd)"
compiler="${BRIEVC:-$compiler_root/target/release/brievc}"
BRIEV_ROOT="$compiler_root" BRIEVC="$compiler" bash tools/briev-load/check-memory.sh