# powerwall-mcp — MCP Server for Powerwall-Dashboard

An optional, self-contained [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server that lets AI agents (Claude, Open WebUI, Hermes, and other MCP-capable clients) query your Powerwall-Dashboard InfluxDB 1.8 data in plain language.

Ask things like:

- "What was my solar ROI last year?"
- "Was buying a Powerwall worth it?"
- "Is cleaning my panels worth it?" (feed it cleaning dates/costs)

…all answered from *your* actual historical data.

## Why a dedicated MCP server?

Most existing InfluxDB MCP servers target InfluxDB 2.x/3.x, while Powerwall-Dashboard ships InfluxDB 1.8. More importantly, the Telegraf exporter writes the **same measurement names into multiple retention policies** (`autogen`, `raw`, `vitals`, `kwh`, `daily`, `grid`, `pod`, `alerts`), each holding a different slice of the data. Generic servers miss this entirely — this tool knows the schema.

The server exposes tools to:

- `get_database_overview` — map every retention policy and measurement (use this first)
- `get_retention_policies` / `get_measurements` / `get_field_keys` — explore the schema
- `query_powerwall` — run InfluxQL `SELECT` queries (read-only)

## Setup

```bash
cd tools/powerwall-mcp
```

Edit `docker-compose.yml` and set `INFLUX_HOST` to the host running your Powerwall-Dashboard InfluxDB (e.g. your dashboard host's LAN IP). Leave `INFLUX_PORT` (8086) and `INFLUX_DB` (powerwall) at their defaults unless you've changed them.

If the port is reachable beyond your own trusted LAN, set `MCP_AUTH_TOKEN` to a strong secret — clients must then send it as a bearer token.

Build and run:

```bash
docker compose up -d --build
```

The MCP server is available at `http://<host-ip>:8765/mcp` (streamable HTTP transport). Add that URL to your MCP-capable agent/client.

> Note: this runs its own compose stack, separate from the dashboard — don't use `compose-dash.sh` here.

## Credit

Based on the original `powerwall-dashboard-mcp` by [@ampersandru](https://github.com/ampersandru/powerwall-dashboard-mcp), contributed via [#848](https://github.com/jasonacox/Powerwall-Dashboard/issues/848). Thank you!

**AI Disclaimer** (from the original author): this was AI-assisted. Use at your own risk!
