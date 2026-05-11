# INVARIANTS.md

**System:** Customer Risk API  
**Architecture:** Candidate C — Nginx reverse proxy with operator-mediated key injection  
**Version:** 1.0  
**Classification:** Training Demo System

---

## How to read this document

Each invariant is a condition that must always be true while the system is operating correctly.
Invariants are not implementation tasks — they are the constraints that implementation tasks
must satisfy. When an invariant is violated, the system is in a broken state regardless of
whether any error has been raised.

**Authorship key:**
- `CD-drafted (confirmed by engineer)` — derived by analysis from ARCHITECTURE.md and the
  data model; must be explicitly confirmed or rejected by the engineer before implementation begins.
- `Engineer-authored` — provided by the engineer as a domain rule not visible in architecture
  or schema; recorded here verbatim after challenge.

**Scope key:**
- `GLOBAL` — must hold for the entire lifetime of the running system.
- `TASK-SCOPED` — must hold only within a specific operation window (e.g. startup, init run).

---

## Structural invariants

Derived from architecture decisions: data flow rules, component boundaries, and state
mutation constraints.

---

### INV-01: Every request processed by FastAPI must carry a valid API key

- **INV-01:** Every HTTP request that reaches FastAPI application logic must carry an
  `X-API-Key` header whose value exactly matches the key loaded from the environment
  at startup. Requests missing the header or carrying an incorrect value must be rejected
  with HTTP 401 before any application logic executes.
- **Category:** Structural
- **Scope:** GLOBAL
- **Authorship:** CD-drafted (confirmed by engineer)

**Why this matters:** If the auth check is absent, misconfigured, or skippable, any caller
who can reach FastAPI's port — whether via Nginx or directly — can read any customer's risk
profile without credentials. Because Nginx injects the key on behalf of the browser, FastAPI
is the only layer that can enforce authentication for non-browser callers. Removing or
weakening this check silently opens the entire dataset to unauthenticated access.

**Enforcement points:**
- FastAPI route dependency (`get_api_key` or equivalent) applied to every route handler —
  not just the risk lookup route, but any future route added to the service.
- Verification test: send a request with no header and assert HTTP 401; send a request with
  a wrong key and assert HTTP 401; send a request with the correct key and assert HTTP 200.

**Failure mode:**

- *Violation:* FastAPI returns HTTP 200 to a request carrying no `X-API-Key` header, or
  to a request carrying an incorrect key value.
- *Detection:* Verification test — only detectable by a test that deliberately sends an
  unauthenticated request and asserts a 401 response. Not detectable from normal usage logs
  if the auth dependency is simply absent from a route.
- *Blast radius:* Security exposure. Any network-reachable caller can read any customer's
  risk tier and factors without credentials. The absence of per-user identity means there is
  no audit trail of who accessed what.

---

### INV-02: The API key value must not appear in any system output

- **INV-02:** The value of the API key must never be present in any HTTP response body,
  HTTP response header, Nginx access log line, FastAPI log entry, or statically served
  file (HTML, JS, or otherwise). The key's value is permitted only in the `.env` file
  and in container environment variables at runtime.
- **Category:** Structural
- **Scope:** GLOBAL
- **Authorship:** CD-drafted (confirmed by engineer)

**Why this matters:** The entire security model of this architecture depends on the key
never reaching the browser. If the key appears in a log, a response header, or a served
asset, any party who can read that output gains the key and can bypass Basic Auth entirely
by calling FastAPI directly — without ever loading the UI.

**Enforcement points:**
- FastAPI logging configuration: must not log raw request headers verbatim. Use a log
  filter that redacts the `X-API-Key` header value before writing to stdout.
- FastAPI response construction: no route handler may return the key value in any field.
- Nginx config: `proxy_set_header` injects the key into the upstream request only; it
  must not be added to the downstream response via `add_header`.
- Nginx access log format: must not include the `$http_x_api_key` variable.
- Verification test: call the API with a valid key, capture the full response (headers +
  body) and the log output, assert the key string does not appear in either.

**Failure mode:**

- *Violation:* The API key value appears verbatim in a FastAPI log line (e.g. from
  verbose header logging), in an HTTP response body (e.g. from a debug or echo endpoint),
  in a response header, or in a served HTML/JS file.
- *Detection:* Verification test — a test that makes a request and scrapes response
  bodies, headers, and captured log output for the key string. Not detectable from Nginx
  access logs (which do not log request headers by default) or from normal usage patterns.
- *Blast radius:* Security exposure. Any party who can read logs or response output gains
  the API key and can make authenticated API requests directly, rendering Basic Auth
  irrelevant as an access gate.

---

### INV-03: FastAPI must not accept requests until db-init has exited with code 0

- **INV-03:** The FastAPI service must not begin accepting or processing requests until
  the db-init container has completed successfully (exit code 0) and a live Postgres
  connection has been established. This condition must hold on every `docker compose up`,
  not only on first run.
- **Category:** Structural
- **Scope:** TASK-SCOPED (startup window)
- **Authorship:** CD-drafted (confirmed by engineer)

**Why this matters:** If FastAPI starts before the schema is created or the seed data is
loaded, every request hits a missing table and produces a 500 error. Because Docker Compose
does not guarantee that Postgres is accepting connections when a dependent container starts,
two sequencing mechanisms are required: Compose `depends_on` for container ordering, and a
retry loop inside FastAPI for Postgres readiness. Either mechanism alone is insufficient.

**Enforcement points:**
- `docker-compose.yml`: `fastapi` service declares `depends_on: db-init:
  condition: service_completed_successfully`.
- FastAPI `lifespan` context manager: retry loop that executes `SELECT 1` against Postgres
  on startup, retrying with backoff until success or a timeout, before the ASGI application
  begins accepting connections.
- Verification test: smoke test that queries a known `customer_id` immediately after
  `docker compose up` completes and asserts a valid response (not 500).

**Failure mode:**

- *Violation:* FastAPI starts and accepts requests while the `customers` or `risk_factors`
  tables do not yet exist, producing `psycopg2.errors.UndefinedTable` exceptions that
  surface as HTTP 500 responses.
- *Detection:* Application layer — visible immediately on the first request after a cold
  `compose up` if sequencing is broken. Also detectable by the smoke test above.
- *Blast radius:* Operational failure. All API requests fail until the container is
  restarted manually. Violates the "starts from `docker compose up` with no manual steps"
  constraint stated in the brief.

---

### INV-04: Each API response must contain data for exactly the requested customer and no other

- **INV-04:** Every successful API response must contain risk data for exactly one
  customer — the customer identified by the `customer_id` in the request URL. The response
  must not contain data for any other customer, and no implicit aggregation, wildcard
  expansion, or batch resolution is permitted.
- **Category:** Structural
- **Scope:** GLOBAL
- **Authorship:** CD-drafted (confirmed by engineer)

**Why this matters:** If a query construction error or parameter binding mistake causes the
wrong customer's record to be returned, the ops staff member acts on another customer's risk
profile. There is no error surfaced — the response is structurally valid, the tier is
plausible, and the factors look reasonable. This is a silent wrong answer with no mechanism
for the user to detect it.

**Enforcement points:**
- FastAPI query: parameterized `WHERE customer_id = %s` with the request parameter bound
  directly. No string interpolation.
- FastAPI response construction: the `customer_id` field in the response body must be
  populated from the database row, not from the request parameter — so a mismatch between
  what was queried and what was returned is visible.
- Verification test: assert `response.body.customer_id == request.path.customer_id` for
  every known seed record.

**Failure mode:**

- *Violation:* An API response contains a `customer_id` field value that does not match
  the `customer_id` in the request URL, or contains risk data for more than one customer.
- *Detection:* Verification test — assert response `customer_id` matches request
  `customer_id`. Unlikely to be caught by a user who does not independently know the
  correct tier for a customer.
- *Blast radius:* Incorrect business decision. An ops staff member viewing risk data for
  the wrong customer may take consequential action (escalating a case, clearing a flag,
  updating a workflow) based on another customer's classification. No error is surfaced.

---

### INV-05: The system must produce no database mutations during API operation

- **INV-05:** No INSERT, UPDATE, DELETE, or DDL statement may be executed against the
  Postgres database during normal API operation. The only permitted database operations
  at runtime are SELECT queries. All writes are confined exclusively to the db-init
  container's execution window.
- **Category:** Structural
- **Scope:** GLOBAL
- **Authorship:** CD-drafted (confirmed by engineer)

**Why this matters:** This is a read-only system by specification. Any mutation during API
operation either represents a code error or a security breach (an attacker who has found an
injection path). Because the system uses raw SQL with no ORM, a write operation does not
fail loudly by default — it executes silently. An accidental mutation to risk data could
change a customer's tier or factors with no audit trail and no error raised.

**Enforcement points:**
- FastAPI query layer: all queries are SELECT statements. No route handler constructs or
  executes an INSERT, UPDATE, DELETE, or DDL statement.
- Postgres role (belt-and-suspenders): the database user used by FastAPI at runtime is
  granted SELECT privileges only — not INSERT, UPDATE, DELETE, or DDL. This mechanically
  enforces the invariant even if a code error constructs a write query.
- Verification test: snapshot all table row counts and a checksum of all row values before
  and after a batch of API requests; assert they are identical.

**Failure mode:**

- *Violation:* A row in `customers` or `risk_factors` is modified, inserted, or deleted
  during an API request lifecycle.
- *Detection:* Verification test (row count + checksum snapshot). Not detectable from HTTP
  responses, Nginx logs, or FastAPI logs unless write queries are explicitly logged at
  DEBUG level. Silent in production.
- *Blast radius:* Data corruption. Risk classifications are altered without audit trail or
  intentional act. Because the data drives financial risk decisions, a silent mutation
  could cause a customer to be assessed at an incorrect tier in perpetuity.

---

## Data invariants

Derived from the entity model, column constraints, cardinality rules, and the state space
implied by the tier classification.

---

### INV-06: Every customer record must have a tier value that is a member of {LOW, MEDIUM, HIGH}

- **INV-06:** The `tier` column on the `customers` table must be NOT NULL and constrained
  to the enumerated set {LOW, MEDIUM, HIGH}. No customer record may exist without a tier
  value, and no tier value outside this set is valid in the database or in any API response.
- **Category:** Data
- **Scope:** GLOBAL
- **Authorship:** CD-drafted (confirmed by engineer)

**Why this matters:** The tier value is the primary output of the system — it is the
classification ops staff act on. A NULL tier is meaningless. An out-of-set tier (e.g.
"UNKNOWN", "CRITICAL", "4") is unrecognised by any downstream consumer and represents a
data integrity failure. Because the system does not compute tiers, a bad value can only
originate from a broken init script or a schema without the appropriate constraint.

**Enforcement points:**
- Schema DDL: `tier` column declared as `VARCHAR NOT NULL CHECK (tier IN ('LOW', 'MEDIUM',
  'HIGH'))` or as a Postgres ENUM type with those three values.
- FastAPI response model: if using Pydantic, the `tier` field is typed as a `Literal['LOW',
  'MEDIUM', 'HIGH']` or an Enum — a value outside the set raises a validation error before
  the response is serialised.
- Verification test: assert every seed record's tier is a member of the set; assert the
  API response tier field matches for every queried record.

**Failure mode:**

- *Violation:* The `tier` field in an API response is NULL, an empty string, or a value
  outside {LOW, MEDIUM, HIGH}.
- *Detection:* DB constraint at write time prevents this if the CHECK constraint is present.
  Without the DB constraint, detectable at the application layer (Pydantic validation error)
  or in a verification test. A NULL tier will not raise a Python error by default — it
  serialises silently as `null` in the JSON response.
- *Blast radius:* Incorrect business decision. Ops staff receiving a NULL or unrecognised
  tier cannot act correctly. Downstream systems that branch on tier value will hit an
  unhandled case.

---

### INV-07: Every customer record must have at least one associated risk factor

- **INV-07:** Every customer row that is reachable via the API must have at least one
  corresponding row in the `risk_factors` table. A customer with zero risk factors is an
  incomplete record. The API must not return a response with an empty `risk_factors` array
  for any customer.
- **Category:** Data
- **Scope:** GLOBAL
- **Authorship:** CD-drafted (confirmed by engineer)

**Why this matters:** A tier without supporting factors is unactionable. Ops staff use the
factor list to understand and communicate why a customer is classified at a given tier. An
empty list looks like a valid response — no error is raised, the HTTP status is 200, and
the tier field is populated — but the record is materially incomplete. If the system is used
to communicate risk rationale externally, an empty factors list is a compliance failure.

**Enforcement points:**
- Application layer: FastAPI must check `len(risk_factors) > 0` after fetching the factor
  rows. If the check fails, return HTTP 500 with an internal error (the record is broken,
  not missing — it should not be a 404).
- Verification test: assert every API response for a known seed `customer_id` contains a
  non-empty `risk_factors` array.
- Init script: seed data must include at least one factor row per customer. The idempotent
  insert logic must cover both the customer row and its factors.

  > **Note on DB-level enforcement:** This invariant cannot be enforced by a simple column
  > constraint because it spans two tables. A DEFERRABLE trigger could enforce it, but this
  > is disproportionate for the current schema scale. Application-layer enforcement is the
  > primary mechanism; the init script is the correctness backstop.

**Failure mode:**

- *Violation:* An API response contains a valid `customer_id` and `tier` but an empty
  `risk_factors` array (`[]`).
- *Detection:* Application layer, if FastAPI explicitly checks before returning. Otherwise
  first visible in a verification test (`assert len(response.risk_factors) > 0`) or via a
  user report. Not detectable from Nginx or FastAPI logs.
- *Blast radius:* Incorrect business decision. A tier without factors is unactionable and
  unjustifiable. If the record is used to communicate risk rationale to a third party, an
  empty factors list constitutes an incomplete and potentially misleading disclosure.

---

### INV-08: Every risk factor row must reference an existing customer

- **INV-08:** Every row in the `risk_factors` table must carry a `customer_id` value (or
  equivalent foreign key) that references an existing row in the `customers` table. The
  foreign key is NOT NULL. No orphaned factor row — one with no valid parent customer — may
  exist in the database.
- **Category:** Data
- **Scope:** GLOBAL
- **Authorship:** CD-drafted (confirmed by engineer)

**Why this matters:** An orphaned factor row indicates a broken init script or a schema
migration error. Under normal JOIN query logic, the orphaned row is never returned by the
API, so the violation is silent at the HTTP layer. The harm is schema integrity — if orphaned
rows exist, the init script's correctness cannot be assumed, which undermines confidence in
the entire seed state.

**Enforcement points:**
- Schema DDL: `risk_factors.customer_id` declared as a FOREIGN KEY referencing
  `customers.customer_id`, with ON DELETE CASCADE or ON DELETE RESTRICT.
- Init script: factor rows are inserted only after their parent customer row has been
  committed.
- Verification test: `SELECT COUNT(*) FROM risk_factors rf LEFT JOIN customers c ON
  rf.customer_id = c.customer_id WHERE c.customer_id IS NULL` must return 0 after init
  completes.

**Failure mode:**

- *Violation:* A row exists in `risk_factors` whose `customer_id` value has no
  corresponding row in `customers`.
- *Detection:* DB constraint at write time prevents this if the FOREIGN KEY is declared.
  Without the constraint, detectable only by the verification test above. Not visible in
  API responses (the JOIN excludes orphaned rows) and not visible in logs.
- *Blast radius:* Schema integrity degradation. No direct user-visible impact. However,
  orphaned rows indicate the init script is broken and that other parts of the seed state
  may also be incorrect. Erodes confidence in the dataset as a whole.

---

### INV-09: `customer_id` must uniquely identify exactly one customer record

- **INV-09:** The `customer_id` column in the `customers` table is the primary key. No two
  rows may share a `customer_id` value. Every API lookup is a point query on this key —
  the result is always exactly one row or zero rows. A state where two rows share a
  `customer_id` is a schema violation.
- **Category:** Data
- **Scope:** GLOBAL
- **Authorship:** CD-drafted (confirmed by engineer)

**Why this matters:** The entire API contract is built on the assumption that a
`customer_id` resolves to at most one record. If duplicates exist and the query uses
`fetchone()`, the response reflects whichever row the database returns first — which
is storage-order dependent and non-deterministic. The same `customer_id` can return
different tiers on successive calls. This is the hardest failure mode to debug because
individual responses look valid.

**Enforcement points:**
- Schema DDL: `customer_id` declared as PRIMARY KEY (implies UNIQUE NOT NULL).
- Init script: `INSERT ... ON CONFLICT DO NOTHING` on `customer_id` ensures re-runs do
  not create duplicates.
- Verification test: `SELECT customer_id, COUNT(*) FROM customers GROUP BY customer_id
  HAVING COUNT(*) > 1` must return zero rows after init.

**Failure mode:**

- *Violation:* Two rows in `customers` share the same `customer_id` value. A query for
  that ID returns a non-deterministic result.
- *Detection:* DB PRIMARY KEY constraint at write time prevents this. If the constraint is
  absent, detectable only by the verification query above. Not visible from API responses
  (individual responses look structurally valid).
- *Blast radius:* Silent wrong answer. The same `customer_id` returns different tiers on
  successive calls depending on storage order. Extremely difficult to diagnose because the
  response format is correct and no error is raised.

---

### INV-10: Every API response must reflect the live database state at request time

- **INV-10:** No API response may be served from an application-level cache, an in-memory
  store, or any intermediate representation of database state. Every response is the result
  of a live SELECT query executed against Postgres at the time of the request.
- **Category:** Data
- **Scope:** GLOBAL
- **Authorship:** CD-drafted (confirmed by engineer)

**Why this matters:** This system's stated purpose is to give ops staff access to the
assessed risk state of a customer. If a caching layer were accidentally introduced, a
customer whose risk tier had been updated (outside this system, in the source database)
would continue to receive the stale cached tier until the cache expired or was invalidated.
Because there is no write path in this system, there is no cache invalidation trigger —
stale data would persist silently.

**Enforcement points:**
- Architecture: no caching middleware (Redis, in-memory dict, response cache decorator)
  is present in FastAPI or Nginx for the `/api/*` path.
- Nginx config: `proxy_cache` must not be configured for the `/api/` location block.
  (Static UI assets may be cached; API responses must not be.)
- Verification test: update a row directly in Postgres and assert the next API response
  for that `customer_id` reflects the update. This test is trivially passing with static
  seed data but serves as a regression guard if a cache is ever added.

**Failure mode:**

- *Violation:* An API response contains a `tier` or `risk_factors` value that does not
  match the current state of the corresponding row(s) in Postgres.
- *Detection:* Verification test (mutate row, assert response reflects mutation). Not
  detectable from logs or normal API usage. Silent in a static seed data system — only
  becomes visible if the underlying data changes.
- *Blast radius:* Incorrect business decision. In the current system the blast radius is
  low because seed data is static. In any operational extension where risk data is updated
  by an external process, stale reads mean ops staff act on outdated classifications.

---

## Domain invariants

> **These invariants are not yet present in this document.**  
>
> Domain invariants encode business rules that are not visible in the architecture, the
> data model, or the component boundaries. They cannot be drafted from ARCHITECTURE.md
> alone. They must be stated by the engineer — who holds the domain knowledge — and then
> challenged before being recorded here.
>
> Examples of rules that would belong here if confirmed:
> - Whether a HIGH-tier customer requires a minimum number of risk factors.
> - Whether certain factor codes are mutually exclusive with one another.
> - Whether tier precedence rules exist (e.g. one HIGH-weight factor forces a HIGH
>   classification regardless of all other factors).
> - Whether `customer_id` values are constrained to a specific population (active
>   customers only, retail segment only, etc.).
> - Whether a customer's tier may ever be NULL as a valid "under review" state, or
>   whether NULL is always an error.
>
> State each domain rule you know to be true and it will be challenged against the six
> tests before being added to this document.

---

## Invariant index

| ID | Statement summary | Category | Scope | Status |
|---|---|---|---|---|
| INV-01 | Every FastAPI request must carry a valid API key | Structural | GLOBAL | CD-drafted |
| INV-02 | The API key value must not appear in any system output | Structural | GLOBAL | CD-drafted |
| INV-03 | FastAPI must not accept requests until db-init exits 0 | Structural | TASK-SCOPED | CD-drafted |
| INV-04 | Each response contains data for exactly the requested customer | Structural | GLOBAL | CD-drafted |
| INV-05 | No database mutations during API operation | Structural | GLOBAL | CD-drafted |
| INV-06 | Every customer tier is a member of {LOW, MEDIUM, HIGH} | Data | GLOBAL | CD-drafted |
| INV-07 | Every customer has at least one risk factor | Data | GLOBAL | CD-drafted |
| INV-08 | Every risk factor row references an existing customer | Data | GLOBAL | CD-drafted |
| INV-09 | `customer_id` uniquely identifies exactly one customer | Data | GLOBAL | CD-drafted |
| INV-10 | Every response reflects live database state at request time | Data | GLOBAL | CD-drafted |

