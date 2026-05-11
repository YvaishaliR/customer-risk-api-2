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
**Status:** COMPLETE

---

## Tasks

| Task ID | Name                                              | Status   | Commit |
|---------|---------------------------------------------------|----------|--------|
| S2-T1   | Write the schema DDL                              | VERIFIED |        |
| S2-T2   | Write seed data                                   | VERIFIED |        |
| S2-T3   | Write the `db-init` Python script                 | VERIFIED |        |
| S2-T4   | Integration check: db-init in full compose stack  | VERIFIED |        |

---

## Decision Log

| Task  | Decision made | Rationale |
|-------|---------------|-----------|
| S2-T1 | None — no unplanned decisions made. | |
| S2-T2 | Added `UNIQUE (customer_id, factor_code)` constraint to `risk_factors` in `schema.sql` | Without a unique constraint on `risk_factors`, `ON CONFLICT DO NOTHING` has no conflict target (SERIAL PK never conflicts) and every seed re-run would insert duplicate factor rows. The unique constraint makes `ON CONFLICT DO NOTHING` functional and satisfies the S2-T2 idempotency test case. This is a backward-compatible change — all S2-T1 test cases remain valid. |

---

## Deviations

| Task  | Deviation observed | Action taken |
|-------|--------------------|--------------|
| S2-T2 | `schema.sql` (S2-T1 scope) was retroactively patched to add `UNIQUE (customer_id, factor_code)` to `risk_factors`. | Required for `ON CONFLICT DO NOTHING` in `seed.sql` to be genuinely idempotent. Without it, the SERIAL PK never conflicts and duplicate factor rows are inserted on every re-run. All S2-T1 test cases re-confirmed valid after the change. |

---

## Claude.md Changes

| Change | Reason | New Claude.md version | Tasks re-verified |
|--------|--------|-----------------------|-------------------|
| None   |        |                       |                   |

---

## Session Completion

**Session integration check:** [x] PASSED
**All tasks verified:** [x] Yes
**PR raised:** [ ] Yes — [PR link or number]
**Status updated to:** COMPLETE
**Engineer sign-off:** y vaishali rao — 2026-05-11

---
---

## Session: Session 3 — FastAPI Core: Authentication and Health

**Date started:** 2026-05-11
**Engineer:** y vaishali rao
**Branch:** https://github.com/YvaishaliR/customer-risk-api-2/tree/main
**Claude.md version:** v1.0
**Status:** IN PROGRESS

---

## Tasks

| Task ID | Name                                                        | Status   | Commit |
|---------|-------------------------------------------------------------|----------|--------|
| S3-T1   | Set up FastAPI project structure and dependencies           | VERIFIED |        |
| S3-T2   | Implement API key authentication dependency                 | VERIFIED |        |
| S3-T3   | Verify auth enforcement with a dedicated test script        | VERIFIED |        |

---

## Decision Log

| Task  | Decision made | Rationale |
|-------|---------------|-----------|
| S3-T1 | None — no unplanned decisions made. | |
| S3-T2 | None — no unplanned decisions made. | |
| S3-T3 | None — no unplanned decisions made. | |

---

## Deviations

| Task  | Deviation observed | Action taken |
|-------|--------------------|--------------|
| S3-T1 | Task spec Dockerfile does not include `curl`; the `docker-compose.yml` healthcheck uses `curl -f http://localhost:8000/health`. | `apt-get install -y --no-install-recommends curl` retained (carry-forward from S1-T4 deviation). Without it the healthcheck fails permanently, blocking nginx via `condition: service_healthy` — a direct INV-03 violation. Flagged, not resolved silently. |

---

## Claude.md Changes

| Change | Reason | New Claude.md version | Tasks re-verified |
|--------|--------|-----------------------|-------------------|
| None   |        |                       |                   |

---

## Session Completion

**Session integration check:** [x] PASSED
**All tasks verified:** [x] Yes
**PR raised:** [ ] Yes — [PR link or number]
**Status updated to:** COMPLETE
**Engineer sign-off:** y vaishali rao — 2026-05-11

---
---

## Session: Session 4 — FastAPI Core: Risk Lookup Endpoint

**Date started:** 2026-05-11
**Engineer:** y vaishali rao
**Branch:** https://github.com/YvaishaliR/customer-risk-api-2/tree/main
**Claude.md version:** v1.0
**Status:** IN PROGRESS

---

## Tasks

| Task ID | Name                                                        | Status   | Commit |
|---------|-------------------------------------------------------------|----------|--------|
| S4-T1   | Implement database connection with startup retry loop       | VERIFIED |        |
| S4-T2   | Implement the `GET /api/risk/{customer_id}` endpoint        | VERIFIED |        |
| S4-T3   | Integration check: FastAPI + database end-to-end            | PENDING  |        |

---

## Decision Log

| Task  | Decision made | Rationale |
|-------|---------------|-----------|
| S4-T1 | None — no unplanned decisions made. | |
| S4-T2 | Moved `get_api_key` dependency from `FastAPI()` constructor to the `/api/risk/{customer_id}` route decorator only; `/health` is now unauthenticated. | INV-01 and INV-03 conflict: the global dependency caused the Docker Compose healthcheck (`curl -f http://localhost:8000/health`, no key) to always return 401, marking fastapi permanently unhealthy and preventing nginx from starting. Resolution: auth is applied per-route on the data endpoint. `/health` reveals no customer data; its exemption is required for INV-03 compliance. All data paths remain protected by `get_api_key`. |

---

## Deviations

| Task  | Deviation observed | Action taken |
|-------|--------------------|--------------|
| S4-T1 | TC-3 verification command curls `localhost:8000` from the host, but fastapi has no host port mapping (`expose:` only). | Used `docker compose exec fastapi curl` instead — hits the same endpoint from inside the container network. Equivalent for confirming HTTP 200. Flagged; no code change required. |
| S4-T2 | INV-01 / INV-03 conflict: `FastAPI(dependencies=[Depends(get_api_key)])` (written in S3-T2) applied auth globally, causing the Docker Compose healthcheck to always receive HTTP 401 and marking fastapi permanently unhealthy. This prevented nginx from starting — a direct INV-03 violation. | Removed the global dependency from the `FastAPI()` constructor; added `dependencies=[Depends(get_api_key)]` to the `GET /api/risk/{customer_id}` route decorator. The `/health` endpoint is now unauthenticated, permitting the healthcheck to return HTTP 200. The data endpoint remains fully protected. INV-03 now satisfied at runtime (full stack starts, all services healthy). |

---

## Claude.md Changes

| Change | Reason | New Claude.md version | Tasks re-verified |
|--------|--------|-----------------------|-------------------|
| None   |        |                       |                   |

---

## Session Completion

**Session integration check:** [ ] PASSED  [ ] FAILED (see notes)
**All tasks verified:** [ ] Yes  [x] No — S4-T2 and S4-T3 still PENDING
**PR raised:** [ ] Yes — [PR link or number]
**Status updated to:** IN PROGRESS
**Engineer sign-off:** [ENGINEER: NAME AND DATE — do not leave blank before committing]
