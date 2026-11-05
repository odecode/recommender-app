# Collector readiness checkpoint — 2026-11-05

Scope: one completed load-harness checkpoint for collector correctness and
bounded memory. This does not complete network users, capacity tests or soaks.

The new `benchmarks/load/check-collector.sh` runs the functional harness suite,
nine existing Valgrind cases, a 640-read descriptor regression, and two
5,000-sample self-observations at 500 Hz. `validate-collector.awk` checks the
schema, ordered sample/timestamp/counter fields, PID/start identity, host units,
missed-arrival accounting and post-warmup memory bounds. Its independent test
accepts an explicit missed-arrival sequence and rejects 15 corruptions.

The source combination is current main 3737396b plus two independent branches:
`fix/read-file-descriptor-lifetime` and `feat/load-collector-prerequisites`.
No Rust compiler change is required. The older dirty integration tree aliases
Data-to-String while its formatter assumes a copy and frees the source; that
combination caused the prior use-after-free. Main retains the encoding copy.
The dirty tree and pending transport reproducer remain preserved.

The descriptor fix closes read_file's successfully opened fd after either EOF
or read failure and returns the original read result. Its independent probe
fails on unchanged main and passes after the fix. All 640 normal/empty/growing/
read-error/open-error calls preserve descriptor availability; Valgrind reports
zero errors and no definite/indirect loss. Upstream PR: #63.

The first combined execution passes all functional gates and nine existing
Valgrind cases. Both preflights emitted 5,000 valid rows. After sample 1,000,
RSS stayed at 379 pages and virtual memory at 3,989,504 bytes in both runs.
The runs recorded zero and eight missed arrivals respectively. Missed arrivals
remain visible; they are not silently counted as dispatched observations.
Page size was 4,096 bytes and clock frequency 100 ticks/second.

Acceptance limits are explicit: at most 64 pages RSS range after warmup and
zero virtual-memory range by default. These are configurable readiness limits,
not capacity guarantees. The only reachable allocation in the collector's
Valgrind run is its 65,536-byte process-lifetime stdout buffer.

Artifacts: `target/load-collector-checkpoint/` contains raw and summary CSV,
functional/memory logs, revisions and source/binary hashes; detailed memory
logs are under `target/load-memory/`. See
`benchmarks/load/COLLECTOR-CHECKPOINT.md` for the reproducible command and limits.
Final publication and the clean integration rerun are recorded below.

## Final verified checkpoint

Status: COMPLETE for collector readiness. Integration commit:
`68e81bf198de77c38d6acceea652df6ba3374b30` on
`integration/load-collector-verified`, checked out at
`C:/Users/wotto/code/recommender-compiler-carveouts/load-collector-prerequisites`.
The original compiler working tree is untouched by this integration.

- PR #63: https://github.com/Randozart/briev-lang/pull/63 — descriptor cleanup,
  commit `6850858a`.
- PR #64: https://github.com/Randozart/briev-lang/pull/64 — measurement primitives,
  commit `c403e943`.
- Each branch and their integration passed 3,499 library tests; the previously
  delegated full source sweep remains with upstream CI. Native integration tests,
  warning-free builds and Praetor passed.
- The complete final checkpoint command passed: validator, full functional suite,
  all ten Valgrind cases (nine original cases plus the 640-read descriptor gate),
  both preflights, and unchanged source/binary hash checks.

| Final run | Samples | Missed arrivals | RSS pages after warmup | Virtual bytes after warmup |
|---|---:|---:|---:|---:|
| 1 | 5,000 | 0 | 373–373 | 3,989,504–3,989,504 |
| 2 | 5,000 | 0 | 393–393 | 3,989,504–3,989,504 |

The final wrapper explicitly exports BRIEV_HOME and BRIEV_CONFIG_DIR for every
build. Exporting them only inside child scripts left the new descriptor compile
using the caller's default environment; the focused compile and entire checkpoint
passed after correcting this build-tool environment boundary.

Compiler SHA-256:
`ab5133c8a97ea699c629d1ce5bd00bca86f03c423675cb1d404a8042ab846bfe`.
Collector SHA-256:
`0eecb10727534a9a155d96704bbd191c1c6d1130dbfc432b4c1b97a09e554707`.
The collector hash matches the earlier successful combined candidate despite
the compiler worktree/build changing. The artifact provenance records the app's
pre-commit base plus exact harness file hashes; the new checkpoint files are
committed after their successful run.

Next checkpoint: controlled client transport, followed by one independently
validated real-server user journey. The tuple-type reproducer remains pending;
no harness workaround was added and no backend capacity claim is made.
