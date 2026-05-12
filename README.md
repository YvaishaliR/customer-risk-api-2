## Prerequisites

- Docker >= 24.0
- Docker Compose v2 (`docker compose`, not `docker-compose`)

## Setup

```
cp .env.example .env
# Edit .env and set real values for all 5 variables
```

## Start

```
docker compose up --build
```

## Verify

```
bash verify/run_all.sh
```

## Stop

```
docker compose down -v
```
