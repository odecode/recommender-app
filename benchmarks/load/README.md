# Load harness

Work in progress. The arrival scheduler and process sampling primitives are
implemented, along with an initial streaming process collector. Its memory
preflight found compiler/stdlib lifetime leaks, so it is not ready for a soak.
Network users, reports and the campaign controller are not yet implemented.
There are no capacity or endurance measurements yet.

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

Do not use the current collector for endurance conclusions: its 5,000-sample
self-preflight showed growing retained memory. The workstream is fixing the
underlying lifetime handling before running sustained backend campaigns.
