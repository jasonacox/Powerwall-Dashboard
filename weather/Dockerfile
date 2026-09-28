FROM python:3.8-alpine
WORKDIR /app
RUN pip3 install requests influxdb-client psycopg2-binary
COPY server.py server.py
COPY README.md README.md
CMD ["python3", "server.py"]
EXPOSE 8676
