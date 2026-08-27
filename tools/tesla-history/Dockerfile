FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends postgresql-client \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir "pypowerwall>=0.15.13" python-dateutil influxdb psycopg2-binary httpx h2
COPY tesla-history.py tesla-history.py
CMD ["python3", "tesla-history.py", "--daemon"]
