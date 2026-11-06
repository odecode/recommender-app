# Retained journey evidence

These small, non-secret artifacts were copied from the final verified run
`target/journey-verified` before the Windows-to-Linux migration. `valgrind.txt`
is the Valgrind log with trailing whitespace removed and its extension changed so log-ignore rules do not hide
it. Input paths identify the historical machine; source and binary hashes remain
recorded for comparison. Rebuild binaries on Linux and record new hashes.

The server log and credentials are deliberately excluded. Dataset/database files
and compiled binaries are reproducible dependencies, not Git artifacts.

See ../../plans/2026-11-06-authenticated-load-journey-results.md for interpretation.
