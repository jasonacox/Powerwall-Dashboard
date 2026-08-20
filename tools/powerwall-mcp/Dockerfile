FROM python:3.12-slim

WORKDIR /app

# uvicorn + starlette are needed for the optional bearer-auth wrapper path;
# harmless if MCP_AUTH_TOKEN is unset.
RUN pip install --no-cache-dir \
    "mcp>=1.0,<2" \
    influxdb \
    uvicorn \
    starlette

COPY server.py .

ENV MCP_HOST=0.0.0.0 \
    MCP_PORT=8000

EXPOSE 8000

CMD ["python", "server.py"]
