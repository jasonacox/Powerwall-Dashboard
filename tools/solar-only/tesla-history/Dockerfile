FROM python:3.11-alpine
WORKDIR /app
RUN pip3 install python-dateutil teslapy influxdb
COPY tesla-history.py tesla-history.py
CMD ["python3", "tesla-history.py", "--daemon"]
