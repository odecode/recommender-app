# HTTP catalogue load checkpoint — 2026-11-05

The implemented journey is a fresh-connection `GET /movies` against an explicitly
selected loopback port. It uses fixed scheduled arrivals, bounded slots, finite
polling and per-attempt deadlines. It validates the catalogue independently and
reports missed arrivals, all five outcomes and latency histograms. Usage and CSV
semantics are in `benchmarks/load/HTTP-LOAD.md`.

## Correctness and resource evidence

- Controlled peers: full and bytewise valid replies, truncation, duplicate
  Content-Length, non-200 status, wrong catalogue IDs, stalled responses and
  connection refusal all produce their expected counts and exit status.
- Saturation: 100 offered at 1000/s with one slot and a 200ms stalled response
  produces 99 missed arrivals and one completed timeout, with no queue growth.
- Valgrind: 50 valid responses and 50 rejected catalogues at 10/s, four slots,
  two-second deadlines: zero errors, zero definitely/indirectly/possibly lost
  bytes and no open network descriptors. A separate 100-refusal check also
  passed. The runtime's 65,536-byte stdout buffer remains reachable at exit.
- The independent response-framing gate covers 20 cases plus incremental
  arrival, limits, EOF, sticky errors and reuse. The catalogue gate covers
  required-key duplicates, invalid IDs/titles/counts and malformed JSON.

## Real application smoke

Executor: WSL2 Linux 6.18.54.1, x86-64, AMD Ryzen 7 3700U (eight visible logical
CPUs), Rust 1.99.0 and Ubuntu clang 18.1.8. Generator, server and PostgreSQL share
this host; these results cannot establish machine-separated backend capacity.

An initial run completed all 25 catalogue requests at 5/s, four slots, two-second
deadlines and 1682 expected items, with zero misses or failures. This establishes
end-to-end functionality, not sustainable capacity. Service latency includes
JSON parsing and validation in the generator. Initial timings are provisional:
compiler builds were running concurrently.

The server was the existing `target/recommender-demo/server` executable built
November 3, SHA-256
`c7b88cacadc1c87fbdf1b55f2bf08a3ab074f0aa3a1d861aa5c92a136bb6a185`.
It was started as an owned process group on port 18992 and stopped after the run.
The isolated integration database was `briev_recommender_i01`, role `briev_test`;
no schema reset or authentication change was performed. A dedicated load role
could not authenticate through this server's native PostgreSQL client, so the
existing integration-test role/database was used explicitly instead.

Dataset SHA-256:

| Input | SHA-256 |
|---|---|
| MovieLens u.data | `06416e597f82b7342361e41163890c81036900f418ad91315590814211dca490` |
| MovieLens u.item | `553841ebc7de3a0fd0d6b62a204ea30c1e651aacfb2814c7a6584ac52f2c5701` |

## Compiler findings and limits

Clean compiler integration: `fd52b03fe19a419755d14db0a6f75886bbf6c10f`, branch
`integration/http-load-final`, worktree
`../recommender-compiler-carveouts/load-http-final`. It extends the prior
`044192d4` transport integration with these main-based carve-outs:

| Change | Commit | PR | Independent library tests passed |
|---|---|---|---|
| Structured-value lifetime facts | `632f602e` | [#68](https://github.com/Randozart/briev-lang/pull/68) | 3505 |
| Statement-match fallthrough | `bb69d282` | [#69](https://github.com/Randozart/briev-lang/pull/69) | 3499 |
| Single field-receiver evaluation | `3fb01c97` | [#70](https://github.com/Randozart/briev-lang/pull/70) | 3499 |
| Incremental response framing | `400952a2` | [#71](https://github.com/Randozart/briev-lang/pull/71) | 3499 |

Each clean branch passed its native regression at O0 and O3 and built without
warnings. The merged integration passes 3511 library tests. Praetor's changed-file
comparison reports the same existing diagnostics, with none added.

The journey exposed three general defects: statement-match fallthrough inherited
the last arm's termination flag; field receivers were evaluated twice; and
structured-value lifetime analysis lost type/provenance facts or introduced
false aliases. Each has a separate main-based fix branch. The HTTP response
framer has its own stdlib-only feature branch. The integration also contains the
previous transport/tuple/borrowing prerequisite branches.

A fresh full-server compilation was attempted but did not complete during the
experiment; it spent substantial time in the ownership graph solver. The real
run therefore does **not** verify a current-source server rebuild. No compiler
performance improvement is claimed. Kani could not start because installed
cargo-kani requires GLIBC_2.32/2.33/2.34 absent from this WSL environment. The long
source-conformance sweep remains delegated to CI as instructed.

Mixed authentication/rating/recommendation journeys, keep-alive, TLS/chunked
responses, a sustained saturation campaign and endurance/resource-growth
measurements remain later checkpoints.

## Final pinned run

The final compiler is `/home/otto/briev-load-tools/http-load-brievc-final`:
`b9866394672f37f1a3f3e0fd74c3625362945f9fa1d0c4d35262b95dbcaad7b7`.
It was built from the clean integration above. The final client SHA-256 is
`bd8530ddc43ae588405b0f0e8d77cf7cb52b905a623701955422a75255cd1470`;
the controlled peer is
`7bd5baaab315103e8719b4dbcf639b985c69250c318151bc94719eb8fef6f6fd`.

Rebuilding with `build-http.sh`, then running `check-http.sh` and
`check-http-memory.sh`, passes all controlled/accounting gates and both 50-request
Valgrind cases. Non-stalling peer processes must exit successfully as well as
producing the expected client outcome. The final real-server repeat uses the
same server, database and dataset recorded above:

```csv
config,port,hz,requests,slots,timeout_ns,items,header_limit,body_limit
config,18992,5,25,4,2000000000,1682,4096,262144
summary,offered,missed,started,finished,ok,application,transport,timeout,validation,elapsed_ns
summary,25,0,25,25,25,0,0,0,0,4837775978
```

**Provisional smoke timings, not capacity measurements:** total latency p50/p95/
p99 bucket upper bounds are 33,999,999 / 42,999,999 / 64,999,999 ns, using 1ms
buckets. Observed total maximum is 64,350,435 ns; scheduling-lag maximum is
1,237,998 ns. All 25 attempts succeeded and no histogram overflow occurred.
Raw final CSV, server log, environment and input hashes are retained under
`target/http-smoke-final`; controlled cases and memory logs are under
`target/http-load`. Owned test servers and peers were cleaned up.

Final compiler checks pass 3511 library tests and all 10 tests across nine
integration-test targets, including native O0/O3 execution, enum/list retention,
descriptor availability, integer-output allocations, transport and wasm32 tuple
verification. The full ten-program IR determinism gate passes. Final build has
no warnings. The single long source-conformance sweep remains delegated to CI.

Clang 17 and 18 each compile and execute all three toolchain-matrix programs.
The raw matrix **fails** byte parity because elapsed-time values differ. A
retained-output copy of the same harness changes only artifact retention; its
outputs match after replacing only numeric values following the exact
`prediction_time_ns:` / `prediction_time_ms:` labels. All other output remains
byte-equivalent. This is a comparator limitation, not a passing raw-byte gate.
Evidence: compiler `target/http-toolchain-matrix`, with `semantic-parity.txt`.
