# WORKFLOW - read this first (every session)

This file governs how we work on the full-stack-webapp effort and the Briev net
stack it grows. It persists across sessions. New agent sessions: READ THIS BEFORE
DOING ANYTHING, then read:

1. docs/plans/2026-10-09-fullstack-stdlib-and-net-stack.md  (the stdlib plan + ledger)
2. .kiro/specs/fullstack-webapp/design.md                   (the app design)
3. .kiro/specs/fullstack-webapp/tasks.md                    (the task list + progress)
4. AGENTS.md                                                (the repo operating contract)

## Prime directive: this is a teaching build

The human is an experienced engineer learning the DETAILS being implemented here
(syscalls, socket ABIs, wire protocols, compiler internals). Therefore:

- DO NOT one-shot a whole module and then test. Work in SMALL increments.
- After each increment, STOP and explain: what was built, HOW it works, and WHY it
  is done this way. Prefer a short teaching note over a wall of code.
- Keep the human in the loop and in overview. Surface decisions, do not bury them.
- When a concept is non-obvious (byte order, two-phase commit, SCRAM, LLVM
  observability), explain the concept, not just the code.
- Favor correctness and understanding over speed. This is production-grade work.

## The environment split (Windows workspace + WSL executor)

- SOURCE OF TRUTH: the Windows workspace at c:\\\\Users\\\\wotto\\\\code\\\\briev-lang.
  All docs and code are authored HERE so the human sees them live in the IDE.
- BUILD/TEST EXECUTOR: WSL (Ubuntu 20.04). The compiler was built in WSL at
  ~/code/briev-lang (a separate clone) - its target/release/brievc is the binary
  we run. The Windows repo is NOT built in; only compiled FROM.
- WSL reaches the Windows files at /mnt/c/Users/wotto/code/briev-lang.
- So: edit Windows-side, compile with the WSL brievc pointed at /mnt/c/... paths.

## Shell gotchas (learned the hard way - follow these)

Commands run through cmd.exe -> wsl. This double shell has sharp edges:

- ONLY single-line commands survive. Multi-line commands / heredocs get split by
  cmd and break. Never rely on a heredoc through this boundary.
- To WRITE a file from WSL, use one printf with many quoted args, appended:
    F=/mnt/c/.../file; printf (percent-s backslash-n) ARG1 ARG2 ... >> "\$F"
  Escape the OUTER double-quotes as backslash-quote. Let \$F EXPAND (do NOT write
  backslash-dollar-F - that makes it literal and the redirect writes nowhere).
- Define any variable you use IN THE SAME command. Each call is a fresh shell;
  nothing persists between execute calls (no F=, no functions, no cwd).
- Avoid single-quotes inside single-quoted args; reword to dodge apostrophes.
- A trailing exit code of -1 from the host is usually a DISPLAY artifact, not a
  real failure. Verify by reading the file / checking output, not by the code.
- VERIFY every write: read the file back (read_file on the Windows path works once
  WSL has written to /mnt/c/...). Do not trust an echo OK alone.
- The build is capped at jobs=2 (.cargo/config.toml). cargo build --release took
  ~12.5 min cold. Use the already-built binary; only rebuild when compiler Rust
  code changes.

## Per-increment checklist (every code step)

1. Write/modify the smallest meaningful piece (one function, one message type).
2. brievc check the file (syntax/typecheck) - see tasks.md for the exact command.
3. If it is testable in isolation, build + run a tiny .bv harness and show output.
4. Explain to the human: what, how, why. Note any surprise or compiler oddity.
5. If a compiler bug/odd behavior appears: log it in BUGS.md AND in the stdlib
   plan bug log, with the triggering .bv snippet and the workaround.
6. Update tasks.md: tick the step, add a one-line note on what was learned.
7. Commit ONLY when a logical unit is done and the human has seen it (ask first -
   this repo prefers continuous commits but the human wants overview here).

## Scope reminder

Pure Briev only: no Python, no Node, no C library for the DB. The DB (Postgres)
is external infrastructure we CONNECT to; the client is Briev. SQLite/FFI is a
LATER, separate exercise - not now.

## Who runs build/test commands (updated 2026-11-01)

The agent may run `cargo`, `brievc`, environment setup, PostgreSQL administration,
and already-built binaries directly in WSL. Do not hand commands back to the
human merely because they invoke Cargo. Keep the human informed through the
small-increment teaching loop above.

Use `cargo check`, compiler builds, and small isolated reproductions during
iteration. Avoid running test suites while implementation or app verification
is still in progress: they take too long. Run required test suites, including
`cargo test --lib`, only as the final verification step after all implementation,
focused repro checks, and app/browser verification are complete. If final tests
expose a failure, fix it and rerun the affected final checks before completion.
This timing rule also applies to per-increment and pre-commit test requirements;
it defers those suites rather than removing the final correctness gate.

## Build and test strategy (decided 2026-10-09 - IMPORTANT)

Source of truth stays on the Windows tree (/mnt/c/...). But do NOT keep the
cargo build cache on /mnt/c: the drvfs mtime behavior makes cargo rebuild the
WHOLE dependency graph every time (a one-line change triggered a ~15 min full
rebuild). The fix is to put ONLY the build cache on the native Linux filesystem
via CARGO_TARGET_DIR, while sources stay on /mnt/c (still visible in the IDE).

Standing commands (run from a WSL shell):

```
# full build (produces the brievc we test with)
cd /mnt/c/Users/wotto/code/briev-lang && source ~/.cargo/env \\\\
  && CARGO_TARGET_DIR=~/briev-target cargo build --release

# the built binary then lives at:
#   ~/briev-target/release/brievc

# fast inner loop while editing compiler Rust - type-check only, no codegen:
CARGO_TARGET_DIR=~/briev-target cargo check

# final verification only, after implementation and app/browser checks:
CARGO_TARGET_DIR=~/briev-target cargo test --lib
```

Notes:
- The FIRST build into a fresh ~/briev-target is a cold ~15 min build (new cache
  location). After that, incremental rebuilds are fast and reliable (Linux fs,
  no mtime churn).
- Prefer cargo check (seconds) over cargo build while iterating on logic; only
  do a full build when you need to actually RUN brievc on a .bv file.
- A debug build (drop --release) is much faster to produce and is fine for
  correctness testing; use ~/briev-target/debug/brievc. Reserve --release for
  when emitted-program speed matters (it does not for our net-stack correctness).
- IMPORTANT: once we build into ~/briev-target, TEST with that binary
  (~/briev-target/release/brievc or debug/brievc), NOT the old WSL-clone binary
  at ~/code/briev-lang/target/..., which does not carry our Windows-tree edits.
- The jobs=2 cap in .cargo/config.toml still applies (intentional, do not change).
- Toolchain note: a modern clang is REQUIRED (clang-15+; we installed clang-17
  and set it as the default via update-alternatives). Stock Ubuntu 20.04 clang-10
  cannot parse the opaque-pointer (ptr) IR the backend emits.

## Code style: variable names (human preference, 2026-10-09)

No bare single-letter variable names in Briev code. Use short but explanatory
names: buf (not b), val (not v), addr (not p), idx (not i) where practical.
Abbreviations are fine; one letter is not. Loop counters in idiomatic math may
be an exception if the human OKs it, but default to meaningful names.

## Upstream PR + branch integration flow (2026-10-15 — follow this exactly)

The remotes (see `git remote -v`):
- `origin` = Randozart/briev-lang (UPSTREAM, no write access).
- `fork`   = odecode/brief-lang (OUR fork, push here; PRs are opened from here).
The human opens/merges PRs and syncs upstream `main`. The agent never force-
pushes, never merges to main directly, never edits git config.

### The feature vessel + carve-out rule
- `feat/fullstack-webapp-demo` is the MAIN VESSEL for stdlib / net-stack work.
- When a logical piece is done (e.g. one stdlib module, one trait), CARVE IT OUT
  into its own clean branch cut FROM `main` containing ONLY that piece's files
  (no compiler-fix commits, no unrelated work), and submit it with the
  PR-and-doc flow below. The feature's final history then lands on main through
  that focused PR, and the vessel branch picks the merge back up via main.
- Carve a feature branch by: `git checkout -b feat/<piece> main` then
  `git checkout <workbranch> -- <only the feature files>`, verify
  `git diff --cached --stat` shows ONLY feature files (zero `src/` compiler
  changes), commit, push to fork.

### Compiler bugs / language gaps hit DURING stdlib work
Stdlib work routinely surfaces compiler bugs (this session found three). When it
does, do NOT patch around them in the stdlib. Instead:
1. Reproduce minimally (a scratch probe under scratch/; a controlled A/B that
   isolates the trigger — e.g. "single member works, add a same-named member →
   breaks" pins the cause).
2. Fix it on its OWN branch cut from `main`:
   `git checkout -b fix/<name> main`. Commit ONLY the compiler fix + its
   regression test(s). Add/update the BUGS.md entry (OPEN → FIXED <date> + the
   one-line root cause and fix).
3. `cargo test --lib` green; the end-to-end repro builds + runs.
4. Push to fork: `git push -u fork fix/<name>`.
5. Write a PR body doc (see below).

### The PR-and-doc flow (EVERY branch that becomes a PR — fix OR feature)
Create a markdown file at the repo ROOT named `PR-<branch-topic>.md` explaining
the change in detail, written to be COPY-PASTED into the PR body. For a FIX:
symptom, a discriminator/controlled-A-B that isolates it, root cause (file:line),
the fix + why it is sound (not a patch), tests, verification, and the merge-order
dependency. For a FEATURE: summary, motivation, design + design notes, tests +
example, and any dependency on fix branches. These PR-*.md files are UNTRACKED
(git-excluded working artifacts) — they are handover scaffolding, not committed.
Prior examples to mirror: PR-liveness-member-collision.md,
PR-needs-state-type-dependent-members.md, PR-net-bytes-sink-trait.md.

### Write PRs for Briev maintainers without outside project context

Assume Briev repository authors have no knowledge of the other projects we
are building. References such as "the recommender", "our collector", or "the
load-test app" are ambiguous without an explanation. Describe the Briev
language construct, compiler behavior, or stdlib API involved, and include a
minimal self-contained Briev example that demonstrates the issue or feature.
Explain expected and actual behavior using terminology available within the
Briev project. Any external project context included must be explained in the
PR itself, with enough detail to understand and reproduce the relevant case.
Apply this to PR titles, bodies, examples, and verification descriptions.

### The integration branch (keep working while PRs are in flight)
A fix PR can take time to merge into upstream `main`. Do NOT block stdlib
progress waiting. Create an INTEGRATION branch so you can keep going AND verify
the changes work in practice:
- Base it on the stdlib work branch and merge the fix branch(es) into it:
  `git checkout -b feat/<piece>-integration <workbranch>`
  `git merge fix/<name> --no-edit` (repeat for each in-flight fix).
  (BUGS.md append-conflicts are expected when two branches both appended entries
  — resolve by KEEPING BOTH entries; the source files merge cleanly.)
- Build the compiler on the integration branch and RUN the stdlib code there to
  confirm the fixes actually unblock it end-to-end.
- The integration branch is a TEMPORARY working surface — it is NOT what gets
  PR'd. The clean carve-out branch (from main, feature files only) is the PR.
  When the fixes land on main: merge main into the vessel branch (fixes arrive
  the proper upstream way), and the feature history on the carve-out branch has
  no direct copy of the fix commits.

### Branch map legend (record the live set in tasks.md "START HERE")
- `fix/<name>` — one compiler fix, from main, PR'd (+ PR-<name>.md).
- `feat/<piece>` — one clean stdlib piece, from main, feature files only, PR'd.
- `feat/<piece>-integration` or `integration/<topic>` — TEMP: work branch +
  in-flight fixes merged, for building/verifying. Never PR'd.
- `feat/fullstack-webapp-demo` — the long-lived vessel.

## Toolchain gotchas (append as found)
- `llc` must be on PATH by its BARE name for `brievc lib` (library-surface
  fixtures) — the tier1 corpus runner builds those. clang-17 was aliased via
  update-alternatives but `llc` may not be: `/usr/bin/llc-17` exists while bare
  `llc` is absent → `brievc lib` fails "llc not found" (seen 2026-10-15 on the
  strexp tier1 library fixture; a PRE-EXISTING env gap, not a code bug). Fix if
  it blocks you: `sudo update-alternatives --install /usr/bin/llc llc /usr/bin/llc-17 100`.
- `ld` prints a harmless cosmetic warning on every native link: "Linking two
  modules of different target triples" (FFI object `x86_64-pc-linux-gnu` vs
  module `x86_64-unknown-linux-gnu`). Not an error; the binary links and runs.
