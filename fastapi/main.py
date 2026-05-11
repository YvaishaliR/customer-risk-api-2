import logging
import os
import re
import time
from contextlib import asynccontextmanager
from typing import List, Literal

import psycopg2
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from pydantic import BaseModel

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


class RiskFactor(BaseModel):
    factor_code: str
    factor_description: str


class RiskResponse(BaseModel):
    customer_id: str
    tier: Literal["LOW", "MEDIUM", "HIGH"]
    risk_factors: List[RiskFactor]


app = FastAPI(lifespan=lifespan)

_CUSTOMER_ID_RE = re.compile(r"^[A-Za-z0-9]{1,20}$")


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/api/risk/{customer_id}", response_model=RiskResponse, dependencies=[Depends(get_api_key)])
def get_risk(customer_id: str, conn: psycopg2.extensions.connection = Depends(get_db_conn)):
    if not _CUSTOMER_ID_RE.match(customer_id):
        raise HTTPException(status_code=400, detail="Invalid customer_id format")

    cur = conn.cursor()
    try:
        cur.execute("SELECT customer_id, tier FROM customers WHERE customer_id = %s", (customer_id,))
        row = cur.fetchone()
    finally:
        cur.close()

    if row is None:
        raise HTTPException(status_code=404, detail="Customer not found")

    db_customer_id, tier = row

    cur = conn.cursor()
    try:
        cur.execute(
            "SELECT factor_code, factor_description FROM risk_factors"
            " WHERE customer_id = %s ORDER BY factor_code",
            (db_customer_id,),
        )
        factor_rows = cur.fetchall()
    finally:
        cur.close()

    if not factor_rows:
        raise HTTPException(status_code=500, detail="Customer record is incomplete: no risk factors found")

    return RiskResponse(
        customer_id=db_customer_id,
        tier=tier,
        risk_factors=[RiskFactor(factor_code=fc, factor_description=fd) for fc, fd in factor_rows],
    )
