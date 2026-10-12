# ODD Tasks: issue-3-pdf-31-39

Issue: mmarcoschambi/hia-tp-optimizacion-bd#3
Branch: issue-3
Decision: user selected authoritative PDF numbering over issue shorthand. PDF page 5 assigns 31–33 to Parte VI, 34–37 to Parte VII, and 38–39 to Parte VIII. Existing uncommitted tasks.md and openspec files are user-owned; preserve them.

## Objective

Provide reproducible MySQL/MariaDB experiments for optimizer statistics, cost, JOIN, eight query optimizations and two-session locking/concurrency; document observations only if run against hotel_db. No database client/server detected locally; deterministic checks cannot replace runtime evidence.

## Tasks

- [x] Unit A: Build optimizer (31–33) and eight paired query (34–37) reproducible experiments with accurate measurement protocol, expected JSON paths, side effects, docs and deterministic validation. Commit identity: `6845362`. Check: `python src/validate_parte_vi_vii.py` passed (offline only). Live measurements pending a database.
- [x] Unit B: Build safe two-session locking/concurrency experiments (38–39), documentation and deterministic validation. Commit identity: `793de86`. Check: `python src/validate_parte_viii.py` passed (offline only). Live blocking observations pending a database.
- [x] Final: update issue tasks.md with verified evidence and explicit pending live measurements. Offline structural checks and 22 read-only EXPLAIN statements passed. Commit identity: `5ec43e3`.
- [ ] External blocker: on an authorized disposable 6M-row database, run paired timings/statistics/index write overhead and two-session blocking trials; capture measured outcomes before claiming PDF 31–39 experimentally complete.

## Constraints

- No fabricated plan trees, costs, times or live lock observations. Local MariaDB 10.6 reachable via Python connector, but no CLI, disposable copy or authorization for DDL/locking experiments; `COUNT(*)` exceeded 45 seconds.
- Never run DDL or hold locks against a live DB automatically.
- Review workload: split independent optimizer and concurrency units into separate commits; no PR/push.
- Worker and explorer unavailable (subagent provider key missing; Loom bridge disabled); inline fallback recorded.
