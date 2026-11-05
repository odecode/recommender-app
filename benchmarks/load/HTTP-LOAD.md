# Scheduled catalogue HTTP load

This runner sends fresh-connection `GET /movies` requests to an explicit
**loopback** port. It independently parses each successful response and checks
the catalogue size, contiguous zero-based item IDs and nonempty titles. It does
not create accounts, ratings or recommendations.

Build in WSL with the matching compiler and stdlib integration:

```bash
export BRIEVC=/path/to/verified/brievc
export BRIEV_HOME=/path/to/matching/compiler-checkout
export PATH=/usr/lib/llvm-18/bin:$PATH
bash benchmarks/load/build-http.sh
bash benchmarks/load/check-http.sh
bash benchmarks/load/check-http-memory.sh  # requires Valgrind
```

Start an isolated recommender instance, then run:

```bash
LOAD_PORT=18992 LOAD_HZ=5 LOAD_REQUESTS=25 LOAD_SLOTS=4 \
LOAD_TIMEOUT_MS=2000 LOAD_ITEMS=1682 target/http-load/http_load > result.csv
```

All six environment values are required positive integers. Limits: port 65535,
rate 10000/s, requests 1000000, slots 256, timeout 60000ms, expected items 10000.
Use a dedicated test instance and record the compiler, stdlib, app revisions,
binary hashes, dataset hashes and exact configuration alongside results.
The binary returns 0 only when every offered request succeeds, 2 for missed or
failed requests, and 70 for a fatal poll failure. Invalid configuration traps.

Scheduling starts after pool and histogram allocation. Arrivals use fixed
monotonic deadlines, not completion-driven pacing. When late, the generator
admits the earliest due arrivals that fit available slots and counts the rest
as missed. It stops after the requested offered count and drains admitted
attempts to their deadlines. There is no unbounded queue or retry.

Each slot has one socket and a reusable 266240-byte response buffer: at most
4096 header bytes and 262144 body bytes. Connections, partial writes and reads
use nonblocking syscalls and finite polling. A deadline covers connection setup,
transfer and validation, measured from actual attempt start. Scheduling lag is
measured separately and also included in total latency.

CSV records:

| Kind | Fields |
|---|---|
| `config` | port, offered rate, requested count, slots, timeout ns, expected items, header/body limits |
| `summary` | offered, missed, started, finished, successful, application errors, transport errors, timeouts, validation errors, elapsed ns |
| `latency` | distribution name, sample count, bucket width ns, overflow count, maximum ns, p50/p95/p99 inclusive bucket upper bounds |

`offered = started + missed`; `started = finished` after draining; finished is
the sum of the five outcome counters. Non-200 responses are application errors;
socket errors are transport errors; invalid HTTP framing or catalogue content
is a validation error. Timeouts remain completed failed samples. Empty latency
distributions report -1 quantiles. Histograms use 1ms buckets; overflow remains
counted and quantiles in overflow return the observed maximum. Successful
latency is reported separately so fast failures cannot improve its percentiles.

Supported HTTP profile: HTTP/1.0 or HTTP/1.1 final responses with strict CRLF and
Content-Length. Chunked, EOF-delimited, interim, TLS and redirected journeys are
not implemented. Those responses must not be counted as catalogue successes.

The controlled peer gate covers full and bytewise replies, truncated and
duplicate-length responses, wrong catalogue IDs, non-200 status, stalls,
connection refusal and slot saturation. These are correctness checks. A small
local smoke run is not a capacity benchmark; mixed account/rating/recommendation
journeys and an endurance campaign remain separate checkpoints.

`run-http-smoke.sh` starts and cleans up its own server process group. Set
`PGUSER`, `PGDATABASE`, `UDATA_PATH`, `UITEM_PATH`, and `LOAD_PORT` explicitly;
set `LOAD_SERVER` to the server executable. It records input hashes and CSV in
`LOAD_RESULT_DIR` (default `target/http-smoke`). The script does not create or
reset the database. Its default workload is 25 requests at 5/s with four slots
and a two-second timeout. Database authentication must be supported by the
server's native PostgreSQL client.
