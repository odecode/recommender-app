# Load harness

Work in progress. The arrival scheduler and process sampling primitives are
implemented; network users, periodic collection, reports and the campaign
controller are not yet implemented.
There are no capacity or endurance measurements yet.

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
