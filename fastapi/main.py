import logging
import os

from fastapi import Depends, FastAPI, Header, HTTPException

# Database lifespan added in S4-T1

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

_API_KEY = os.environ.get("API_KEY")
if not _API_KEY:
    raise RuntimeError("API_KEY environment variable is not set")

logger.info("FastAPI: API key authentication configured")


def get_api_key(x_api_key: str = Header(None)) -> str:
    if x_api_key is None or x_api_key != _API_KEY:
        raise HTTPException(status_code=401, detail="Invalid or missing API key")
    return x_api_key


app = FastAPI(dependencies=[Depends(get_api_key)])


@app.get("/health")
def health():
    return {"status": "ok"}
