# Authenticated journey checkpoint results — 2026-11-06

Gate C's bounded single-user journey is complete. It is a correctness smoke
checkpoint; fixed-rate multi-user scheduling and endurance remain next.

## Provenance

Compiler local main and fork main were fast-forwarded to upstream
`9f49b2f81f5a36ace14c316b5c4b06ca37fa29bb`, preserving the dirty integration tree. During final verification upstream advanced; local/fork main were synchronized again to `b9933004ed49bd26e4d064ad829b1aaa7846fbb9`. The tested compiler pin retains the initial base plus the four fixes.
Client source: app `b3e046f`. Server source: app `bfa4cc3d2d5a837be8bfadce2b844801eb05ba9f`, freshly built with
that upstream compiler. Client compiler integration: `0adcbba2c26f99633e1a8793238d077759767792` (`integration/load-journey-verified`, clean checkout `../recommender-compiler-carveouts/load-journey-verified`).
Four focused main-based fixes: [#72](https://github.com/Randozart/briev-lang/pull/72) (`43671154`), [#73](https://github.com/Randozart/briev-lang/pull/73) (`94c763f5`), [#74](https://github.com/Randozart/briev-lang/pull/74) (`5a6e5513`), [#75](https://github.com/Randozart/briev-lang/pull/75) (`80e5c099`).

Pinned debug compiler `/home/otto/briev-load-tools/journey-fixed-brievc`:
`3e0626adff9211f7dd6d93a34f7a11680ae676690ab180ee3b1de4b4e620841f`.
Client `target/journey/journey`:
`b2e193a4d66d8a707039752aef2552b8f047135279d4e6141b15f0e918d206fa`.
Fresh server `target/journey-server/server`:
`77788d2c0f2dd751fbb34d60ab7b16f4b9507a286213f28fd47c1e778280c8af`.
MovieLens 100K `u.data`:
`06416e597f82b7342361e41163890c81036900f418ad91315590814211dca490`.
`u.item`: `553841ebc7de3a0fd0d6b62a204ea30c1e651aacfb2814c7a6584ac52f2c5701`.
WSL Ubuntu 20.04, clang 18, PostgreSQL 12, database `briev_recommender_i01`,
role `briev_test`, loopback port 18995, worker generation 1. No schema reset.

## Gates

- Independent oracle: all cases pass, including reversed stage order,
  duplicates, stale revision/foreign account/epoch, wrong operation/delta,
  wrong generation, duplicate JSON field, sticky save failure, duplicate and
  out-of-range recommendation IDs, trailing JSON and cold-start transition.
- Controlled wire: eight peer modes plus refused connection pass. Positive
  modes include coalesced/bytewise delivery and ping; negative modes include
  masked, fragmented, truncated, stalled and wrong-accept responses.
- Real final run: account 148, username `load_1793953328_3759`, epoch
  `b2cc07795addcfbd4fccfb4b2a4ff3ac`. Five accepted/saved/predicted operations,
  revisions 1–5; fifth response has five ranked unrated movies. Logout succeeds.
- Independent SQL: `5|5|5` ratings, saved receipts and distinct operation IDs;
  five separate exact account/epoch/operation/revision receipt checks return 1.
- Valgrind: 220,053 allocations, 220,052 frees; zero errors and zero definitely,
  indirectly or possibly lost bytes. One 65,536-byte process-lifetime allocation
  remains reachable. No open network descriptors. This is bounded-run evidence,
  not a long-duration memory stability claim.
- Compiler: 3,516 combined library tests pass. Isolated branches pass 3,511
  (integer), 3,512 (entropy), 3,513 (trait defaults) and 3,513 (tuple fields).
  Source-conformance sweep remains delegated to CI. Native integer regression
  passes AST/HIR at O0/O3. Ten-program IR determinism and eight-program AST/HIR
  byte parity pass. Builds have no warnings; changed-file Praetor adds zero
  diagnostics. Clang 17/18 execute all three matrix programs; raw parity fails
  solely on labelled prediction_time_ns/prediction_time_ms values, and a retained
  output comparison confirms all other lines match. Kani cannot start because
  this WSL glibc lacks required versions 2.32–2.34. No Kani proof is claimed.

Raw local evidence: `target/journey-verified/` (results.csv, durable.txt,
expected-receipts.csv, receipt-checks.txt, inputs.sha256, environment.txt,
server.log and valgrind.log). Stage timings there are **provisional functional
measurements under Valgrind**, not capacity or latency benchmark results.
Earlier failed memory runs are retained separately and are not passing evidence.

## Compiler findings

1. Native Bool enum payload i8 compared with boxed Bool parameter i64 generated
   invalid LLVM. Normalize unequal physical integer widths at binary emission.
2. Linux getrandom was missing its synchronous output-buffer borrowing effect.
3. Trait-default bodies and concrete free-call method effects were missing from
   ownership analysis. Analyze the same Self-specialized dispatch as lowering.
4. Tuple fields merged unrelated provenance: sending a JSON pair's key appeared
   to expose the value's pointer graph. Index-labelled fields remove that false
   escape while negative tests retain actual selected/raw pointer escapes.

A string-concatenation provenance experiment did not resolve the escape and was
reverted. The decisive analysis discriminator was the sendto external owner set:
all JSON allocation families before tuple separation, empty afterward. The
runtime gate then changed from roughly 35.6 MB retained/lost allocations to zero
lost bytes. No application workaround or weakened validation was introduced.

## Remaining boundaries

Hydration's `model_generation` is an opaque snapshot identity, whereas worker
events use numeric generation 1. `LOAD_GENERATION` pins the independently known
expectation; snapshot identity is logged separately. The run owns an otherwise
idle server and delays refresh. It assumes MovieLens 100K, five serial ratings
on items 0–4, and fresh-server revisions 1–5. The oracle validates ranking
structure and freshness, not an independent numerical model implementation.

Next checkpoint: connect this authenticated journey to the existing arrival
scheduler and stage histograms with multiple identities and explicit overload
outcomes, then controlled capacity and long endurance runs. Usage:
[benchmarks/load/JOURNEY.md](../../benchmarks/load/JOURNEY.md).

Migration preservation: non-secret raw client/SQL/memory evidence is committed in [docs/verification/2026-11-06-journey](../verification/2026-11-06-journey/README.md). Use [the Linux handoff](../agent/START-HERE.md) to rebuild on a fresh machine.

## Upstream CI at migration handoff

All four compiler PRs passed their complete upstream Default gates on 2026-11-06:

- #72: https://github.com/Randozart/briev-lang/actions/runs/42188538515
- #73: https://github.com/Randozart/briev-lang/actions/runs/42189187332
- #74: https://github.com/Randozart/briev-lang/actions/runs/42189780570
- #75: https://github.com/Randozart/briev-lang/actions/runs/42190526051

This includes testing against the newer upstream merge base. Check live PR status
before replacing the explicitly pinned integration; passing CI is not a merge.
