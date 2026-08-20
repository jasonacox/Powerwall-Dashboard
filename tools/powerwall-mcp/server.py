"""Powerwall-Dashboard InfluxDB MCP server (HTTP transport, Docker-ready).

The Powerwall-Dashboard Telegraf exporter writes the SAME measurement names
into MULTIPLE retention policies (RPs), each holding a different slice of the
data:

  autogen  (default, 7d)  http (1-min power flow: solar/home/grid/battery kW), weather
  raw      (72h)          alerts, cpu, disk, diskio, http (80-field Powerwall status),
                          kernel, mem, powerwall_dashboard, processes, swap, system
  vitals   (7d)           http (inverter vitals: PW1_p_out, PW1_v_out, PW1_f_out, ...)
  kwh      (7d)           http (hourly kWh: solar/home/to_grid/to_pw/from_grid/from_pw)
  daily    (7d)           http (daily kWh totals)
  grid     (7d)           http (grid_status)
  pod      (7d)           http (battery: nominal_energy_remaining, backup_reserve_percent)
  alerts   (7d)           alerts (Powerwall alert events)
  strings / pwtemps / monthly / fans  (created, currently empty)

CRITICAL: InfluxQL `SHOW MEASUREMENTS` and unqualified `SELECT`/`SHOW FIELD KEYS`
only ever address the DEFAULT retention policy (autogen). To read data from any
other RP you MUST qualify the table as  "rp".measurement  (e.g. "kwh".http).

This version runs over Streamable HTTP so it can be exposed on the network and
linked to agents via a URL (http://<host>:<port>/mcp), instead of stdio.
Configuration is via environment variables so it can be set in docker-compose
without editing code:

  INFLUX_HOST   default: 127.0.0.1
  INFLUX_PORT   default: 8086
  INFLUX_DB     default: powerwall
  MCP_HOST      default: 0.0.0.0   (bind address inside the container)
  MCP_PORT      default: 8000
  MCP_AUTH_TOKEN  optional bearer token; if set, requests must include
                  Authorization: Bearer <token>
"""

import hmac
import json
import os
import re
from typing import Optional

from mcp.server.fastmcp import FastMCP
from influxdb import InfluxDBClient

INFLUX_HOST = os.environ.get("INFLUX_HOST", "127.0.0.1")
INFLUX_PORT = int(os.environ.get("INFLUX_PORT", "8086"))
INFLUX_DB = os.environ.get("INFLUX_DB", "powerwall")

MCP_HOST = os.environ.get("MCP_HOST", "0.0.0.0")
MCP_PORT = int(os.environ.get("MCP_PORT", "8000"))
MCP_AUTH_TOKEN = os.environ.get("MCP_AUTH_TOKEN")  # optional bearer token

# Initialize the MCP Server, bound for HTTP hosting.
mcp = FastMCP("Powerwall_Dashboard", host=MCP_HOST, port=MCP_PORT)

client = InfluxDBClient(host=INFLUX_HOST, port=INFLUX_PORT, database=INFLUX_DB)

# Measurement names written by the Powerwall-Dashboard Telegraf config. Used to
# probe each RP, because InfluxQL has no "SHOW MEASUREMENTS FROM <rp>".
_KNOWN_MEASUREMENTS = {
    "alerts", "cpu", "disk", "diskio", "http", "kernel", "mem",
    "powerwall_dashboard", "processes", "swap", "system", "weather",
}

# Cache for the expensive all-RP scan so repeated overview calls are instant.
_OVERVIEW_CACHE = None

# Identifiers we will interpolate into InfluxQL: bare word characters, dots
# and hyphens. Anything else (quotes, semicolons, spaces, parens...) is
# rejected so tool arguments can never break out of the quoted identifier.
_IDENT_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.\-]*$")


def _safe_ident(name: str) -> bool:
    return bool(name) and bool(_IDENT_RE.match(name))


def _measurement_pool():
    """Union of default-RP measurements and the known Powerwall measurement set."""
    names = set(_KNOWN_MEASUREMENTS)
    try:
        for p in client.query("SHOW MEASUREMENTS").get_points():
            names.add(p.get("name"))
    except Exception:
        pass
    return sorted(n for n in names if n)


def _rps():
    """Names of all retention policies in the database."""
    try:
        return [p["name"] for p in client.query("SHOW RETENTION POLICIES").get_points()]
    except Exception as e:
        return [f"Error: {e}"]


def _build_overview():
    """Map every RP -> {measurement: {latest_time, fields}} for tables with data."""
    overview = {}
    pool = _measurement_pool()
    for rp in _rps():
        if not isinstance(rp, str) or rp.startswith("Error"):
            continue
        rp_map = {}
        for m in pool:
            try:
                pts = list(
                    client.query(
                        f'SELECT * FROM "{rp}"."{m}" ORDER BY time DESC LIMIT 1'
                    ).get_points()
                )
            except Exception:
                continue
            if not pts:
                continue  # no data in this RP for this measurement
            latest = pts[0]
            fields = [k for k in latest.keys() if k != "time" and not k.startswith("tags")]
            rp_map[m] = {"latest_time": latest.get("time"), "fields": fields}
        overview[rp] = rp_map
    return overview


def _get_overview(force=False):
    global _OVERVIEW_CACHE
    if _OVERVIEW_CACHE is None or force:
        _OVERVIEW_CACHE = _build_overview()
    return _OVERVIEW_CACHE


@mcp.tool()
def get_database_overview() -> str:
    """Map the WHOLE database: every retention policy and, for each, the
    measurements that actually contain data, with their latest point time and
    field names. Use this FIRST to discover what is available before querying.
    (The old get_measurements only saw the default 'autogen' RP and missed the
    real Powerwall data in raw/vitals/kwh/daily/grid/pod/alerts.)"""
    try:
        return json.dumps(_get_overview(), indent=2, default=str)
    except Exception as e:
        return f"Error: {str(e)}"


@mcp.tool()
def get_retention_policies() -> str:
    """List all retention policies (RPs) with their duration. You must qualify
    queries with an RP name to read non-default data, e.g. SELECT * FROM "kwh".http."""
    try:
        return json.dumps(
            list(client.query("SHOW RETENTION POLICIES").get_points()),
            indent=2,
            default=str,
        )
    except Exception as e:
        return f"Error: {str(e)}"


@mcp.tool()
def get_measurements(retention_policy: Optional[str] = None) -> str:
    """List measurements that contain data.
    - retention_policy=None (default): returns EVERY RP -> [measurements with data].
    - retention_policy='kwh' (etc.): returns just that RP's [measurements with data].
    Note: unqualified InfluxQL only sees the default RP ('autogen'), so always
    pass the RP you care about when you know it."""
    try:
        overview = _get_overview()
        if retention_policy is None:
            return json.dumps(
                {rp: sorted(meas.keys()) for rp, meas in overview.items()},
                indent=2,
            )
        meas = overview.get(retention_policy, {})
        return json.dumps(
            {"retention_policy": retention_policy, "measurements": sorted(meas.keys())},
            indent=2,
        )
    except Exception as e:
        return f"Error: {str(e)}"


@mcp.tool()
def get_field_keys(measurement: str, retention_policy: str = "autogen") -> str:
    """Get the field (column) names for a measurement in a SPECIFIC retention
    policy. retention_policy defaults to 'autogen' — pass e.g. 'raw' or 'kwh'
    to inspect those RPs. Returns [] if that RP has no data for the measurement.
    Useful fields: raw.http has the full 80-field Powerwall status; kwh.http and
    daily.http have solar/home/to_grid/to_pw/from_grid/from_pw energy totals."""
    if not (_safe_ident(measurement) and _safe_ident(retention_policy)):
        return (
            "Error: Security exception. retention_policy and measurement must be "
            "plain identifiers (letters, digits, '_', '-', '.')."
        )
    try:
        result = client.query(f'SHOW FIELD KEYS FROM "{retention_policy}"."{measurement}"')
        return json.dumps(list(result.get_points()), indent=2, default=str)
    except Exception as e:
        return f"Error: {str(e)}"


@mcp.tool()
def query_powerwall(query: str) -> str:
    """Execute an InfluxQL SELECT query against the Powerwall InfluxDB.

    IMPORTANT — retention policies: unqualified tables only hit the default RP
    ('autogen'). To read the real Powerwall data, qualify the table as
    "rp".measurement. Examples:
      SELECT * FROM "kwh".http ORDER BY time DESC LIMIT 10
      SELECT mean("solar") FROM "autogen".http WHERE time >= now() - 1h GROUP BY time(5m)
      SELECT "solar","home","to_grid","to_pw" FROM "daily".http ORDER BY time DESC LIMIT 7
      SELECT * FROM "pod".http ORDER BY time DESC LIMIT 1   -- battery state
      SELECT * FROM "vitals".http ORDER BY time DESC LIMIT 1  -- inverter vitals
    Available RPs: autogen, raw, vitals, kwh, daily, grid, pod, alerts
    (strings, pwtemps, monthly, fans are empty).
    Only SELECT statements are allowed."""
    q = query.strip()
    # Allow (and strip) trailing statement terminators, as agents often emit
    # them; any remaining semicolon means multiple statements.
    q = q.rstrip(";").rstrip()
    if not q.upper().startswith("SELECT"):
        return "Error: Security exception. Only SELECT queries are allowed."
    if ";" in q:
        return "Error: Security exception. Multiple statements are not allowed."
    if re.search(r"\bINTO\b", q, re.IGNORECASE):
        return "Error: Security exception. SELECT ... INTO writes are not allowed."
    try:
        result = client.query(q)
        data = list(result.get_points())
        return json.dumps(data, indent=2, default=str)
    except Exception as e:
        return f"Query Error: {str(e)}"


def _run():
    # streamable-http exposes the server at http://<host>:<port>/mcp
    # This is the transport modern MCP clients/agents expect for a URL-based
    # remote connection (replaces the older, now-deprecated SSE transport).
    if not MCP_AUTH_TOKEN:
        mcp.run(transport="streamable-http")
        return

    # Wrap the ASGI app with a simple bearer-token check so this isn't wide
    # open to anyone who can reach the port. Required whenever this container
    # is exposed beyond your own trusted LAN.
    import uvicorn
    from starlette.responses import JSONResponse
    from starlette.middleware.base import BaseHTTPMiddleware

    class BearerAuthMiddleware(BaseHTTPMiddleware):
        async def dispatch(self, request, call_next):
            auth = request.headers.get("authorization", "")
            expected = f"Bearer {MCP_AUTH_TOKEN}"
            # Constant-time compare to avoid leaking the token via timing.
            if not hmac.compare_digest(auth.encode(), expected.encode()):
                return JSONResponse({"error": "unauthorized"}, status_code=401)
            return await call_next(request)

    app = mcp.streamable_http_app()
    app.add_middleware(BearerAuthMiddleware)
    uvicorn.run(app, host=MCP_HOST, port=MCP_PORT)


if __name__ == "__main__":
    _run()
