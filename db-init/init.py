import os
import sys
import time

import psycopg2

POSTGRES_HOST     = os.environ.get("POSTGRES_HOST", "postgres")
POSTGRES_DB       = os.environ["POSTGRES_DB"]
POSTGRES_USER     = os.environ["POSTGRES_USER"]
POSTGRES_PASSWORD = os.environ["POSTGRES_PASSWORD"]

conn = None

for attempt in range(1, 11):
    try:
        print(f"db-init: connecting to database (attempt {attempt}/10) ...")
        conn = psycopg2.connect(
            host=POSTGRES_HOST,
            dbname=POSTGRES_DB,
            user=POSTGRES_USER,
            password=POSTGRES_PASSWORD,
        )
        print("db-init: connection established")
        break
    except psycopg2.OperationalError as e:
        print(f"db-init: attempt {attempt}/10 failed — {e}")
        if attempt < 10:
            time.sleep(3)

if conn is None:
    print("db-init: could not connect after 10 attempts — exiting")
    sys.exit(1)

try:
    cur = conn.cursor()

    with open("schema.sql") as f:
        schema_sql = f.read()
    try:
        cur.execute(schema_sql)
        conn.commit()
        print("db-init: schema applied")
    except Exception as e:
        print(f"db-init: schema execution failed — {e}")
        sys.exit(1)

    with open("seed.sql") as f:
        seed_sql = f.read()
    try:
        cur.execute(seed_sql)
        conn.commit()
        print("db-init: seed data loaded")
    except Exception as e:
        print(f"db-init: seed execution failed — {e}")
        sys.exit(1)

    cur.close()

finally:
    if conn is not None:
        conn.close()
