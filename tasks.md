# Tasks: issue #3 — PDF points 31–39

Decision: use the authoritative course PDF numbering (page 5), not the original issue shorthand. PDF 31–33 = optimizer (Parte VI), 34–37 = optimization (Parte VII), 38–39 = concurrency (Parte VIII). The issue's leftmost-prefix theme is covered as an additional index experiment, not mislabeled as PDF P38–39.

- [x] P31–33: document statistics, estimated cardinality, cost-selection caveats and JOIN experiments.
  - Evidence: `src/parte_vi_vii_experimentos.sql`, `docs/parte_vi_explain_indices.md` (including observed Q1/Q3/P32 JSON plans on local MariaDB 10.6).
- [x] P34–37: supply eight original/alternative pairs, measurement protocol, index and write-side-effect hypotheses.
  - Evidence: Q1–Q8 in `src/parte_vi_vii_experimentos.sql`; `docs/parte_vi_explain_indices.md` distinguishes hypotheses from measurements.
- [x] P38–39: supply two-connection manual table/row locking protocol with bounded wait and rollback.
  - Evidence: `src/parte_viii_session_a.sql`, `src/parte_viii_session_b.sql`, `docs/parte_viii_bloqueos.md`.
- [x] Deterministic offline structural checks and read-only SQL plan syntax checks.
  - Evidence: `python src/validate_parte_vi_vii.py` and `python src/validate_parte_viii.py` passed; all 22 `EXPLAIN FORMAT=JSON` statements executed successfully on MariaDB 10.6 via connector. Lock scripts and SELECT payloads were not executed.
- [ ] Run all eight paired queries and record actual timings, cost fields where supported, real rows, refreshed statistics, JOIN effects and write overhead on a disposable database.
  - Blocked: no disposable 6M-row instance authorized; local read-only EXPLAIN sample only. An exact `COUNT(*)` attempt exceeded 45 s.
- [ ] Run P38–39 interactively in two sessions and record actual waits/errors; not safe to run automatically on the reachable database.

Issue: https://github.com/mmarcoschambi/hia-tp-optimizacion-bd/issues/3
Work units: `6845362` (optimizer), `793de86` (concurrency); final evidence commit recorded in Git history.
