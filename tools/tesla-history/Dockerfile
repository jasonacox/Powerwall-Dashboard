FROM python:3.11-alpine
WORKDIR /app
RUN apk add build-base \
  && pip install python-dateutil pypowerwall influxdb \
  && apk del build-base
COPY tesla-history.py tesla-history.py
CMD ["python3", "tesla-history.py", "--daemon"]
