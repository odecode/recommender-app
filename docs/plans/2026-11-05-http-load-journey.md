# Scheduled catalogue HTTP journey — 2026-11-05

Implement a Briev-only, fixed-rate GET /movies runner using the existing arrival
scheduler, attempt slots, histograms, nonblocking sockets and finite polling.
Use bounded concurrent slots, fresh connections, bounded headers/body, explicit
connect/write/read states and an absolute per-attempt deadline. Stop admitting
at the requested arrival count and drain existing attempts to their deadlines.
Report offered/missed/started/finished/outcomes, latency and scheduling lag.

First add reusable strict Content-Length response framing to stdlib on a clean
feature branch. This profile supports HTTP/1.0 and HTTP/1.1 final responses;
reject transfer encoding, ambiguous/duplicate lengths, oversized/truncated
responses and malformed header syntax. No TLS, chunked decoding or redirects.
Incrementally test split bytes, malformed framing, bounds and EOF.

Then implement the transport state machine and independent catalogue JSON
validation (expected item count, contiguous IDs and nonempty titles). Controlled
Briev peers must exercise split responses, refusal, truncation, malformed data,
non-200 status, timeout and saturation. Run Valgrind and resource checks before
using numbers. Finally start an owned recommender server on an explicit local
port with the dedicated load database and run a small offered-rate experiment.
Do not touch the demo database or stop unrelated processes. Record exact sources,
binaries, configuration and results; local smoke results are not capacity claims.

Update load usage and result-schema documentation and the workflow task ledger.
Compiler bugs follow WORKFLOW's minimal repro, clean fix branch and PR flow;
do not work around compiler defects in the client. Final required compiler
suites follow functional application verification, with the source conformance
sweep still delegated to CI. Preserve existing dirty files.

Completion: the bounded catalogue journey and controlled/memory gates pass;
the final real-app smoke completes 25/25 requests with zero misses or failures.
Compiler fixes and response framing are published as PRs #68–#71, with clean
integration `fd52b03f`. See `2026-11-05-http-load-checkpoint-results.md` for hashes,
commands, verification and limitations. The run uses the existing server binary
and existing isolated integration-test database; it does not establish a fresh
server build, capacity, a rating/save/recommendation journey, or endurance.
