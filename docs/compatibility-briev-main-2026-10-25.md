# Briev `main` compatibility — 2026-10-25

This branch aligns the recommender with the current compiler/stdlib naming and
makes the native service compile against current `main`.

## Renames

- `Matrix` → `FloatMatrix`
- `Vector` → `FloatVector`
- `IntVec` remains unchanged

## Status

- Browser `app.rbv`: builds and loads with current `brievc` (zero page errors).
- Server `server.bv`: `brievc check` passes and `brievc build` links the native
  executable.
- Fixtures: the seven `tests/fixtures/recommender/*.bv` files still used the
  old `Vector` spelling; they now use `FloatVector`.
- `run_active_scratch.sh`: PASS.
- `run_active_profile.sh`: PASS under the harness-exact `-O3 -flto` build.
- `run_worker.sh`: PASS through install, generation-2 prediction, shutdown and
  reap. The recovery suffix needs PostgreSQL because it spawns the
  persistence worker, so `persistent_ipc=false` is expected locally.
- Local PostgreSQL 18.6 + MovieLens 100k + Playwright Chromium gates:
  - `run_profile_admission.sh`, `run.sh`, `run_accounts.sh`,
    `run_cache.sh`, `run_operation_store.sh`, `run_prediction_workers.sh`,
    and `run_worker.sh` PASS.
  - `run_server.sh` PASS through catalogue/reactor/json/api/io/protocol/loop
    and malformed WebSocket frames. The repository-level
    `recommender_server_properties` test is absent and is reported as skipped.
  - `browser_pending_peer.mjs`: the `Live` binding now works (compiler
    `b7bdfb08` preserves hyphens in `b-window` event names); the gate now
    stalls on the 1682-movie catalogue load.
- The app receipt payload is JSON-serialized and reparsed at the wire boundary
  to avoid the current constructed-`JsonValue`-in-`Array` copy bug (companion
  BUGS.md); parsed payloads behave correctly.

## Compatibility changes

The service now states every callee precondition it relies on as an explicit
`when !(...) { trap; };` guard. The guard families cover:

- reactor row access and socket file descriptors
- vector/ivec indexing and CSR/matrix capacities
- PostgreSQL result rows/columns
- system-call constants and buffer slices
- rating-population begin/end and mean accessors
- profile/imputation indexes

Two compiler fixes were required and are carried by the companion Briev
change:

1. Destructuring `let` no longer falls back to `Int` when tuple inference
   fails; the inference error is propagated (the fallback hid the real mismatch).
2. Proven guards are eliminated by the compiler after typechecking; the source
   guards stay as intent/documentation. Never delete a source guard as a manual
   optimization (`AGENTS.md` Rule 25).
3. `Type { field: value }.field` is reduced to `value` by the proof engine, so
   struct-literal arguments (`Socket { fd: fd }`, `ByteBuf { ... }`) discharge
   bounds already guarded by the caller.

`std/posix/syscall.bv` on current `main` does not export `SYS_KILL`,
`SYS_PRCTL`, or `SYS_SOCKETPAIR`; the worker modules define those three
constants locally. Migrate them to the stdlib import once it exports them.

## Reproduction

```sh
BRIEV_STDLIB=/path/to/briev/lib/std brievc check examples/recommender/server.bv \
  --stdlib-path /path/to/briev/lib
BRIEV_STDLIB=/path/to/briev/lib/std brievc build examples/recommender/server.bv \
  --stdlib-path /path/to/briev/lib --out target/recommender-demo
BRIEV_STDLIB=/path/to/briev/lib/std brievc build examples/recommender/app.rbv \
  --stdlib-path /path/to/briev/lib --split --out target/recommender-web
```
