# Controlled transport checkpoint

Run from the application repository on Linux x86-64:

```sh
BRIEV_ROOT=../recommender-compiler-carveouts/load-transport-verified \
BRIEVC=/home/otto/briev-load-tools/transport-brievc-final \
bash benchmarks/load/check-transport.sh
```

The compiler/stdlib must include the tuple representation, client lifetime
analysis and nonblocking transport changes. The script records compiler and
source hashes in `target/load-transport-checkpoint/provenance.txt`.

Upstream changes: [tuple values #65](https://github.com/Randozart/briev-lang/pull/65),
[lifetime proofs #66](https://github.com/Randozart/briev-lang/pull/66), and
[transport APIs #67](https://github.com/Randozart/briev-lang/pull/67).

Four controlled-peer probes verify:

- Partial sends, backpressure/EAGAIN, unchanged read length on EAGAIN, and EOF.
- Split binary reads, readable bytes accompanying hangup, and broken-peer EPIPE
  without SIGPIPE terminating the process.
- Successful loopback TCP connection and refusal on an ephemeral reserved port,
  using readiness followed by SO_ERROR.
- Poll readiness clearing, invalid descriptors, finite waits, and resource
  cleanup. Eleven invalid bounds/lifetime cases must trap.

Every successful probe runs under Valgrind and rejects memory errors,
definite/indirect leaks, or descriptors opened by the process left at exit.
Inherited descriptors are permitted, including Valgrind's log descriptor.
The process-lifetime stdout buffer remains reachable.

`ByteBuf.put_u8` returns an updated buffer view. The backpressure probe retains
that result on each iteration; discarding it leaves the logical length stale.

This checkpoint validates the transport foundation. It does not yet drive an
HTTP user journey or measure application capacity. Next: attach bounded
connection/write/read states to the arrival scheduler and attempt accounting,
then validate one real request/response journey before increasing offered load.
