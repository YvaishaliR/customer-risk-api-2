# SESSION_LOG.md

## Session: Session 1 — Project Scaffold and Environment

**Date started:** 2026-05-11
**Engineer:** y vaishali rao
**Branch:** https://github.com/YvaishaliR/customer-risk-api-2/tree/main
**Claude.md version:** v1.0
**Status:** COMPLETE

---

## Tasks

| Task ID | Name                                                    | Status   | Commit |
|---------|---------------------------------------------------------|----------|--------|
| S1-T1   | Create project directory structure and `.env` contract  | VERIFIED |        |
| S1-T2   | Write `docker-compose.yml` with all five services       | VERIFIED |        |
| S1-T3   | Write stub Dockerfiles for all three custom services    | VERIFIED |        |
| S1-T4   | Smoke test: full `docker compose up` with stubs         | VERIFIED |        |

<!-- Update status: PENDING → IN PROGRESS → VERIFIED → (optionally BLOCKED) -->
<!-- Record commit hash after each VERIFIED task. Use 'Task N.N — ' prefix consistently. -->

---

## Decision Log

<!-- Record any decision made during the session that is not in EXECUTION_PLAN.md. -->
| Task  | Decision made | Rationale |
|-------|---------------|-----------|
| S1-T1 | Used `.gitkeep` as the placeholder file in each subdirectory | Task spec said ".gitkeep or equivalent". `.gitkeep` is the conventional Git placeholder for tracking empty directories. No functional difference from any alternative. |
| S1-T2 | Used `$$POSTGRES_USER` / `$$POSTGRES_DB` in postgres healthcheck test string | Docker Compose expands `$VAR` from the host `.env` at parse time. `$$VAR` escapes to a literal `$` so the container shell expands it at healthcheck runtime instead — the correct behaviour for referencing container environment variables inside a `test:` array. |

---

## Deviations

| Task  | Deviation observed | Action taken |
|-------|--------------------|--------------|
| S1-T4 | `fastapi/Dockerfile` stub did not include `curl`, which is required by the `docker-compose.yml` healthcheck (`curl -f http://localhost:8000/health`). Without it, the fastapi healthcheck fails permanently, blocking nginx from ever starting. | Added `RUN apt-get update && apt-get install -y --no-install-recommends curl` to the fastapi stub Dockerfile. Flagged as a deviation from the S1-T3 "minimum" spec; driven by S1-T4 smoke test requirement. The real Dockerfile (S3-T1) will carry this forward. |
| S1-T4 | `docker compose ps -q db-init` returns nothing for exited containers — only running containers appear without `--all`. This caused the db-init state check to read `unknown / exit=-1` indefinitely. | Changed to `docker compose ps -q --all db-init` in `verify/s1_smoke.sh`. This is a Docker Compose CLI behaviour, not a project configuration issue. |

---

## Claude.md Changes

| Change | Reason | New Claude.md version | Tasks re-verified |
|--------|--------|-----------------------|-------------------|
| None   |        |                       |                   |

---

## Session Completion

<!-- Fill in when all tasks in this session are VERIFIED. -->
**Session integration check:** [x] PASSED
**All tasks verified:** [x] Yes
**PR raised:** [ ] Yes — [PR link or number]
**Status updated to:** COMPLETE
**Engineer sign-off:** y vaishali rao — 2026-05-11

---
---

## Session: Session 2 — Database Schema and Seed Data

**Date started:** 2026-05-11
**Engineer:** y vaishali rao
**Branch:** https://github.com/YvaishaliR/customer-risk-api-2/tree/main
**Claude.md version:** v1.0
**Status:** IN PROGRESS

---

## Tasks

| Task ID | Name                                              | Status   | Commit |
|---------|---------------------------------------------------|----------|--------|
| S2-T1   | Write the schema DDL                              | VERIFIED |        |
| S2-T2   | Write seed data                                   | PENDING  |        |
| S2-T3   | Write the `db-init` Python script                 | PENDING  |        |
| S2-T4   | Integration check: db-init in full compose stack  | PENDING  |        |

---

## Decision Log

| Task  | Decision made | Rationale |
|-------|---------------|-----------|
| S2-T1 | None — no unplanned decisions made. | |

---

## Deviations

| Task | Deviation observed | Action taken |
|------|--------------------|--------------|
|      | None               |              |

---

## Claude.md Changes

| Change | Reason | New Claude.md version | Tasks re-verified |
|--------|--------|-----------------------|-------------------|
| None   |        |                       |                   |

---

## Session Completion

**Session integration check:** [ ] PASSED  [ ] FAILED (see notes)
**All tasks verified:** [ ] Yes  [x] No — S2-T2 through S2-T4 still PENDING
**PR raised:** [ ] Yes — [PR link or number]
**Status updated to:** IN PROGRESS
**Engineer sign-off:** [ENGINEER: NAME AND DATE — do not leave blank before committing]
