# ODD Tasks: issue-3-pdf-31-39

Issue: mmarcoschambi/hia-tp-optimizacion-bd#3
Branch: issue-3
Decision: user selected authoritative PDF numbering over issue shorthand. PDF page 5 assigns 31–33 to Parte VI, 34–37 to Parte VII, and 38–39 to Parte VIII. Existing uncommitted tasks.md and openspec files are user-owned; preserve them.

## Objective

Provide reproducible MariaDB experiments for optimizer statistics, cost, JOIN, eight query optimizations and two-session locking/concurrency; document observations only if run against hotel_db. Local MariaDB 10.6 was explicitly authorized as a disposable lab; deterministic checks complement, not replace, runtime evidence.

## Tasks

- [x] Unit A: Build optimizer (31–33) and eight paired query (34–37) reproducible experiments with accurate measurement protocol, expected JSON paths, side effects, docs and deterministic validation. Commit identity: `6845362`. Check: `python src/validate_parte_vi_vii.py` passed (offline only). Live measurements pending a database.
- [x] Unit B: Build safe two-session locking/concurrency experiments (38–39), documentation and deterministic validation. Commit identity: `793de86`. Check: `python src/validate_parte_viii.py` passed (offline only). Live blocking observations pending a database.
- [x] Final: update issue tasks.md with verified evidence and explicit pending live measurements. Offline structural checks and 22 read-only EXPLAIN statements passed. Commit identity: `5ec43e3`.
- [x] Lab concurrency: user authorized localhost:3306/hotel_db as disposable TP environment; corrected B's autocommit precondition and measured table/row waits with two sessions. Commit identity: `4581b79`. Check: structural validator, py_compile and `python src/run_parte_viii_lab.py --run` passed; observed 1.513 s table and 1.503 s row wait, plain read 0.001 s, final value unchanged.
- [x] Lab optimizer: bounded eight-pair plan/measurement variants, refreshed statistics, four index builds, rollback-only write probes, keyset page equivalence and 18-room temporary JOIN fixture. Commit identity: `2255c56`. Checks: validators, py_compile, 22 EXPLAIN statements passed. Limits: no numeric cost_info, exact COUNT(*) timed out after 60 s, Q3 originals timed out at 12 s, Q6 real JOIN empty, Q1–Q6 measured count variants, only one pass. All owned indexes removed.
- [x] Close evidence: update docs/tasks with observed results, limitations and checks. Commit identity: `5342793`. Checks: validators, py_compile and diff checks passed; no temporary indexes remain.
- [ ] Payload/cache work unit: benchmark original payload SELECTs in repeated, bounded warm-state runs; capture row equivalence, Q7 payload differences and Q8 page equivalence. Preserve database indexes and restore owned experimental indexes. Commit identity: pending.
- [ ] Follow-up outside this request: obtain representative hotel master rows for real JOIN and measure INSERT/DELETE overhead before claiming a general performance improvement.

## Constraints

- No fabricated plan trees, costs, times or live lock observations. Local MariaDB 10.6 available via Python connector; user authorized this exact database as disposable. `COUNT(*)` previously exceeded 45 seconds.
- B connection defaults to autocommit=0 (observed), despite the initial protocol's autocommit=1 assumption; set it explicitly and guarantee cleanup. DDL may take minutes; bound SELECT and lock waits.
- Review workload: split independent optimizer and concurrency units into separate commits; no PR/push.
- Worker and explorer unavailable (subagent provider key missing; Loom bridge disabled); inline fallback recorded.
