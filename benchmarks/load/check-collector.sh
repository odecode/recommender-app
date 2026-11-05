#!/usr/bin/env bash
#===----------------------------------------------------------------------===#
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#===----------------------------------------------------------------------===#
# Reproducible collector checkpoint, not a target-capacity benchmark.
set -euo pipefail
cd "$(dirname "$0")/../.."
compiler_root="$(cd "${BRIEV_ROOT:-../briev-lang}" && pwd)"
compiler="$(realpath "${BRIEVC:-$compiler_root/target/release/brievc}")"
export BRIEV_ROOT="$compiler_root" BRIEVC="$compiler"
export BRIEV_HOME="$compiler_root" BRIEV_CONFIG_DIR="$compiler_root/config"
output="$PWD/target/load-collector-checkpoint"
mkdir -p "$output"
# Windows-created worktrees contain an absolute Windows gitdir path. Resolve
# it for the WSL reader without rewriting shared Git metadata or configuration.
repo_git() {
    local root="$1" gitdir
    shift
    if [[ -f "$root/.git" ]]; then
        gitdir="$(sed -n 's/^gitdir: //p' "$root/.git" | tr -d '\r')"
        if [[ "$gitdir" =~ ^[A-Za-z]:[/\\] ]] && command -v wslpath >/dev/null; then
            git --git-dir="$(wslpath -u "$gitdir")" --work-tree="$root" "$@"
            return
        fi
    fi
    git -C "$root" "$@"
}
compiler_revision="$(repo_git "$compiler_root" rev-parse HEAD)"
app_revision="$(git rev-parse HEAD)"
compiler_hash="$(sha256sum "$compiler")"
# Declared acceptance limits: 64 pages of post-warmup RSS variation, no VM
# growth. These are readiness thresholds, not measured platform guarantees.
rss_limit="${LOAD_PREFLIGHT_RSS_PAGES:-64}"
vm_limit="${LOAD_PREFLIGHT_VM_BYTES:-0}"
[[ "$rss_limit" =~ ^[0-9]+$ && "$vm_limit" =~ ^[0-9]+$ ]] || {
    echo 'Preflight memory limits must be nonnegative integers.' >&2; exit 64;
}
{
    printf 'compiler=%s\nstdlib_root=%s\n' "$compiler" "$compiler_root"
    printf 'compiler_root_revision=%s\n' "$compiler_revision"
    printf 'app_revision=%s\n' "$app_revision"
    printf 'samples=5000\nrate_hz=500\nwarmup=1000\nrss_limit_pages=%s\nvm_limit_bytes=%s\n' "$rss_limit" "$vm_limit"
    printf '%s\n' "$compiler_hash"
} > "$output/provenance.txt"
find "$compiler_root/src" "$compiler_root/lib" "$compiler_root/config" \
    -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > "$output/source-files.sha256"
sha256sum "$compiler_root/tests/fixtures/load/file_descriptor_lifetime.bv" \
    >> "$output/source-files.sha256"
find "$PWD/benchmarks/load" -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum \
    > "$output/harness-files.sha256"
bash benchmarks/load/check-collector-validator.sh
bash benchmarks/load/check.sh | tee "$output/functional.log"
bash benchmarks/load/check-memory.sh | tee "$output/memory.log"
"$compiler" build "$compiler_root/tests/fixtures/load/file_descriptor_lifetime.bv" \
    --stdlib-path "$compiler_root/lib" --config-dir "$compiler_root/config" \
    --out "$output" > "$output/descriptors.build.log" 2>&1
head -c 20000 /dev/zero > "$output/growth"
(
    cd "$output"
    timeout 90s valgrind --leak-check=full --errors-for-leak-kinds=definite,indirect \
        --error-exitcode=91 --log-file=descriptors.valgrind ./file_descriptor_lifetime
) > "$output/descriptors.stdout"
grep -Fxq file_descriptors_stable "$output/descriptors.stdout"
printf 'PASS descriptor lifetime (640 reads, Valgrind)\n'
sha256sum target/load-memory/collect >> "$output/provenance.txt"
for run in 1 2; do
    LOAD_PID=0 LOAD_HZ=500 LOAD_SAMPLES=5000 timeout 60s target/load-memory/collect \
        > "$output/preflight-$run.csv"
    awk -v rows=5000 -v warmup=1000 -v pages="$(getconf PAGESIZE)" \
        -v ticks="$(getconf CLK_TCK)" -v rss_limit="$rss_limit" -v vm_limit="$vm_limit" \
        -f benchmarks/load/validate-collector.awk "$output/preflight-$run.csv" \
        > "$output/summary-$run.csv"
    printf 'PASS collector preflight %s (5000 samples)\n' "$run"
done
sha256sum --check --status "$output/source-files.sha256"
sha256sum --check --status "$output/harness-files.sha256"
[[ "$(sha256sum "$compiler")" == "$compiler_hash" ]] || {
    echo 'Compiler binary changed during the checkpoint.' >&2; exit 1;
}
printf 'PASS collector checkpoint: %s\n' "$output"
