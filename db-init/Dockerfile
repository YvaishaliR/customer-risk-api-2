FROM python:3.10-slim
RUN pip install psycopg2-binary
COPY init.py schema.sql seed.sql .
CMD ["python", "init.py"]
