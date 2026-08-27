FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir \
    "mcp>=1.0,<2" \
    "pydantic-settings<2.15" \
    psycopg2-binary \
    uvicorn \
    starlette

COPY server.py .

ENV MCP_HOST=0.0.0.0
ENV MCP_PORT=8000

EXPOSE 8000

CMD ["python", "server.py"]
