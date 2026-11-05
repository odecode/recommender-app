# Collector checkpoint

Run the complete collector readiness gate from the app repository in Linux/WSL:

```sh
PATH=/usr/lib/llvm-18/bin:$PATH \
BRIEV_ROOT=../recommender-compiler-carveouts/load-collector-prerequisites \
BRIEVC=/home/otto/briev-target/debug/brievc \
bash benchmarks/load/check-collector.sh
```

Build that compiler from the recorded integration source before running. The
integration combines current-main compiler code, `feat/load-collector-prerequisites`
and `fix/read-file-descriptor-lifetime`. Do not substitute the dirty legacy
integration compiler: its Data-to-String alias cast conflicts with the current
stdlib formatter's copy-and-free ownership contract.

This command checks the validator, runs the full functional suite and nine
Valgrind cases, checks descriptor stability across 640 reads under Valgrind,
then runs two independent 5,000-sample self-observations at
500 Hz. It validates every row: schema, sample index, process identity, host
units, timestamp ordering, monotonic counters and missed-arrival accounting.
A failed observation or truncated run fails the checkpoint. Missed arrivals
remain visible and do not by themselves fail this collector-correctness gate.

Memory readiness uses samples 1,000 onward. The default allowed RSS range is
64 pages; virtual-memory range must be zero. These are explicit acceptance
limits, not measured guarantees. Override with `LOAD_PREFLIGHT_RSS_PAGES` and
`LOAD_PREFLIGHT_VM_BYTES`; both limits are recorded in provenance.

Artifacts are in `target/load-collector-checkpoint/`: raw CSV for both runs,
summary CSV, functional/memory logs, compiler and collector hashes, Git
revisions, and hashes for the complete compiler source/stdlib/config and
harness inputs. Source and binary changes during the run fail verification.
Valgrind's detailed logs remain in `target/load-memory/`. The collector's
process-lifetime stdout buffer may remain reachable; definite/indirect losses
or memory-access errors fail the gate.

These are collector correctness and bounded-memory results. Network journeys,
worker discovery, PSS, backend capacity and endurance campaigns are separate
checkpoints. The pending transport probe is not included in this passing gate.
