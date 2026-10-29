# Recommender session bug report

Date: 2026-10-25  
Scope: startup, account creation and use of the recommender example, plus
compiler, generated browser runtime, native service, and test harness defects
found while reproducing those failures.

This report records the problems investigated and fixes committed in
`894fcfa5` (`Fix recommender startup and account flow`). The known environment
failures in the full compiler suite (including GPU target and SPIR-V toolchain
cases) are explicitly not treated as recommender bugs and were not pursued.

## Bugs fixed

### Generated browser app failed to parse at startup

**Area:** Compiler web generator and recommender browser app.

**Cause:** The generated event-trigger call still inserted a leading comma for
an implicit state argument after the trigger argument list stopped including
that state. This produced invalid JavaScript such as
`this._txn("select_stars")(, 1)`. Node rejected the module before the browser
could initialize.

**Reproduction:** Generate the recommender web app, then run `node --check`
against its `app.mjs`, or open it in a browser. The syntax error is at the
star-rating trigger and the app never starts.

**Fix:** Build the trigger argument list from the actual declared arguments
and emit separators only between present arguments. Add browser and generator
regression coverage for generated collection and event behavior.

### Browser app imports were incomplete and values used the wrong widths

**Area:** Compiler web generator, reflection, stateless call lowering, and
browser JSON handling.

**Cause:** The generated module omitted heap/runtime imports needed by the
compiled app. Separate lowering paths also disagreed about declared integer
and boolean widths, so integer JSON fields and decimal recommendation scores
could be read or emitted with an incompatible representation.

**Reproduction:** Generate and load the recommender WASM app, exercise JSON
parsing for integer fields and recommendation scores, and use stateless calls
and boolean match literals. Before the fix, module initialization or value
handling failed at those boundaries.

**Fix:** Emit the required runtime imports, carry declared widths through
stateless calls and boolean match lowering, and keep reflection/JSON conversion
consistent with those widths. Add regression tests for declared integer call
widths, boolean match literal width, and browser JSON values.

### Empty prediction-worker model read past its CSR buffer

**Area:** Recommender prediction worker and native runtime memory safety.

**Cause:** The empty model allocated one CSR offset for each side, but a
zero-row CSR still reads its terminal offset. That terminal read was one item
past the allocation.

**Reproduction:** Start a prediction worker with an empty model under
AddressSanitizer and exercise its empty-model gate. ASan reports an out-of-bounds
read at the terminal CSR offset.

**Fix:** Allocate and initialize both offset entries for an empty CSR. Add an
empty-model regression gate.

### Optimized JSON handling crashed when a returned value escaped

**Area:** LLVM backend object and aggregate lifetime lowering; recommender
catalogue API response.

**Cause:** An escaping structure-return value was backed by a temporary stack
image whose lifetime ended before the optimized caller finished consuming it.
The ordinary LTO-linked output crashed; disabling inlining made the failure
disappear, which localized it to the optimized lifetime path. Removing alias
attributes did not resolve the failure.

**Reproduction:** Compile the JSON response path with the normal optimized LTO
link and parse its returned value across the call boundary. The optimized
binary crashes. Repeating with inlining disabled passes, exposing the
optimization-sensitive lifetime defect.

**Fix:** Materialize the escaping result in owned storage in the emitted IR so
its lifetime covers its use. Add coverage for enum aggregate lifetime and
local enum returns. The ineffective alias-attribute change was not retained.

### Guarded negative index still evaluated at index zero

**Area:** LLVM backend logical expression lowering; recommender prediction
worker's previous-item check.

**Cause:** The expression used a short-circuit guard before checking the
previous item. Ordinary expression lowering evaluated both sides eagerly, so
the previous-item predicate still read index `-1` at the first item. ASan
reported the invalid access.

**Reproduction:** Run the worker path at item index zero with ASan, or exercise
a logical `&&` whose right side indexes the prior item. The right side is
evaluated despite a false left side.

**Fix:** Route ordinary logical expressions through control-flow-graph-based
short-circuit lowering. Preserve mutable parameter/local slots and only reuse
cached values where they dominate the use. Add behavioral regressions for
short-circuit expressions and mutable slots.

### Catalogue scan trapped on a dangling state-list header

**Area:** LLVM-generated browser WebAssembly code; recommender catalogue scan.

**Cause:** A collection state field initialized with `[]` built its
`[data, cap, len]` header with `alloca` inside `init_state`, then stored that
stack address in `%State`. `init_state` returned before the catalogue response,
so the first scan dereferenced a dead frame and trapped. The scan also had
unbounded wasm recursion at 1682 entries, but that was a separate stack-depth
limit; the immediate trap was the dangling header.

**Reproduction:** Compile the browser app to WASM and load the catalogue. The
module traps in `browser_catalogue_scan` while reading the first movie handle,
before the app can complete the interaction.

**Fix:** Compiler commit `6604ae53` heap-owns state-collection construction
headers, isolates callable-txn emission from a preceding tail-lowered defn, and
lowers eligible wasm self-tail recursion to an explicit loop. Compiler commit
`210c5b9b` seeds top-level unpacked instances on assignment, fixing the real
server's lost registration response. `b1de89fc` clears txn identity at defn
entry and stops keyed-row churn, fixing the real browser responsiveness gate.
`569cf69b` retains every enum return image, fixing the server protocol and
runtime ownership crashes. Otto Westerlund’s PR #48 (`2288e4ec`, merged at
`97bc4fa0`) fixes pooled-object replacement and mixed-width member storage.
`3f633135` reserves the full row width in view snapshots; `e110fd1e` snapshots
flush records before effects can grow and detach wasm memory. `mem2reg` and
`tailcallelim` remain in the wasm pipeline, but they did not fix the immediate
lifetime fault. Verified with `browser_pending_peer.mjs` (twice) and the I11
real browser/server gate; no throughput claim is made.

### Specialized catalogue iteration called an incompatible erased adapter

**Area:** Compiler transaction specialization and recommender movie catalogue
iterator.

**Cause:** The concrete `iter_chain<MovieCard>` transaction called an erased
generic adapter whose element stride did not match the concrete movie-card
layout. The mismatch corrupted catalogue traversal.

**Reproduction:** Run the movie catalogue iteration gate with multiple
struct-valued elements; concatenate a chain of distinct `MovieCard` values and
verify every item. The erased adapter uses incompatible element strides.

**Fix:** Extend the existing specialization worklist to transactions while
preserving contracts and convergence behavior. Expand collection snapshot
coverage to concatenate twelve distinct struct elements, and add dedicated
catalogue gates.

### Loading the catalogue caused extreme native server memory growth

**Area:** Recommender native server catalogue API serialization.

**Cause:** The response builder repeatedly concatenated immutable strings.
Each append copied the response accumulated so far, causing large transient
allocations even though the final catalogue response was about 85 KB.

**Reproduction:** Request the catalogue from the native service while recording
its RSS. Before the fix, one request added roughly 412 MiB while producing an
85,469-byte body.

**Fix:** Append response chunks into one owned growable buffer and release it
after serialization. The response remained byte-for-byte identical and a
repeat request measured a 0 KiB RSS change in the recorded probe.

### Account creation was difficult to diagnose and validate

**Area:** Recommender browser account form and registration API.

**Cause:** The form and service did not give clear, early feedback for invalid
credentials, so users could not tell which input prevented account creation.
The browser flow also needed to keep registration distinct from sign-in and
surface the service response.

**Reproduction:** Submit an empty username, a password shorter than eight
characters, or otherwise invalid registration data from the browser form.
Before the fix, the user did not receive a useful field-level explanation.

**Fix:** Validate the username and minimum password length in the browser and
again at the service boundary, return actionable registration errors, and
display successful account creation feedback with a clear next sign-in step.

## Related usage and lifecycle repairs

The session also repaired service and test-harness paths needed to reproduce
and reliably exercise the app: worker shutdown/reaping, worker crash/restart
and timeout handling, malformed-message isolation, prediction-pool fairness
and generation cleanup, and empty imports in the recommender fixtures. These
changes are covered by the worker process and server API gates. The demo
launcher now builds and starts the native service and browser frontend with
explicit service configuration.

## Verification and limits

The four focused LLVM crash-regression tests passed. The real browser/server
integration exercised account creation, login, ratings, recommendations while
a database save was blocked, and saved confirmation. It verified that the
pending result remained visible, no follow-up GET or synchronous XHR occurred,
and the recommendation list did not rerender after save. The browser peer,
worker process, collection snapshot/JSON, logical lowering, view compiler, and
web generator gates also passed during the session.

The full `cargo test --lib` run was explicitly stopped at the user's request.
It had reported host-dependent GPU and SPIR-V failures before stopping; the
user identified the compiler suite's 38 GPU/SPIR-V failures as known
environment issues and instructed that they not be fixed. They are therefore
not included in the recommender bug list or treated as a release gate here.
