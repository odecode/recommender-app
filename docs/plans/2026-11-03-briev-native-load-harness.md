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

## Periodic collector increment

Add a standalone Briev collector using the existing monotonic arrival scheduler
and process observations. Stream raw CSV rows without retaining history; record
missed sample arrivals, bracket timestamps, identity and read errors. Query Linux
auxiliary-vector page size and clock frequency rather than assuming units.
Initial mode monitors one explicit PID (or itself for validation); process-tree
discovery remains separate. Validate schema, known errors, scheduling and a live
run before claiming this collector ready for endurance measurements. Update the
load README with configuration and limits; no app capacity claim is made.

Collector functional gate is green: success/error CSV rows have 19 fields,
independent units and ordered timestamps; failed reads exit 2. The self-preflight
and Valgrind checks found retained file, format and parsed-value allocations.
Compiler work is tracked in 2026-11-03-collector-lifetime-closure.md; no soak
readiness is claimed. While those fixes validate, add bounded per-operation
latency/outcome accounting with reusable attempt slots, duplicate-completion
rejection and separate scheduled-to-finish, service and scheduling-lag histograms.
Synthetic gates must cover success, application/transport/validation failure,
timeout and unfinished requests before attaching real network journeys.

Validation checkpoint: collector schema/unit/error gates and attempt accounting
pass. Attempt gates cover overlapping/out-of-order completions, slot reuse, all
five outcomes, per-outcome latency distributions, pending denominators and 11
invalid lifecycle/timestamp/overflow cases. The 5,000-sample memory preflight
remains a failed readiness gate; no endurance or backend capacity claim follows.

## 2026-11-04 — collector memory closure

The compiler now derives nonescaping allocation regions and reclaims actual
allocations at proved call boundaries. Container images and active payloads are
tracked independently of caller destinations and borrowed/static values. The
collector source contains no manual-free workaround. Native safety fixtures
cover late-used/returned aliases, borrowed heap/static strings, nested enums,
caller-retained fields, recursion and early exits. Allocator bookkeeping also
covers explicit free across suspended scopes, realloc and allocation failure.

All nine `benchmarks/load/check-memory.sh` cases pass with zero definite/indirect
loss and zero Valgrind errors. Only the process-lifetime 65,536-byte stdout buffer
remains reachable. The full `benchmarks/load/check.sh` functional gate passes,
including schema, units, ordered timestamps, missing-process errors, scheduling
and attempt accounting. Prior failed-read and memory observations above remain
historical evidence; this checkpoint supersedes their readiness verdict.

Two self-preflights each emitted 5,000 successful, 19-column rows at 500 Hz.
Run 1 RSS was 337→369 pages and stayed at 369 after row 1,000; run 2 was 335→335
and stayed at 335. Virtual memory stayed at 3,989,504 bytes after row 1,000 in
both runs (4,096-byte pages, 100 clock ticks/second). These are bounded-memory
results, not throughput or backend-capacity results. Raw CSV and summary:
`target/load-memory/preflight-5000-{1,2}.csv`, `preflight-summary.json`.

Compiler SHA-256: `f5ba791191c856209da10038260565438ade299ef68317f5165fba97316f9ebe`;
collector SHA-256: `546751f383480194bf2635f932bf335f136754b57b07b666509529fdbb4e0cec`.
Compiler design/validation record:
`C:/Users/wotto/code/briev-lang/docs/plans/2026-11-04-collector-reclamation-closure.md`.
Continue with incremental client transport and one verified real user journey;
worker discovery, PSS and sustained backend campaigns remain ahead.

Final compiler verification checkpoint (same day): entry scopes now reject
unclassified global initialization and include reactor-condition effects.
Wasm allocator/store width gates also drove general representation fixes.
The final native build again passes all nine Valgrind cases with zero loss or
errors. Both repeated 5,000-row runs remain flat after warmup: run 1 RSS
323→355 pages (355 constant after row 1,000), run 2 346→378 (378 constant).
Virtual memory is 3,989,504 bytes after warmup in both. CSV identity, sample
indices, errors, 19-column schema, units and ordered times were checked.
Raw final files replace the generated preflight artifacts named above.

Final compiler SHA-256:
`5a1025d902a5ba719ef74ad502a6be0c5b1c20411867660763657aa14279dffe`.
Final collector SHA-256:
`285f48f0c08b327b499bacd0ee7027300e3992db856da8f7fbbeaeda375eb37a`.
Wasm collection/JSON and object-layout gates and native allocation/alias
regressions pass. Kani cannot start on the executor's older glibc; no formal
verification claim is made. Compiler library/determinism results are recorded
in the compiler closure plan. Backend capacity and endurance remain unmeasured.

Final compiler build after regression corrections:
`d2582dd65100673fd48f4f6c976a7e6dfb7668356b939a444fac162f522875ff`.
It emits the same collector hash recorded in the final checkpoint. Library
verification passes 3,459 tests with only the delegated source sweep excluded;
native and both wasm integrations pass. Full IR determinism passes seven
programs. The collector memory blocker is closed in the working checkout.
