FROM python:3.11-alpine
WORKDIR /app
RUN apk add build-base \
  && pip install python-dateutil teslapy influxdb \
  && apk del build-base
COPY tesla-history.py tesla-history.py
CMD ["python3", "tesla-history.py", "--daemon"]
