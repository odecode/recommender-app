# Migration inventory — 2026-11-06

Compiler backup repository: https://github.com/odecode/brief-lang. All refs below
were uploaded without force-pushing and checked against GitHub object IDs.
Application work and handoff are on https://github.com/odecode/recommender-app.

Preserved 85 original local branch heads, 16 dirty-worktree snapshots, and 8 tags.
Worktree snapshots use a temporary Git index; original working directories,
branches and staging state were left unchanged. Some snapshots contain no
semantic change because their reported dirt was only line-ending metadata.

## Resume verified work

Use `integration/load-journey-verified` at `0adcbba2c26f99633e1a8793238d077759767792`.
Read [START-HERE.md](START-HERE.md). Migration snapshots are unverified recovery
points, not replacements for the verified compiler and not candidates for PRs.

## Recover any branch or unfinished worktree

```bash
git fetch fork
git switch -c recovered-work --track fork/migration/2026-11-06/wip/integration/recommender-main-merge
```

Choose a backup branch from the table. Use `git show <commit>:<path>` to recover
a single file. The root snapshot preserves `.kiro` text/design/task records and
PR body documents that were previously local-only. The nested unrelated
ocamlpoker project, credentials, build caches, database dumps, datasets and
research PDFs were intentionally not included. LF/CRLF checkout differences
are not independent source changes.

Original branch heads are under `migration/2026-11-06/heads/<original-branch>`.
Their complete names and SHAs are in [migration-branch-heads.json](migration-branch-heads.json).
Snapshots and file lists are in [migration-worktrees.json](migration-worktrees.json).
Tag objects are preserved under `refs/tags/migration/2026-11-06/<original-tag>`;
see [migration-tags.json](migration-tags.json). The manifests let a fresh agent
verify remote refs without access to the Windows filesystem.

## Unfinished worktree snapshots

| Original branch | Snapshot commit | GitHub backup |
|---|---|---|
| integration/recommender-main-merge | 152756b1d5c88f5f3c75e0abb2f134950628002e | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/integration/recommender-main-merge) |
| codex/print-traversal | 977fff96768ddbfaa9cea32dbb08c534cd0b886a | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/codex/print-traversal) |
| fix/stdout-integer-lifetime | 38358f322ca6bc610b9d3d382158737673c298ec | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/fix/stdout-integer-lifetime) |
| codex/event-trap-liveness | 136fdc5d66fac1883b6b9cb48a0f7de82d38d60a | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/codex/event-trap-liveness) |
| fix/collection-index-writes | 4c91a716b9bc08e24f0091c811fc767e7031da39 | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/fix/collection-index-writes) |
| codex/module-metadata-clean | e027d29f8b671b5fa4e38d044e4f1cdaacc7414e | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/codex/module-metadata-clean) |
| codex/reflection-liveness | e3719147ac02c2e8f8437be46dcc4c15e8316a29 | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/codex/reflection-liveness) |
| codex/wasm-const-width | 1028e6212e130a3b1a9d8e4cbab08e57eb7e0870 | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/codex/wasm-const-width) |
| fix/browser-transaction-publication | 3d6dae74362b8a5e762961a70d350dda07394473 | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/fix/browser-transaction-publication) |
| fix/callable-transaction-emission | a758e8315d2db5d690275f113d512bcf8572a1f9 | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/fix/callable-transaction-emission) |
| fix/enum-field-constructor-context | dfccb59c18fb7714a5f2f5bb04c41df301b6d462 | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/fix/enum-field-constructor-context) |
| fix/enum-object-layout | 826f694523e323cf00ee0988f1752219c35c8830 | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/fix/enum-object-layout) |
| fix/enum-object-projection-lifetime | 279a7e7195c35f72d5916626fd6d4a6dbf0b009b | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/fix/enum-object-projection-lifetime) |
| integration/load-transport-development | 5fac3eadea0b7751f4359dfc3286dd8c133029d3 | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/integration/load-transport-development) |
| integration/load-journey-dev | e0c9bc8830bd959cf0e1908cdde602019e8c37d5 | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/integration/load-journey-dev) |
| integration/http-load-journey | 65f0ca88fc8d101cf1df7d134e041249fb8ac36c | [snapshot](https://github.com/odecode/brief-lang/tree/migration/2026-11-06/wip/integration/http-load-journey) |
