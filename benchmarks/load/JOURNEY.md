# Authenticated journey smoke test

This checkpoint runs one bounded Briev client through registration, login,
profile/catalogue hydration, WebSocket setup, five serial ratings and logout.
The fifth rating crosses cold start. Each operation requires independently
validated admission, save acknowledgement and recommendations, matched by
account, server epoch, revision, operation ID (where present), and expected
worker generation. A separate PostgreSQL connection verifies all five durable
ratings and exact receipt identities after the client exits.

## Run

Use WSL/Linux, clang 18, PostgreSQL client tools and matching MovieLens 100K
`u.data`/`u.item`. The compiler requires the four fixes recorded in the checkpoint
evidence. `BRIEV_HOME` must match its stdlib/config; exporting it is necessary
in addition to passing the compiler path.

```bash
export BRIEVC=/path/to/verified/brievc
export BRIEV_HOME=/path/to/matching/compiler/checkout
bash benchmarks/load/build-journey.sh
bash benchmarks/load/check-journey.sh
export PGUSER=your_test_role PGDATABASE=your_test_database
export UDATA_PATH=/path/to/ml-100k/u.data UITEM_PATH=/path/to/ml-100k/u.item
export LOAD_SERVER=/path/to/built/server LOAD_PORT=18995 LOAD_GENERATION=1
bash benchmarks/load/run-journey-smoke.sh
JOURNEY_VALGRIND=1 JOURNEY_RESULT_DIR=target/journey-memory \
  bash benchmarks/load/run-journey-smoke.sh
```

Use an isolated initialized test database with the application's schema and
supported PostgreSQL authentication. The script starts and stops its own server
process group, generates unique test credentials and leaves the account/ratings
in the database as evidence. It never resets a schema. The server must have
exclusive traffic during the run: expected revisions are 1 through 5. Optional
`LOAD_USERNAME` and `LOAD_PASSWORD` must be 8–64 lowercase letters, digits,
underscores or hyphens. Do not reuse an existing account.

The current server exposes an opaque database snapshot identity during hydration
but numeric worker generation tags in prediction events. Set `LOAD_GENERATION`
from the known server configuration (the initial worker is 1). The client logs
the snapshot identity separately; it does not infer the expected generation from
the prediction it is checking. Refresh is delayed to 3600 seconds for this test.

## Results and limits

`target/journey-smoke/` contains results.csv, input binary/dataset hashes,
non-secret environment details, server output and independent SQL checks.
`journey_ok` plus `journey_durable_ok` means the entire journey passed. Client
failure, missing stage, malformed payload, stale-only traffic, database mismatch
or timeout fails the command. Admission/save/prediction times are measured from
sending that operation. Completion is the last required stage, not necessarily
the prediction. These are functional smoke measurements, not capacity results.

The independent oracle checks payload shape, rating delta, cold-start behavior,
five unique in-range unrated recommendations, finite scores and ranking order.
It does not recompute the model's numerical predictions. Duplicate fields fail;
stale/foreign events cannot complete an operation; failures remain sticky.

Transport is loopback HTTP and the application's exact WebSocket handshake
profile, with Content-Length bodies, fresh random client nonce/masks, bounded
buffers and 30-second whole-operation deadlines. Controlled peers exercise
coalesced and bytewise frames, ping, masked/fragmented/truncated frames, wrong
accept hashes, stalls and connection refusal. TLS, chunked HTTP, fragmented
WebSocket message assembly, reconnect/retry, multiple users, arrival scheduling,
capacity curves and long endurance runs remain later checkpoints.

The shell handles process orchestration and SQL verification. All HTTP,
WebSocket, workload and event-oracle behavior is Briev using stdlib codecs,
without importing server validation logic.

See the [verified checkpoint evidence](../../docs/plans/2026-11-06-authenticated-load-journey-results.md) for exact compiler/source pins and results.
