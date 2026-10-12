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
- [x] Lab concurrency: user authorized localhost:3306/hotel_db as disposable TP environment; corrected B's autocommit precondition and measured table/row waits with two sessions. Commit identity: `4581b79`. Check: structural validator, py_compile and `python src/run_parte_viii_lab.py --run` passed; observed 1.513 s table and 1.503 s row wait, plain read 0.001 s, final value unchanged.
- [ ] Lab optimizer: bounded eight-pair measurements, statistics/index choices and write overhead; report unavailable cost fields. Commit identity: pending.
- [ ] Close evidence: update docs/tasks with observed results, limitations and checks; record commit identity. Commit identity: pending.

## Constraints

- No fabricated plan trees, costs, times or live lock observations. Local MariaDB 10.6 available via Python connector; user authorized this exact database as disposable. `COUNT(*)` previously exceeded 45 seconds.
- B connection defaults to autocommit=0 (observed), despite the initial protocol's autocommit=1 assumption; set it explicitly and guarantee cleanup. DDL may take minutes; bound SELECT and lock waits.
- Review workload: split independent optimizer and concurrency units into separate commits; no PR/push.
- Worker and explorer unavailable (subagent provider key missing; Loom bridge disabled); inline fallback recorded.
