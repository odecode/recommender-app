# Start here: load harness and Linux migration

Updated 2026-11-06. This is the entry point for an agent with no prior conversation.
Read this, [WORKFLOW.md](WORKFLOW.md), the compiler's AGENTS.md,
[JOURNEY.md](../../benchmarks/load/JOURNEY.md), and the
[checkpoint evidence](../plans/2026-11-06-authenticated-load-journey-results.md).
Historical Windows paths and older compatibility pins elsewhere are not the
bootstrap instructions for a fresh machine.

## Completed and remaining work

Completed: arrival scheduler, accounting/histograms, process sampling, streaming
collector, bounded-memory gates, and scheduled catalogue HTTP requests with
bounded slots and separate missed/failed/successful outcomes. The newest checkpoint
is one authenticated user: register/login, hydrate state/catalogue, WebSocket,
five serial ratings, independent accepted/saved/fresh-recommendation validation,
cold-start transition, logout, and exact durable receipt verification through SQL.

The combined compiler passed 3,516 library tests, native AST/HIR execution at
O0/O3, ten-program IR determinism, eight-program AST/HIR byte parity, and builds
without warnings or new Praetor diagnostics. Client Valgrind reports zero errors,
zero lost bytes and no open network sockets; one 64 KiB allocation remains reachable.
There is no capacity or multi-day endurance result. The authenticated journey is
not yet connected to the arrival scheduler.

## Repositories and verified pins

| Purpose | Repository/ref |
|---|---|
| Application and this handoff | https://github.com/odecode/recommender-app, main |
| Compiler upstream | https://github.com/Randozart/briev-lang |
| Writable compiler fork | https://github.com/odecode/brief-lang (spelling: **brief-lang**) |
| Journey compiler | fork `integration/load-journey-verified`, `0adcbba2c26f99633e1a8793238d077759767792` |
| Earlier HTTP compiler | fork `integration/http-load-final`, `fd52b03fe19a419755d14db0a6f75886bbf6c10f` |
| Journey implementation | app `b3e046f`; later commits preserve notes and migration documentation |

The journey compiler is upstream `9f49b2f8` plus four fixes:
[#72](https://github.com/Randozart/briev-lang/pull/72) integer representations,
[#73](https://github.com/Randozart/briev-lang/pull/73) getrandom borrowing,
[#74](https://github.com/Randozart/briev-lang/pull/74) trait-default effects,
[#75](https://github.com/Randozart/briev-lang/pull/75) tuple-field provenance.
Check live CI/merge status. Local/fork main were synchronized again to `b9933004`
during verification; do not assume main includes these PRs. Use the verified
integration until an upstream replacement passes the same gates. Never PR an
integration branch or migration snapshot.

## Fresh Linux bootstrap

Target native x86-64 Linux. Compiler CI uses Ubuntu 24.04. The historical run used
WSL Ubuntu 20.04, Rust 1.99.0, clang 18.1.8 and PostgreSQL 12. A new machine is a
new measurement environment: rerun gates and record fresh hashes. No Windows
directory, cached executable, database dump or private token is required.

On Ubuntu 24.04 with Rustup installed:

```bash
sudo apt-get update
sudo apt-get install -y git build-essential clang-18 lld-18 llvm-18 \
  pkg-config libssl-dev spirv-tools postgresql postgresql-client valgrind unzip
rustup toolchain install 1.99.0
mkdir -p "$HOME/code"
cd "$HOME/code"
git clone https://github.com/odecode/recommender-app.git
git clone https://github.com/Randozart/briev-lang.git
git -C briev-lang remote add fork https://github.com/odecode/brief-lang.git
git -C briev-lang fetch fork
git -C briev-lang switch -c integration/load-journey-verified \
  --track fork/integration/load-journey-verified
test "$(git -C briev-lang rev-parse HEAD)" = 0adcbba2c26f99633e1a8793238d077759767792
cp recommender-app/docs/agent/compiler-Cargo.lock briev-lang/Cargo.lock
export PATH="/usr/lib/llvm-18/bin:$PATH"
export BRIEV_HOME="$HOME/code/briev-lang"
export BRIEV_ROOT="$BRIEV_HOME"
export BRIEV_STDLIB="$BRIEV_HOME/lib"
export BRIEV_CONFIG_DIR="$BRIEV_HOME/config"
export CARGO_TARGET_DIR="$HOME/.cache/briev-target"
cd "$BRIEV_HOME"
cargo +1.99.0 build --locked --release --bin brievc
export BRIEVC="$CARGO_TARGET_DIR/release/brievc"
cd "$HOME/code/recommender-app"
```

The archived lockfile is the dependency resolution used by the verified combined
build; the compiler normally ignores Cargo.lock. Retain jobs=2. Keep source and
build caches on native Linux storage. LLVM tools (`clang`, `llc`, `opt`) must be
available by bare name. Export BRIEV_HOME even when also passing stdlib/config
flags: omitting it produced misleading glue/type failures during development.
A changed compiler or dependency lock is a new candidate, not the verified pin.

Old Ubuntu 20.04 SPIR-V tools were too old for the full suite; that executor built
SPIRV-Tools `efadd8a7fa2a8dd26567694dfcb5d9b5f36d4ca4`. Ubuntu 24.04 CI installs
its packaged spirv-tools. Kani could not start on the old glibc; no Kani proof is
claimed. Diagnose actual tool failures before changing compiler behavior.

## Dataset and isolated database

Get MovieLens **100K**, not latest-small, from the
[official dataset page](https://grouplens.org/datasets/movielens/100k/). Review its
README/terms and extract outside Git. Dataset hashes are in the checkpoint evidence.

```bash
export UDATA_PATH="$HOME/datasets/ml-100k/u.data"
export UITEM_PATH="$HOME/datasets/ml-100k/u.item"
sha256sum "$UDATA_PATH" "$UITEM_PATH"
```

Dataset files, old test accounts, database contents and snapshots are not uploaded.
Startup bootstraps a new database from these files. The harness leaves unique
accounts/receipts in its dedicated database as evidence.

For a NEW dedicated local database only:

```bash
sudo systemctl start postgresql
sudo -u postgres createuser --no-superuser --no-createdb --no-createrole briev_load
sudo -u postgres createdb --owner=briev_load briev_load
sudo -u postgres psql -d briev_load -c 'GRANT USAGE, CREATE ON SCHEMA public TO briev_load'
sudo -u postgres psql -Atc 'SHOW hba_file'
```

The native Briev PG client currently uses trust authentication. In the displayed
pg_hba.conf, put this exact database/role/loopback rule before broader host rules:

```text
host briev_load briev_load 127.0.0.1/32 trust
```

```bash
sudo systemctl reload postgresql
export PGUSER=briev_load PGDATABASE=briev_load
psql -X -h 127.0.0.1 -v ON_ERROR_STOP=1 -c 'select current_user, current_database()'
```

Keep the rule scoped to this isolated local test database. PostgreSQL uses the
first matching rule; see its
[pg_hba documentation](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html).
The native app connects to 127.0.0.1:5432. Do not assume PGHOST/PGPORT change the
native destination merely because psql accepts them. Check isolation before
reusing an existing database; never drop a schema to get a green run.

## Reproduce the checkpoint

```bash
cd "$HOME/code/recommender-app"
bash benchmarks/load/build-journey.sh
bash benchmarks/load/check-journey.sh
"$BRIEVC" build examples/recommender/server.bv \
  --stdlib-path "$BRIEV_STDLIB" --config-dir "$BRIEV_CONFIG_DIR" \
  --out target/journey-server
export LOAD_SERVER="$PWD/target/journey-server/server"
export LOAD_PORT=18995 LOAD_GENERATION=1
bash benchmarks/load/run-journey-smoke.sh
JOURNEY_VALGRIND=1 JOURNEY_RESULT_DIR=target/journey-memory \
  bash benchmarks/load/run-journey-smoke.sh
```

The historical server was built with upstream 9f49b2f8. Rebuilding it with the
integration creates a new candidate artifact: require the smoke and memory gates
before treating the new machine as verified. Large server builds can take several
minutes; do not silently substitute an older binary for a still-running build.

Success requires `journey_oracle_ok`, eight wire cases plus refusal, then both
`journey_ok` and `journey_durable_ok`. SQL counts must be `5|5|5`; all five exact
receipt checks must be `1`. Save and prediction may arrive in either order.
`LOAD_GENERATION=1` pins the known initial worker generation; hydration's similarly
named field is an opaque snapshot identity. The script owns an otherwise idle
server, expects revisions 1–5 and postpones refresh. Revisit these assumptions
for multiple users and refresh overlap.

Other gates, with the matching compiler environment restored:

```bash
bash benchmarks/load/check.sh
bash benchmarks/load/check-collector.sh
bash benchmarks/load/build-http.sh
bash benchmarks/load/check-http.sh
bash benchmarks/load/check-http-memory.sh
```

Consult [HTTP-LOAD.md](../../benchmarks/load/HTTP-LOAD.md) and the
[collector instructions](../../benchmarks/load/README.md). No browser/Node
dependency is needed for these native load-harness gates.

## Next checkpoint and working discipline

Read the [load plan](../plans/2026-11-03-briev-native-load-harness.md) and the
[system map](../architecture/applications/recommender-system-map.md) before
choosing the next slice. The dated plan records the original campaign; the
completion summary above and checkpoint evidence are the current status.

| File under benchmarks/load | Responsibility |
|---|---|
| schedule.bv | Intended arrival deadlines and missed arrivals |
| metrics.bv | Attempt lifecycle, outcome counters, latency histograms |
| process_metrics.bv / collect.bv | Process identity, CPU/RSS counters and streaming samples |
| http_attempt.bv / http_load.bv | Bounded nonblocking slots and scheduled catalogue traffic |
| journey.bv | Current serial authenticated state progression |
| journey_wire.bv | Bounded HTTP/WebSocket transport and deadlines |
| journey_values.bv / journey_oracle.bv | Independent parsing, identity and stage validation |
| probes/ and tests/ | Controlled peers, adversarial oracle and accounting regressions |

Connect authenticated users to the existing arrival scheduler and accounting.
Use bounded user states and separate admission, durable-save and prediction
histograms. Count offered, missed, started and every failed/completed operation;
retain scheduling lag. Resolve global versus per-account revisions explicitly
instead of reusing this probe's fixed 1–5 assumption. Keep the oracle independent
of server validation. Add controlled multi-user/overload cases, a small real run,
and a bounded memory gate before capacity/endurance campaigns. Record source,
dataset, configuration and binary provenance. Refresh, retry/reconnect and
ambiguous outcomes need explicit semantics, not silently successful samples.

Work in small increments and explain how/why. Workload, network and oracle code
stay Briev; shell orchestration and SQL evidence are infrastructure. Compiler
defects get minimal repros and general fixes on separate upstream-main-based
branches, tests, BUGS/architecture records and upstream PRs from the fork. Keep
an integration branch for app validation. The user authorizes commits and PR
creation without additional approval. Defer full suites until implementation and
focused app checks finish; preserve all uncommitted work. WORKFLOW.md retains the
complete teaching contract; its Windows paths and older approval wording are
superseded by these migration instructions.

For ownership/codegen changes keep negative escape tests, native execution,
required compiler gates and the real client memory gate. Do not weaken contracts
or remove source guards to compensate for missing compiler behavior.

Praetor is a separately installed tool, not vendored by these repositories. A
fresh compiler-development setup must make it available before the compiler's
per-commit checks; report a missing tool rather than silently claiming its gate.

## Recover unfinished work

[Migration inventory](MIGRATION-INVENTORY.md) maps compiler branches and dirty
worktree snapshots to GitHub. They are **unverified backups**; use the verified
integration for continued load work. The root snapshot includes formerly ignored
.kiro design/tasks/workflow text and PR body documents. Build caches, credentials,
datasets, database dumps, research PDFs and unrelated ocamlpoker are excluded.
