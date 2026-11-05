# Controlled transport checkpoint — 2026-11-05

The pending transport probe now runs with a clean compiler integration. Tuple
construction and destructuring retain element types, including raw-pointer and
float representations; lifetime analysis preserves tuple metadata as well.
Socket borrowing effects and concrete explicit-receiver method effects allow
the transport scopes to reclaim temporary wrappers. Zero-copy or unknown send
flags remain conservatively capturing.

`benchmarks/load/check-transport.sh` passes all four successful probes under
Valgrind with zero errors, zero definite/indirect loss, and no newly opened
descriptors remaining. All eleven invalid-input/lifetime cases trap. The
probe's buffer-fill loop now retains the value returned by `put_u8`.

The collector regression gate also passes: functional tests, nine original
Valgrind cases, the 640-read descriptor probe, and two 5,000-sample preflights
at 500 Hz. Post-warmup RSS was constant at 369 and 365 pages respectively;
virtual memory stayed at 3,989,504 bytes. Both runs reported zero missed arrivals.
These are bounded-memory readiness results, not throughput measurements.

Validation compiler SHA-256:
`f27fa9956e56cd8dd435b8a06434146a90697f2362462d90182d555a07ddb5c6`.
Clean compiler integration: `044192d4` on `integration/load-transport-verified`,
at `../recommender-compiler-carveouts/load-transport-verified`. It includes
upstream `2d9d37b7`, the earlier collector prerequisites, and these carve-outs:

| Change | Commit | PR | Library tests passed |
| --- | --- | --- | --- |
| Tuple representation and metadata | `05d8aef7` | [#65](https://github.com/Randozart/briev-lang/pull/65) | 3,501 |
| Socket and method lifetime proofs | `59ec602e` | [#66](https://github.com/Randozart/briev-lang/pull/66) | 3,503 |
| Nonblocking stdlib transport | `1eb1d3a0` | [#67](https://github.com/Randozart/briev-lang/pull/67) | 3,499 |
| Combined integration | `044192d4` | local verification branch | 3,505 |

Each clean branch also built without warnings. The single source conformance
sweep remains delegated to CI. Kani could not start because the WSL glibc is
older than its runtime requirement; no formal-verification result is claimed.

Final merged validation also passes five native integration tests (including
O0/O3 tuple execution), independent wasm32 execution, and all ten programs in
the full IR determinism gate. Praetor introduced no new diagnostics.

Clang 17 and 18 each compile and execute all three toolchain corpus programs.
The raw matrix script reports a parity failure because the two data-driven
programs print elapsed time. Inspection of retained outputs confirms that only
the numeric values immediately after `prediction_time_ns:` and
`prediction_time_ms:` differ. Removing just those label/value pairs gives
identical semantic output for all three programs. This is a harness comparison
limitation, not a passing raw-byte matrix gate or a timing comparison.
Captured outputs are in the compiler worktree's `target/toolchain-matrix`.
The standard [MovieLens 100K input](https://files.grouplens.org/datasets/movielens/ml-100k.zip)
was used with the harness-generated similarity matrix; `u.data` SHA-256 is
`06416e597f82b7342361e41163890c81036900f418ad91315590814211dca490`.

Raw logs, binaries, CSV and provenance are under `target/load-transport-checkpoint`
and `target/load-collector-checkpoint`. This resolves the earlier tuple-type
blocker; prior investigation records remain unchanged.

Next checkpoint: one bounded HTTP journey connected to scheduled arrivals and
attempt outcomes. Worker discovery, PSS and sustained capacity campaigns remain
ahead. No backend capacity claim is made here.
