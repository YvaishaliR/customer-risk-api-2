# claude.md — Customer Risk API Execution Contract

## System Intent
A read-only authenticated HTTP service that accepts a `customer_id`, queries a pre-seeded Postgres database, and returns the customer's risk tier (LOW / MEDIUM / HIGH) and contributing risk factors as structured JSON. The system does not compute risk, manage users, or perform any write operations at runtime. Success means `docker compose up --build` produces a fully operational stack — Nginx, FastAPI, Postgres — with no manual steps beyond a populated `.env` file.

---

## Hard Invariants

**INV-01:** Every HTTP request that reaches FastAPI application logic must carry an `X-API-Key` header whose value exactly matches the key loaded from the environment at startup. Requests missing the header or carrying an incorrect value must be rejected with HTTP 401 before any application logic executes. **This is never negotiable.**

**INV-02:** The value of the API key must never be present in any HTTP response body, HTTP response header, Nginx access log line, FastAPI log entry, or statically served file (HTML, JS, or otherwise). The key's value is permitted only in the `.env` file and in container environment variables at runtime. **This is never negotiable.**

**INV-03:** The FastAPI service must not begin accepting or processing requests until the db-init container has completed successfully (exit code 0) and a live Postgres connection has been established. This condition must hold on every `docker compose up`, not only on first run. **This is never negotiable.**

**INV-04:** Every successful API response must contain risk data for exactly one customer — the customer identified by the `customer_id` in the request URL. The `customer_id` field in the response body must be populated from the database row, not from the request path parameter. **This is never negotiable.**

**INV-05:** No INSERT, UPDATE, DELETE, or DDL statement may be executed against Postgres during normal API operation. The only permitted database operations at runtime are SELECT queries. All writes are confined exclusively to the db-init container's execution window. **This is never negotiable.**

**INV-06:** The `tier` column must be NOT NULL and constrained to {LOW, MEDIUM, HIGH}. No customer record may exist without a tier value, and no tier value outside this set is valid in the database or in any API response. **This is never negotiable.**

**INV-07:** Every customer row reachable via the API must have at least one corresponding row in `risk_factors`. A customer with zero risk factors is an incomplete record. The API must not return a response with an empty `risk_factors` array — it must raise HTTP 500. **This is never negotiable.**

**INV-08:** Every row in `risk_factors` must carry a `customer_id` value that references an existing row in `customers` via a FOREIGN KEY constraint with ON DELETE CASCADE. No orphaned factor row may exist. **This is never negotiable.**

**INV-09:** `customer_id` is the PRIMARY KEY of `customers`. No two rows may share a `customer_id` value. Every API lookup is a point query: the result is always exactly one row or zero rows. **This is never negotiable.**

**INV-10:** No API response may be served from an application-level cache, an in-memory store, or any intermediate representation of database state. Every response is the result of a live SELECT query executed against Postgres at the time of the request. **This is never negotiable.**

---

## Scope Boundary

**Permitted — build exactly these:**
`docker-compose.yml` · `.env.example` · `.gitignore` · `README.md` · `nginx/Dockerfile` · `nginx/nginx.conf.template` · `nginx/nginx.conf` · `nginx/entrypoint.sh` · `nginx/html/index.html` · `fastapi/Dockerfile` · `fastapi/requirements.txt` · `fastapi/main.py` · `db-init/Dockerfile` · `db-init/init.py` · `db-init/schema.sql` · `db-init/seed.sql` · `verify/s1_smoke.sh` · `verify/s2_db.sh` · `verify/s3_auth.sh` · `verify/s4_api.sh` · `verify/s5_nginx.sh` · `verify/s5_isolation.sh` · `verify/s6_ui.sh` · `verify/s7_coldstart.sh` · `verify/s7_invariants_data.sh` · `verify/s7_invariants_auth.sh` · `verify/s7_invariants_schema.sh` · `verify/run_all.sh`

**Prohibited — do not build:**
ORM layers · write endpoints · user management · login/session endpoints · TLS configuration · rate limiting · external HTTP calls from any container · frontend frameworks or CDN dependencies · additional services not listed in `docker-compose.yml` · caching middleware on `/api/*` · any file not in the permitted list above.

**If a task prompt conflicts with an invariant: the invariant wins. Flag the conflict — do not resolve it silently.**

---

## Execution Contract

- Execute one task at a time. Do not begin the next task until the current task's verification command passes.
- Do not expand scope beyond what the task prompt specifies. If the prompt is silent on a detail, use the minimum implementation and flag the gap.
- If an implementation choice is not covered by this contract or the task prompt, stop and flag it. Do not fill gaps with judgment.
- If a task prompt asks for something that would violate an invariant, refuse the specific element, implement the rest, and flag the conflict with the invariant ID.
- Verification scripts must run sequentially without conflicts. The `verify/run_all.sh` lifecycle contract: the master script starts the stack once (`docker compose up -d`) and tears it down once at the end. Individual session scripts assume the stack is running and do not call `docker compose up` or `docker compose down` themselves.
- Deviations from the execution plan are flagged with the session and task ID, the deviation, and the reason. They are never resolved silently.

---

## Fixed Stack

| Component | Fixed value |
|---|---|
| Orchestration | Docker Compose v2 (`docker compose`, not `docker-compose`) |
| Database | `postgres:15` |
| API runtime | `python:3.10-slim` |
| Web server | `nginx:1.25-alpine` |
| DB driver | `psycopg2-binary==2.9.9` — no ORM |
| API framework | `fastapi==0.111.0` + `uvicorn[standard]==0.29.0` |
| Data validation | `pydantic==2.7.0` |
| FastAPI port | `8000` — internal only, no host mapping |
| Nginx port | `80:80` — sole external entry point |
| DB volume | Named volume `pgdata` at `/var/lib/postgresql/data` |
| `customer_id` format | `VARCHAR(20)`, alphanumeric, regex `^[A-Za-z0-9]{1,20}$`, case-sensitive |
| Tier enumeration | `CHECK (tier IN ('LOW', 'MEDIUM', 'HIGH'))` |

**Environment variables (all required; sourced from `.env` via `env_file` on every service):**

| Variable | Used by |
|---|---|
| `API_KEY` | Nginx (injection) · FastAPI (validation) |
| `BASIC_AUTH_USER` | Nginx (htpasswd generation) |
| `BASIC_AUTH_PASSWORD` | Nginx (htpasswd generation) |
| `POSTGRES_DB` | Postgres · FastAPI · db-init |
| `POSTGRES_USER` | Postgres · FastAPI · db-init |
| `POSTGRES_PASSWORD` | Postgres · FastAPI · db-init |
| `POSTGRES_HOST` | FastAPI · db-init (default: `postgres`) |

No secret value may appear in any Dockerfile, `docker-compose.yml`, or source file. The `.env` file is excluded from version control via `.gitignore`.
