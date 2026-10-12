# Tasks: issue #3 — PDF points 31–39

Decision: follow the authoritative course PDF numbering (page 5), not the original issue shorthand. PDF 31–33 = optimizer (Parte VI), 34–37 = optimization (Parte VII), 38–39 = concurrency (Parte VIII). Leftmost-prefix examples supplement the PDF tasks.

- [x] P31–32: observe optimizer statistics, access choices and limitations of JSON cost reporting.
  - Evidence: `docs/parte_vi_explain_indices.md`; `src/run_parte_vi_vii_lab.py` captured before/after `ANALYZE TABLE` cardinality estimates and an `ALL` versus covering `ref` choice. MariaDB 10.6 did not emit numeric `cost_info.query_cost`.
- [x] P33: compare JOIN access with expression versus direct equality.
  - Evidence: the real `habitacion` is empty, so both original joins return zero; an isolated 18-room temporary fixture in `src/run_parte_vi_vii_lab.py --stage join-fixture` produced `BNL` versus `eq_ref`, 18 rows each. Not evidence of speedup on representative hotel master data.
- [x] P34–36: provide eight SQL pairs, bounded plan measurements, composite/covering indexes and leftmost-prefix checks.
  - Evidence: `src/parte_vi_vii_experimentos.sql` Q1–Q8, `src/run_parte_vi_vii_lab.py`, `docs/parte_vi_explain_indices.md`. Q1–Q6 timings use count variants; Q7/Q8 fetch results. Q8 pages matched on the same snapshot, but keyset was slower at offset 1000.
- [x] P37: record index footprint and rollback-only UPDATE probe; restore lab schema.
  - Evidence: four indexes built and removed; `Index_length` estimate 269 MB before, 740 MB with all four, 298 MB after cleanup and statistics refresh. Single-row write timings in docs are not general INSERT/DELETE throughput.
- [x] P38–39: run bounded two-connection table and row lock experiments.
  - Evidence: `src/run_parte_viii_lab.py --run` observed B waiting while A held table READ and row FOR UPDATE locks; updates finished after release (1.513 s and 1.503 s); a plain row SELECT took 0.001 s; final value unchanged. See `docs/parte_viii_bloqueos.md`.
- [x] Structural/syntax checks: both Python validators and `py_compile` passed; all 22 SQL `EXPLAIN FORMAT=JSON` statements succeeded on MariaDB 10.6 after revision.
- [ ] Follow-up for rigorous performance claims: repeat original payload SELECTs with controlled cache/snapshot and report latency distributions; provision representative hotel master data for the real P33 JOIN; measure representative INSERT/DELETE overhead. Exact 6M-row COUNT(*) exceeded the 60-second statement limit and Q3 expression count variant exceeded 12 seconds; numeric JSON costs unavailable on this server.

Issue: https://github.com/mmarcoschambi/hia-tp-optimizacion-bd/issues/3
Work units: `6845362`, `793de86`, `4581b79`, `2255c56`; evidence commit recorded in Git history. Existing `openspec/changes/issue-3/` is user-owned and was not staged.
