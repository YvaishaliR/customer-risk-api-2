from fastapi import FastAPI

# Auth dependency added in S3-T2
# Database lifespan added in S4-T1

app = FastAPI()


@app.get("/health")
def health():
    return {"status": "ok"}
