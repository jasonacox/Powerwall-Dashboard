FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir "pypowerwall>=0.15.12" python-dateutil influxdb httpx h2
COPY tesla-history.py tesla-history.py
CMD ["python3", "tesla-history.py", "--daemon"]
