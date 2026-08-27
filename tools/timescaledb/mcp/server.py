#!/usr/bin/env python3
"""Powerwall-Dashboard TimescaleDB MCP server.

EXPERIMENTAL. Ported from the InfluxDB version of this tool
(tools/powerwall-mcp in the upstream project) to work against this fork's
TimescaleDB (PostgreSQL) datastore instead -- see ../../../timescaledb/README.md
for the schema this server understands, and ./README.md for setup.

Exposes a handful of MCP tools over HTTP streamable transport so an AI agent
can explore the schema and run read-only SQL against real Powerwall history:

  get_database_overview  -- map every table: kind, time range, approx rows
  get_tables              -- list tables with hypertable/compression info
  get_columns              -- column names/types for a "wide" table
  get_metric_names        -- distinct metric_name/alert_name values for a
                              "narrow" (EAV) table
  query_powerwall          -- run a read-only SELECT/WITH query

Design notes (why this isn't a 1:1 port of the InfluxDB version):

* No retention policies here -- this schema uses real tables instead: a
  handful of "wide" tables (one column per field) and several "narrow"/EAV
  tables (time, metric_name, value) for per-Powerwall-pack fields that scale
  with hardware count. get_field_keys from the original splits into
  get_columns (wide tables) and get_metric_names (narrow tables) because
  those two shapes need different schema questions answered.

* Query safety is layered, not just regex. The InfluxDB original relied
  entirely on string validation because InfluxDB 1.8's auth model is coarse.
  Postgres actually supports real least-privilege roles, so the primary
  boundary here is meant to be a dedicated read-only DB role (see
  readonly_role.sql) with SELECT-only grants and its own pinned search_path
  -- the in-process validation below (single SELECT/WITH statement, no
  writes/DDL/comments, capped LIMIT, statement_timeout) is defense in depth
  on top of that, not the only thing standing between an LLM and a DROP
  TABLE.

* search_path is pinned to `public` at the connection level (both via the
  connect() options and, if you ran readonly_role.sql, at the role level).
  This database has a second, unrelated `energy` schema with same-named
  empty decoy tables for every pw_* table in this project -- see
  timescaledb/README.md's "Gotchas" section. An unqualified query that
  resolved against `energy` instead of `public` would silently return empty
  results with no error, which is exactly the wrong failure mode for a tool
  an LLM uses to answer factual questions about your data.
"""

import hmac
import os
import re
import time
from contextlib import contextmanager
from typing import Optional

import psycopg2
import psycopg2.pool
from psycopg2 import sql
from psycopg2.extras import RealDictCursor

from mcp.server.fastmcp import FastMCP

# --------------------------------------------------------------------------
# Configuration (env vars)
# --------------------------------------------------------------------------

TIMESCALEDB_HOST = os.environ.get("TIMESCALEDB_HOST", "127.0.0.1")
TIMESCALEDB_PORT = int(os.environ.get("TIMESCALEDB_PORT", "5432"))
POSTGRES_DB = os.environ.get("POSTGRES_DB", "powerwall")
TIMESCALEDB_SSLMODE = os.environ.get("TIMESCALEDB_SSLMODE", "disable")

# Deliberately NOT POSTGRES_USER/POSTGRES_PASSWORD -- those are the stack's
# admin/write role from timescaledb.env. This server should connect as its
# own dedicated read-only role. See readonly_role.sql.
MCP_DB_USER = os.environ.get("MCP_DB_USER", "mcp_readonly")
MCP_DB_PASSWORD = os.environ.get("MCP_DB_PASSWORD", "")

MCP_HOST = os.environ.get("MCP_HOST", "0.0.0.0")
MCP_PORT = int(os.environ.get("MCP_PORT", "8000"))
MCP_AUTH_TOKEN = os.environ.get("MCP_AUTH_TOKEN", "").strip()

MAX_QUERY_ROWS = int(os.environ.get("MAX_QUERY_ROWS", "1000"))
QUERY_TIMEOUT_MS = int(os.environ.get("QUERY_TIMEOUT_MS", "30000"))
OVERVIEW_CACHE_TTL = float(os.environ.get("OVERVIEW_CACHE_TTL", "300"))

# --------------------------------------------------------------------------
# Known schema (see timescaledb/schema.sql). Only used to annotate results
# and to pick the right key column (metric_name vs alert_name) for narrow
# tables -- get_tables()/get_columns() always cross-check against the live
# database via information_schema, so an unlisted/new table still works,
# just without the friendly annotation.
# --------------------------------------------------------------------------

# table_name -> key column holding the metric identifier
EAV_TABLES = {
    "pw_vitals_log": "metric_name",
    "pw_strings_log": "metric_name",
    "pw_fans_log": "metric_name",
    "pw_pod_log": "metric_name",
    "pw_pwtemps_log": "metric_name",
    "pw_weather_log": "metric_name",
    "pw_alerts_log": "alert_name",
}

_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _safe_ident(name: str) -> str:
    """Validate a Postgres identifier coming from a tool argument (not
    trusted user SQL text). Raises ValueError if it doesn't look like a
    plain identifier -- callers must not string-format this into SQL
    directly even after validation; use psycopg2.sql.Identifier()."""
    if not name or not _IDENT_RE.match(name):
        raise ValueError(f"'{name}' is not a valid identifier")
    return name


# --------------------------------------------------------------------------
# Connection pool
# --------------------------------------------------------------------------

_pool: Optional[psycopg2.pool.SimpleConnectionPool] = None


def _get_pool() -> psycopg2.pool.SimpleConnectionPool:
    global _pool
    if _pool is None:
        if not MCP_DB_PASSWORD:
            raise RuntimeError(
                "MCP_DB_PASSWORD is not set. Create the read-only role with "
                "readonly_role.sql and set MCP_DB_USER/MCP_DB_PASSWORD."
            )
        _pool = psycopg2.pool.SimpleConnectionPool(
            1,
            5,
            host=TIMESCALEDB_HOST,
            port=TIMESCALEDB_PORT,
            dbname=POSTGRES_DB,
            user=MCP_DB_USER,
            password=MCP_DB_PASSWORD,
            sslmode=TIMESCALEDB_SSLMODE,
            connect_timeout=10,
            # Belt-and-suspenders alongside readonly_role.sql's
            # `ALTER ROLE ... SET search_path`: pin it here too, so this
            # server is safe even against a role that was created without
            # running that script.
            options="-c search_path=public",
        )
    return _pool


@contextmanager
def _cursor():
    """Borrow a pooled, read-only connection with a statement timeout and
    yield a dict-row cursor. Always rolls back (nothing here ever commits --
    these are all reads) and returns the connection to the pool."""
    pool = _get_pool()
    conn = pool.getconn()
    try:
        conn.set_session(readonly=True, autocommit=True)
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql.SQL("SET statement_timeout = %s"), (QUERY_TIMEOUT_MS,))
            yield cur
    finally:
        pool.putconn(conn)


# --------------------------------------------------------------------------
# MCP server
# --------------------------------------------------------------------------

mcp = FastMCP("powerwall-timescaledb", host=MCP_HOST, port=MCP_PORT)

_OVERVIEW_CACHE = None
_OVERVIEW_CACHE_TIME = 0.0


def _live_tables() -> list[str]:
    with _cursor() as cur:
        cur.execute(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema = 'public' AND table_type = 'BASE TABLE' "
            "ORDER BY 1"
        )
        return [r["table_name"] for r in cur.fetchall()]


def _hypertable_info() -> dict:
    """table_name -> {compressed, chunk_interval, approx_row_count}."""
    info: dict = {}
    with _cursor() as cur:
        cur.execute(
            "SELECT hypertable_name, compression_enabled "
            "FROM timescaledb_information.hypertables "
            "WHERE hypertable_schema = 'public'"
        )
        for r in cur.fetchall():
            info[r["hypertable_name"]] = {
                "hypertable": True,
                "compression_enabled": r["compression_enabled"],
            }
    return info


def _approx_row_count(table: str, is_hypertable: bool) -> Optional[int]:
    try:
        with _cursor() as cur:
            if is_hypertable:
                cur.execute(
                    sql.SQL("SELECT approximate_row_count({}) AS n").format(
                        sql.Literal(f"public.{table}")
                    )
                )
            else:
                cur.execute(
                    "SELECT reltuples::bigint AS n FROM pg_class "
                    "WHERE relname = %s",
                    (table,),
                )
            row = cur.fetchone()
            return int(row["n"]) if row and row["n"] is not None else None
    except Exception:
        return None


def _time_range(table: str) -> Optional[dict]:
    """min/max(time) for a table, or None if it has no `time` column."""
    with _cursor() as cur:
        cur.execute(
            "SELECT 1 FROM information_schema.columns "
            "WHERE table_schema = 'public' AND table_name = %s AND column_name = 'time'",
            (table,),
        )
        if cur.fetchone() is None:
            return None
        cur.execute(
            sql.SQL("SELECT min(time) AS oldest, max(time) AS newest FROM {}").format(
                sql.Identifier(table)
            )
        )
        row = cur.fetchone()
        return {
            "oldest": row["oldest"].isoformat() if row["oldest"] else None,
            "newest": row["newest"].isoformat() if row["newest"] else None,
        }


def _build_overview() -> dict:
    tables = _live_tables()
    ht_info = _hypertable_info()
    overview = {}
    for t in tables:
        ht = ht_info.get(t)
        entry = {
            "kind": "hypertable" if ht else "table",
            "shape": "narrow (metric_name/value rows -- call get_metric_names)"
            if t in EAV_TABLES
            else "wide (one column per field -- call get_columns)",
        }
        if ht:
            entry["compression_enabled"] = ht["compression_enabled"]
        entry["approx_row_count"] = _approx_row_count(t, ht is not None)
        entry["time_range"] = _time_range(t)
        overview[t] = entry
    return overview


def _get_overview(force: bool = False) -> dict:
    global _OVERVIEW_CACHE, _OVERVIEW_CACHE_TIME
    now = time.time()
    if force or _OVERVIEW_CACHE is None or (now - _OVERVIEW_CACHE_TIME) > OVERVIEW_CACHE_TTL:
        _OVERVIEW_CACHE = _build_overview()
        _OVERVIEW_CACHE_TIME = now
    return _OVERVIEW_CACHE


@mcp.tool()
def get_database_overview(refresh: bool = False) -> dict:
    """Map the WHOLE database: every table, whether it's a TimescaleDB
    hypertable, whether it's "wide" (one column per field -- use
    get_columns) or "narrow"/EAV (time, metric_name, value rows scaled to
    however much hardware you have -- use get_metric_names), its time range,
    and an approximate row count. Cached for a few minutes unless
    refresh=true. Start here before writing a query_powerwall query.
    """
    return _get_overview(force=refresh)


@mcp.tool()
def get_tables() -> dict:
    """List every table in the database with its kind (plain table vs
    TimescaleDB hypertable) and compression status. Unlike the old InfluxDB
    version of this tool, there are no retention policies to enumerate --
    every table here is just... a table. See get_database_overview for time
    ranges and row counts too.
    """
    tables = _live_tables()
    ht_info = _hypertable_info()
    return {
        t: (ht_info.get(t) or {"hypertable": False, "compression_enabled": None})
        for t in tables
    }


@mcp.tool()
def get_columns(table: str) -> dict:
    """Get the column names/types for a WIDE table (one column per field --
    e.g. http, pw_autogen_1m, pw_kwh_1h, pw_grid_1m). For a NARROW/EAV table
    (pw_vitals_log, pw_pwtemps_log, pw_strings_log, pw_fans_log, pw_pod_log,
    pw_weather_log, pw_alerts_log) this will just show you the fixed
    (time, metric_name, value) shape -- call get_metric_names instead to see
    what's actually IN metric_name for that table.
    """
    _safe_ident(table)
    if table not in _live_tables():
        return {"error": f"Unknown table '{table}'. Call get_tables() first."}
    with _cursor() as cur:
        cur.execute(
            "SELECT column_name, data_type, is_nullable FROM information_schema.columns "
            "WHERE table_schema = 'public' AND table_name = %s ORDER BY ordinal_position",
            (table,),
        )
        # Wrapped in a dict (one content block) rather than returned as a
        # bare list -- FastMCP serializes a list return as one MCP content
        # block PER ITEM, which for a 100+ column table like `http` would
        # fragment into 100+ separate blocks instead of one JSON array.
        return {"table": table, "columns": cur.fetchall()}


@mcp.tool()
def get_metric_names(table: str) -> dict:
    """Get the distinct metric_name (or alert_name, for pw_alerts_log)
    values actually present in a NARROW/EAV table -- e.g. for pw_vitals_log
    this returns things like 'ISLAND_VL1N_Load', 'PW1_PINV_VSplit1',
    'PW2_v_out', etc. There's no fixed list; it scales with however many
    Powerwalls/strings/fans you have. Only valid for the narrow tables
    listed in get_database_overview as "shape: narrow" -- wide tables have
    no metric_name column at all, use get_columns for those instead.
    """
    _safe_ident(table)
    key_col = EAV_TABLES.get(table)
    if key_col is None:
        return {
            "error": (
                f"'{table}' isn't a known narrow/EAV table. "
                "Call get_database_overview() and check the 'shape' field, "
                "or get_columns() if it's a wide table."
            )
        }
    with _cursor() as cur:
        cur.execute(
            sql.SQL("SELECT DISTINCT {col} AS name FROM {tbl} ORDER BY 1 LIMIT 500").format(
                col=sql.Identifier(key_col), tbl=sql.Identifier(table)
            )
        )
        return {"table": table, "key_column": key_col, "values": [r["name"] for r in cur.fetchall()]}


# --------------------------------------------------------------------------
# query_powerwall: the read-only SQL executor
# --------------------------------------------------------------------------

# Whole-word deny list. This is a SECOND layer, not the primary defense --
# see the module docstring. Anything not caught here is still stopped by
# MCP_DB_USER's Postgres-level grants (readonly_role.sql), which is the real
# boundary.
_FORBIDDEN_KEYWORDS = re.compile(
    r"\b("
    r"INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|GRANT|REVOKE|CREATE|COPY|"
    r"CALL|EXECUTE|PREPARE|DEALLOCATE|VACUUM|REINDEX|CLUSTER|ANALYZE|"
    r"REFRESH|DISCARD|LISTEN|NOTIFY|UNLISTEN|DO|MERGE|LOCK|SET|RESET|"
    r"INTO|SECURITY|DBLINK|PG_SLEEP|PG_TERMINATE_BACKEND|PG_CANCEL_BACKEND|"
    r"PG_READ_FILE|PG_READ_BINARY_FILE|LO_IMPORT|LO_EXPORT"
    r")\b",
    re.IGNORECASE,
)
_LEADING_STMT = re.compile(r"^\s*(SELECT|WITH)\b", re.IGNORECASE)
_TRAILING_LIMIT = re.compile(r"\bLIMIT\s+(\d+)\s*;?\s*$", re.IGNORECASE)


def _validate_and_cap(query: str) -> str:
    q = query.strip()
    if not q:
        raise ValueError("Empty query.")

    # Reject comments outright rather than trying to strip them -- a
    # forbidden keyword hidden inside a comment would otherwise sail past
    # the keyword scan below.
    if "--" in q or "/*" in q:
        raise ValueError("Security exception: SQL comments are not allowed.")

    # Reject multiple statements. Strip one single trailing semicolon
    # first (harmless/common), then anything left is a second statement.
    q_no_trailing = q[:-1].rstrip() if q.rstrip().endswith(";") else q
    if ";" in q_no_trailing:
        raise ValueError("Security exception: only a single statement is allowed.")
    q = q_no_trailing

    if not _LEADING_STMT.match(q):
        raise ValueError("Security exception: only SELECT/WITH queries are allowed.")

    if _FORBIDDEN_KEYWORDS.search(q):
        raise ValueError("Security exception: query contains a disallowed keyword.")

    # Cap (not require) LIMIT: append MAX_QUERY_ROWS if missing, clamp down
    # if the caller asked for more than that. Deliberately NOT requiring a
    # LIMIT the way the InfluxDB version does -- most of this schema's real
    # queries (see the Grafana dashboards) are bounded by a time range and a
    # GROUP BY, not a row count, and forcing every query to end in a
    # arbitrary LIMIT would fight that pattern for no safety benefit once
    # we're capping it here anyway.
    m = _TRAILING_LIMIT.search(q)
    if m:
        requested = int(m.group(1))
        if requested > MAX_QUERY_ROWS:
            q = q[: m.start()] + f"LIMIT {MAX_QUERY_ROWS}"
    else:
        q = f"{q}\nLIMIT {MAX_QUERY_ROWS}"

    return q


@mcp.tool()
def query_powerwall(query: str) -> dict:
    """Execute a read-only SQL query against the Powerwall TimescaleDB
    database. Only a single SELECT or WITH (CTE) statement is allowed --
    no writes, no DDL, no comments, no multiple statements. Results are
    capped at MAX_QUERY_ROWS rows (a LIMIT is added/clamped automatically if
    you don't include one or ask for too many).

    Everything is unqualified `public` schema -- do not prefix table names
    with a schema. Use get_database_overview()/get_tables() first to see
    what's available, get_columns()/get_metric_names() to see what's in a
    given table, then write your query.

    Time columns: most tables use `timestamptz` (time-zone aware) except the
    raw Telegraf-written tables (http, alerts, powerwall_dashboard), whose
    `time` column is a naive UTC timestamp -- compare it directly against
    UTC literals or now(), don't attach a timezone offset to a literal
    string when filtering it (Postgres will silently reinterpret an offset
    string through the session's local TimeZone instead of erroring, which
    silently shifts your query window).
    """
    try:
        safe_query = _validate_and_cap(query)
    except ValueError as e:
        return {"error": str(e)}

    try:
        with _cursor() as cur:
            cur.execute(safe_query)
            rows = cur.fetchall()
            return {"row_count": len(rows), "rows": rows}
    except Exception as e:
        return {"error": f"Error: {e}"}


# --------------------------------------------------------------------------
# Startup / transport (mirrors the InfluxDB version's optional bearer auth)
# --------------------------------------------------------------------------


def _run():
    if not MCP_AUTH_TOKEN:
        mcp.run(transport="streamable-http")
        return

    # Wrap the ASGI app with constant-time bearer token auth.
    import uvicorn
    from starlette.applications import Starlette
    from starlette.responses import PlainTextResponse
    from starlette.types import ASGIApp, Receive, Scope, Send

    inner_app = mcp.streamable_http_app()

    class BearerAuthMiddleware:
        def __init__(self, app: ASGIApp, token: str):
            self.app = app
            self.token = token

        async def __call__(self, scope: Scope, receive: Receive, send: Send):
            if scope["type"] != "http":
                await self.app(scope, receive, send)
                return
            headers = dict(scope.get("headers") or [])
            auth = headers.get(b"authorization", b"").decode("latin-1")
            presented = auth[7:] if auth.lower().startswith("bearer ") else ""
            if not presented or not hmac.compare_digest(presented, self.token):
                response = PlainTextResponse("Unauthorized", status_code=401)
                await response(scope, receive, send)
                return
            await self.app(scope, receive, send)

    app = BearerAuthMiddleware(inner_app, MCP_AUTH_TOKEN)
    uvicorn.run(app, host=MCP_HOST, port=MCP_PORT)


if __name__ == "__main__":
    _run()
