# Briev Recommender

A browser-based movie recommender with account registration, sign-in, rating,
and live recommendations. This repository contains the application sources,
its focused compiler/runtime gates, and the recommender architecture notes.

## Build dependency

The Briev compiler and standard library are separate dependencies and are not
vendored here. This repository is an application source repository; a checkout
alone is not sufficient to compile it. Use a compatible Briev compiler build
and point `BRIEV_STDLIB` at that compiler checkout's `lib/std` directory.

Compatibility pin: `Randozart/briev-lang` commit `24a0fd0e` (2026-10-29). It
includes the state-collection lifetime fix, top-level unpacked-instance
assignment, enum-return ownership, defn flush isolation, keyed DOM-row churn,
Otto Westerlund’s pooled-object replacement fix (PR #48), and the browser view
snapshot/flush-record fixes. Older compiler commits build the app but trap on
catalogue load, lose the registration response, corrupt the rendered
catalogue, or fail the browser responsiveness gate.

The app targets MovieLens 100K. Supply the dataset files yourself and set
`UDATA_PATH` to `u.data` and `UITEM_PATH` to `u.item`. The native service needs
local PostgreSQL on `127.0.0.1:5432`, a role/database configured for local
trust authentication, and the schema privileges needed by the app. Set
`PGUSER` and `PGDATABASE` accordingly.

With those dependencies available, `examples/recommender/run-demo.sh` builds
the native service and split browser app, serves the frontend, and starts the
service. It accepts `BRIEVC` (compiler executable), `BRIEV_STDLIB`,
`MOVIELENS_DIR` or the individual dataset paths, `PGUSER`, `PGDATABASE`,
`PORT`, and `FRONTEND_PORT`.

The equivalent build commands are:

```bash
brievc build examples/recommender/server.bv \
  --stdlib-path "$BRIEV_STDLIB" --out target/recommender-demo
brievc build examples/recommender/app.rbv \
  --stdlib-path "$BRIEV_STDLIB" --split --out target/recommender-web
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
