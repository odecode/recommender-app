# Authenticated load journey checkpoint

Implement the next Gate C slice: one bounded Briev client registers a unique
test account, logs in, validates catalogue/profile hydration, opens the live
channel, and submits five serial ratings. Each operation must independently
observe admission, durable-save confirmation and a matching fresh prediction.
The fifth rating crosses the cold-start threshold. Verify durable data through
a separate database query after the client exits. This is a correctness smoke
checkpoint, not a capacity measurement or the later scheduled mixed workload.

1. Independent JSON/event oracle with adversarial fixture coverage. Import
   stdlib codecs only, never server protocol/business validation.
2. Bounded nonblocking HTTP and WebSocket transport, finite whole-operation
   deadlines, explicit failure outcomes and cleanup. Exercise controlled peers.
3. Execute against an isolated real server/database; retain exact binary,
   source, dataset and environment provenance. Do not reset shared schemas.
4. Document commands, limits, evidence and the remaining scheduler integration.

Compiler upstream/local/fork main synchronized to 9f49b2f8 on 2026-11-06.
Use clean worktree `../recommender-compiler-carveouts/load-journey-main`.
Any compiler defect follows WORKFLOW: minimal discriminator, separate main-based
fix branch, regression, BUGS/architecture documentation, final gates and PR.
Preserve existing dirty files. No compiler performance change is planned.

Documentation: add a journey usage/evidence document, preserve existing HTTP
documentation and rationale comments, append the workflow task/stdlib ledgers
when the checkpoint is verified. Historical result documents remain unchanged.
