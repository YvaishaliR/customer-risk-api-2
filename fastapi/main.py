import logging
import os
import time
from contextlib import asynccontextmanager

import psycopg2
from fastapi import Depends, FastAPI, Header, HTTPException, Request

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

_API_KEY = os.environ.get("API_KEY")
if not _API_KEY:
    raise RuntimeError("API_KEY environment variable is not set")

logger.info("FastAPI: API key authentication configured")

_DB_HOST = os.environ.get("POSTGRES_HOST", "postgres")
_DB_NAME = os.environ["POSTGRES_DB"]
_DB_USER = os.environ["POSTGRES_USER"]
_DB_PASS = os.environ["POSTGRES_PASSWORD"]


def _connect() -> psycopg2.extensions.connection:
    for attempt in range(1, 11):
        try:
            conn = psycopg2.connect(
                host=_DB_HOST,
                dbname=_DB_NAME,
                user=_DB_USER,
                password=_DB_PASS,
            )
            conn.autocommit = False
            cur = conn.cursor()
            cur.execute("SELECT 1")
            cur.close()
            return conn
        except psycopg2.OperationalError:
            logger.info("FastAPI: waiting for database... (attempt %d/10)", attempt)
            if attempt < 10:
                time.sleep(3)
    raise RuntimeError("Database connection failed")


@asynccontextmanager
async def lifespan(app: FastAPI):
    conn = _connect()
    app.state.db = conn
    logger.info("FastAPI: database connection established")
    try:
        yield
    finally:
        if app.state.db and not app.state.db.closed:
            app.state.db.close()


def get_api_key(x_api_key: str = Header(None)) -> str:
    if x_api_key is None or x_api_key != _API_KEY:
        raise HTTPException(status_code=401, detail="Invalid or missing API key")
    return x_api_key


def get_db_conn(request: Request) -> psycopg2.extensions.connection:
    conn = request.app.state.db
    if conn.closed:
        try:
            conn = _connect()
            request.app.state.db = conn
        except RuntimeError:
            raise HTTPException(status_code=503, detail="Database unavailable")
    return conn


app = FastAPI(dependencies=[Depends(get_api_key)], lifespan=lifespan)


@app.get("/health")
def health():
    return {"status": "ok"}
