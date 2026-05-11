# ARCHITECTURE.md

**System:** Customer Risk API  
**Architecture:** Candidate C — Nginx reverse proxy with operator-mediated key injection  
**Version:** 1.0  
**Classification:** Training Demo System

---

## 1. Problem framing

### What this system solves

Internal operations staff at a financial services client need to query customer risk tier
information — the tier classification (LOW / MEDIUM / HIGH) and the factors that drove it —
without requiring direct database access or analyst intermediation. The current path to this
data is ad-hoc SQL against Postgres, which bypasses access controls, has no audit trail, and
requires SQL literacy. This system replaces that with a controlled, authenticated HTTP interface
that exposes exactly the data consumers need, nothing more.

The specific access problem this architecture addresses is the API key exposure risk inherent in
browser-based clients: because the browser is the primary consumer, and because the brief mandates
API key authentication on all endpoints, a naive implementation would either embed the key in a
JavaScript bundle or require users to enter it manually. This architecture eliminates both failure
modes by ensuring the API key never travels to the browser at all.

### What this system explicitly does not solve

- **Risk computation.** The database holds pre-assessed values. This system is a read interface
  over existing data, not a risk engine. No scoring logic lives here.
- **User management or role-based access.** There is one API key. There are no per-user
  identities, no roles, and no fine-grained permissions.
- **Write or update operations.** The system is strictly read-only. There are no endpoints that
  modify risk data.
- **Production hardening.** TLS termination, secrets management at scale, rate limiting, and
  high-availability configuration are out of scope. This is an internal ops tool, not a
  production SaaS surface.
- **Programmatic consumer consistency.** Downstream tools that call the API directly (not via the
  browser UI) must hold the API key separately and pass it themselves. The key injection mechanism
  is a browser-layer concern only.

---

## 2. Five key design decisions

---

### Decision 1 — Nginx injects the API key as a proxy header; the browser never receives it

**What was decided:**  
The API key lives exclusively in the `.env` file and is loaded into the Nginx container as an
environment variable. When the browser submits a request to `/api/*`, Nginx intercepts it, appends
`X-API-Key: <value>` via `proxy_set_header`, and forwards the enriched request to FastAPI. The
JavaScript in the browser makes a plain fetch with no key in the request. FastAPI validates the
header on every inbound request. The browser has no knowledge of the key's value at any point in
the request lifecycle.

**Rationale:**  
Any architecture that serves the API key to the browser creates an exfiltration surface. A
`/config.js` endpoint (Candidate A) can be called by anyone who reaches port 80. A key embedded
in a JS bundle is readable in DevTools. A user-entered key ends up on shared notes. The only way
to genuinely satisfy the implied constraint — that the key should not be trivially extractable from
a browser client — is to ensure it never arrives there. Nginx's `proxy_set_header` is a
single-line config change that achieves this with no application code involvement.

**Alternatives rejected:**

- *Serve key via `/config.js` (Candidate A approach):* The endpoint is unauthenticated by
  necessity — the browser needs the key before it can authenticate. Anyone on the same network can
  retrieve it with a plain HTTP request. Rejected as it does not meaningfully protect the key.
- *Embed key in served HTML at build time:* Bakes a secret into a static artifact. Key rotation
  requires a rebuild and redeploy. Visible in browser source. Rejected unconditionally.
- *User enters key manually per session:* Acceptable in theory; unacceptable in practice. A
  shared key entered by hand will be written down, shared over chat, or stored in browser
  autofill within days. Transfers an architectural problem into a human process problem with
  worse outcomes. Rejected.

---

### Decision 2 — Nginx enforces HTTP Basic Auth as a gate in front of the entire UI

**What was decided:**  
Nginx requires HTTP Basic Auth credentials before serving any content on port 80, including the
static UI page. Credentials (username and password) are stored in a `htpasswd`-formatted value,
generated automatically by the Nginx container entrypoint from environment variables in `.env`.
No static `htpasswd` file is checked into source. This creates two distinct authentication
layers: Basic Auth (Nginx) for UI access, API key (FastAPI) for data access.

**Rationale:**  
If Nginx injects the API key into all proxied requests, and the browser never receives the key,
then the Nginx layer itself becomes the access gate. Without a credential requirement at the Nginx
level, any unauthenticated user who can reach port 80 can load the UI and query risk data —
because the API key will be silently added by Nginx on their behalf. Basic Auth is the simplest
mechanism that restricts who can load the UI to credentialed staff, without introducing user
management infrastructure that is explicitly out of scope.

**Alternatives rejected:**

- *No UI-layer authentication (rely on API key only):* If Nginx injects the key, the key
  provides no protection for unauthenticated browser sessions — Nginx adds it regardless of who
  is making the request. Without a UI gate, anyone on the internal network can query any
  customer's risk profile. Rejected as it undermines the access control objective entirely.
- *Session-based authentication in FastAPI:* Requires login endpoints, session storage, and
  cookie management — none of which are in the stack spec and all of which constitute user
  management infrastructure. Rejected as out of scope and disproportionate to the problem.
- *IP allowlisting at Nginx:* Restricts access to known IP ranges rather than named credentials.
  Brittle (IP ranges change), provides no audit trail of which individual accessed what, and
  offers no credential to revoke if access needs to be withdrawn from a specific person. Rejected
  as insufficiently granular.

---

### Decision 3 — A dedicated db-init container runs schema creation and seed data load, then exits

**What was decided:**  
Database initialisation (schema DDL and seed data INSERT statements) is handled by a separate
`db-init` container that runs a Python script against Postgres, waits for completion, and then
exits with code 0. Docker Compose's `depends_on` with a `service_completed_successfully`
condition ensures FastAPI does not start until db-init has finished. The Postgres container uses
a named volume so data persists across restarts. The init script is idempotent: it uses
`CREATE TABLE IF NOT EXISTS` and `INSERT ... ON CONFLICT DO NOTHING` so re-running it against
an already-populated database is safe.

**Rationale:**  
The brief requires the system to start from a cold `docker compose up` with no manual steps.
That means schema creation and seed data must be automated. Encoding this in Postgres's
`/docker-entrypoint-initdb.d/` convention only runs on first initialisation of the data volume —
it does not re-run on subsequent `compose up` calls, which makes it unsuitable for environments
where volumes may be recreated. A dedicated init container that is always idempotent handles
both the first-run and subsequent-run cases correctly, and makes the initialisation logic
explicit and testable independently of the Postgres image.

**Alternatives rejected:**

- *Postgres `initdb.d` scripts:* Only run on first-time volume initialisation. If a volume is
  torn down and recreated, they re-run and may fail on conflict. If a volume persists but the
  schema changes, they do not re-run at all. The behaviour is volume-state-dependent in ways
  that are not obvious to operators. Rejected in favour of explicit idempotent init.
- *FastAPI runs migrations on startup:* Mixes initialisation logic into the application layer.
  Startup time increases, and a failed migration can prevent the API from starting even if the
  schema is already correct. Rejected as it couples two concerns that should be independent.
- *Manual seed via psql:* Constitutes a manual setup step. Rejected unconditionally by the
  stated constraints.

---

### Decision 4 — FastAPI uses psycopg2 with parameterized queries exclusively; no ORM, no query builder

**What was decided:**  
All database access goes through psycopg2 with `%s`-style parameterized queries. No ORM
(SQLAlchemy, Tortoise, etc.) and no query builder (aiopg, databases, etc.) is used. A single
connection is opened at application startup via FastAPI's lifespan context manager, with a
retry loop that handles the Postgres readiness race. The connection is reused across requests.
All query parameters — including `customer_id` — are passed as parameterized arguments, never
interpolated into query strings.

**Rationale:**  
The brief specifies psycopg2 with no ORM as a fixed stack constraint. Beyond compliance,
parameterized queries are the only acceptable mitigation for SQL injection in a raw-SQL
context, and they must be applied to every query without exception. A single startup connection
with retry is appropriate for a low-concurrency internal tool: connection pooling adds complexity
with no benefit at the expected load. The retry loop at startup is necessary because Docker
Compose does not guarantee that Postgres is accepting connections when the FastAPI container
starts, even with `depends_on` on the db-init container.

**Alternatives rejected:**

- *Connection pool (psycopg2 pool or pgbouncer):* Appropriate for high-concurrency workloads.
  This is an internal ops tool used by a small number of staff. A pool adds configuration
  surface and failure modes (pool exhaustion, stale connections) with no material benefit.
  Rejected as over-engineering for the stated use case.
- *String interpolation for customer_id:* `f"SELECT ... WHERE customer_id = '{cid}'"` is a
  textbook SQL injection vector. Rejected unconditionally regardless of input validation
  elsewhere.
- *ORM (SQLAlchemy):* Violates the fixed stack constraint. Also adds a schema declaration
  layer that duplicates the database schema in Python — unnecessary for a read-only system with
  a small, stable schema. Rejected on both grounds.

---

### Decision 5 — All secrets flow through a single `.env` file; nothing is hardcoded or built into images

**What was decided:**  
Three secrets are required: the API key (used by Nginx for header injection and by FastAPI for
validation), the Basic Auth credentials (used by Nginx), and the Postgres password (used by both
Postgres and FastAPI). All three are defined in a single `.env` file at the project root, loaded
by Docker Compose via `env_file` directives, and accessed inside containers as environment
variables. A `.env.example` file with placeholder values is checked into source so operators
know exactly what to provide. The `.env` file itself is in `.gitignore`. No secret value appears
anywhere in source code, Dockerfiles, or `docker-compose.yml`.

**Rationale:**  
The brief specifies that setup requires only providing an `.env` file — this is both the
operator interface for secrets and the boundary of what may be hardcoded. Secrets in source or
image layers are immutable until a rebuild and create permanent exposure if the repository is
ever made non-private. Environment variables are the standard mechanism for container secret
injection at this scale. Centralising all secrets in one file reduces the cognitive load on
operators: there is exactly one place to look and one file to protect.

**Alternatives rejected:**

- *Hardcode secrets in `docker-compose.yml` or application code:* Creates permanent exposure
  in source history. Rotation requires a code change and redeploy. Rejected unconditionally.
- *Separate `.env` files per service:* Distributes secrets across multiple files, increasing
  the risk of inconsistency (e.g. API key in Nginx `.env` out of sync with FastAPI `.env`) and
  making rotation more error-prone. Rejected in favour of a single source of truth.
- *Docker secrets (swarm mode):* Appropriate for production multi-node deployments. Requires
  Docker Swarm, which is not part of the specified stack, and adds significant operational
  overhead for a single-node compose deployment. Rejected as disproportionate.

---

## 3. Challenge my decisions

---

### Challenge 1 — Does Nginx key injection actually solve the exposure problem, or just move it?

**Strongest argument against:**  
Nginx injecting the API key protects against a browser-side attacker — someone who opens
DevTools and inspects network traffic. But it does nothing against a server-side attacker. If
the Nginx container is compromised, the API key is readable in its environment variables. More
practically: the same protection could be achieved more simply by making the API key irrelevant
for browser-originated requests — for example, by scoping the API key check to non-UI origins
only. The injection approach adds Nginx configuration complexity while only partially solving
the underlying access control problem.

**Assessment: Partially valid, but not a reason to reject the decision.**  
The challenge correctly identifies that environment variable injection is not an HSM. However,
the threat model for this system is internal operations tooling, not an adversarial
environment. The key injection solves the specific, concrete failure modes identified in the
analysis: keys in DevTools, keys in JS bundles, keys on sticky notes. A compromised container
is outside the threat model of a system explicitly classified as not production-hardened. The
simpler counter-proposal (scope key check to non-UI origins) would require application code
changes and origin validation logic that introduces its own failure modes. The challenge is
noted but does not warrant a design change within the stated scope.

---

### Challenge 2 — Basic Auth is too blunt; it will frustrate legitimate ops staff

**Strongest argument against:**  
HTTP Basic Auth presents a browser credential prompt on first visit and re-prompts on
credential expiry or cache clearance. There is no logout, no "remember me," and no graceful
session expiry. For ops staff who use the tool frequently, this is friction without benefit —
particularly because Basic Auth credentials are shared team-wide (there is one username and
password, not per-user credentials), meaning the audit trail it creates is at the team level,
not the individual level. You get the UX cost of authentication without the audit benefit of
per-user identity.

**Assessment: Valid as a limitation; not a reason to reject the decision.**  
The challenge is accurate. Basic Auth with shared credentials does not provide individual
accountability. However, the brief explicitly excludes user management and per-user identity.
Within those constraints, Basic Auth is the lightest mechanism available that gates UI access
without adding user management infrastructure. The audit trail at the Nginx layer (IP address,
timestamp, path) is still meaningful even without individual identity. The friction is real but
proportionate to a low-frequency internal tool. If per-user audit becomes a requirement, the
correct response is to promote the system to a user-managed auth layer — not to paper over the
gap with a more complex workaround at this tier.

---

### Challenge 3 — A dedicated db-init container is over-engineering for a seed data problem

**Strongest argument against:**  
The Postgres official image already provides an `initdb.d` mechanism specifically for this
use case: drop a `.sql` file in `/docker-entrypoint-initdb.d/` and it runs automatically on
first volume initialisation. This is well-documented, requires no extra container, no extra
image, no Python script, and no `depends_on` sequencing complexity. The idempotency argument
for the dedicated container is solved equally well by writing idempotent SQL (`IF NOT EXISTS`,
`ON CONFLICT DO NOTHING`). A separate container adds a moving part that can fail, adds an
image to maintain, and solves a problem that the database image already solves natively.

**Assessment: Valid challenge. The decision should be revisited.**  
The strongest counter-argument — that `initdb.d` only runs on first volume initialisation and
not on subsequent restarts — is real, but its practical impact depends on operator behaviour.
If operators never destroy the volume, `initdb.d` is sufficient. If volumes are routinely
recreated (e.g. in a CI/test context), the idempotent init container is genuinely safer. The
right resolution is to document the volume behaviour explicitly and default to the `initdb.d`
approach for simplicity, with the dedicated container as an optional hardening step. This
decision is flagged for revisiting during implementation.

---

### Challenge 4 — A single psycopg2 connection is a latent reliability failure

**Strongest argument against:**  
A single database connection opened at startup and reused indefinitely will silently die if
Postgres is restarted, the connection is killed by a timeout, or the network briefly interrupts.
FastAPI will continue accepting requests, but every database call will fail until the application
is restarted. There is no reconnection logic in a basic psycopg2 connection — you have to build
it yourself. At least a minimal connection pool (even `psycopg2.pool.SimpleConnectionPool` with
min=1, max=2) handles reconnection and provides a second connection for overlapping requests
without significant complexity overhead.

**Assessment: Valid. The implementation must include connection health checking or a minimal pool.**  
The challenge is correct that a bare `psycopg2` connection without any resilience logic is a
reliability risk even for an internal tool. The resolution is not necessarily a full pool: a
`ping` check (or `SELECT 1`) before each query, with reconnection on failure, is sufficient for
the load profile. Alternatively, `psycopg2.pool.SimpleConnectionPool(minconn=1, maxconn=3)` is
four lines of code and handles both reconnection and minimal concurrency. This must be addressed
in implementation; it is not a reason to change the architectural decision about psycopg2 vs
an ORM, but it is a requirement on how psycopg2 is used.

---

### Challenge 5 — A single `.env` file for all secrets is a single point of compromise

**Strongest argument against:**  
Putting all three secrets (API key, Basic Auth credentials, Postgres password) in one file
means that anyone who can read `.env` has full access to every credential in the system.
Separating secrets by service (Nginx gets only Basic Auth and API key; FastAPI gets only API
key and Postgres password; Postgres gets only its own password) limits blast radius if one
service's environment is read by an attacker. A single file is convenient but violates the
principle of least privilege at the secret distribution layer.

**Assessment: Theoretically valid; rejected as disproportionate within the stated scope.**  
The principle of least privilege argument is sound in a production context. However, the brief
explicitly calls out that secrets management at scale is out of scope, and this system runs on
a single host where a process that can read one container's environment variables can almost
certainly read another's. The threat model does not support the added operational complexity of
per-service secret scoping, which would also make rotation more error-prone (three files to
update instead of one). The single `.env` file with a well-protected `.gitignore` is the
correct trade-off within the stated constraints. Revisit if the system ever moves toward a
shared hosting or multi-tenant environment.

---

## 4. Key risks

**Risk 1 — Basic Auth credential sharing erodes the access control intent.**  
If the Basic Auth username and password are shared across the whole ops team as a single
credential pair, they will circulate informally (Slack messages, shared docs, written down).
There is no revocation mechanism short of rotating the password for everyone. The risk is not
that someone unauthorised gains access — the system is internal — but that the access control
becomes unauditable and un-revocable in practice. Mitigation: document clearly that Basic Auth
credentials are team-scoped, treat them as a network-level gate rather than individual
accountability, and ensure the API key (which is not visible to UI users) remains the actual
secret worth protecting.

**Risk 2 — Nginx `proxy_set_header` silently fails if misconfigured.**  
If the `proxy_set_header X-API-Key` directive is missing from the Nginx location block, every
API request from the browser will be rejected with 401 by FastAPI. There is no warning from
Nginx — it simply does not add the header. The failure mode looks to the end user identical to
a wrong API key, and to a developer is not immediately obvious without reading both the Nginx
config and FastAPI logs together. Mitigation: include a health check endpoint in FastAPI that
the Nginx config calls during startup, so a misconfigured header injection fails fast rather
than silently at runtime.

**Risk 3 — Named Postgres volume persists stale schema across significant version changes.**  
If the database schema evolves (e.g. a risk factors column is renamed) and the Postgres volume
is not destroyed before `compose up`, the old schema will still be in place and the init script
will not update it (idempotency prevents re-running existing DDL). The API may start without
error but return incorrect or incomplete data. Mitigation: document explicitly that schema
changes require `docker compose down -v` to destroy and recreate the volume, and treat the
seed data as disposable demo data rather than persistent state.

**Risk 4 — `htpasswd` generation failure blocks all access silently.**  
The Nginx container entrypoint generates the `htpasswd` file from environment variables at
startup. If the environment variables are missing or malformed, the generated file will be
empty or invalid, and Nginx will either reject all requests or fail to start. Depending on how
the entrypoint handles the error, this may not surface a clear error message. Mitigation:
validate that `BASIC_AUTH_USER` and `BASIC_AUTH_PASSWORD` are non-empty in the entrypoint
script before calling `htpasswd`, and exit with a descriptive error if either is absent.

---

## 5. Key assumptions

- **The browser is the primary, and effectively the only, consumer of the UI path.** The
  architecture's key injection mechanism is designed for browser-based access. Downstream tools
  that call the API programmatically must hold and pass the API key themselves; they do not
  benefit from Nginx injection.

- **All consumers are on a trusted internal network.** Port 80 is not exposed to the public
  internet. The absence of TLS is acceptable because traffic does not leave the internal network.
  If this assumption is false, the entire auth model needs revisiting.

- **A single shared API key is sufficient for the access control requirement.** There is no
  per-consumer key management. All authorised callers use the same key. If the brief's intent
  was per-consumer keys (e.g. different keys for the UI vs downstream tools), the architecture
  requires extension.

- **`customer_id` is a stable, queryable identifier of known format.** The brief does not
  specify the type or format of `customer_id`. The implementation assumes it can be indexed
  effectively in Postgres (integer or short string), that it uniquely identifies a customer, and
  that a well-formed vs malformed request distinction (400 vs 404) can be made at validation time.

- **The seed data is static and representative for the lifetime of this system.** No tooling for
  updating or rotating seed records is provided. If the demo dataset needs to change, it requires
  a code change to the init script and a volume rebuild.

- **Docker Compose v2 syntax is available.** The `depends_on` `service_completed_successfully`
  condition used for db-init sequencing requires Compose v2. Compose v1 (`docker-compose`)
  does not support this condition and would require a workaround.

---

## 6. Open questions

**Q1 — What is the `customer_id` format and type?**  
Is it an integer, a UUID, a short alphanumeric code? This drives column type, index strategy,
URL parameter validation, and the distinction between a 400 (malformed request) and a 404 (valid
format, no record found). Without this, the API cannot perform meaningful input validation.

**Q2 — What is the structure of a risk factor?**  
The brief says to return "the list of risk factors that contributed to that tier" but does not
define what a risk factor looks like. Is it a free-text label? A structured object with a code,
description, and weight? This drives the schema of the `risk_factors` table and the shape of
the JSON response. The response contract cannot be finalised without this.

**Q3 — Who holds the Basic Auth credentials, and how are they distributed to ops staff?**  
There is one username and password for the whole team. Is there a documented process for how
these credentials are communicated to new staff, and what happens when staff leave? Without
this, the access control degrades quickly in practice.

**Q4 — Are downstream programmatic callers anticipated?**  
If other internal tools or pipelines need to query the API directly (not via the browser UI),
they must hold the API key and pass it themselves — Nginx injection is a browser-only path. This
is architecturally inconsistent and should be documented as a known constraint. If programmatic
access is a first-class requirement, the key injection approach needs reconsideration.

**Q5 — What is the expected behaviour on a malformed `customer_id`?**  
The brief specifies 404 for not-found and 401 for unauthenticated. It does not specify 400 for
malformed input. Should a non-existent but syntactically valid ID return 404? Should a
syntactically invalid ID (e.g. a string where an integer is expected) return 400 or 404? The
response contract for the error path needs to be consistent and agreed before implementation.

**Q6 — Should the volume be ephemeral or persistent by default?**  
The init script is idempotent, but schema evolution requires volume destruction. Should the
`docker-compose.yml` default to a named persistent volume (safer for operators who restart
frequently) or an anonymous ephemeral volume (safer for developers who iterate on the schema)?
This should be an explicit choice documented in the README, not an implicit default.
