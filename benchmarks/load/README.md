# Load harness

For a fresh Linux setup or a new agent, start with
[docs/agent/START-HERE.md](../../docs/agent/START-HERE.md).

The scheduler, process sampler/collector, scheduled catalogue HTTP client and
bounded authenticated five-rating journey are implemented and verified.
See [HTTP-LOAD.md](HTTP-LOAD.md) and [JOURNEY.md](JOURNEY.md). Multi-user scheduled
authenticated journeys, campaign reporting, capacity and endurance remain open.
The sections below describe the accounting and collector foundations.

`metrics.bv` tracks reusable attempt slots and per-operation admission,
completion, in-flight and outcome counts. Latencies include all completions,
including timeouts, with separate distributions for each outcome. Total
latency starts at the intended arrival; service latency starts at dispatch.
Scheduling lag includes every started attempt, including those still pending.
Histograms retain counts, overflow and maximum values; their fixed bin width
defines quantile precision. Invalid lifecycle transitions trap. These are
accounting primitives; network journeys and report serialization remain open.

The workload code is Briev. `check.sh` is build/test tooling, not the load
generator. On Linux or WSL, point it at a compiler built from the matching
Briev checkout and make LLVM tools available on PATH:

```sh
BRIEV_ROOT=../briev-lang BRIEVC=/absolute/path/to/brievc \
    bash benchmarks/load/check.sh
```

The scheduler separates offered demand, dispatched actions and missed arrivals.
`arrival_schedule(start_ns, rate)` accepts a nonnegative monotonic start time
and 1–1,000,000,000 actions per second. Arrival zero is due at the start time.
Poll only at or after that time. `arrival_poll(schedule, now_ns, capacity)`
returns the first arrival index, number to dispatch and number missed. It
updates the schedule in place. Time must never move backward.

`journey_pool.bv` (2026-11-06) adds bounded multi-user journey accounting: one
pool per run, slot-based user states and stage transitions that run exactly in
the declared order (register → login → hydrate → catalogue → upgrade → ratings
→ logout). Arrivals the bounded pool cannot admit are counted as missed and
never queued. Stages and ratings trap on invalid lifecycle use; a stage may
finish at most once, in order. Rating operations are serial per account with
explicit outcome classes: ok, rejected, transport, timeout, validation and
uncertain. Uncertain outcomes (connection loss with a pending operation) are
counted but never measured — no histogram receives invented samples; pending
operations finish with an outcome instead of disappearing. Separate
admission/save/prediction histograms reference the acceptance instant, the
measurement contract's three denominator surfaces. Arrival timestamps and lag
remain separate from per-rating timestamps, and a successful rating requires
accepted, saved and predicted evidence. `journey_pool_gate` pins a
three-journey synthetic walk (positive) and `journey_pool_limits_gate` traps
fifteen invalid lifecycle cases (double arrival, stage skip, rating before
stage, serial violations, duplicate finish, empty failure reason, pending
logout, dispatched > scheduled, unknown outcome, or success without evidence).

Capacity is the available dispatch budget at that poll, not a connection count.
Arrivals that exceed it are counted as missed and consumed. This avoids an
unbounded catch-up queue. The caller must retain separate counts for network
admission, completion, failure and timeout after dispatch.

Use `arrival_due_ns(schedule, index)` to measure scheduling lag and total
latency from the intended deadline. Deadlines use ceiling division with no
accumulated fractional-period rounding. Do not replace the scheduled timestamp
with the poll timestamp: doing so hides generator overload. Arithmetic overflow
and invalid inputs trap instead of wrapping counters or timestamps.

The gates cover fractional-rate boundaries, repeated polls, delayed polls,
zero capacity, simulated three-day elapsed time, the largest representable
timestamp, invalid rates/times/capacity and arithmetic overflow. These gates
verify scheduling arithmetic; they do not demonstrate achievable dispatch rate.

`process_metrics.bv` brackets a Linux process-stat read with monotonic clock
samples. It retains the read interval and computes CPU/fault deltas between
matching PID/start-time identities. Counter decreases, overlapping sample
intervals, changed identities and overflow return errors. Read failures remain
missing samples rather than becoming zero CPU or memory readings.

CPU is retained in clock ticks, RSS in pages and virtual memory in bytes.
Record the target machine's clock-tick frequency and page size before converting
units. CPU percentage of one core is `100 * cpu_ticks / tick_hz / elapsed_seconds`;
values above 100% are valid for a multithreaded process. RSS is approximate and
includes shared pages; it is not unique memory. The sampler gate covers process
reuse, reset counters, invalid intervals, overflow and live process observations.

`collect.bv` streams 19-column CSV with raw process counters, PID/start-time
identity, read-bracketing times, intended sample deadlines and missed arrivals.
It obtains page/tick units through `std/os/auxv.bv` and records them on every
row. Read failures produce `error` rows with blank counters; any failed read
makes the run exit 2. Configuration uses `LOAD_PID` (0/unset = self), `LOAD_HZ`
(0/unset = 1, otherwise 1–1000), and `LOAD_SAMPLES` (0/unset = 10, otherwise
1–1,000,000). Negative values are rejected. Output blocking remains visible in
the timing and missed-arrival columns. This monitors one PID; it does not yet
discover workers, measure PSS or track file descriptors.

Build it with the same explicit compiler/stdlib paths used by `check.sh`.
For a short diagnostic run after that check has built it:

```sh
LOAD_PID=12345 LOAD_HZ=1 LOAD_SAMPLES=10 target/load-tests/collect > process.csv
```

The repaired compiler passes two 5,000-sample self-preflights at 500 Hz with
flat RSS and virtual memory after warmup. Use the matching compiler checkout;
older compilers retained file results, parser storage and observations. This
checks collector memory stability; sustained backend campaigns remain ahead.

Run `bash benchmarks/load/check-memory.sh` with the same compiler environment
as `check.sh` and Valgrind on PATH. It rebuilds the programs, checks one and
twenty independent file reads, and checks a twenty-sample collector run. A
memory error or definite/indirect loss fails the check. The reports and raw
output are in `target/load-memory`. The isolated probe distinguishes file
result ownership from collector scheduling, parsing and formatting. This check
passes all nine cases with the repaired compiler. See
`docs/plans/2026-11-03-briev-native-load-harness.md` for the dated evidence.

## Repository layout (2026-11-07)

The generic engine now lives in the standalone [briev-load](https://github.com/odecode/briev-load)
tool, vendored here as the `tools/briev-load` git submodule (pinned commit). It
owns the arrival scheduler, attempt accounting/histograms, process collector, and
the protocol-neutral nonblocking HTTP/WebSocket transport.

This directory keeps only the recommender **scenario**: the authenticated
journey client and independent oracle (`journey*.bv`), the catalogue contract
(`catalogue.bv`, `http_load.bv`), durable SQL verification, and the server/journey
runner scripts. Scenario files import the engine through
`tools/briev-load/lib/*.bv`.

Fresh checkout:

```sh
git submodule update --init tools/briev-load
```

`check.sh` delegates the engine gates to `tools/briev-load/check.sh` and then
gates the recommender pool scenario. `check-memory.sh` and `check-collector.sh`
delegate to the tool. To add another application, implement a scenario against
the tool's documented contract; no engine file needs to change.
