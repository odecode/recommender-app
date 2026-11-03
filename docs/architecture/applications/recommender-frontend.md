# Recommender browser frontend

`examples/recommender/app.rbv` provides asynchronous registration/login,
account hydration, a movie catalogue, account-owned ratings, a five-distinct-
rating cold-start gate, and the latest WebSocket recommendation set. Movie
numbers displayed in the UI are one-based; the HTTP/WebSocket protocol uses
zero-based item IDs. Updating an existing rating does not count as another
distinct movie.

Choosing a movie reads its title and updates selection flags using only the
visible page (at most 12 cards), preserving titles, ratings and page order.
Choosing does not filter the catalogue, recompute rating overlays, or send a
request. Search, pagination and profile updates remain responsible for
refreshing catalogue contents.

The native `GET /movies` endpoint returns the ordered MovieLens catalogue with
each zero-based `item_id` and UTF-8 `title`. The UI improvement plan in
`.kiro/specs/recommender-app/tasks-uiux-improvement.md` migrates the current
numeric display to browsable, searchable title selection and resolves live
recommendation IDs through that catalogue.

Account requests use `POST /v1/register` and `POST /v1/login`. The native
server accepts those routes and their unversioned aliases. Login returns the
protocol version, authenticated account identity, session token and process
epoch; the following `/v1/state` response carries a versioned profile envelope.
The server epoch remains stable through state copies and changes after restart,
so browser profile checks are scoped to the live server process.

The browser keeps an operation record per save. It paints that rating locally
before sending, marks it pending, and submits over WebSocket when the live
channel is open. Otherwise it sends the same operation ID through asynchronous
HTTP. A transport failure becomes uncertain and is reconciled by operation
status; the browser never silently replays a possibly accepted write. Definite
rejections remain unsent, while accepted, saved, failed, retrying, discarding,
and discarded states are tracked separately. Save confirmation only changes
save status; it does not render recommendations. Recommendations update only
when a prediction matches the current profile revision, and the previous list
stays visible while that prediction is pending.

Login, profile hydration, catalogue reads, saves, operation resolution and
reconnect are asynchronous HTTP requests. The host keeps bounded request
handles outside WASM's String ABI; completion events are checked against the
current session generation before their bodies are applied. Logout explicitly
asks before leaving unresolved operations, cancels owned requests and the live
channel, invalidates stale callbacks, cancels the reconnect timer and clears
account state. A `beforeunload` warning is active while local operations remain
unresolved.

## Run locally (Linux/WSL)

From the repository root, with PostgreSQL accepting the configured local test
role on 127.0.0.1:5432 and the MovieLens `u.data` file available:

```bash
source ~/.cargo/env
CARGO_TARGET_DIR=~/briev-target cargo build --release
~/briev-target/release/brievc build examples/recommender/server.bv --out /tmp/briev-recommender
PATH="/usr/lib/llvm-17/bin:$PATH" ~/briev-target/release/brievc build examples/recommender/app.rbv --split --out target/recommender-web
PGUSER=briev_test PGDATABASE=briev_recommender_test UDATA_PATH=/path/to/u.data /tmp/briev-recommender/server
```

In another terminal:

```bash
python3 -m http.server 8081 --bind 127.0.0.1 --directory target/recommender-web
```

Open `http://localhost:8081/app.html`. The backend defaults to port 8080.
An alternate backend can be selected with
`app.html?api=http://127.0.0.1:18080`. The frontend and backend have separate
listeners. The backend's `CACHE_PATH` controls its persisted model; a cold
start builds it before listening. See recommender-server.md for configuration
and refresh ownership. Run database gates only against a dedicated test DB.

## Host and lifetime boundaries

The browser prelude supplies portable casting/formatting and iterator modules,
without Linux process/environment/syscall lanes. `std/web/fetch.bv` retains the
legacy synchronous `fetch` helpers for compatibility and adds bounded async
request handles for interactive flows. Promise objects never cross the WASM
String ABI: JavaScript stores the response, then dispatches a window event with
the numeric handle. The Briev app copies the body and releases the handle.
HTTP error bodies retain their status and reach Briev for application-level
diagnostics.

`std/web/websocket.bv` wraps per-channel host handles. Each channel owns a bounded
FIFO (128 text messages / 1 MiB UTF-8), its error and event name. Queued browser
notifications recheck channel ownership, preventing a closed/logged-out channel
from emitting stale callbacks. Binary/oversized messages close the channel.
Unexpected closure starts one owned timer, backing off from 250 ms to 8 seconds;
reconnect reloads persisted account state before replacing the channel. Successful
open resets backoff. Each notification drains pending updates in order, so the
last received recommendation set becomes the displayed set.

The host allocator starts beyond initial WASM memory to preserve globals/stack,
grows by pages and coalesces free blocks. Realloc/calloc/copy/fill and String doors
share checked pointer/range handling. Boxed payload words retain their existing
64-bit layout while target-native registers and parameters use explicit casts.
Collection state objects are heap allocated so initialization frames cannot
invalidate their handles. View snapshots grow with actual collection cardinality;
they are consumed synchronously and reused within the WASM instance.

Frontend analysis computes possible global writes through direct helper calls
to a fixed point. Commit flushes consume these sets to update views. These are
conservative DOM invalidation sets, not concurrency or optimization proofs.
String item views decode UTF-8, render values, and reconcile DOM order to the
latest item order. Recommendation movie strings are unique identity keys.

## Verification

`tests/web_host_transport.mjs` covers HTTP verbs/error bodies, channel isolation,
FIFO/limits/lifecycle and timer cancellation. `tests/web_heap.mjs` covers memory
growth, stack isolation, coalescing, realloc, zeroing and invalid ranges.
Build `tests/fixtures/collection_snapshot.rbv --split` and pass the resulting
WASM to `tests/web_collection_snapshot.mjs` for persistent initialized state,
Unicode, more than 1023 items, snapshot reuse and reset. Native JSON encoding
has its own fixture, and browser JSON is checked with actual generated WASM.

`tests/fixtures/recommender/browser_pending_peer.mjs` runs the generated app
against a controllable in-page HTTP/WebSocket peer. It covers optimistic paint,
accepted/saved/predicted ordering in both orders, duplicate events, delayed HTTP
fallback, failed writes, cancellation on confirmed logout, the reload warning,
and stale login generations. Run it after building the app with Playwright and
Edge or Chromium available:

```bash
node tests/fixtures/recommender/browser_pending_peer.mjs target/recommender-I09
```

It is a mocked browser gate; it does not establish real server integration.

The generated app also has a real native-server gate:
`tests/fixtures/recommender/browser_live_server.mjs <web-output> <api-url>`.
It registers an account, signs in, seeds a profile, holds the account's database
row lock, submits a rating, and verifies that recommendations paint before the
save can finish. Releasing the lock must produce save confirmation without
duplicate recommendation rendering, follow-up GETs, or synchronous XHR.
The gate requires PostgreSQL and Playwright; it creates a distinct test account.

The 2026-10-25 crash recovery establishes these runtime invariants: snapshot
buffers grow to the collection size; global collection headers survive boot;
generic callable transactions use concrete element layouts; String decoding
uses UTF-8; unchanged text is not rewritten on repeated flushes. Window events
on the same element retain their individual handlers. WASM lowering promotes
allocas and eliminates eligible tail recursion before stack-machine emission.

Search input uses `b-bind:value="movie_search"`, which routes input text to
the field's writer transaction, `search_changed`. Do not add a second
parameterless input trigger for that transaction: it runs after the bound
call without the query and clears the filter. The browser pending-peer
fixture covers mixed-case matching, no matches, and clearing the search.
