# EXECUTION_PLAN.md

**System:** Customer Risk API  
**Architecture:** Candidate C — Nginx reverse proxy with operator-mediated key injection  
**Version:** 1.0

---

## How to read this document

Each session delivers a self-contained vertical slice or logical component. Sessions are
ordered so that each one has a runnable integration check before the next begins. No session
depends on a subsequent one.

**Task timing reference:**
- Standard task (no invariant touch): 28–40 min in Claude Code
- Invariant-touching task: 33–50 min in Claude Code
- Verification time is not included in estimates

**Invariant notation:** Tasks marked `[INV-XX]` must have their code review checklist
applied before the task is considered complete.

---

## Session map

| Session | Scope | Tasks | Est. duration |
|---|---|---|---|
| S1 | Project scaffold and environment | 4 tasks | ~2h 00m |
| S2 | Database schema and seed data | 4 tasks | ~2h 30m |
| S3 | FastAPI core — auth and health | 3 tasks | ~2h 05m |
| S4 | FastAPI core — risk lookup endpoint | 3 tasks | ~2h 15m |
| S5 | Nginx — proxy, key injection, Basic Auth | 4 tasks | ~2h 45m |
| S6 | Browser UI | 3 tasks | ~1h 45m |
| S7 | End-to-end integration and invariant verification | 5 tasks | ~3h 10m |

**Total estimated build time (excluding verification):** ~16h 30m across 7 sessions.

---

## Session 1 — Project scaffold and environment

**Goal:** Establish the complete project directory structure, Docker Compose skeleton,
and `.env` contract so every subsequent session has a known file layout to write into.
Nothing runs at the end of this session, but `docker compose config` validates cleanly.

**Estimated duration:** ~2h 00m (4 standard tasks × ~30 min avg)

---

### S1-T1 — Create project directory structure and `.env` contract

**Description:**  
Input: nothing. Output: the top-level directory tree, a `.env.example` file listing all
required variables with placeholder values, a `.gitignore` that excludes `.env`, and a
root-level `README.md` stub with the startup command.

**Prompt for Claude Code:**
```
Create the project directory structure for the Customer Risk API. The project root should
contain:
  - docker-compose.yml (empty skeleton — services block with no content yet)
  - .env.example with these exact keys and placeholder values:
      API_KEY=change-me-api-key
      BASIC_AUTH_USER=opsuser
      BASIC_AUTH_PASSWORD=change-me-password
      POSTGRES_DB=riskdb
      POSTGRES_USER=riskuser
      POSTGRES_PASSWORD=change-me-pg-password
  - .gitignore containing: .env
  - README.md with a single section "## Startup" containing the command:
      docker compose up --build
  - Subdirectories: nginx/, fastapi/, db-init/
  - Each subdirectory should contain a placeholder file (.gitkeep or equivalent)
    so the directory is tracked by git.

Do not create any Dockerfiles or application code yet.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| `.env.example` exists and contains all 6 keys | All 6 keys present, no real secrets |
| `.env` is absent from the repository | `.gitignore` entry prevents accidental commit |
| All 3 subdirectories exist | `ls nginx/ fastapi/ db-init/` returns content |

**Verification command:**
```bash
# All keys present in .env.example
grep -c "=" .env.example | grep -q "^6$" && echo "PASS: 6 keys" || echo "FAIL"

# .env excluded by gitignore
echo "TEST_SECRET=abc" > .env && git check-ignore -q .env && echo "PASS: .env ignored" || echo "FAIL"
rm .env

# Directories exist
for d in nginx fastapi db-init; do [ -d "$d" ] && echo "PASS: $d exists" || echo "FAIL: $d missing"; done
```

**Touches invariant:** No.

---

### S1-T2 — Write `docker-compose.yml` with all five services declared

**Description:**  
Input: directory structure from S1-T1. Output: a complete `docker-compose.yml` with all
five services declared (`postgres`, `db-init`, `fastapi`, `nginx`, and implicit network).
Build contexts, `env_file`, `depends_on` conditions, volume mounts, and port exposure are
all present. No Dockerfiles exist yet — `build:` directives reference paths that will be
populated in later sessions.

**Prompt for Claude Code:**
```
Write the docker-compose.yml for the Customer Risk API. Requirements:

Services:
  postgres:
    - Image: postgres:15
    - Environment from .env: POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD
    - Named volume: pgdata mounted at /var/lib/postgresql/data
    - Healthcheck: pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}, interval 5s,
      retries 10

  db-init:
    - Build context: ./db-init
    - env_file: .env
    - depends_on: postgres condition service_healthy
    - Restart policy: on-failure (runs once and exits)

  fastapi:
    - Build context: ./fastapi
    - env_file: .env
    - depends_on: db-init condition service_completed_successfully
    - Exposes port 8000 internally only (no host port mapping)
    - Healthcheck: curl -f http://localhost:8000/health, interval 10s, retries 5

  nginx:
    - Build context: ./nginx
    - env_file: .env
    - depends_on: fastapi condition service_healthy
    - Ports: "80:80"

Named volumes block: pgdata

All services should share the default network (no explicit network declaration needed).

Use env_file: .env for all services that need secrets. Do not hardcode any values.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| `docker compose config` parses without error | Exit code 0, no warnings |
| `depends_on` chain is correct | db-init → postgres; fastapi → db-init; nginx → fastapi |
| No host port on fastapi | FastAPI's 8000 not in ports section |
| pgdata volume declared | Volume present in `volumes:` block |

**Verification command:**
```bash
# Copy example env so config can resolve variables
cp .env.example .env

docker compose config --quiet && echo "PASS: compose config valid" || echo "FAIL: config error"

# Check depends_on chain
docker compose config | grep -A3 "depends_on" | grep -E "db-init|fastapi|nginx|postgres"

# Verify fastapi has no host port binding
docker compose config | python3 -c "
import sys, yaml
cfg = yaml.safe_load(sys.stdin)
fa_ports = cfg.get('services',{}).get('fastapi',{}).get('ports',[])
print('PASS: fastapi no host port' if not fa_ports else 'FAIL: fastapi has host port')
"

rm .env
```

**Touches invariant:** `INV-03` (startup sequencing via `depends_on`).

**Code review checklist (INV-03):**
- `fastapi` service uses `condition: service_completed_successfully` on `db-init`, not just `service_started`.
- `db-init` service uses `condition: service_healthy` on `postgres`.
- No `restart: always` on `db-init` — it must run once and exit.

---

### S1-T3 — Write stub Dockerfiles for all three custom services

**Description:**  
Input: directory structure from S1-T1. Output: minimal `Dockerfile` in each of `nginx/`,
`fastapi/`, and `db-init/`. These are build-valid stubs — they will produce images that
start and exit cleanly, allowing `docker compose build` to succeed. Application code is
not added yet.

**Prompt for Claude Code:**
```
Create stub Dockerfiles for three services. Each must be buildable and produce a working
image, but should contain only the minimum needed to pass `docker compose build`.

nginx/Dockerfile:
  - FROM nginx:1.25-alpine
  - COPY a placeholder nginx.conf to /etc/nginx/nginx.conf
  - The placeholder nginx.conf should be a valid minimal config that starts nginx on
    port 80 and returns 200 for all requests (use return 200 in a location block)

fastapi/Dockerfile:
  - FROM python:3.10-slim
  - RUN pip install fastapi uvicorn
  - Create a minimal main.py that starts a FastAPI app with a single GET /health
    endpoint returning {"status": "ok"}
  - CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]

db-init/Dockerfile:
  - FROM python:3.10-slim
  - RUN pip install psycopg2-binary
  - Create a minimal init.py that prints "db-init: no-op stub" and exits 0
  - CMD ["python", "init.py"]

Also create nginx/nginx.conf as the placeholder config described above.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| `docker compose build` exits 0 | All three images build without error |
| Each Dockerfile references only the correct base image | python:3.10-slim, nginx:1.25-alpine |

**Verification command:**
```bash
cp .env.example .env
docker compose build 2>&1 | tail -5
echo "Exit: $?"
rm .env
```

**Touches invariant:** No.

---

### S1-T4 — Smoke test: full `docker compose up` with stubs

**Description:**  
Input: stubs from S1-T1 through S1-T3. Output: confirmation that the stub stack starts,
all services reach their expected states (postgres healthy, db-init exits 0, fastapi healthy,
nginx up), and `docker compose down` cleans up without errors. This is the first full
integration check of the project scaffold.

**Prompt for Claude Code:**
```
Create a .env file for local testing by copying .env.example and substituting real
(but non-production) values:
  API_KEY=test-api-key-session1
  BASIC_AUTH_USER=opsuser
  BASIC_AUTH_PASSWORD=testpass123
  POSTGRES_DB=riskdb
  POSTGRES_USER=riskuser
  POSTGRES_PASSWORD=testpgpass123

Then write a shell script verify/s1_smoke.sh that:
1. Runs docker compose up -d --build
2. Waits up to 60 seconds for all services to be healthy/exited as expected
3. Checks: postgres is healthy, db-init has exited 0, fastapi is healthy
4. Curls http://localhost:80 and asserts HTTP 200
5. Runs docker compose down -v
6. Prints PASS or FAIL with a reason for each check

The script must be executable (chmod +x) and must not leave containers running on failure.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| Cold start from `docker compose up` | All services reach expected state within 60s |
| `GET http://localhost:80` | HTTP 200 from nginx stub |
| `docker compose ps` after full start | db-init shows `Exited (0)`, others `Up` |
| `docker compose down -v` | Clean teardown, pgdata volume removed |

**Verification command:**
```bash
chmod +x verify/s1_smoke.sh && bash verify/s1_smoke.sh
```

**Touches invariant:** `INV-03` (partial — verifies db-init exits 0 before fastapi accepts requests, using stub services).

**Code review checklist (INV-03):**
- Script confirms db-init exits with code 0, not just "exited".
- Script confirms fastapi does not reach healthy state before db-init has exited.

---

## Session 2 — Database schema and seed data

**Goal:** The `db-init` container runs a real Python script that creates the schema and
seeds representative data. At the end of this session, `docker compose up` results in
a live Postgres database with `customers` and `risk_factors` tables, all constraints
in place, and seed data covering LOW, MEDIUM, and HIGH tiers. Direct Postgres queries
confirm all data invariants.

**Estimated duration:** ~2h 30m  
(2 standard tasks × ~30 min + 2 invariant-touching tasks × ~42 min avg)

---

### S2-T1 — Write the schema DDL

**Description:**  
Input: `db-init/` directory. Output: `db-init/schema.sql` containing complete DDL for
the `customers` and `risk_factors` tables, with all column constraints, primary key,
foreign key, and tier CHECK constraint.

**Prompt for Claude Code:**
```
Create db-init/schema.sql with the DDL for two tables. Requirements:

customers table:
  - customer_id: VARCHAR(20) PRIMARY KEY
  - name: VARCHAR(100) NOT NULL
  - tier: VARCHAR(10) NOT NULL CHECK (tier IN ('LOW', 'MEDIUM', 'HIGH'))
  - created_at: TIMESTAMPTZ NOT NULL DEFAULT NOW()

risk_factors table:
  - id: SERIAL PRIMARY KEY
  - customer_id: VARCHAR(20) NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE
  - factor_code: VARCHAR(50) NOT NULL
  - factor_description: TEXT NOT NULL
  - created_at: TIMESTAMPTZ NOT NULL DEFAULT NOW()

Additional requirements:
  - Use CREATE TABLE IF NOT EXISTS for both tables
  - Add an index on risk_factors(customer_id) for query performance
  - The schema file must be valid PostgreSQL 15 syntax
  - Add a comment above each table explaining its purpose

Do not add any INSERT statements — seed data is in a separate file.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| Schema applied to fresh Postgres | Both tables created, no errors |
| INSERT with tier='INVALID' | Rejected with constraint violation |
| INSERT risk_factor with non-existent customer_id | Rejected with FK violation |
| INSERT customer with NULL tier | Rejected with NOT NULL violation |
| Re-run schema DDL against existing tables | No error (IF NOT EXISTS) |

**Verification command:**
```bash
# Apply schema to a live postgres and verify constraints
cp .env.example .env && \
  sed -i 's/change-me-pg-password/testpgpass123/g' .env && \
  sed -i 's/change-me-api-key/test-api-key/g' .env && \
  sed -i 's/change-me-password/testpass123/g' .env

docker compose up -d postgres
sleep 10

docker compose exec postgres psql -U riskuser -d riskdb -f /dev/stdin < db-init/schema.sql
echo "Schema apply exit: $?"

# Constraint tests
docker compose exec postgres psql -U riskuser -d riskdb -c \
  "INSERT INTO customers(customer_id,name,tier) VALUES('T1','Test','INVALID');" 2>&1 | \
  grep -q "violates check constraint" && echo "PASS: tier CHECK enforced" || echo "FAIL"

docker compose exec postgres psql -U riskuser -d riskdb -c \
  "INSERT INTO risk_factors(customer_id,factor_code,factor_description) VALUES('NONE','X','Y');" 2>&1 | \
  grep -q "violates foreign key constraint" && echo "PASS: FK enforced" || echo "FAIL"

docker compose down -v && rm .env
```

**Touches invariant:** `INV-06` (tier CHECK constraint), `INV-08` (FK constraint), `INV-09` (PRIMARY KEY).

**Code review checklist (INV-06, INV-08, INV-09):**
- `tier` column has `CHECK (tier IN ('LOW', 'MEDIUM', 'HIGH'))` — not just NOT NULL.
- `risk_factors.customer_id` has a FOREIGN KEY referencing `customers.customer_id`.
- `customers.customer_id` is PRIMARY KEY (not just UNIQUE).
- ON DELETE CASCADE is present on the FK — confirm this is the intended behaviour.

---

### S2-T2 — Write seed data

**Description:**  
Input: `db-init/schema.sql`. Output: `db-init/seed.sql` with INSERT statements for at
least 9 customers (3 per tier) and at least 2 risk factors per customer. All inserts
use `ON CONFLICT DO NOTHING` for idempotency.

**Prompt for Claude Code:**
```
Create db-init/seed.sql with representative seed data for the Customer Risk API.

Requirements:
  - Minimum 9 customers: 3 with tier LOW, 3 with tier MEDIUM, 3 with tier HIGH
  - Each customer must have at least 2 rows in risk_factors
  - customer_id format: use short alphanumeric codes like CUST001, CUST002, etc.
  - factor_code should be a short uppercase label (e.g. 'HIGH_DEBT_RATIO',
    'MISSED_PAYMENTS', 'LOW_CREDIT_SCORE')
  - factor_description should be a human-readable sentence explaining the factor
  - Make the factor codes plausible for a financial risk context but fictional
  - All INSERTs must use ON CONFLICT DO NOTHING for idempotency

Example structure (expand to meet minimums):
  INSERT INTO customers (customer_id, name, tier)
  VALUES ('CUST001', 'Alice Marchetti', 'LOW')
  ON CONFLICT DO NOTHING;

  INSERT INTO risk_factors (customer_id, factor_code, factor_description)
  VALUES ('CUST001', 'STABLE_INCOME', 'Customer has maintained stable employment
          for over 5 years.')
  ON CONFLICT DO NOTHING;

Ensure HIGH-tier customers have factors that plausibly justify HIGH classification,
and LOW-tier customers have factors that plausibly justify LOW classification.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| All 3 tiers represented | At least 1 customer with each of LOW, MEDIUM, HIGH |
| Every customer has ≥ 2 factors | No customer_id in customers has < 2 rows in risk_factors |
| Re-running seed.sql is safe | Second run produces no errors, row counts unchanged |

**Verification command:**
```bash
# Requires schema already applied from S2-T1 flow
# Run seed and check counts
docker compose exec postgres psql -U riskuser -d riskdb -f /dev/stdin < db-init/seed.sql

docker compose exec postgres psql -U riskuser -d riskdb -t -c \
  "SELECT tier, COUNT(*) FROM customers GROUP BY tier ORDER BY tier;" | \
  grep -E "(HIGH|LOW|MEDIUM)" | awk '{print $1, $3}' | \
  while read tier count; do
    [ "$count" -ge 3 ] && echo "PASS: $tier has $count customers" || echo "FAIL: $tier has only $count"
  done

docker compose exec postgres psql -U riskuser -d riskdb -t -c \
  "SELECT COUNT(*) FROM customers c WHERE (SELECT COUNT(*) FROM risk_factors r WHERE r.customer_id=c.customer_id) < 2;" | \
  grep -q "^ 0$" && echo "PASS: all customers have >=2 factors" || echo "FAIL"
```

**Touches invariant:** `INV-06` (tier values in seed data), `INV-07` (at least one factor per customer), `INV-08` (FK integrity in seed inserts), `INV-09` (no duplicate customer_id in seed).

**Code review checklist (INV-06, INV-07, INV-08, INV-09):**
- No tier value outside {LOW, MEDIUM, HIGH} in any INSERT.
- Every customer_id in customers has at least one corresponding INSERT in risk_factors.
- No risk_factor INSERT references a customer_id not in the customers INSERT block.
- No two INSERT statements share the same customer_id (the CONFLICT DO NOTHING would mask duplicates — they should not exist in the first place).

---

### S2-T3 — Write the `db-init` Python script

**Description:**  
Input: `schema.sql`, `seed.sql`. Output: `db-init/init.py` — the Python script that
reads both SQL files and executes them against Postgres using psycopg2. The script
connects using environment variables, waits for Postgres to be ready with a retry
loop, applies schema, applies seed, and exits 0 on success or 1 on failure.

**Prompt for Claude Code:**
```
Write db-init/init.py. This script runs inside the db-init container and is the only
place in the system where database writes occur.

Requirements:
  - Connect to Postgres using these environment variables:
      POSTGRES_HOST (default: "postgres")
      POSTGRES_DB
      POSTGRES_USER
      POSTGRES_PASSWORD
  - Implement a retry loop: attempt connection up to 10 times with 3-second delays.
    Print a message on each attempt. Exit 1 if all attempts fail.
  - After connecting, execute schema.sql in full, then seed.sql in full, each as a
    single execute() call with the file contents as a string.
  - Wrap each SQL execution in a try/except. On exception, print the error and exit 1.
  - Commit after each file. Close the connection cleanly on exit.
  - Print "db-init: schema applied" and "db-init: seed data loaded" on success.
  - Use psycopg2 only. No ORM. No other libraries except os, sys, time.
  - The script must be idempotent: re-running against an already-initialised database
    must produce exit code 0 with no data changes (the SQL files handle this with
    IF NOT EXISTS and ON CONFLICT DO NOTHING).

Update db-init/Dockerfile to:
  - COPY init.py, schema.sql, and seed.sql into the container
  - CMD ["python", "init.py"]
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| First run against empty database | Exits 0, tables created, seed loaded |
| Second run against populated database | Exits 0, no errors, row counts unchanged |
| Run with Postgres not yet ready | Retries up to 10 times, then exits 1 |
| Run with wrong POSTGRES_PASSWORD | Exits 1 with authentication error message |

**Verification command:**
```bash
cp .env.example .env
sed -i 's/change-me-pg-password/testpgpass123/g; s/change-me-api-key/testkey/g; s/change-me-password/testpass/g' .env

docker compose up -d postgres
sleep 10
docker compose up db-init
echo "db-init exit: $?"

# Second run — idempotency
docker compose up db-init
echo "Second run exit: $?"

# Row counts unchanged after second run
docker compose exec postgres psql -U riskuser -d riskdb -t -c \
  "SELECT COUNT(*) FROM customers;" | grep -q "9" && \
  echo "PASS: row count stable" || echo "FAIL: row count changed"

docker compose down -v && rm .env
```

**Touches invariant:** `INV-03` (db-init exit code is what triggers FastAPI startup), `INV-05` (all writes confined to db-init execution window).

**Code review checklist (INV-03, INV-05):**
- Script exits with code 0 on success, non-zero on any failure — `sys.exit(0)` and `sys.exit(1)` are explicit.
- Script performs only DDL and seed INSERTs — no SELECT queries are misidentified as writes, and no updates to existing rows.
- Retry loop logs each attempt but does not swallow the final error.

---

### S2-T4 — Integration check: db-init in full compose stack

**Description:**  
Input: complete db-init implementation. Output: a verification script that starts the
full stack (postgres + db-init only), confirms the schema and seed data, and runs all
data invariant SQL checks directly against Postgres.

**Prompt for Claude Code:**
```
Create verify/s2_db.sh — a verification script for the database layer. It should:

1. Start only postgres and db-init: docker compose up -d postgres db-init
2. Wait for db-init to exit (poll docker compose ps until db-init shows "Exited (0)")
   with a 90-second timeout.
3. Run each of the following SQL checks and print PASS or FAIL for each:

   CHECK A (INV-06): All tier values are valid
     SELECT COUNT(*) FROM customers WHERE tier NOT IN ('LOW','MEDIUM','HIGH');
     Expected: 0

   CHECK B (INV-07): All customers have at least one risk factor
     SELECT COUNT(*) FROM customers c
     WHERE NOT EXISTS (SELECT 1 FROM risk_factors r WHERE r.customer_id = c.customer_id);
     Expected: 0

   CHECK C (INV-08): No orphaned risk factor rows
     SELECT COUNT(*) FROM risk_factors rf
     LEFT JOIN customers c ON rf.customer_id = c.customer_id
     WHERE c.customer_id IS NULL;
     Expected: 0

   CHECK D (INV-09): No duplicate customer_id values
     SELECT COUNT(*) FROM (
       SELECT customer_id FROM customers GROUP BY customer_id HAVING COUNT(*) > 1
     ) dupes;
     Expected: 0

   CHECK E: All three tiers are represented
     SELECT COUNT(DISTINCT tier) FROM customers;
     Expected: 3

   CHECK F: Minimum 9 seed records
     SELECT COUNT(*) FROM customers;
     Expected: >= 9

4. Run docker compose down -v
5. Exit 0 if all checks pass, 1 if any fail.

Make the script executable.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| All 6 SQL checks on clean seed | All PASS |
| db-init timeout exceeded | Script exits 1 with "timeout" message |

**Verification command:**
```bash
chmod +x verify/s2_db.sh && bash verify/s2_db.sh
```

**Touches invariant:** `INV-06`, `INV-07`, `INV-08`, `INV-09` (all verified by SQL checks in this script).

**Code review checklist (INV-06, INV-07, INV-08, INV-09):**
- Each SQL check is an exact reproduction of the verification query specified in INVARIANTS.md — not a paraphrase.
- The script does not exit early on first failure; it runs all checks and reports each.
- The PASS/FAIL output identifies which invariant check failed, not just a count.

---

## Session 3 — FastAPI core: authentication and health

**Goal:** FastAPI has a real application with two working endpoints: `GET /health` and the
API key authentication dependency. The auth dependency is applied globally and enforced on
every route. No database connection yet. At the end of this session, `curl` against the
FastAPI container directly confirms auth behaviour — 401 without key, 200 with correct key.

**Estimated duration:** ~2h 05m  
(1 standard task × ~30 min + 2 invariant-touching tasks × ~42 min avg)

---

### S3-T1 — Set up FastAPI project structure and dependencies

**Description:**  
Input: stub `fastapi/` directory. Output: `fastapi/main.py`, `fastapi/requirements.txt`,
and an updated `fastapi/Dockerfile` that installs dependencies properly and runs the app.

**Prompt for Claude Code:**
```
Set up the FastAPI application structure. Replace the stub with a real project.

fastapi/requirements.txt:
  fastapi==0.111.0
  uvicorn[standard]==0.29.0
  psycopg2-binary==2.9.9
  pydantic==2.7.0
  python-dotenv==1.0.1

fastapi/Dockerfile (replace the stub):
  FROM python:3.10-slim
  WORKDIR /app
  COPY requirements.txt .
  RUN pip install --no-cache-dir -r requirements.txt
  COPY . .
  CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]

fastapi/main.py (minimal skeleton):
  - Create a FastAPI app instance
  - Add a GET /health endpoint that returns {"status": "ok"} with HTTP 200
  - No database, no auth dependency yet — those are added in subsequent tasks
  - Include a module-level comment: "# Auth dependency added in S3-T2"
  - Include a module-level comment: "# Database lifespan added in S4-T1"

The app must start cleanly with uvicorn and respond to GET /health.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| `GET /health` | HTTP 200, body `{"status": "ok"}` |
| Image builds without error | `docker compose build fastapi` exits 0 |

**Verification command:**
```bash
cp .env.example .env
sed -i 's/change-me-pg-password/testpgpass123/g; s/change-me-api-key/testkey/g; s/change-me-password/testpass/g' .env
docker compose build fastapi

# Start fastapi only (it will fail its depends_on on db-init, so run directly)
docker run --rm -d -p 8000:8000 --env-file .env \
  $(docker compose config --images | grep fastapi | head -1) \
  uvicorn main:app --host 0.0.0.0 --port 8000 2>/dev/null || \
  docker run --rm -d -p 8000:8000 -e API_KEY=testkey \
  $(docker images --format "{{.Repository}}:{{.Tag}}" | grep fastapi | head -1) \
  uvicorn main:app --host 0.0.0.0 --port 8000

sleep 3
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health | \
  grep -q "200" && echo "PASS: /health returns 200" || echo "FAIL"

docker stop $(docker ps -q --filter "publish=8000")
rm .env
```

**Touches invariant:** No.

---

### S3-T2 — Implement API key authentication dependency

**Description:**  
Input: `fastapi/main.py` skeleton. Output: a `get_api_key` FastAPI dependency function
that reads the expected key from the `API_KEY` environment variable at startup and
validates the `X-API-Key` header on every request. Applied to all routes including
`/health`.

**Prompt for Claude Code:**
```
Add API key authentication to fastapi/main.py.

Requirements:
  - Read the expected API key from the API_KEY environment variable at module load time.
    If API_KEY is not set, raise a RuntimeError on startup — the app must not start
    without a key configured.
  - Create a dependency function get_api_key(x_api_key: str = Header(None)) that:
      - Returns the key value if it matches the expected key
      - Raises HTTPException(status_code=401, detail="Invalid or missing API key")
        if the header is missing (None) or does not match
  - Apply this dependency to ALL routes using app = FastAPI() with a global dependency:
      app = FastAPI(dependencies=[Depends(get_api_key)])
    This ensures any route added in future sessions is automatically protected.
  - The /health endpoint should remain but now requires the API key.
  - Under no circumstances should the key value appear in any log statement,
    error message, or response body.
  - Add a log line on startup: "FastAPI: API key authentication configured" (no key value).

Do not add any route that returns or echoes the key value. Do not log request headers.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| `GET /health` with no `X-API-Key` header | HTTP 401 |
| `GET /health` with wrong `X-API-Key` value | HTTP 401 |
| `GET /health` with correct `X-API-Key` value | HTTP 200 |
| Response body of 401 | Does not contain the key value |
| FastAPI logs after request | Do not contain the key value |

**Verification command:**
```bash
# Build and run fastapi container standalone
docker compose build fastapi
CID=$(docker run --rm -d -p 8001:8000 -e API_KEY=secret-test-key customer-risk-api-fastapi 2>/dev/null || \
      docker run --rm -d -p 8001:8000 -e API_KEY=secret-test-key \
      $(docker images --format "{{.Repository}}" | grep -i fastapi | head -1) )
sleep 3

# No key → 401
curl -s -o /dev/null -w "%{http_code}" http://localhost:8001/health | \
  grep -q "401" && echo "PASS: no key → 401" || echo "FAIL: no key → unexpected response"

# Wrong key → 401
curl -s -o /dev/null -w "%{http_code}" -H "X-API-Key: wrong-key" http://localhost:8001/health | \
  grep -q "401" && echo "PASS: wrong key → 401" || echo "FAIL"

# Correct key → 200
curl -s -o /dev/null -w "%{http_code}" -H "X-API-Key: secret-test-key" http://localhost:8001/health | \
  grep -q "200" && echo "PASS: correct key → 200" || echo "FAIL"

# Key value not in response body
BODY=$(curl -s -H "X-API-Key: secret-test-key" http://localhost:8001/health)
echo "$BODY" | grep -q "secret-test-key" && echo "FAIL: key in response body" || echo "PASS: key not in body"

docker stop $CID
```

**Touches invariant:** `INV-01` (every request must carry valid key), `INV-02` (key must not appear in system output).

**Code review checklist (INV-01, INV-02):**
- The dependency is applied via `FastAPI(dependencies=[Depends(get_api_key)])` — not added per-route. Confirm no route bypasses this.
- No `logging.info` or `print` statement anywhere in the auth path includes the header value or the expected key variable.
- The 401 response body contains only `{"detail": "Invalid or missing API key"}` — no key value, no header echo.
- `API_KEY` is read at module load, not per-request — correct. Confirm it raises `RuntimeError` when absent, not silently defaulting to `None`.

---

### S3-T3 — Verify auth enforcement with a dedicated test script

**Description:**  
Input: auth-enabled FastAPI from S3-T2. Output: `verify/s3_auth.sh` — a script that
starts FastAPI standalone and runs the full auth test matrix, including the log
scrape for key leakage (INV-02).

**Prompt for Claude Code:**
```
Create verify/s3_auth.sh. This script tests the API key authentication layer in isolation,
without requiring Nginx or Postgres to be running.

The script should:

1. Build the fastapi image if not already built.
2. Start the fastapi container with a known test key:
     docker run --rm -d --name fastapi-auth-test -p 8002:8000 \
       -e API_KEY=inv01-test-key-do-not-use \
       <fastapi-image-name>
3. Wait up to 30 seconds for /health to respond (poll with curl).
4. Run these checks and print PASS/FAIL with the invariant ID for each:

   [INV-01-A] No header → HTTP 401
   [INV-01-B] Wrong header value → HTTP 401
   [INV-01-C] Correct header value → HTTP 200
   [INV-01-D] 401 response body does not contain the string "inv01-test-key-do-not-use"
   [INV-02-A] Response headers for a valid request do not contain "inv01-test-key-do-not-use"
   [INV-02-B] Container logs after all requests do not contain "inv01-test-key-do-not-use"

5. Stop and remove the container regardless of pass/fail.
6. Print overall PASS if all 6 checks pass, FAIL otherwise.
7. Exit 0 on overall PASS, 1 on overall FAIL.

Make the script executable.
```

**Test cases:**

| Check ID | Scenario | Expected |
|---|---|---|
| INV-01-A | No `X-API-Key` header | 401 |
| INV-01-B | `X-API-Key: wrong` | 401 |
| INV-01-C | `X-API-Key: inv01-test-key-do-not-use` | 200 |
| INV-01-D | 401 body | No key string |
| INV-02-A | Valid response headers | No key string |
| INV-02-B | Container logs | No key string |

**Verification command:**
```bash
chmod +x verify/s3_auth.sh && bash verify/s3_auth.sh
```

**Touches invariant:** `INV-01`, `INV-02`.

**Code review checklist (INV-01, INV-02):**
- The log scrape (INV-02-B) collects logs via `docker logs fastapi-auth-test` — confirm it runs after all requests, not before.
- The test key string used in the script (`inv01-test-key-do-not-use`) is distinct from the `.env.example` placeholder — prevents false negatives if the placeholder leaks.

---

## Session 4 — FastAPI core: risk lookup endpoint

**Goal:** FastAPI connects to Postgres on startup with a retry loop and exposes a working
`GET /api/risk/{customer_id}` endpoint. The response contract is complete. 404 and 401
behave correctly. At the end of this session, `curl` against FastAPI directly with the
API key returns real data from the seeded database.

**Estimated duration:** ~2h 15m  
(1 standard task × ~30 min + 2 invariant-touching tasks × ~42 min avg)

---

### S4-T1 — Implement database connection with startup retry loop

**Description:**  
Input: `fastapi/main.py` with auth. Output: a `lifespan` context manager that opens a
psycopg2 connection on startup with a retry loop, stores it on `app.state`, and closes
it on shutdown. No queries yet.

**Prompt for Claude Code:**
```
Add database connectivity to fastapi/main.py.

Requirements:
  - Read these environment variables for the DB connection:
      POSTGRES_HOST (default: "postgres")
      POSTGRES_DB
      POSTGRES_USER
      POSTGRES_PASSWORD
  - Implement a lifespan context manager (FastAPI lifespan pattern) that:
      1. Attempts psycopg2.connect() up to 10 times with 3-second delays between attempts
      2. After each failed attempt, logs: "FastAPI: waiting for database... (attempt N/10)"
      3. On successful connection, executes SELECT 1 to confirm readiness
      4. Stores the connection as app.state.db
      5. On shutdown (finally block), closes the connection if it is open
      6. If all 10 attempts fail, raises RuntimeError("Database connection failed") —
         this prevents FastAPI from accepting any requests
  - Use psycopg2 connection-level autocommit=False
  - Do not pool connections — a single connection is correct for this workload
  - Add a connection health check function get_db_conn(request: Request) that:
      - Returns app.state.db if the connection is open
      - Attempts reconnection once if the connection is closed
      - Raises HTTPException(503) if reconnection fails
  - Log "FastAPI: database connection established" on success (no credentials in log)

Do not add any query logic yet — that is in S4-T2.
Replace the "# Database lifespan added in S4-T1" comment with the implementation.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| Startup with Postgres available | Connects within 3 attempts, logs success |
| Startup with Postgres unavailable | Retries 10 times, then raises RuntimeError |
| `GET /health` after DB connect | Still returns 200 (DB connect doesn't break health) |

**Verification command:**
```bash
cp .env.example .env
sed -i 's/change-me-pg-password/testpgpass123/g; s/change-me-api-key/testkey/g; s/change-me-password/testpass/g' .env

# Start with postgres available — expect clean startup
docker compose up -d postgres
sleep 10
docker compose up -d --build fastapi
sleep 15
docker compose logs fastapi | grep -q "database connection established" && \
  echo "PASS: DB connection logged" || echo "FAIL"

docker compose down && rm .env
```

**Touches invariant:** `INV-03` (FastAPI retry loop is the second mechanism for startup sequencing).

**Code review checklist (INV-03):**
- The retry loop uses `time.sleep(3)` between attempts — not exponential backoff that could delay startup beyond the healthcheck timeout.
- On final failure, `RuntimeError` is raised, not `sys.exit()` — uvicorn will report this and prevent the ASGI app from accepting connections.
- `SELECT 1` is executed after connect to confirm Postgres is not just accepting TCP but is actually serving queries.

---

### S4-T2 — Implement the `GET /api/risk/{customer_id}` endpoint

**Description:**  
Input: `main.py` with DB connection. Output: the complete risk lookup endpoint with
Pydantic response models, parameterized queries for both tables, and all error handling
(404, 500 for empty factors). No string interpolation in any query.

**Prompt for Claude Code:**
```
Add the risk lookup endpoint to fastapi/main.py.

Pydantic response models (add these to main.py):
  class RiskFactor(BaseModel):
      factor_code: str
      factor_description: str

  class RiskResponse(BaseModel):
      customer_id: str
      tier: Literal['LOW', 'MEDIUM', 'HIGH']
      risk_factors: List[RiskFactor]

Endpoint: GET /api/risk/{customer_id}
  - Path parameter: customer_id (str)
  - Validate customer_id: must be 1–20 alphanumeric characters (regex: ^[A-Za-z0-9]{1,20}$)
    Return HTTP 400 if validation fails.
  - Use get_db_conn() dependency to get the database connection.
  - Execute this parameterized query to fetch the customer:
      SELECT customer_id, tier FROM customers WHERE customer_id = %s
    Pass customer_id as the parameter. Use cursor.fetchone().
  - If no row returned: raise HTTPException(404, detail="Customer not found")
  - Execute this parameterized query to fetch factors:
      SELECT factor_code, factor_description FROM risk_factors
      WHERE customer_id = %s ORDER BY factor_code
    Pass customer_id as the parameter. Use cursor.fetchall().
  - If risk_factors list is empty: raise HTTPException(500,
      detail="Customer record is incomplete: no risk factors found")
  - Build and return a RiskResponse. Populate customer_id from the DATABASE ROW,
    not from the request path parameter.
  - Do not use string interpolation or f-strings in any query. Use %s parameters only.
  - Close cursors in finally blocks.

CRITICAL: No query in this function may be anything other than a SELECT statement.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| `GET /api/risk/CUST001` with valid key | HTTP 200, correct tier, ≥1 factor |
| `GET /api/risk/NONEXISTENT` with valid key | HTTP 404 |
| `GET /api/risk/CUST001` with no key | HTTP 401 |
| `GET /api/risk/CUST001` with wrong key | HTTP 401 |
| `GET /api/risk/<injection>` e.g. `'; DROP TABLE` | HTTP 400 (validation rejects) |
| Response `customer_id` field | Matches path param (from DB row) |
| Response `tier` field | Member of {LOW, MEDIUM, HIGH} |

**Verification command:**
```bash
cp .env.example .env
sed -i 's/change-me-pg-password/testpgpass123/g; s/change-me-api-key/testkey/g; s/change-me-password/testpass/g' .env

docker compose up -d postgres db-init
sleep 30  # wait for db-init to complete
docker compose up -d fastapi
sleep 10

# Valid request
HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "X-API-Key: testkey" http://localhost:8000/api/risk/CUST001)
[ "$HTTP" = "200" ] && echo "PASS: valid request → 200" || echo "FAIL: got $HTTP"

# 404
HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "X-API-Key: testkey" http://localhost:8000/api/risk/NOTREAL)
[ "$HTTP" = "404" ] && echo "PASS: not found → 404" || echo "FAIL: got $HTTP"

# 401
HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:8000/api/risk/CUST001)
[ "$HTTP" = "401" ] && echo "PASS: no key → 401" || echo "FAIL: got $HTTP"

# customer_id in response matches request
BODY=$(curl -s -H "X-API-Key: testkey" http://localhost:8000/api/risk/CUST001)
echo "$BODY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['customer_id'] == 'CUST001', f'FAIL: got {d[\"customer_id\"]}'
assert d['tier'] in ['LOW','MEDIUM','HIGH'], f'FAIL: tier {d[\"tier\"]}'
assert len(d['risk_factors']) > 0, 'FAIL: empty factors'
print('PASS: response shape valid')
"

docker compose down && rm .env
```

**Touches invariant:** `INV-01` (auth on this route), `INV-04` (response contains only requested customer's data), `INV-05` (only SELECT queries), `INV-06` (tier value validated by Pydantic), `INV-07` (empty factors triggers 500), `INV-10` (live query, no cache).

**Code review checklist (INV-01, INV-04, INV-05, INV-06, INV-07, INV-10):**
- The route is covered by the global `Depends(get_api_key)` — no `dependencies=[]` override on this route that could bypass it.
- `customer_id` in response is populated from `row[0]` (database), not from the path parameter variable.
- Both queries are SELECT statements. No INSERT, UPDATE, DELETE, DDL anywhere in this function.
- The Pydantic model uses `Literal['LOW', 'MEDIUM', 'HIGH']` for `tier` — a value outside this set raises a validation error before the response is returned.
- The empty-factors check (`if not risk_factors`) is present and raises HTTP 500, not 404.
- No `@lru_cache`, `functools.cache`, or dict-based caching around the query calls.

---

### S4-T3 — Integration check: FastAPI + database end-to-end

**Description:**  
Input: complete FastAPI with auth and endpoint. Output: `verify/s4_api.sh` — a script
that starts postgres, db-init, and fastapi; runs the full API test matrix; and verifies
INV-04 and INV-05 with a table snapshot check.

**Prompt for Claude Code:**
```
Create verify/s4_api.sh. This script tests FastAPI end-to-end against the live database,
without Nginx.

1. Start postgres, db-init, fastapi: docker compose up -d postgres db-init fastapi
2. Wait for db-init to exit 0 and fastapi to be healthy (up to 90 seconds).
3. Run these checks:

   [S4-A] GET /api/risk/CUST001 with correct key → HTTP 200
   [S4-B] GET /api/risk/CUST001 response: customer_id == "CUST001"
   [S4-C] GET /api/risk/CUST001 response: tier in {LOW, MEDIUM, HIGH}
   [S4-D] GET /api/risk/CUST001 response: risk_factors is non-empty array
   [INV-04] response customer_id matches request customer_id for all 9 seed customers
   [INV-05] Snapshot customers row count before requests; make 20 requests;
            snapshot after; assert counts are equal
   [S4-E] GET /api/risk/NONEXISTENT with correct key → HTTP 404
   [S4-F] GET /api/risk/CUST001 with no key → HTTP 401
   [S4-G] GET /api/risk/CUST001 with wrong key → HTTP 401

4. Run docker compose down -v.
5. Exit 0 if all pass, 1 if any fail. Print each check result.

Make executable. Use the API_KEY value from .env.
```

**Test cases:** As enumerated in the script checks above.

**Verification command:**
```bash
chmod +x verify/s4_api.sh && bash verify/s4_api.sh
```

**Touches invariant:** `INV-04`, `INV-05`.

**Code review checklist (INV-04, INV-05):**
- The INV-04 check iterates all 9 known seed customer IDs, not just CUST001.
- The INV-05 snapshot uses `SELECT COUNT(*) FROM customers` and `SELECT COUNT(*) FROM risk_factors` — both tables checked.

---

## Session 5 — Nginx: proxy, key injection, and Basic Auth

**Goal:** The Nginx container serves the UI page, gates all access via HTTP Basic Auth,
and transparently injects the API key into all `/api/*` requests forwarded to FastAPI.
The browser never receives the key. At the end of this session, `curl` against port 80
confirms the complete auth layering: Basic Auth required, key injected, FastAPI protected.

**Estimated duration:** ~2h 45m  
(1 standard task × ~30 min + 3 invariant-touching tasks × ~45 min avg)

---

### S5-T1 — Write the Nginx configuration

**Description:**  
Input: `nginx/` directory. Output: `nginx/nginx.conf.template` — an Nginx config
template (using `envsubst` variable substitution) that configures Basic Auth for all
locations, injects `X-API-Key` on `/api/*`, and proxies to FastAPI.

**Prompt for Claude Code:**
```
Write nginx/nginx.conf.template. This is an envsubst template — variable references
use ${VAR_NAME} syntax and will be substituted at container startup.

Requirements:

server block (port 80):

  auth_basic section:
    - auth_basic "Restricted";
    - auth_basic_user_file /etc/nginx/.htpasswd;
    - Apply to the entire server block (not per-location) so all paths require Basic Auth.

  location / (serves static UI):
    - root /usr/share/nginx/html;
    - index index.html;
    - try_files $uri $uri/ /index.html;
    - No proxy_pass here — static files only.
    - Do NOT add any header that includes ${API_KEY} here.

  location /api/ (proxies to FastAPI):
    - proxy_pass http://fastapi:8000;
    - proxy_set_header Host $host;
    - proxy_set_header X-Real-IP $remote_addr;
    - proxy_set_header X-API-Key ${API_KEY};
    - proxy_hide_header X-API-Key; (prevents the header from being reflected in responses)
    - Do NOT add the X-API-Key to response headers via add_header.

  access_log configuration:
    - Use a custom log format that does NOT include $http_x_api_key
    - The log format should include: $remote_addr, $time_local, $request,
      $status, $body_bytes_sent, $http_referer, $http_user_agent

Also write nginx/nginx.conf as a non-template fallback (used by the stub Dockerfile) —
this can remain the minimal "return 200" version from S1-T3.

The template must be valid nginx config syntax.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| Template substitution with known vars | Valid nginx.conf produced, no literal `${VAR}` remaining |
| `proxy_set_header X-API-Key` present in `/api/` location | Key injection confirmed |
| `proxy_hide_header X-API-Key` present | Key not reflected in responses |
| `$http_x_api_key` absent from log format | Key not logged |
| `auth_basic` applies at server level | Every location requires Basic Auth |

**Verification command:**
```bash
# Dry-run template substitution
API_KEY=test-key-nginx envsubst '${API_KEY}' < nginx/nginx.conf.template > /tmp/nginx-test.conf
nginx -t -c /tmp/nginx-test.conf 2>&1 | grep -q "syntax is ok" && \
  echo "PASS: nginx config valid" || echo "FAIL: nginx config invalid"

# Confirm key injection directive is present
grep -q "proxy_set_header X-API-Key" /tmp/nginx-test.conf && \
  echo "PASS: key injection present" || echo "FAIL"

# Confirm key not in log format
grep -q "http_x_api_key" /tmp/nginx-test.conf && \
  echo "FAIL: key in log format" || echo "PASS: key not in log format (INV-02)"

# Confirm no template variables remain
grep -q '\${' /tmp/nginx-test.conf && \
  echo "FAIL: unsubstituted variables remain" || echo "PASS: full substitution"
```

**Touches invariant:** `INV-02` (key must not appear in logs or responses).

**Code review checklist (INV-02):**
- `proxy_hide_header X-API-Key` is present — prevents the header being forwarded from FastAPI's response back to the browser.
- The access log `log_format` definition does not include any variable that could capture the API key (no `$http_x_api_key`, no `$upstream_http_x_api_key`).
- `add_header X-API-Key` does not appear anywhere — the key is only in `proxy_set_header` (upstream only).

---

### S5-T2 — Write the Nginx container entrypoint for `htpasswd` generation

**Description:**  
Input: `nginx/nginx.conf.template`. Output: `nginx/entrypoint.sh` — a shell script that
validates `BASIC_AUTH_USER` and `BASIC_AUTH_PASSWORD` are set, generates the `htpasswd`
file, substitutes the API key into `nginx.conf`, and starts Nginx. Also update
`nginx/Dockerfile` to use the entrypoint.

**Prompt for Claude Code:**
```
Write nginx/entrypoint.sh. This script runs at container startup and must complete
before Nginx starts.

Requirements:
  1. Check that BASIC_AUTH_USER is non-empty. If empty or unset:
       echo "ERROR: BASIC_AUTH_USER is required" >&2 && exit 1
  2. Check that BASIC_AUTH_PASSWORD is non-empty. If empty or unset:
       echo "ERROR: BASIC_AUTH_PASSWORD is required" >&2 && exit 1
  3. Check that API_KEY is non-empty. If empty or unset:
       echo "ERROR: API_KEY is required" >&2 && exit 1
  4. Generate /etc/nginx/.htpasswd:
       htpasswd -cb /etc/nginx/.htpasswd "$BASIC_AUTH_USER" "$BASIC_AUTH_PASSWORD"
  5. Substitute the API_KEY into the nginx config template:
       envsubst '${API_KEY}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
  6. Validate the generated config: nginx -t
     If validation fails: echo "ERROR: nginx config invalid" >&2 && exit 1
  7. Start Nginx in the foreground: exec nginx -g "daemon off;"

Update nginx/Dockerfile:
  - FROM nginx:1.25-alpine
  - RUN apk add --no-cache apache2-utils (provides htpasswd)
  - COPY nginx.conf.template /etc/nginx/nginx.conf.template
  - COPY nginx.conf /etc/nginx/nginx.conf (fallback, overwritten by entrypoint)
  - COPY entrypoint.sh /entrypoint.sh
  - RUN chmod +x /entrypoint.sh
  - ENTRYPOINT ["/entrypoint.sh"]

Make entrypoint.sh executable.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| All 3 env vars set | `htpasswd` created, nginx.conf generated, Nginx starts |
| `BASIC_AUTH_USER` empty | Container exits 1 with error message |
| `BASIC_AUTH_PASSWORD` empty | Container exits 1 with error message |
| `API_KEY` empty | Container exits 1 with error message |
| Generated `nginx.conf` contains no `${API_KEY}` | Template fully substituted |

**Verification command:**
```bash
docker compose build nginx

# Happy path
docker run --rm \
  -e BASIC_AUTH_USER=testuser \
  -e BASIC_AUTH_PASSWORD=testpass \
  -e API_KEY=test-key-nginx \
  -p 8080:80 \
  --name nginx-test \
  $(docker images --format "{{.Repository}}:{{.Tag}}" | grep nginx | grep -v none | head -1) &
sleep 5
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ | \
  grep -q "401" && echo "PASS: Basic Auth active" || echo "FAIL"  # 401 = no credentials, expected

# Missing BASIC_AUTH_USER
docker run --rm \
  -e BASIC_AUTH_USER="" \
  -e BASIC_AUTH_PASSWORD=testpass \
  -e API_KEY=test-key \
  $(docker images --format "{{.Repository}}:{{.Tag}}" | grep nginx | grep -v none | head -1) 2>&1 | \
  grep -q "BASIC_AUTH_USER is required" && echo "PASS: empty user caught" || echo "FAIL"

docker stop nginx-test 2>/dev/null; true
```

**Touches invariant:** `INV-02` (entrypoint validates API_KEY is set before starting Nginx — prevents key injection with empty value).

**Code review checklist (INV-02):**
- `envsubst '${API_KEY}'` uses single quotes to limit substitution to only `API_KEY` — it must not accidentally substitute other nginx variables like `$host` or `$uri`.
- The generated `nginx.conf` is written to a path that overwrites the fallback — not a second config file included alongside it.
- The validation step (`nginx -t`) runs against the generated file, not the template.

---

### S5-T3 — Integration check: Nginx Basic Auth and key injection

**Description:**  
Input: complete Nginx container. Output: `verify/s5_nginx.sh` — a script that starts
the full stack (postgres, db-init, fastapi, nginx) and verifies the full auth layering:
Basic Auth at port 80, key injection on `/api/*`, and key non-appearance in any response.

**Prompt for Claude Code:**
```
Create verify/s5_nginx.sh. This script tests the full auth chain through Nginx.

Setup: docker compose up -d, wait for all services healthy (up to 120 seconds).

Checks:

  [S5-A] GET http://localhost:80/ with no credentials → HTTP 401
  [S5-B] GET http://localhost:80/ with correct Basic Auth credentials → HTTP 200
  [S5-C] GET http://localhost:80/api/risk/CUST001 with no Basic Auth → HTTP 401
  [S5-D] GET http://localhost:80/api/risk/CUST001 with Basic Auth only (key injected by Nginx) → HTTP 200
  [INV-02-C] Response headers for S5-D do not contain the API_KEY value
  [INV-02-D] Response body for S5-D does not contain the API_KEY value
  [INV-02-E] Nginx access logs after all requests do not contain the API_KEY value
  [S5-E] GET http://localhost:80/api/risk/NONEXISTENT with Basic Auth → HTTP 404

Use curl -u user:pass for Basic Auth. Read BASIC_AUTH_USER, BASIC_AUTH_PASSWORD, and
API_KEY from .env.

Teardown: docker compose down -v.
Exit 0 if all pass.
Make executable.
```

**Test cases:** As per script checks above.

**Verification command:**
```bash
chmod +x verify/s5_nginx.sh && bash verify/s5_nginx.sh
```

**Touches invariant:** `INV-01` (FastAPI still validates the injected key), `INV-02` (key not in any response or log via Nginx path).

**Code review checklist (INV-01, INV-02):**
- Check S5-D uses Basic Auth credentials but no explicit `X-API-Key` header — confirms Nginx injection is doing the work.
- INV-02-E collects Nginx logs via `docker compose logs nginx` after all requests have completed.
- The API_KEY variable used for log scraping is read from `.env`, not hardcoded — ensures the test uses the actual configured value.

---

### S5-T4 — Verify that FastAPI is unreachable on port 8000 from the host

**Description:**  
Input: running full stack. Output: a check confirming that FastAPI's port 8000 is not
exposed to the host network — only port 80 (Nginx) is accessible. This is a constraint
verification, not an implementation task.

**Prompt for Claude Code:**
```
Add a check to verify/s5_nginx.sh (or create a separate verify/s5_isolation.sh) that
confirms FastAPI is not directly reachable from the host network.

The check should:
1. Attempt: curl --connect-timeout 3 http://localhost:8000/health
2. Assert the connection is refused or times out (not HTTP 200)
3. Print [S5-ISOLATION] PASS if connection fails, FAIL if it receives a 200

This confirms that the docker-compose.yml correctly does not expose fastapi port 8000
to the host, meaning all external traffic must pass through Nginx (and therefore through
Basic Auth and key injection).

Make the script executable.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| `curl http://localhost:8000/health` | Connection refused or timeout |
| `curl http://localhost:80/api/risk/CUST001` (via Nginx) with credentials | HTTP 200 |

**Verification command:**
```bash
chmod +x verify/s5_isolation.sh && bash verify/s5_isolation.sh
```

**Touches invariant:** `INV-01` (FastAPI auth is the only enforcement layer for non-browser callers — this test confirms the network architecture supports the intended flow).

**Code review checklist (INV-01):**
- If this test fails (port 8000 is exposed), the consequence is that any host process can call FastAPI directly — bypassing Basic Auth entirely. Document this as a deployment constraint in the README.

---

## Session 6 — Browser UI

**Goal:** A single HTML page with a customer ID input field is served by Nginx. The page
calls `/api/risk/{customer_id}` via fetch (no API key in the JS), displays the result, and
handles error states. At the end of this session, a browser visiting `localhost` with Basic
Auth credentials can look up any seeded customer.

**Estimated duration:** ~1h 45m (3 standard tasks × ~35 min avg)

---

### S6-T1 — Write the UI HTML page

**Description:**  
Input: Nginx static file serving configuration. Output: `nginx/html/index.html` — a
single-file HTML page with inline CSS and vanilla JavaScript. No frameworks, no external
CDN dependencies.

**Prompt for Claude Code:**
```
Create nginx/html/index.html. This is the complete UI for the Customer Risk API.

Requirements:
  - Single HTML file with all CSS and JavaScript inline (no external files)
  - No frontend frameworks (no React, Vue, etc.) — vanilla JS only
  - No external CDN links — fully self-contained

Page structure:
  - Title: "Customer Risk Lookup"
  - A text input field with placeholder "Enter customer ID"
  - A "Look up" button
  - A results area that shows either:
      Success: customer_id, tier (visually distinct — e.g. colour-coded LOW/MEDIUM/HIGH),
               and an unordered list of risk factors (factor_code + factor_description)
      Error 404: "Customer not found"
      Error 401: "Authentication error — contact your administrator"
      Other error: "An unexpected error occurred (HTTP <status>)"
  - A loading state while the request is in flight

JavaScript behaviour:
  - On button click (or Enter key): fetch /api/risk/<value> using the Fetch API
  - No API key in the fetch request — Nginx injects it
  - Handle response status codes: 200, 401, 404 explicitly; all others as generic error
  - Clear the results area before each new request
  - Disable the button while a request is in flight

Do not hardcode any API key, URL, or credential in the JavaScript.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| Valid customer ID entered | Tier and factors displayed |
| Non-existent customer ID entered | "Customer not found" message |
| Page loaded with no interaction | Empty results area, input focused |
| Enter key in input | Triggers lookup (same as button) |

**Verification command:**
```bash
# Static validation — no key in the HTML file
grep -i "api.key\|x-api-key\|apikey" nginx/html/index.html && \
  echo "FAIL: API key reference in HTML" || echo "PASS: no API key in HTML (INV-02)"

# No external URLs
grep -E "http[s]?://" nginx/html/index.html && \
  echo "WARN: external URL found" || echo "PASS: no external URLs"

# Valid HTML (basic check)
python3 -c "
from html.parser import HTMLParser
class V(HTMLParser):
    def __init__(self): super().__init__(); self.errors=[]
v = V()
v.feed(open('nginx/html/index.html').read())
print('PASS: HTML parses' if not v.errors else 'FAIL')
"
```

**Touches invariant:** `INV-02` (HTML/JS must contain no API key value).

**Code review checklist (INV-02):**
- No string resembling an API key, no `X-API-Key` header set in fetch() calls, no JavaScript variable storing a key value.
- The fetch call uses a relative URL (`/api/risk/...`), not an absolute URL that could bypass Nginx.

---

### S6-T2 — Update Nginx Dockerfile to serve static UI files

**Description:**  
Input: `nginx/html/index.html`. Output: updated `nginx/Dockerfile` that copies
`html/index.html` into the image at the path Nginx's config expects for static serving.

**Prompt for Claude Code:**
```
Update nginx/Dockerfile to include the static UI file.

Add to the existing nginx/Dockerfile:
  COPY html/ /usr/share/nginx/html/

This must come after the COPY for entrypoint.sh and nginx.conf files so the image
layer order is: base image → tools → config → static assets.

Verify the full nginx/Dockerfile reads correctly end-to-end and produces a valid image
when built. The ENTRYPOINT should remain ["/entrypoint.sh"].

Also ensure nginx/html/ directory exists with index.html in it.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| `docker compose build nginx` | Image builds cleanly |
| `GET http://localhost:80/` with Basic Auth | Returns index.html content |
| `GET http://localhost:80/index.html` with Basic Auth | Returns index.html content |

**Verification command:**
```bash
cp .env.example .env
sed -i 's/change-me-pg-password/testpgpass123/g; s/change-me-api-key/testkey/g; s/change-me-password/testpass/g' .env

docker compose build nginx
docker compose up -d nginx

sleep 5
curl -s -u opsuser:testpass123 http://localhost:80/ | \
  grep -q "Customer Risk Lookup" && echo "PASS: UI served" || echo "FAIL"

docker compose down && rm .env
```

**Touches invariant:** No.

---

### S6-T3 — Browser integration smoke test

**Description:**  
Input: full stack with UI. Output: `verify/s6_ui.sh` — a script that validates the UI
file is served correctly, that the fetch path works end-to-end, and that no API key
appears in the served HTML.

**Prompt for Claude Code:**
```
Create verify/s6_ui.sh. This script validates the UI layer.

Setup: docker compose up -d, wait for nginx healthy (up to 120 seconds).

Checks:
  [S6-A] GET http://localhost:80/ with no credentials → HTTP 401
  [S6-B] GET http://localhost:80/ with correct Basic Auth → HTTP 200
  [S6-C] Response body of S6-B contains "Customer Risk Lookup"
  [S6-D] Response body of S6-B contains the lookup input form elements
  [INV-02-F] The served HTML content does not contain the API_KEY value from .env
  [S6-E] GET http://localhost:80/api/risk/CUST001 via Nginx with Basic Auth → HTTP 200
         (validates the full browser path: UI → same origin → /api/ → FastAPI)
  [S6-F] Response of S6-E is valid JSON with keys: customer_id, tier, risk_factors

Teardown: docker compose down -v.
Exit 0 on all pass. Make executable.
```

**Test cases:** As per script checks.

**Verification command:**
```bash
chmod +x verify/s6_ui.sh && bash verify/s6_ui.sh
```

**Touches invariant:** `INV-02` (served HTML must not contain the API key value).

**Code review checklist (INV-02):**
- INV-02-F compares the entire HTML body against the `API_KEY` value from `.env` — not a hardcoded test key.

---

## Session 7 — End-to-end integration and invariant verification

**Goal:** The complete system is running. Every invariant from INVARIANTS.md has a
verification test that is run against the live stack. A master verification script
runs all session scripts in sequence and produces a single PASS/FAIL report. The
system is production-ready within the stated scope.

**Estimated duration:** ~3h 10m  
(2 standard tasks × ~30 min + 3 invariant-touching tasks × ~47 min avg)

---

### S7-T1 — Cold-start integration test

**Description:**  
Input: complete system. Output: `verify/s7_coldstart.sh` — a script that tears down
all volumes, runs `docker compose up` from scratch, and confirms the system reaches
full operational state from a completely cold start in under 120 seconds.

**Prompt for Claude Code:**
```
Create verify/s7_coldstart.sh. This verifies the "no manual steps" constraint from
the brief.

Steps:
1. docker compose down -v (ensure clean state)
2. Record start time
3. docker compose up -d --build
4. Poll until all of the following are true (timeout 120 seconds):
     - postgres: healthy
     - db-init: Exited (0)
     - fastapi: healthy
     - nginx: healthy
   Check every 5 seconds; print status on each check.
5. Record end time. Print elapsed seconds.
6. Run these integration checks:

   [S7-COLD-A] GET http://localhost:80/ with Basic Auth → HTTP 200
   [S7-COLD-B] GET http://localhost:80/api/risk/CUST001 with Basic Auth → HTTP 200
   [S7-COLD-C] Response contains tier and non-empty risk_factors
   [INV-03] db-init Exited (0) timestamp is BEFORE fastapi first-healthy timestamp
            (use docker inspect to get timestamps)

7. docker compose down -v
8. Print elapsed time and PASS/FAIL for each check.
Make executable.
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| Cold start | All services healthy within 120s |
| First request after cold start | Valid response, no 500 |
| INV-03 timing check | db-init finish time < fastapi healthy time |

**Verification command:**
```bash
chmod +x verify/s7_coldstart.sh && bash verify/s7_coldstart.sh
```

**Touches invariant:** `INV-03` (startup sequencing timing verification).

**Code review checklist (INV-03):**
- The timestamp comparison uses `docker inspect` container start/finish times, not wall-clock approximations.
- The script performs a real cold start (`down -v` first) — not a restart of an already-running stack.

---

### S7-T2 — Invariant verification suite: INV-05 and INV-10

**Description:**  
Input: running full stack. Output: `verify/s7_invariants_data.sh` — tests for the
read-only guarantee (INV-05) and live-query guarantee (INV-10).

**Prompt for Claude Code:**
```
Create verify/s7_invariants_data.sh.

Setup: docker compose up -d, wait for healthy.

[INV-05] Read-only enforcement:
  1. Record a checksum of all data before any API requests:
       SELECT md5(string_agg(customer_id || tier, ',' ORDER BY customer_id))
       FROM customers;
     and
       SELECT md5(string_agg(customer_id || factor_code, ',' ORDER BY id))
       FROM risk_factors;
  2. Make 50 API requests: mix of GET /api/risk/<id> for all 9 seed customers
  3. Record checksums again
  4. Assert pre == post for both tables
  5. Print [INV-05] PASS if equal, FAIL with diff if not

[INV-10] Live query (no cache):
  1. Read the current tier for CUST001 via the API. Record it.
  2. Directly update the tier in Postgres (via docker compose exec):
       UPDATE customers SET tier='HIGH' WHERE customer_id='CUST001'
       AND tier != 'HIGH';
     (Only updates if not already HIGH — to avoid a no-op)
  3. Immediately call GET /api/risk/CUST001 via the API.
  4. Assert the response tier matches the updated value in the database.
  5. Restore the original tier value.
  6. Print [INV-10] PASS/FAIL

Teardown: docker compose down -v. Make executable.
```

**Test cases:**

| Check | Expected |
|---|---|
| INV-05: checksums pre vs post API requests | Identical |
| INV-10: API returns updated tier | Matches DB value, not cached |

**Verification command:**
```bash
chmod +x verify/s7_invariants_data.sh && bash verify/s7_invariants_data.sh
```

**Touches invariant:** `INV-05`, `INV-10`.

**Code review checklist (INV-05, INV-10):**
- The INV-05 checksum covers both tables — a write to either would be detected.
- The INV-10 test updates the DB directly (bypassing the API) to confirm the API does not serve a cached value.
- The tier is restored after the INV-10 test so the seed data is consistent for any tests that follow.

---

### S7-T3 — Invariant verification suite: INV-01 and INV-02 via full stack

**Description:**  
Input: running full stack. Output: `verify/s7_invariants_auth.sh` — the complete auth
invariant verification run through Nginx (not FastAPI standalone as in S3).

**Prompt for Claude Code:**
```
Create verify/s7_invariants_auth.sh. These checks run through the full Nginx → FastAPI
path, not against FastAPI directly.

Setup: docker compose up -d, wait for healthy.

[INV-01-FULLSTACK-A] Request with no Basic Auth credentials → Nginx returns 401
  (FastAPI is never reached; Nginx blocks first)
[INV-01-FULLSTACK-B] Request with Basic Auth but deliberate wrong X-API-Key header
  (simulate a non-browser caller): GET /api/risk/CUST001 via Nginx with
  -u user:pass -H "X-API-Key: wrong-key"
  Expected: HTTP 401 from FastAPI (Nginx injects its key, but the explicit header
  from the caller may override — test and document whichever behaviour occurs)
[INV-01-FULLSTACK-C] Request via Nginx with Basic Auth, no explicit X-API-Key → HTTP 200
  (Nginx injects the key; FastAPI accepts it)
[INV-02-FULLSTACK-A] Full response headers of a 200 response via Nginx do not contain
  the API_KEY value
[INV-02-FULLSTACK-B] Full response body of a 200 response does not contain API_KEY value
[INV-02-FULLSTACK-C] Nginx access logs after all requests do not contain API_KEY value
[INV-02-FULLSTACK-D] FastAPI logs after all requests do not contain API_KEY value

Read API_KEY, BASIC_AUTH_USER, BASIC_AUTH_PASSWORD from .env.
Teardown: docker compose down -v. Make executable.
```

**Test cases:** As per script checks. Note: INV-01-FULLSTACK-B tests and documents the
header precedence behaviour between caller and Nginx injection — the correct outcome
depends on Nginx's `proxy_set_header` override behaviour.

**Verification command:**
```bash
chmod +x verify/s7_invariants_auth.sh && bash verify/s7_invariants_auth.sh
```

**Touches invariant:** `INV-01`, `INV-02`.

**Code review checklist (INV-01, INV-02):**
- INV-01-FULLSTACK-B should result in HTTP 401 if Nginx's `proxy_set_header` *replaces* an existing header (which is the default Nginx behaviour). If it appends, FastAPI sees two `X-API-Key` headers, and behaviour is implementation-dependent. Confirm in code review which behaviour the Nginx version exhibits and document it.
- INV-02-FULLSTACK-C and D both use `docker compose logs` with `--no-log-prefix` to get clean log lines for grepping.

---

### S7-T4 — Invariant verification suite: INV-04, INV-06, INV-07, INV-08, INV-09

**Description:**  
Input: running full stack. Output: `verify/s7_invariants_schema.sh` — all data invariants
verified through a combination of direct DB queries and API response assertions.

**Prompt for Claude Code:**
```
Create verify/s7_invariants_schema.sh.

Setup: docker compose up -d, wait for healthy.

Run all of the following checks via docker compose exec postgres psql:

[INV-06-DB] SELECT COUNT(*) FROM customers WHERE tier NOT IN ('LOW','MEDIUM','HIGH');
  Expected: 0

[INV-07-DB] SELECT COUNT(*) FROM customers c
  WHERE NOT EXISTS (SELECT 1 FROM risk_factors r WHERE r.customer_id = c.customer_id);
  Expected: 0

[INV-08-DB] SELECT COUNT(*) FROM risk_factors rf
  LEFT JOIN customers c ON rf.customer_id = c.customer_id
  WHERE c.customer_id IS NULL;
  Expected: 0

[INV-09-DB] SELECT COUNT(*) FROM (
  SELECT customer_id FROM customers GROUP BY customer_id HAVING COUNT(*) > 1
) dupes;
  Expected: 0

Then run API-layer checks for all 9 seed customers (loop over known IDs):

[INV-04-API] For each seed customer_id:
  GET /api/risk/<customer_id> via Nginx with Basic Auth
  Assert response.customer_id == request customer_id
  Assert response.tier in {LOW, MEDIUM, HIGH}
  Assert len(response.risk_factors) > 0

[INV-06-API] Assert response.tier for every customer is in {LOW, MEDIUM, HIGH}
[INV-07-API] Assert response.risk_factors is non-empty for every customer

Teardown: docker compose down -v. Print pass/fail per invariant. Make executable.
```

**Test cases:** All checks enumerated above for all 9 seed customers.

**Verification command:**
```bash
chmod +x verify/s7_invariants_schema.sh && bash verify/s7_invariants_schema.sh
```

**Touches invariant:** `INV-04`, `INV-06`, `INV-07`, `INV-08`, `INV-09`.

**Code review checklist (INV-04, INV-06, INV-07, INV-08, INV-09):**
- INV-04 check iterates all 9 known seed IDs — if seed data changes, this list must be updated.
- INV-07 is checked both at the DB layer (no customer with zero factor rows) and API layer (no empty array in response).

---

### S7-T5 — Master verification script and README completion

**Description:**  
Input: all `verify/s*.sh` scripts. Output: `verify/run_all.sh` — a master script that
runs all verification scripts in order, produces a summary report, and exits 0 only if
every script passes. Also completes `README.md` with setup instructions.

**Prompt for Claude Code:**
```
Create verify/run_all.sh. This is the single command to run after `docker compose up`
to verify the entire system.

The script should:
1. Run each of the following scripts in order and capture the exit code of each:
     verify/s2_db.sh
     verify/s3_auth.sh
     verify/s4_api.sh
     verify/s5_nginx.sh
     verify/s5_isolation.sh
     verify/s6_ui.sh
     verify/s7_coldstart.sh
     verify/s7_invariants_data.sh
     verify/s7_invariants_auth.sh
     verify/s7_invariants_schema.sh
2. After all scripts run, print a summary table:
     Script              | Result
     verify/s2_db.sh     | PASS
     verify/s3_auth.sh   | PASS
     ...
3. Print overall PASS if all exit 0, FAIL with list of failed scripts otherwise.
4. Exit 0 on overall PASS, 1 on any failure.
Make executable.

Also update README.md to include:
  ## Prerequisites
  - Docker >= 24.0
  - Docker Compose v2 (docker compose, not docker-compose)

  ## Setup
  cp .env.example .env
  # Edit .env and set real values for all 5 variables

  ## Start
  docker compose up --build

  ## Verify
  bash verify/run_all.sh

  ## Stop
  docker compose down -v
```

**Test cases:**

| Scenario | Expected outcome |
|---|---|
| All verify scripts pass | Master script exits 0, summary shows all PASS |
| One verify script fails | Master script exits 1, summary identifies which |

**Verification command:**
```bash
chmod +x verify/run_all.sh && bash verify/run_all.sh
```

**Touches invariant:** All invariants (master integration check).

**Code review checklist (all):**
- Each sub-script performs its own `docker compose up` / `down` — or the master script manages a single up/down and sub-scripts reuse the running stack. Choose one pattern; mixed behaviour will cause failures. Recommend: master script starts the stack once, sub-scripts assume it is running, master script tears down at the end.

---

## Appendix: invariant-to-task coverage matrix

| Invariant | First enforcement | Verification |
|---|---|---|
| INV-01 | S3-T2 (FastAPI auth dependency) | S3-T3, S7-T3 |
| INV-02 | S3-T2 (no log), S5-T1 (Nginx config) | S3-T3, S5-T3, S6-T3, S7-T3 |
| INV-03 | S1-T2 (compose depends_on), S4-T1 (retry loop) | S7-T1 |
| INV-04 | S4-T2 (response from DB row) | S4-T3, S7-T4 |
| INV-05 | S4-T2 (SELECT only), S2-T3 (writes in init only) | S4-T3, S7-T2 |
| INV-06 | S2-T1 (CHECK constraint), S4-T2 (Pydantic Literal) | S2-T4, S7-T4 |
| INV-07 | S4-T2 (empty-factors check) | S2-T4, S7-T4 |
| INV-08 | S2-T1 (FOREIGN KEY constraint) | S2-T4, S7-T4 |
| INV-09 | S2-T1 (PRIMARY KEY) | S2-T4, S7-T4 |
| INV-10 | S4-T2 (no cache) | S7-T2 |
