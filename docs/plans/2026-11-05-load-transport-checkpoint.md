# Transport prerequisite checkpoint — 2026-11-05

The existing functional suite passed with the previously built November 4
compiler. The new `benchmarks/load/probes/transport_progress.bv` is a pending
controlled stream-peer probe, not part of the passing suite. It currently
exposes unannotated tuple element types erased to Int in LLVM codegen.
A partial compiler fix was rejected because local tuple construction still
loses types. Runtime transport assertions remain unvalidated.

Rebuilding the current compiler also exposed a collector regression: native
process_metrics_gate segfaults and Valgrind reports use-after-free. The emitted
int_to_str frees the allocation returned as its String value. Earlier collector
memory results do not establish readiness of this rebuilt compiler.

Compiler findings and next gates are recorded in
`../briev-lang/docs/plans/2026-11-05-load-transport-tuple-types.md`.
No application capacity or endurance run was started. Existing app changes
were preserved, and no failing implementation was committed.
