# Briev-native load and endurance harness

Date: 2026-11-03
Status: design and initial capability audit; no performance measurements yet.

## Goal and ownership

Implement controller, virtual users, host collector, statistics and report generation in Briev. Application journeys belong in benchmarks/load; reusable client transport, polling, time, statistics and process observation belong in the compiler repository stdlib. Fix compiler defects with minimal reproductions and regression tests; do not encode workarounds in the harness. Preserve unrelated working changes in both repositories.

Initial target: Linux x86-64, developed through WSL. Use a dedicated test database and dataset, never the running demo database. Only stop processes started by the harness. Record target address explicitly. Machine-separated generation is required for published capacity claims.

## Measurement contract

Track connections, active users and offered actions per second independently. Support closed user journeys and independently scheduled arrivals. Record scheduled, dispatched and completed monotonic timestamps; missed arrivals and generator scheduling lag remain visible. Bound pending requests and all telemetry buffers.

For a rating, correlate operation ID, account, epoch, revision and model generation. Measure admission, durable save, fresh recommendation and full completion separately. Record rejected, failed, timed-out, uncertain and superseded outcomes. Retries retain identity where required by the protocol; report attempt latency and total journey latency. Do not count an acceptance as a durable success. Drain pending work at stage end with a bounded deadline and report unresolved operations.

Use bounded mergeable histograms with declared precision and overflow counts. Report count, p50/p95/p99/max per operation and outcome; merge bins, never percentiles. No credentials or session tokens in output. Stream rotating raw samples and bounded diagnostic traces.

## Workload

Returning visitor: login, hydrate profile/catalogue, establish live connection, browse with think time. Active rater: submit rating, observe independent save and prediction events. Additional scenarios: registration, reconnect and uncertain outcome resolution, two sessions sharing an account, slow readers. Shared codecs are permitted; correctness assertions must be independent of server business logic.

Use seeded workload selection with popular and long-tail items, small and large profiles. Security nonces use OS entropy, not the workload PRNG. A newer revision can legitimately supersede an earlier prediction; validate latest-profile completion rather than demand every intermediate result.

## Campaign

1. Correctness smoke: 1-5 users for five minutes.
2. Concurrency staircase: 1,2,4,8... with 10-15 minute stages, refine around failure boundary.
3. Idle-connection sweep at fixed action rate; action-rate sweep at controlled connections.
4. Spike then recovery and bounded drain.
5. Fixed-population soak: eight hours, then 24-72 hours; update existing ratings.
6. Growing-population soak: controlled account/rating additions with database growth recorded.
7. Explicit fault runs: worker restart and database interruption, distinct from capacity measurements.

Capacity means sustained completion meeting configured latency/error objectives without growing backlog. Thresholds are configuration, not invented measured guarantees. Validate source revisions, hardware, dataset, build flags, database starting state, seed and workload geometry for every run.

## Monitoring

Collect process CPU deltas, RSS, periodic PSS/private memory, page faults, descriptors, network and disk activity, host pressure and database waits. Identify processes by PID and start time; include prediction, persistence and refresh children. Do not sum RSS and call it unique memory. Sample inexpensive metrics each second and expensive memory metrics less frequently. Monitor generator headroom and lag too.

Application counters: reactor delay, admitted/rejected counts by reason, pending count and oldest age, worker occupancy, save/prediction completions, refresh duration and generation transitions. Measure instrumentation overhead. Memory slope must be interpreted against retained profiles, receipts and dataset growth; compare post-warmup and post-drain states.

## Initial evidence and capability audit

- examples/recommender/server_state.bv:157-169 starts persistence and prediction child channels.
- examples/recommender/protocol_types.bv defines separate accepted, saved and prediction payloads.
- tests/fixtures/recommender/README.md documents existing HTTP/WebSocket partial-write, fragmentation and account gates.
- Compiler lib/std/net/socket.bv supplies TCP and nonblocking primitives.
- Compiler lib/std/net/http.bv exposes request parsing and server responses; its function inventory contains no HTTP response parser. Audit the rest of stdlib before declaring a missing API, then implement a general client parser if absent.
- Compiler lib/std/net/websocket.bv supplies frame decoding and masked encoding. Client handshake validation, entropy, fragmentation and lifecycle need verification.
- Compiler lib/std/os/time.bv supplies monotonic time. Its failure path returns -1 despite a nonnegative postcondition: resolve error-contract consistency before adopting it for measurement.
- WSL has /home/otto/briev-target/release/brievc, cargo, clang and a responding PostgreSQL service. Binary/source provenance and dedicated test credentials are not yet verified.
- Compiler checkout contains substantial pre-existing uncommitted modifications. No changes made there in this initial audit.

## Delivery gates

A. Audit client parsing, nonblocking connect completion, poll readiness, deadlines, cancellation, entropy, timing, process observation and histogram support. Verify compiler binary provenance and dedicated test database.
B. Add controlled Briev peers with known delays, split responses, disconnects and malformed frames. Check generator accounting and bounded memory before using its measurements.
C. Implement one complete real-server user journey with independent save and recommendation checks.
D. Add scheduling, controller and incremental result artifacts; calibrate generator capacity.
E. Add collection, instrumentation and staged runs; then soak and recovery.

Every compiler/stdlib fix gets a minimal fixture and required repository gates: cargo test --lib, cargo build, Praetor on changed directories, and relevant backend/determinism gates. Commit only intended files after applicable checks pass. No performance optimization before the prescribed actual-IR experiment.

## Baseline and results

| Baseline | Before | After |
|---|---|---|
| Full compiler runtime benchmark suite | Not run; mandatory before compiler performance changes | Not run |
| Single-user acceptance/save/recommendation | Harness not implemented | Not run |
| Concurrency and arrival-rate capacity | Not run | Not run |
| Eight-hour fixed-population soak | Not run | Not run |

Capture a clean release build and all results from benchmarks/build_and_bench.sh --runtime in the compiler repository before performance changes. Use its locked baseline comparison for regression investigations. Never substitute these placeholders for measured results.

## Documentation

Maintain this dated execution record through additive progress entries. Add benchmarks/load usage and result-schema documentation with implementation. Update app server/reactor/persistence architecture docs when instrumentation contracts change. Update Briev architecture docs for new stdlib APIs, preserve rationale comments, and log discovered defects with reproductions in BUGS.md. Historical plans remain intact.

## Execution update: native measurement prerequisites

The dedicated PostgreSQL role and database are both `briev_load`. Local
administration now works through the user's scoped sudo rule. Authentication
has not been weakened; the existing native database client still needs
password-challenge support before this database can serve a real journey.

Implemented checked monotonic time and bounded, mergeable histograms in the
Briev stdlib. The histogram exercise exposed dropped indexed collection writes,
incorrect exits from inline methods, scalar argument coercion and inline
aggregate storage defects in the compiler. General fixes are under validation;
the harness does not contain replacement storage or timing workarounds.

Current focused results: four native fixtures pass, five collection backend
tests pass, valid/invalid index integration passes, and the clock integration
passes. A further type-checking gate validates the declared writer signature.
The remaining library suite is running with a locally built current SPIR-V
validator. The user explicitly delegates the long conformance sweep to upstream
CI; it is excluded from local execution. No capacity or soak result exists yet.

Next delivery remains the incremental client transport and one verified real
user journey. Process observation also needs a real stdlib implementation:
the reserved `std/os/resource.bv` module currently supplies no functionality.

Scheduler increment: `benchmarks/load/schedule.bv` now provides fixed-rate
arrival deadlines, bounded dispatch batches and explicit missed-demand counts.
Its native gates pass fractional-rate boundaries, delayed/repeated polls,
zero capacity, three simulated days at the maximum representable rate, and
seven invalid-input/overflow cases. This validates arithmetic, not throughput.
`benchmarks/load/check.sh` supplies reproducible external-compiler build/test
commands; production workload logic remains Briev.

Compiler validation update: the remaining library suite passes 3,437 tests
with zero failures and the single delegated conformance sweep excluded.
All five native prerequisite fixtures and both clock/bounds integrations pass.
The monotonic clock change is committed as `a8434136` in the compiler checkout.

Process sampling increment: `process_metrics.bv` brackets reads with monotonic
timestamps and calculates CPU/fault deltas only across matching process
identities. Synthetic and live-process gates pass, including counter resets,
invalid sample intervals and overflow. The reusable Linux stat reader lives in
Briev's `std/os/proc_stat.bv`; it retains ticks/pages for explicit unit conversion.
Periodic export, worker discovery and private/PSS memory sampling remain ahead.
