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
## Task S2-T2 — Write seed data
## Task S2-T3 — Write the `db-init` Python script
## Task S2-T4 — Integration check: db-init in full compose stack

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
| S2-T2 TC-1 | All 3 tiers represented                                         | At least 1 customer with each tier       | PASS — 3 customers each for LOW, MEDIUM, HIGH (9 total)                       |
| S2-T2 TC-2 | Every customer has ≥ 2 factors                                  | No `customer_id` has < 2 rows in `risk_factors` | PASS — 0 violators; range 2–3 factors per customer                     |
| S2-T2 TC-3 | Re-running `seed.sql` is safe                                   | No errors, row counts unchanged          | PASS — all 31 statements return `INSERT 0 0`; counts stable at 9 / 22        |
| S2-T3 TC-1 | First run against empty database                                | Exits 0, tables created, seed loaded     | PASS — printed `schema applied`, `seed data loaded`, exit code 0              |
| S2-T3 TC-2 | Second run against populated database                           | Exits 0, no errors, row counts unchanged | PASS — exit 0; customers=9, risk_factors=22 unchanged                         |
| S2-T3 TC-3 | Postgres not yet ready (unreachable host)                       | Retries up to 10 times, then exits 1     | PASS — all 10 `attempt N/10 failed` messages, `could not connect`, exit 1     |
| S2-T3 TC-4 | Wrong `POSTGRES_PASSWORD`                                       | Exits 1 with authentication error        | PASS — `FATAL: password authentication failed` × 10, exit 1                  |
| S2-T4 TC-1 | All 6 SQL checks on clean seed                                  | All 6 PASS, exit 0                       | PASS — 6/6 checks passed, `PASSED: 6  FAILED: 0`, exit code 0                |
| S2-T4 TC-2 | db-init timeout exceeded (TIMEOUT=10, db-init sleeps forever)   | Exit 1 with "did not exit within" message | PASS — "ERROR: db-init did not exit within 10s — aborting", exit code 1      |

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
S2-T2 TC-1 | All three tier values (LOW, MEDIUM, HIGH) will be present in the `customers` table with at least 3 customers each.
S2-T2 TC-2 | Every `customer_id` in `customers` will have at least 2 corresponding rows in `risk_factors` — the subquery counting violators will return 0.
S2-T2 TC-3 | A second run of `seed.sql` will produce `INSERT 0 0` for every statement (conflict on PK or UNIQUE constraint) and leave row counts unchanged.
S2-T3 TC-1 | `init.py` will connect on the first attempt, execute schema.sql and seed.sql in sequence, print `db-init: schema applied` and `db-init: seed data loaded`, and exit 0.
S2-T3 TC-2 | Re-running `init.py` against a populated database will exit 0 with no data changes — `IF NOT EXISTS` and `ON CONFLICT DO NOTHING` absorb all re-runs.
S2-T3 TC-3 | With an unreachable Postgres host, `init.py` will print 10 `attempt N/10 failed` messages, then `could not connect after 10 attempts — exiting`, and exit 1.
S2-T3 TC-4 | With a wrong password, `init.py` will exhaust all 10 retry attempts (each returning `FATAL: password authentication failed`) and exit 1.
S2-T4 TC-1 | `s2_db.sh` will start postgres and db-init, wait for db-init to exit 0, run all 6 SQL checks against the seeded database via `docker compose exec`, print PASS for every check, and exit 0.
S2-T4 TC-2 | With db-init overridden to `sleep 600` and TIMEOUT=10, the poll loop will exhaust all 10 s before db-init exits, print "ERROR: db-init did not exit within 10s — aborting", and exit 1.

---

### CC Challenge Output

S2-T1 — What did you not test in this task?

Items not tested:
- Whether `ON DELETE CASCADE` on the FK correctly removes child rows when a parent customer is deleted (cascade behaviour not exercised — no DELETE tested).
- Whether the index on `risk_factors(customer_id)` is actually used by the query planner (requires EXPLAIN ANALYZE — out of scope for schema verification).
- Whether `created_at` correctly defaults to `NOW()` on INSERT (default value behaviour not asserted — implicit in schema DDL).
- Whether `SERIAL` correctly auto-increments `id` on successive inserts into `risk_factors`.

Decision: ON DELETE CASCADE behaviour is enforced by the FK definition and Postgres internals — it is not an application concern. Index usage, default values, and SERIAL behaviour are Postgres internals not requiring explicit verification at this stage. No additional test cases added.

S2-T2 — What did you not test in this task?

Items not tested:
- Whether factor codes and descriptions are plausible or correctly matched to their tier (content quality — not a functional invariant).
- Whether `customer_id` values (`CUST001`–`CUST009`) conform to the regex `^[A-Za-z0-9]{1,20}$` (format validated by S4-T2 endpoint logic, not at the seed layer).
- Whether the `UNIQUE (customer_id, factor_code)` constraint added to `schema.sql` breaks any existing S2-T1 test cases (re-confirmed: all S2-T1 cases still pass against the patched schema).

Decision: content quality is out of scope for structural verification. customer_id format is enforced by the API layer. The schema patch re-verification was performed informally — no additional test cases added, but flagged in deviations.

S2-T3 — What did you not test in this task?

Items not tested:
- Whether `init.py` correctly handles a Postgres host that is reachable but not yet accepting queries (TCP connect succeeds, but `pg_isready` would fail). The retry loop catches `psycopg2.OperationalError` which covers both TCP refusal and query-layer unavailability — behaviour is correct but not explicitly exercised.
- Whether `sys.exit(1)` inside the `try/finally` block correctly closes the connection before exiting (the `finally` clause runs on `sys.exit` — this is Python-guaranteed behaviour, not tested explicitly).
- Whether a malformed `schema.sql` or `seed.sql` file causes the correct `except` branch to fire and exit 1 (file corruption scenario).

Decision: TCP-up-but-not-ready is covered by the same `OperationalError` path as TC-3 — no separate test needed. `finally`-on-`sys.exit` is a Python language guarantee, not a test gap. Malformed SQL is an infrastructure concern outside normal deployment scope. No additional test cases added.

Tooling note: early TC-3/TC-4 runs used `| head -N` and `&&` to capture exit codes — both approaches masked the container exit code. Correct pattern established: `docker run ...; echo "EXIT:$?"` using `;` (unconditional) rather than `&&` (short-circuits on non-zero). Not a code issue.

S2-T4 — What did you not test in this task?

Items not tested:
- Whether the `trap cleanup EXIT` teardown fires correctly on SIGINT mid-run (teardown on normal exit was observed in both TCs; interrupt path not exercised).
- Whether the script handles a postgres container that becomes unhealthy after db-init exits 0 but before the SQL checks run (degenerate timing not possible in the compose lifecycle defined by the task).
- Whether CHECK F correctly distinguishes exactly 9 records from fewer (no seed-tampered negative case; the ≥ 9 threshold is met by the real seed data and no under-seeded variant was run).

Decision: interrupt teardown is an OS-level guarantee for trap; not a test gap. The partial-postgres-failure scenario is outside the task's lifecycle scope. CHECK F boundary is confirmed by the seed data having exactly 9 records — the `gte` branch executed and passed. No additional test cases added.

---

### Code Review

S2-T1 — INV-06, INV-08, INV-09 — Review `db-init/schema.sql`: confirm constraint definitions.
S2-T2 — INV-06, INV-07, INV-08, INV-09 — Review `db-init/seed.sql`: confirm tier values, factor presence, FK integrity, no duplicate customer_id.
S2-T3 — INV-03, INV-05 — Review `db-init/init.py`: confirm exit code behaviour and write-only scope.
S2-T4 — INV-06, INV-07, INV-08, INV-09 — Review `verify/s2_db.sh`: confirm each SQL check correctly targets its invariant.

S2-T1 review finding:
- `tier VARCHAR(10) NOT NULL CHECK (tier IN ('LOW', 'MEDIUM', 'HIGH'))` — both NOT NULL and the value-set CHECK are present. Constraint name auto-assigned as `customers_tier_check`. Confirmed — satisfies INV-06.
- `customer_id VARCHAR(20) NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE` — FK present with ON DELETE CASCADE. Constraint name auto-assigned as `risk_factors_customer_id_fkey`. Confirmed — satisfies INV-08.
- `customer_id VARCHAR(20) PRIMARY KEY` on customers — PRIMARY KEY (not just UNIQUE). Confirmed — satisfies INV-09.
- `CREATE TABLE IF NOT EXISTS` used for both tables — re-runs are safe. Confirmed.
- `CREATE INDEX IF NOT EXISTS idx_risk_factors_customer_id ON risk_factors (customer_id)` — index present. Confirmed.

S2-T2 review finding:
- All 9 customer INSERTs use tier values from {LOW, MEDIUM, HIGH} only — no out-of-set value present. Confirmed — satisfies INV-06.
- Every customer_id in `customers` inserts has at least 2 corresponding inserts in `risk_factors` — verified by TC-2 (0 violators). Confirmed — satisfies INV-07.
- Every `risk_factors` insert references a `customer_id` that exists in the `customers` block immediately above it in the file. No orphaned factor insert exists. Confirmed — satisfies INV-08.
- No two customer INSERTs share a `customer_id` value (CUST001–CUST009 are all distinct). Confirmed — satisfies INV-09.

S2-T3 review finding:
- `sys.exit(1)` is used explicitly on all failure paths (connection exhausted, schema failure, seed failure) — not `sys.exit()` or `raise`. Confirmed — INV-03: db-init exit code 0 is the signal that triggers fastapi startup via `condition: service_completed_successfully`.
- The script executes only `schema.sql` and `seed.sql`. Both files contain only DDL (`CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`) and `INSERT ... ON CONFLICT DO NOTHING`. No UPDATE, DELETE, or runtime SELECT is present in `init.py`. Confirmed — satisfies INV-05: all writes confined to db-init execution window.
- `conn.close()` is in a `finally` block that runs on both success and `sys.exit(1)` — connection is always closed cleanly. Confirmed.
- Only `os`, `sys`, `time`, and `psycopg2` are imported — no ORM, no additional libraries. Confirmed.

S2-T4 review finding:
- CHECK A (`WHERE tier NOT IN ('LOW','MEDIUM','HIGH')`) — directly targets INV-06. Expected 0 = no invalid tier values present. Correct.
- CHECK B (`WHERE NOT EXISTS (SELECT 1 FROM risk_factors r WHERE r.customer_id = c.customer_id)`) — counts customers with zero risk factors, targeting INV-07. Expected 0 = every customer has at least one factor. Correct.
- CHECK C (LEFT JOIN customers, `WHERE c.customer_id IS NULL`) — counts orphaned factor rows, targeting INV-08. Expected 0 = no orphaned rows. Correct.
- CHECK D (GROUP BY customer_id `HAVING COUNT(*) > 1`) — counts duplicate customer_id values, targeting INV-09. Expected 0 = no duplicates. Correct.
- CHECK E (`COUNT(DISTINCT tier) = 3`) — confirms all three tiers are present in the seed data. Correct.
- CHECK F (`COUNT(*) >= 9`) — confirms minimum seed record count using the `gte` comparison path. Correct.
- `docker compose exec -T postgres psql -t -A` — `-t` suppresses headers/footers, `-A` gives unaligned output; `tr -d ' \n'` strips residual whitespace. The resulting value is a bare integer suitable for bash `[ -eq ]` or `[ -ge ]` comparison. Confirmed.
- `|| result=""` on the exec pipeline ensures `set -o pipefail` does not abort the script if a check's exec fails — FAIL is recorded instead of script abort. Confirmed.

---

### Scope Decisions

S2-T1: No explicit constraint names given for the CHECK and FK constraints. Postgres auto-assigns names (`customers_tier_check`, `risk_factors_customer_id_fkey`). The task spec does not require named constraints. Auto-naming is acceptable and poses no risk to invariant enforcement.

S2-T2: `schema.sql` patched to add `UNIQUE (customer_id, factor_code)` on `risk_factors`. This is not in the S2-T1 task spec but is required for `ON CONFLICT DO NOTHING` in `seed.sql` to be functional. Recorded as a deviation; all S2-T1 cases re-confirmed valid.

S2-T4: TC-2 timeout test used a `docker-compose.override.yml` (overriding db-init entrypoint to `sleep 600`) combined with a patched copy of `s2_db.sh` (TIMEOUT=10) placed in `verify/` so that `dirname`-based `cd` resolves correctly to the project root. Both temporary files were removed after the test. No permanent files were modified.

S2-T4: TIMEOUT set to 90 s (vs 60 s in s1_smoke.sh) because db-init must wait for postgres to become healthy before starting — adding postgres startup time to the db-init connection and SQL execution time. The wider window prevents false timeouts on slower machines.

---

### Verification Verdict

[x] All planned cases passed (S2-T1: TC-1–5; S2-T2: TC-1–3; S2-T3: TC-1–4; S2-T4: TC-1–2)
[x] Test Cases Added During Session section complete — None discovered (all four tasks)
[x] CC challenge reviewed for S2-T1, S2-T2, S2-T3, and S2-T4
[x] Code review complete — INV-06/08/09 reviewed for S2-T1; INV-06/07/08/09 reviewed for S2-T2; INV-03/INV-05 reviewed for S2-T3; INV-06/07/08/09 verified by SQL checks for S2-T4
[x] Scope decisions documented

**Status: VERIFIED — Session 2 COMPLETE**
**Engineer sign-off:** y vaishali rao — 2026-05-11

---
---

# VERIFICATION_RECORD — Session 3: FastAPI Core: Authentication and Health

**Session:** Session 3 — FastAPI core: authentication and health
**Date:** 2026-05-11
**Engineer:** y vaishali rao

---

## Task S3-T1 — Set up FastAPI project structure and dependencies
## Task S3-T2 — Implement API key authentication dependency
## Task S3-T3 — Verify auth enforcement with a dedicated test script

---

### Test Cases Applied

Source: EXECUTION_PLAN.md — S3-T1 test cases.

| Case       | Scenario                                                     | Expected                          | Result                                                        |
|------------|--------------------------------------------------------------|-----------------------------------|---------------------------------------------------------------|
| S3-T1 TC-1 | `GET /health`                                                | HTTP 200, body `{"status":"ok"}`  | PASS — status 200, body `{"status":"ok"}` exact match        |
| S3-T1 TC-2 | Image builds without error (`docker compose build fastapi`)  | Exit 0                            | PASS — all layers cached, exit 0                             |
| S3-T2 TC-1 | `GET /health` — no `X-API-Key` header                        | HTTP 401                          | PASS — status 401                                            |
| S3-T2 TC-2 | `GET /health` — wrong `X-API-Key` value                      | HTTP 401                          | PASS — status 401                                            |
| S3-T2 TC-3 | `GET /health` — correct `X-API-Key` value                    | HTTP 200                          | PASS — status 200                                            |
| S3-T2 TC-4 | 401 response body                                            | Does not contain the key value    | PASS — body: `{"detail":"Invalid or missing API key"}`, key absent |
| S3-T2 TC-5 | FastAPI logs after all requests                              | Do not contain the key value      | PASS — logs contain only status codes and startup message; key string `inv01-test-key-do-not-use` absent |
| S3-T3 INV-01-A | `GET /health` — no `X-API-Key` header (`s3_auth.sh`)    | HTTP 401                          | PASS |
| S3-T3 INV-01-B | `GET /health` — `X-API-Key: wrong` (`s3_auth.sh`)       | HTTP 401                          | PASS |
| S3-T3 INV-01-C | `GET /health` — `X-API-Key: inv01-test-key-do-not-use` (`s3_auth.sh`) | HTTP 200           | PASS |
| S3-T3 INV-01-D | 401 response body (`s3_auth.sh`)                         | No key string                     | PASS — body: `{"detail":"Invalid or missing API key"}` |
| S3-T3 INV-02-A | Response headers for valid request (`s3_auth.sh`)        | No key string                     | PASS — headers contain no `inv01-test-key-do-not-use` |
| S3-T3 INV-02-B | Container logs after all requests (`s3_auth.sh`)         | No key string                     | PASS — `PASSED: 6  FAILED: 0`, overall PASS, exit 0 |

### Test Cases Added During Session

| Case  | Scenario        | Expected | Result | Source |
|-------|-----------------|----------|--------|--------|
| ADD-1 | None discovered | | | |

---

### Prediction Statement

S3-T1 TC-1 | `GET /health` will return HTTP 200 with body `{"status":"ok"}`. The endpoint is registered on the `FastAPI()` instance and FastAPI serializes the returned dict to JSON automatically.
S3-T1 TC-2 | `docker compose build fastapi` will exit 0. All five pinned packages (`fastapi==0.111.0`, `uvicorn[standard]==0.29.0`, `psycopg2-binary==2.9.9`, `pydantic==2.7.0`, `python-dotenv==1.0.1`) install cleanly from PyPI into `python:3.10-slim`.
S3-T2 TC-1 | `GET /health` with no `X-API-Key` header will return HTTP 401. FastAPI's `Header(None)` default passes `None` to the dependency; the `x_api_key is None` branch raises `HTTPException(401)` before any route logic executes.
S3-T2 TC-2 | `GET /health` with a wrong key value will return HTTP 401. The `x_api_key != _API_KEY` branch raises `HTTPException(401)`. The comparison is exact and case-sensitive.
S3-T2 TC-3 | `GET /health` with the correct key value will return HTTP 200. The dependency returns without raising; the route handler executes and returns `{"status": "ok"}`.
S3-T2 TC-4 | The 401 response body will be `{"detail":"Invalid or missing API key"}` — a fixed string that contains no key value.
S3-T2 TC-5 | FastAPI logs will contain only request lines (method, path, status code) and the startup message. The key value (`inv01-test-key-do-not-use`) will not appear in any log line — no header logging, no key variable logging.
S3-T3 INV-01-A | The `get_api_key` dependency receives `None` for a missing header and raises `HTTPException(401)` before any route handler executes. The script will receive HTTP 401.
S3-T3 INV-01-B | `"wrong-key" != _API_KEY` is True; `HTTPException(401)` is raised. The script will receive HTTP 401.
S3-T3 INV-01-C | The correct key passes both the `is None` and `!= _API_KEY` checks; the dependency returns without raising. The `/health` handler executes and returns HTTP 200.
S3-T3 INV-01-D | The `HTTPException` detail is the fixed string `"Invalid or missing API key"` — no variable substitution. The key string `inv01-test-key-do-not-use` will not appear in the JSON response body.
S3-T3 INV-02-A | Uvicorn does not copy request headers into response headers. The response headers (`content-type`, `content-length`, `date`, `server`) contain no key string.
S3-T3 INV-02-B | No `logger`, `print`, or uvicorn access-log format includes the `X-API-Key` header value. Log lines show only method, path, and status code. The key string will not appear.

---

### CC Challenge Output

S3-T1 — What did you not test in this task?

Items not tested:
- Whether `uvicorn` correctly handles SIGTERM and shuts down cleanly (process lifecycle — not relevant for the skeleton stage).
- Whether `python-dotenv` correctly loads `.env` values when running outside Docker (not imported or used by `main.py` yet — added to `requirements.txt` for use in S4-T1).
- Whether the image starts cleanly when no environment variables are provided (main.py reads no env vars at this stage — no failure path exists yet to test).
- Whether the `WORKDIR /app` correctly isolates paths when `COPY . .` copies both `requirements.txt` and `main.py` — no conflicts in the current file set.

Decision: process lifecycle is irrelevant for a skeleton with no signal handling. python-dotenv readiness is implicit in the build success. Missing env var behaviour is the scope of S3-T2. WORKDIR isolation is confirmed by the build succeeding. No additional test cases added.

S3-T2 — What did you not test in this task?

Items not tested:
- Whether the 200 response body also contains no key value (only the 401 body was checked for absence — the 200 body `{"status":"ok"}` cannot contain the key by construction, but was not explicitly asserted).
- Whether `API_KEY=""` (empty string) also raises `RuntimeError` at startup — `if not _API_KEY` catches empty string and `None` alike, but this path was not run as a formal test case.
- Whether the `X-API-Key` header value comparison is case-sensitive (it is — `!=` is an exact Python string comparison — but no mixed-case variant was submitted to confirm rejection).
- Whether response headers for a 200 response contain the key value (tested separately in the S3-T2 build-time verification run; not included in the five formal TCs).

Decision: the 200 body cannot contain the key by construction — there is no code path that reads `_API_KEY` into the response. Empty-string `API_KEY` is a deployment concern not present in normal operation. Case-sensitivity of header values is Python-default behaviour. Response header key-absence is verified in S3-T3 (INV-02-A). No additional test cases added.

S3-T3 — What did you not test in this task?

Items not tested:
- Whether the script exits 1 when any single check fails — only the all-pass path was exercised; the failure branch of `fail()` and the final `Overall: FAIL` / `exit 1` path were not run.
- Whether the 30-second readiness timeout correctly aborts with a non-zero exit when fastapi never starts — the happy path was the only run.
- Whether INV-02-B captures log lines written asynchronously after the last curl returns but before `docker logs` executes — uvicorn writes access logs synchronously within the request cycle, so no race condition exists in practice, but the timing was not stress-tested.

Decision: the failure-branch of the script is structurally identical to s1_smoke.sh and s2_db.sh, both of which had their failure paths exercised in earlier sessions. The timeout abort path is analogous to s2_db.sh TC-2, already verified. Uvicorn's synchronous logging is a framework guarantee. No additional test cases added.

---

### Code Review

S3-T1 — No invariant touched. No code review required.

S3-T2 — INV-01, INV-02 — Review `fastapi/main.py`: confirm auth enforcement and key non-disclosure.

S3-T2 review finding:
- `_API_KEY = os.environ.get("API_KEY")` — read once at module import, not per-request. No repeated env lookups. Confirmed.
- `if not _API_KEY: raise RuntimeError("API_KEY environment variable is not set")` — catches both `None` (unset) and empty string. Uvicorn propagates this as a fatal import error and exits non-zero (exit 1 confirmed). Container does not accept connections. Confirmed — satisfies INV-01: app cannot start without a configured key.
- `def get_api_key(x_api_key: str = Header(None))` — `Header(None)` means a missing header delivers `None` to the function; no special case needed for "missing vs wrong".
- `if x_api_key is None or x_api_key != _API_KEY` — both missing and wrong key raise `HTTPException(status_code=401, detail="Invalid or missing API key")`. The detail string is a fixed literal; it contains no key value, no header echo. Confirmed — satisfies INV-02.
- `app = FastAPI(dependencies=[Depends(get_api_key)])` — the global dependency is applied at the `FastAPI` constructor level. Every route registered on this `app` instance — present and future — is automatically protected. No per-route `dependencies=[]` override exists. Confirmed — satisfies INV-01.
- `logger.info("FastAPI: API key authentication configured")` — the only log statement in the auth path. Contains no key value. Confirmed — satisfies INV-02.
- No `print`, `logger.debug`, or `logger.warning` statement anywhere in `main.py` that references `_API_KEY`, `x_api_key`, or any request header value. TC-5 log output confirmed: `inv01-test-key-do-not-use` absent from all log lines after four requests. Confirmed — satisfies INV-02.

S3-T3 — INV-01, INV-02 — Review `verify/s3_auth.sh`: confirm checks correctly target the invariants.

S3-T3 review finding:
- INV-01-A uses `curl` with no `-H` flag — confirms the "missing header" path, not the "wrong header" path. The two failure modes are tested separately (INV-01-A and INV-01-B). Confirmed.
- INV-01-D captures the 401 body from a request with no header (no key sent) — the body cannot be influenced by a key the server never received. `grep -q "$TEST_KEY"` checks the exact test key string. Confirmed.
- INV-02-A uses `curl -D - -o /dev/null` to capture only response headers, not the body. The grep checks headers for the key string. Confirmed — this closes the gap noted in S3-T2's CC challenge (response headers not formally tested in TC-1–5).
- INV-02-B collects `docker logs "$CONTAINER" 2>&1` after all six curl requests have completed — stderr (uvicorn startup) is included via `2>&1`. The key string `inv01-test-key-do-not-use` is distinct from the `.env.example` placeholder, preventing false negatives. Confirmed.
- The `trap cleanup EXIT` fires `docker stop` and `docker rm` on all exit paths including `exit 1` from the timeout abort — no container is left running on failure. Confirmed.
- The readiness poll sends `X-API-Key: $TEST_KEY` — required since `/health` now enforces auth. A poll without the key would always receive 401 and loop until timeout. Confirmed.

---

### Scope Decisions

S3-T1: `curl` retained in the Dockerfile despite not appearing in the task spec. Required by the `docker-compose.yml` healthcheck (`curl -f http://localhost:8000/health`). Without it the healthcheck fails permanently, blocking nginx via `condition: service_healthy` — an INV-03 violation. Carry-forward of the S1-T4 deviation; flagged as a deviation in SESSION_LOG.md.

S3-T1: `python-dotenv==1.0.1` included in `requirements.txt` per task spec. Not used in `main.py` at this stage — its use begins in S4-T1 when environment variable loading is explicit.

S3-T1: `# Auth dependency added in S3-T2` and `# Database lifespan added in S4-T1` placed at module level as forward-reference markers. The S3-T2 and S4-T1 task specs explicitly instruct replacing these comments with their respective implementations.

S3-T2: The `# Auth dependency added in S3-T2` comment was removed and replaced with the actual implementation. The `# Database lifespan added in S4-T1` comment was retained — its implementation is not yet in scope.

S3-T2: Test key `inv01-test-key-do-not-use` used for TC-1 through TC-5. This matches the key specified in the S3-T3 task spec (which calls for the same string) — using it here ensures consistent key-absence checks across both tasks. It is distinct from the `.env.example` placeholder (`change-me-api-key`) to prevent false negatives from placeholder leakage.

S3-T2: `return x_api_key` in the dependency function returns the validated key value to FastAPI's DI framework. This is standard FastAPI practice — routes that declare the dependency as a parameter receive the return value. No current route declares it as a parameter, so the return value is unused. INV-02 is not implicated by this: the value is not written to any response or log.

S3-T3: The script runs the fastapi container standalone via `docker run` — no `docker compose up` — confirming auth enforcement is a property of the application, not of the compose startup chain.

S3-T3: Image name resolved dynamically via `docker images --format` after `docker compose build fastapi` — avoids hardcoding a project-name-derived tag that could break if the directory is renamed.

---

### Verification Verdict

[x] All planned cases passed (S3-T1: TC-1–2; S3-T2: TC-1–5; S3-T3: INV-01-A through INV-02-B)
[x] Test Cases Added During Session section complete — None discovered (all three tasks)
[x] CC challenge reviewed for S3-T1, S3-T2, and S3-T3
[x] Code review complete — S3-T1 touches no invariant; INV-01/INV-02 reviewed for S3-T2; INV-01/INV-02 script review for S3-T3
[x] Scope decisions documented

**Status: VERIFIED — Session 3 COMPLETE**
**Engineer sign-off:** y vaishali rao — 2026-05-11

---
---

# VERIFICATION_RECORD — Session 4: FastAPI Core: Risk Lookup Endpoint

**Session:** Session 4 — FastAPI core: risk lookup endpoint
**Date:** 2026-05-11
**Engineer:** y vaishali rao

---

## Task S4-T1 — Implement database connection with startup retry loop

<!-- S4-T2 and S4-T3 will be added when completed. -->

---

### Test Cases Applied

Source: EXECUTION_PLAN.md — S4-T1 test cases.

| Case       | Scenario                                                            | Expected                                         | Result                                                                                     |
|------------|---------------------------------------------------------------------|--------------------------------------------------|--------------------------------------------------------------------------------------------|
| S4-T1 TC-1 | Startup with Postgres available                                     | Connects within 3 attempts, logs success         | PASS — connected on attempt 1; `"database connection established"` logged before startup complete |
| S4-T1 TC-2 | Startup with Postgres unavailable (host 192.0.2.1)                  | Retries 10 times, then `RuntimeError`, exit non-zero | PASS — all 10 attempt messages logged; `RuntimeError: Database connection failed`; "Application startup failed. Exiting.", exit 3 |
| S4-T1 TC-3 | `GET /health` after DB connect                                      | HTTP 200                                         | PASS — `docker compose exec fastapi curl` returns 200 with correct key                     |

### Test Cases Added During Session

| Case  | Scenario        | Expected | Result | Source |
|-------|-----------------|----------|--------|--------|
| ADD-1 | None discovered | | | |

---

### Prediction Statement

S4-T1 TC-1 | `_connect()` will succeed on the first attempt (postgres is healthy before fastapi starts per `depends_on`). The log line `"FastAPI: database connection established"` will appear between "Waiting for application startup." and "Application startup complete." in the uvicorn output.
S4-T1 TC-2 | With `POSTGRES_HOST=192.0.2.1` (an unroutable RFC 5737 address), every `psycopg2.connect()` call will raise `OperationalError`. After attempt 10, `_connect()` raises `RuntimeError("Database connection failed")`, which propagates through the lifespan context manager. Uvicorn catches this as a startup failure, logs the traceback, and exits non-zero without accepting any connections.
S4-T1 TC-3 | The lifespan connects to the DB on startup before uvicorn signals readiness. The `/health` route handler does not use the DB connection, so a successful DB connect has no negative effect on the endpoint. HTTP 200 will be returned.

---

### CC Challenge Output

S4-T1 — What did you not test in this task?

Items not tested:
- Whether `get_db_conn()` correctly attempts reconnection when `conn.closed` is non-zero — the reconnect path was not exercised (no test dropped the connection mid-run).
- Whether `HTTPException(503)` is raised correctly when the reconnect in `get_db_conn()` also fails — this path was not run as it requires no route that calls `get_db_conn()` yet.
- Whether the `finally` block in `lifespan` correctly closes the connection on normal shutdown (no explicit shutdown test was performed — teardown was via `docker compose down`).
- Whether `autocommit=False` is correctly set on the connection object (set immediately after `psycopg2.connect()` returns; not asserted explicitly).

Decision: `get_db_conn()` is tested end-to-end in S4-T2 when the risk endpoint uses it. The `finally` close path is exercised on every `docker compose down`. `autocommit=False` is a psycopg2 default and is confirmed by code inspection. No additional test cases added.

---

### Code Review

S4-T1 — INV-03 — Review `fastapi/main.py`: confirm startup retry loop and failure behaviour.

S4-T1 review finding:
- `_connect()` attempts `psycopg2.connect()` up to 10 times with `time.sleep(3)` between failures. On success, `SELECT 1` is executed to confirm query readiness (not just TCP connectivity). Confirmed — satisfies INV-03: FastAPI will not accept requests if the DB is not ready.
- `raise RuntimeError("Database connection failed")` is raised after all 10 attempts fail. Uvicorn propagates this as a fatal startup error, printing "Application startup failed. Exiting." and exiting non-zero (exit 3 confirmed). The ASGI app never calls `startup_complete`, so no requests are accepted. Confirmed — satisfies INV-03.
- The `lifespan` context manager stores the connection as `app.state.db` before `yield`. The `finally` block closes it if `not app.state.db.closed` — psycopg2 uses an integer `closed` attribute (0 = open, nonzero = closed). Confirmed.
- `conn.autocommit = False` is set after connect — psycopg2 default, but set explicitly per spec. Confirmed.
- No credential values (`_DB_PASS`, `_DB_USER`, `_DB_NAME`, `_DB_HOST`) appear in any log statement. Only `"database connection established"` is logged on success; only `"waiting for database... (attempt N/10)"` on failure. Confirmed — INV-02 not implicated.

---

### Scope Decisions

S4-T1: TC-3 verified via `docker compose exec fastapi curl` rather than `curl localhost:8000` from the host. Fastapi's compose service uses `expose: 8000` (no host port mapping) — a host-side curl fails with connection refused. `docker compose exec` hits the same endpoint from inside the container network and is equivalent. Recorded as a deviation in SESSION_LOG.md.

S4-T1: `_DB_NAME`, `_DB_USER`, `_DB_PASS` are read with `os.environ["KEY"]` (raising `KeyError` if unset), while `_DB_HOST` uses `os.environ.get("POSTGRES_HOST", "postgres")` (default per spec). A missing required DB variable causes a `KeyError` at module load — same failure mode as a missing `API_KEY`, exits before accepting requests.

S4-T1: `get_db_conn()` is defined in this task but not wired to any route yet — it will be used as a dependency in S4-T2. Its presence here is required by the task spec and does not expand scope.

---

### Verification Verdict

[x] All planned cases passed (S4-T1: TC-1–3)
[x] Test Cases Added During Session section complete — None discovered
[x] CC challenge reviewed for S4-T1
[x] Code review complete — INV-03 reviewed for S4-T1
[x] Scope decisions documented

**Status: VERIFIED (S4-T1 — session IN PROGRESS)**
**Engineer sign-off:** y vaishali rao — 2026-05-11
