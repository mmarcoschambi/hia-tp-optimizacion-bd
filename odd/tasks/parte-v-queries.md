# ODD Tasks: parte-v-queries

Issue: mmarcoschambi/hia-tp-optimizacion-bd#2
Branch: issue-2

## Objective

Implement, optimize, and document Parte V complex business queries for points 24 through 30 over `hotel_db`, focused on the 6M-row `reserva` table and related hotel domain tables.

## Tasks

- [x] Punto 24: Query reservations by date range and status with counts and amounts.
  - Evidence: `src/parte_v_consultas_negocio.sql` P24.
- [x] Punto 25: Query guest relationship and history using INNER JOIN and LEFT JOIN.
  - Evidence: `src/parte_v_consultas_negocio.sql` P25.
- [x] Punto 26: Analyze occupancy by hotel and room type.
  - Evidence: `src/parte_v_consultas_negocio.sql` P26.
- [x] Punto 27: Detect cancellation patterns with subqueries / EXISTS.
  - Evidence: `src/parte_v_consultas_negocio.sql` P27.
- [x] Punto 28: Segment customers and classify with CASE WHEN.
  - Evidence: `src/parte_v_consultas_negocio.sql` P28.
- [x] Punto 29: Add advanced aggregations with GROUP BY, HAVING, and performance-oriented ordering.
  - Evidence: `src/parte_v_consultas_negocio.sql` P29.
- [x] Punto 30: Document efficient keyset pagination for large volumes, avoiding high OFFSET.
  - Evidence: `src/parte_v_consultas_negocio.sql` P30; validator asserts no `OFFSET` in P30.
- [x] Verification: Run deterministic syntax/structural validations.
  - Evidence: `python src/validate_parte_v_sql.py` passed.
- [ ] Commit: Create one Conventional Commit on branch `issue-2`.

## Evidence

- SQL script: `src/parte_v_consultas_negocio.sql`.
- Documentation: `docs/parte_v_consultas_negocio.md`.
- Deterministic validation: `src/validate_parte_v_sql.py`.
- Delegation note: attempted `gentle-ai-worker`; Loom returned `agent_not_ready`, so implementation proceeded inline with bounded edit surfaces.
