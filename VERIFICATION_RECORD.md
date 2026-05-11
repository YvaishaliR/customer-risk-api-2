# VERIFICATION_RECORD — Session 1: Project Scaffold and Environment

**Session:** Session 1 — Project scaffold and environment
**Date:** 2026-05-11
**Engineer:** y vaishali rao

---

## Task S1-T1 — Create project directory structure and `.env` contract
## Task S1-T2 — Write `docker-compose.yml` with all five services
## Task S1-T3 — Write stub Dockerfiles for all three custom services
## Task S1-T4 — Smoke test: full `docker compose up` with stubs

---

### Test Cases Applied

Source: EXECUTION_PLAN.md — all S1 task test cases.

| Case        | Scenario                                                        | Expected                                                        | Result                                                          |
|-------------|-----------------------------------------------------------------|-----------------------------------------------------------------|-----------------------------------------------------------------|
| S1-T1 TC-1  | `.env.example` exists and contains all 6 keys                   | All 6 keys present, no real secret values                       | PASS — `grep -c "=" .env.example` returns 6                    |
| S1-T1 TC-2  | `.env` is absent from the repository                            | `.gitignore` entry prevents accidental commit                   | PASS — `git check-ignore -q .env` exits 0                      |
| S1-T1 TC-3  | All 3 subdirectories exist                                      | `nginx/`, `fastapi/`, `db-init/` each present                   | PASS — all three directories confirmed                          |
| S1-T2 TC-1  | `docker compose config` parses without error                    | Exit code 0, no warnings                                        | PASS — `docker compose config --quiet` exits 0                  |
| S1-T2 TC-2  | `depends_on` chain is correct                                   | db-init→postgres (service_healthy); fastapi→db-init (service_completed_successfully); nginx→fastapi (service_healthy) | PASS — all three conditions confirmed via `docker compose config` |
| S1-T2 TC-3  | No host port on fastapi                                         | FastAPI's 8000 not in `ports:` section                          | PASS — no `published:` entry for fastapi in config output       |
| S1-T2 TC-4  | pgdata volume declared                                          | Volume present in `volumes:` block                              | PASS — `pgdata` resolves to `customer-risk-api-dg_pgdata`       |
| S1-T3 TC-1  | `docker compose build` exits 0                                  | All three images build without error                            | PASS — nginx, db-init, fastapi all `Built`, exit code 0         |
| S1-T3 TC-2  | nginx Dockerfile references correct base image                  | `nginx:1.25-alpine`                                             | PASS — `head -1 nginx/Dockerfile` confirmed                     |
| S1-T3 TC-2  | fastapi Dockerfile references correct base image                | `python:3.10-slim`                                              | PASS — `head -1 fastapi/Dockerfile` confirmed                   |
| S1-T3 TC-2  | db-init Dockerfile references correct base image                | `python:3.10-slim`                                              | PASS — `head -1 db-init/Dockerfile` confirmed                   |
| S1-T4 TC-1  | Cold start from `docker compose up`                             | All services reach expected state within 60s                    | PASS — all services ready at first poll (0s); images cached     |
| S1-T4 TC-2  | `GET http://localhost:80`                                       | HTTP 200 from nginx stub                                        | PASS — `curl` returns HTTP 200                                  |
| S1-T4 TC-3  | `docker compose ps` after full start                            | db-init `Exited (0)`, postgres/fastapi/nginx `Up`               | PASS — all four services in correct state confirmed             |
| S1-T4 TC-4  | `docker compose down -v`                                        | Clean teardown, `pgdata` volume removed                         | PASS — volume removed, no containers remain                     |

### Test Cases Added During Session

| Case  | Scenario | Expected | Result | Source |
|-------|----------|----------|--------|--------|
| ADD-1 | None discovered | | | |

---

### Prediction Statement

S1-T1 TC-1 | `.env.example` will contain exactly 6 lines with `=`, one per required variable (API_KEY, BASIC_AUTH_USER, BASIC_AUTH_PASSWORD, POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD). No real secret values.
S1-T1 TC-2 | `.gitignore` will contain `.env` causing `git check-ignore` to exit 0 and the file to be excluded from version control.
S1-T1 TC-3 | `nginx/`, `fastapi/`, and `db-init/` directories will all be present with at least one file (`.gitkeep`) inside each.
S1-T2 TC-1 | `docker compose config` will parse without error — exit code 0, no warnings.
S1-T2 TC-2 | `depends_on` chain will be: db-init waits on postgres (service_healthy); fastapi waits on db-init (service_completed_successfully); nginx waits on fastapi (service_healthy).
S1-T2 TC-3 | FastAPI will have no `ports:` entry — port 8000 exposed internally only via `expose:`.
S1-T2 TC-4 | `pgdata` named volume will be declared in the top-level `volumes:` block.
S1-T3 TC-1 | `docker compose build` will exit 0 — all three stub images build from their respective Dockerfiles without error.
S1-T3 TC-2 | Each Dockerfile's first line will be exactly the required base image: `nginx:1.25-alpine` for nginx, `python:3.10-slim` for fastapi and db-init.
S1-T4 TC-1 | All four services will reach expected states within 60 seconds: postgres `healthy`, db-init `Exited (0)`, fastapi `healthy`, nginx `Up`.
S1-T4 TC-2 | `curl http://localhost:80` will return HTTP 200 from the nginx stub `return 200` location block.
S1-T4 TC-3 | `docker compose ps --all` will show db-init as `Exited (0)` and the remaining three services as `Up`.
S1-T4 TC-4 | `docker compose down -v` will remove all containers and the `pgdata` named volume cleanly with exit code 0.

---

### CC Challenge Output

S1-T1 — What did you not test in this task?

Items not tested:
- Whether `docker-compose.yml` skeleton is parseable by `docker compose config` (no `.env` present yet for variable resolution — this is tested in S1-T2).
- Whether `.gitkeep` files are correctly tracked by git (i.e., `git status` shows them as untracked/staged).
- Whether `README.md` renders correctly as Markdown (only structural content was verified).
- Whether the `## Startup` heading and command are present in `README.md`.

Decision: rejected as out of scope for S1-T1. The `docker compose config` check belongs to S1-T2 per the execution plan. Git tracking of `.gitkeep` files and README content are implicit in the file creation steps and would add no meaningful signal at this stage.

S1-T2 — What did you not test in this task?

Items not tested:
- Whether the postgres healthcheck actually succeeds at runtime (requires a running container — tested in S1-T4).
- Whether the fastapi healthcheck curl succeeds at runtime (requires a built fastapi image — tested in S1-T4).
- Whether `restart: on-failure` on db-init correctly prevents it from looping indefinitely on repeated failure (runtime behaviour — tested in S1-T4).
- Whether `db-init` can reach postgres before the healthcheck passes (startup race condition — enforced by `depends_on: condition: service_healthy` and tested in S1-T4).

Decision: all items are runtime behaviours that require running containers. They are correctly deferred to S1-T4 (smoke test). No additional test cases added for S1-T2.

S1-T3 — What did you not test in this task?

Items not tested:
- Whether the stub fastapi image actually starts and responds to `GET /health` (requires a running container — tested in S1-T4).
- Whether the stub db-init image prints "db-init: no-op stub" and exits 0 at runtime (requires a running container — tested in S1-T4).
- Whether the stub nginx image starts and returns 200 for all requests (requires a running container — tested in S1-T4).
- Whether `docker compose build` still passes after the real application files are added in later sessions (regression risk — each session's build step covers this).

Decision: all items require running containers or belong to later sessions. Correctly deferred to S1-T4. No additional test cases added for S1-T3.

S1-T4 — What did you not test in this task?

Items not tested:
- Whether the stack recovers correctly if postgres is slow to start on a real cold start (no volume cache). All runs in this session used cached images; first-ever cold start on a fresh machine may take longer than 60s for image pulls alone.
- Whether `restart: on-failure` on db-init causes it to loop if it fails (negative path not exercised — the stub always exits 0).
- Whether fastapi rejects requests while db-init is still running (not applicable for stubs; enforced by `depends_on` at the compose layer, tested more thoroughly in S4).
- Whether nginx returns 200 for paths other than `/` (only root was curled).

Decision: image pull timing is a deployment concern, not a code correctness issue; flagged in scope decisions. The negative db-init path belongs to S2. The fastapi/db-init ordering guarantee is an INV-03 concern covered in S7-T1. nginx path coverage is out of scope for a stub smoke test. No additional test cases added.

---

### Code Review

S1-T1 — No invariant touched. No code review required.

S1-T2 — INV-03 — Review `docker-compose.yml`: confirm startup sequencing via `depends_on`.
S1-T3 — No invariant touched. No code review required.
S1-T4 — INV-03 (partial) — Review `verify/s1_smoke.sh`: confirm db-init exit code check and ordering.

Review finding:
- `fastapi` uses `condition: service_completed_successfully` on `db-init` — confirmed. This requires db-init to exit 0, not merely start.
- `db-init` uses `condition: service_healthy` on `postgres` — confirmed. Postgres must pass `pg_isready` before db-init container starts.
- `db-init` has `restart: on-failure`, not `restart: always` — confirmed. It will retry on non-zero exit but will not loop after a successful exit 0.
- No `restart: always` or `restart: unless-stopped` on db-init anywhere in the file — confirmed.

INV-03 satisfied at the compose layer.

S1-T4 INV-03 review finding:
- Poll loop checks `$DI_EXIT = "0"` explicitly — not just `$DI_STATE = "exited"`. A non-zero exit would not satisfy the condition and the loop would time out with a FAIL. Confirmed.
- The loop breaks only when postgres is healthy AND db-init has exited 0 AND fastapi is healthy simultaneously — the ordering guarantee is implicitly verified by the fact that all three conditions must be true at the same time, which can only happen after the compose `depends_on` chain has resolved correctly. Confirmed.
- `docker compose ps -q --all db-init` used (not `ps -q`) to correctly detect exited containers. Confirmed.

---

### Scope Decisions

S1-T1: `verify/` subdirectory was not created in this task. The execution plan places `verify/` creation in S1-T4 (smoke test script). Not creating it here is correct per scope.

S1-T1: `docker-compose.yml` was created as a skeleton (`services:` block only, no service definitions). Service definitions are the scope of S1-T2. Correct per spec.

S1-T2: No explicit `networks:` block declared. Task spec says "all services should share the default network (no explicit network declaration needed)." Docker Compose creates a default bridge network automatically. Correct per spec.

S1-T2: `start_period` not added to healthchecks. Task spec does not mention it; minimum implementation used. Flagged for S1-T4 in case startup timing requires adjustment.

S1-T3: No `WORKDIR` set in any stub Dockerfile. Task spec says "minimum needed to pass `docker compose build`". WORKDIR is not required for the stubs to build or run. The real fastapi Dockerfile (S3-T1) will add `WORKDIR /app`. Correct per scope.

S1-T4: The 60-second timeout was not exercised on a genuine cold start (no cached images). All runs used pre-built layers. On a truly fresh machine, image pulls for `postgres:15`, `python:3.10-slim`, and `nginx:1.25-alpine` may push total startup beyond 60s. The timeout in `s1_smoke.sh` covers runtime startup only, not image pull time — this is acceptable since `docker compose up -d --build` completes the pull/build phase before the poll loop begins.

S1-T4: `fastapi/Dockerfile` stub modified to install `curl` (deviation from S1-T3 minimum spec). Required for the healthcheck declared in `docker-compose.yml`. Without it, the entire `depends_on` chain stalls. Accepted and recorded as a deviation.

---

### Verification Verdict

[x] All planned cases passed (S1-T1: TC-1–3; S1-T2: TC-1–4; S1-T3: TC-1–2; S1-T4: TC-1–4)
[x] Test Cases Added During Session section complete — None discovered (all four tasks)
[x] CC challenge reviewed for S1-T1, S1-T2, S1-T3, and S1-T4
[x] Code review complete — INV-03 reviewed for S1-T2 (compose) and S1-T4 (script); S1-T1 and S1-T3 had no invariant touch
[x] Scope decisions documented

**Status: VERIFIED — Session 1 COMPLETE**
**Engineer sign-off:** y vaishali rao — 2026-05-11

---
---

# VERIFICATION_RECORD — Session 2: Database Schema and Seed Data

**Session:** Session 2 — Database schema and seed data
**Date:** 2026-05-11
**Engineer:** y vaishali rao

---

## Task S2-T1 — Write the schema DDL

<!-- S2-T2 through S2-T4 will be added as each task is completed. -->

---

### Test Cases Applied

Source: EXECUTION_PLAN.md — S2-T1 test cases.

| Case       | Scenario                                                        | Expected                                 | Result                                                                        |
|------------|-----------------------------------------------------------------|------------------------------------------|-------------------------------------------------------------------------------|
| S2-T1 TC-1 | Schema applied to fresh Postgres                                | Both tables created, no errors           | PASS — `CREATE TABLE` × 2, `CREATE INDEX`, exit 0; `\dt` and `\di` confirmed |
| S2-T1 TC-2 | `INSERT` with `tier='INVALID'`                                  | Rejected with check constraint violation | PASS — `violates check constraint "customers_tier_check"` (INV-06)            |
| S2-T1 TC-3 | `INSERT` risk_factor with non-existent `customer_id`            | Rejected with FK violation               | PASS — `violates foreign key constraint "risk_factors_customer_id_fkey"` (INV-08) |
| S2-T1 TC-4 | `INSERT` customer with `NULL tier`                              | Rejected with NOT NULL violation         | PASS — `null value in column "tier" violates not-null constraint` (INV-06)    |
| S2-T1 TC-5 | Re-run schema DDL against existing tables                       | No error (IF NOT EXISTS)                 | PASS — `NOTICE: relation already exists, skipping` × 3, no ERROR             |

### Test Cases Added During Session

| Case  | Scenario        | Expected | Result | Source |
|-------|-----------------|----------|--------|--------|
| ADD-1 | None discovered | | | |

---

### Prediction Statement

S2-T1 TC-1 | Schema will apply cleanly to a fresh database — `CREATE TABLE` for customers and risk_factors, `CREATE INDEX` for the customer_id index, exit code 0.
S2-T1 TC-2 | Inserting `tier='INVALID'` will trigger the `CHECK (tier IN ('LOW', 'MEDIUM', 'HIGH'))` constraint and be rejected with a check constraint violation error.
S2-T1 TC-3 | Inserting a risk_factor row referencing a non-existent `customer_id` will be rejected by the FOREIGN KEY constraint on `risk_factors.customer_id`.
S2-T1 TC-4 | Inserting a customer row with `tier=NULL` will be rejected by the `NOT NULL` constraint on the `tier` column.
S2-T1 TC-5 | Re-running the schema DDL against an already-initialised database will produce `NOTICE: relation already exists, skipping` for each object and exit 0 — no ERROR.

---

### CC Challenge Output

S2-T1 — What did you not test in this task?

Items not tested:
- Whether `ON DELETE CASCADE` on the FK correctly removes child rows when a parent customer is deleted (cascade behaviour not exercised — no DELETE tested).
- Whether the index on `risk_factors(customer_id)` is actually used by the query planner (requires EXPLAIN ANALYZE — out of scope for schema verification).
- Whether `created_at` correctly defaults to `NOW()` on INSERT (default value behaviour not asserted — implicit in schema DDL).
- Whether `SERIAL` correctly auto-increments `id` on successive inserts into `risk_factors`.

Decision: ON DELETE CASCADE behaviour is enforced by the FK definition and Postgres internals — it is not an application concern. Index usage, default values, and SERIAL behaviour are Postgres internals not requiring explicit verification at this stage. No additional test cases added.

---

### Code Review

S2-T1 — INV-06, INV-08, INV-09 — Review `db-init/schema.sql`: confirm constraint definitions.

Review finding:
- `tier VARCHAR(10) NOT NULL CHECK (tier IN ('LOW', 'MEDIUM', 'HIGH'))` — both NOT NULL and the value-set CHECK are present on a single column. Constraint name auto-assigned as `customers_tier_check`. Confirmed — satisfies INV-06.
- `customer_id VARCHAR(20) NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE` — FOREIGN KEY present with ON DELETE CASCADE. Constraint name auto-assigned as `risk_factors_customer_id_fkey`. Confirmed — satisfies INV-08. ON DELETE CASCADE is the intended behaviour: removing a customer removes all associated risk factors, preventing orphan rows.
- `customer_id VARCHAR(20) PRIMARY KEY` on customers — PRIMARY KEY (not UNIQUE). Postgres enforces both uniqueness and NOT NULL implicitly. Confirmed — satisfies INV-09.
- `CREATE TABLE IF NOT EXISTS` used for both tables — re-runs are safe. Confirmed.
- `CREATE INDEX IF NOT EXISTS idx_risk_factors_customer_id ON risk_factors (customer_id)` — index present for query performance. Confirmed.

---

### Scope Decisions

S2-T1: No explicit constraint names given for the CHECK and FK constraints. Postgres auto-assigns names (`customers_tier_check`, `risk_factors_customer_id_fkey`). The task spec does not require named constraints. Auto-naming is acceptable and poses no risk to invariant enforcement.

---

### Verification Verdict

[x] All planned cases passed (S2-T1: TC-1–5)
[x] Test Cases Added During Session section complete — None discovered
[x] CC challenge reviewed for S2-T1
[x] Code review complete — INV-06, INV-08, INV-09 reviewed for S2-T1
[x] Scope decisions documented

**Status: VERIFIED (S2-T1 only — session IN PROGRESS)**
**Engineer sign-off:** y vaishali rao — 2026-05-11
