# Briev Recommender

A browser-based movie recommender with account registration, sign-in, rating,
and live recommendations. This repository contains the application sources,
its focused compiler/runtime gates, and the recommender architecture notes.

## Build dependency

The Briev compiler and standard library are separate dependencies and are not
vendored here. This repository is an application source repository; a checkout
alone is not sufficient to compile it. Use a compatible Briev compiler build
and point `BRIEV_STDLIB` at that compiler checkout's `lib` directory (containing `std`). Set `BRIEV_CONFIG_DIR` to its
`config` directory; the launcher also discovers a config directory beside `lib`.

Compatibility pin: `Randozart/briev-lang` commit `24a0fd0e` (2026-10-29). It
includes the state-collection lifetime fix, top-level unpacked-instance
assignment, enum-return ownership, defn flush isolation, keyed DOM-row churn,
Otto Westerlund’s pooled-object replacement fix (PR #48), and the browser view
snapshot/flush-record fixes. Older compiler commits build the app but trap on
catalogue load, lose the registration response, corrupt the rendered
catalogue, or fail the browser responsiveness gate.

The current app also needs the compiler fixes for enum object layout, enum field
constructor context, enum object projection lifetime, callable transaction
emission, and browser transaction publication (Briev PRs #49–#53). A compiler
built from the Briev checkout containing those fixes was used for the build
and live startup described below. The earlier compatibility pin documents the
prior recovery baseline.

Correct browser prediction-score formatting also requires the guarded
tail-return compiler fix in [Briev PR #56](https://github.com/Randozart/briev-lang/pull/56).

From WSL, with the Briev compiler checkout beside this repository and the
MovieLens files available, run:

```bash
cd /mnt/c/Users/wotto/code/recommender-app
bash examples/recommender/run-demo.sh
```

The launcher defaults to `$HOME/briev-target/release/brievc`, the sibling
`briev-lang/lib` directory, and `/mnt/c/Users/wotto/AutAI/ml-100k` for MovieLens.
Set `BRIEVC`, `BRIEV_STDLIB`, or `MOVIELENS_DIR` to override these paths.
It derives `BRIEV_CONFIG_DIR` and `BRIEV_HOME` from `BRIEV_STDLIB`,
adds LLVM 17 tools when installed, and starts local PostgreSQL if it is down
(`sudo` may request your password). Set `PORT` and `FRONTEND_PORT` when the
standard 8080/8081 ports are occupied. The generated page receives the chosen backend port automatically; `?api=` can override it. Open the printed frontend URL. The
command builds both targets and keeps the frontend and backend running until
interrupted.

The app targets MovieLens 100K. Supply the dataset files yourself and set
`UDATA_PATH` to `u.data` and `UITEM_PATH` to `u.item`. The native service needs
local PostgreSQL on `127.0.0.1:5432`, a role/database configured for local
trust authentication, and the schema privileges needed by the app. Set
`PGUSER` and `PGDATABASE` accordingly.

With those dependencies available, `examples/recommender/run-demo.sh` builds
the native service and split browser app, serves the frontend, and starts the
service. It accepts `BRIEVC` (compiler executable), `BRIEV_STDLIB`,
`BRIEV_CONFIG_DIR`, `BRIEV_HOME` (normally derived from `BRIEV_STDLIB`), `MOVIELENS_DIR` or the individual dataset paths, `PGUSER`, `PGDATABASE`,
`PORT`, and `FRONTEND_PORT`.

The equivalent build commands are:

```bash
brievc build examples/recommender/server.bv \
  --stdlib-path "$BRIEV_STDLIB" --config-dir "$BRIEV_CONFIG_DIR" --out target/recommender-demo
brievc build examples/recommender/app.rbv \
  --stdlib-path "$BRIEV_STDLIB" --config-dir "$BRIEV_CONFIG_DIR" --split --out target/recommender-web
```

## Layout

- `examples/recommender/` contains the browser app, native service, worker
  processes, and shared application modules.
- `tests/fixtures/recommender/` contains targeted compiler/runtime and service
  gates. The runner documentation describes the required PostgreSQL setup.
- `docs/architecture/applications/` records the account, frontend, persistence,
  reactor, responsiveness, and server contracts.
- `docs/architecture/applications/recommender-system-map.md` gives component,
  runtime ownership, rating-flow, and startup/refresh diagrams.
- `docs/session/2026-10-25-bug-report.md` records the bugs found and fixed in
  the recommender recovery session, with causes and reproduction steps.

Some focused gates require the Briev compiler, stdlib, PostgreSQL, and browser
or Node dependencies. This repository does not claim to build independently
of those tools.

## License

See `LICENSE` and `NOTICE`. Briev sources use Apache-2.0 WITH LLVM-exception.
