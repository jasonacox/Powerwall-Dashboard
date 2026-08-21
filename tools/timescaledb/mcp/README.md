# Powerwall-Dashboard TimescaleDB MCP server

> **EXPERIMENTAL.** An extension of the [TimescaleDB extension](../),
> itself experimental and not part of the core supported stack. Expect
> rough edges.

An MCP (Model Context Protocol) server that lets an AI agent (Claude, etc.)
explore your Powerwall-Dashboard TimescaleDB schema and run read-only SQL
against it conversationally -- "what was my solar ROI last month," "when did
my Powerwall temperatures last look off," that kind of thing, answered from
your actual historical data instead of a guess.

This is a port of the upstream project's
[`tools/powerwall-mcp`](https://github.com/jasonacox/Powerwall-Dashboard/tree/main/tools/powerwall-mcp),
which does the same thing against InfluxDB. It isn't a drop-in translation --
this schema doesn't have InfluxDB's retention-policy concept, has a mix of
"wide" tables and narrow/EAV tables that don't map onto InfluxDB's field-key
model, and (being real Postgres) can enforce read-only access with an actual
database role instead of just string validation. See the comments at the top
of `server.py` for the full list of differences and why.

## Tools it exposes

- **`get_database_overview`** -- every table: hypertable or plain, wide or
  narrow, time range, approximate row count. Cached a few minutes. Start
  here.
- **`get_tables`** -- table list with hypertable/compression status only
  (no time ranges/row counts -- lighter weight than the overview).
- **`get_columns(table)`** -- column names/types for a **wide** table (one
  column per field -- `http`, `pw_autogen_1m`, `pw_kwh_1h`, `pw_grid_1m`,
  `powerwall_dashboard`, `alerts`).
- **`get_metric_names(table)`** -- distinct `metric_name` (or `alert_name`,
  for `pw_alerts_log`) values actually present in a **narrow**/EAV table
  (`pw_vitals_log`, `pw_pwtemps_log`, `pw_strings_log`, `pw_fans_log`,
  `pw_pod_log`, `pw_weather_log`, `pw_alerts_log`). These tables scale with
  however much hardware you have -- there's no fixed schema to read off,
  you have to ask the data what's actually in it.
- **`query_powerwall(query)`** -- run a read-only `SELECT`/`WITH` query.
  Rows are capped at `MAX_QUERY_ROWS` (a `LIMIT` is added or clamped down
  automatically if you don't include one or ask for too many). No writes,
  DDL, comments, or multiple statements -- see "Safety model" below.

## Setup

Requires the [TimescaleDB extension](../) already set up (`tools/timescaledb/setup.sh`).

1. **Create the read-only database role** (once). This is the real safety
   boundary -- read `readonly_role.sql`'s header comment before running it,
   especially if your TimescaleDB server hosts more than just this
   database (the header explains why that matters and gives the exact
   command).

2. **Configure the server:**
   ```bash
   cp tools/timescaledb/mcp/mcp.env.sample mcp.env
   ```
   Edit `mcp.env`: fill in `MCP_DB_PASSWORD` to match what you set in
   `readonly_role.sql`, and confirm `TIMESCALEDB_HOST`/`PORT` match your
   `timescaledb.env`. `mcp.env` is gitignored, same as `timescaledb.env`.

3. **Add the service.** `docker compose` only reads a single
   `powerwall.extend.yml`, and you already have one from the TimescaleDB
   extension setup -- merge the `powerwall-mcp` service from
   [`powerwall.extend.yml.sample`](powerwall.extend.yml.sample) into it by
   hand (same manual-merge pattern documented for
   [`tools/pgadmin`](../../pgadmin/) and
   [`tools/tesla-history`](../../tesla-history/) when you already have an
   extend file from another add-on).

4. **Start it:**
   ```bash
   docker compose -f powerwall.yml -f powerwall.extend.yml up -d --build powerwall-mcp
   ```
   The server listens at `http://127.0.0.1:8765/mcp` by default (bound to
   localhost only -- see the port comment in `powerwall.extend.yml.sample`
   if you need it reachable from elsewhere, and set `MCP_AUTH_TOKEN` in
   `mcp.env` if you do).

## Connecting Claude

Add it as an MCP server pointed at `http://<host>:8765/mcp` (streamable
HTTP transport) in whatever client you're using -- Claude Code, Claude
Desktop, etc. If you set `MCP_AUTH_TOKEN`, configure that client to send
`Authorization: Bearer <token>`.

## Safety model

Three layers, in order of how much you should actually trust them:

1. **The `mcp_readonly` database role** (`readonly_role.sql`) is the real
   boundary. It has `SELECT` only, on `public` schema tables, nothing else
   -- no `INSERT`/`UPDATE`/`DELETE`, no DDL, no `CREATE`. Even a total bug
   in `server.py`'s validation can't turn into a write, because the
   database connection itself is incapable of one.
2. **`search_path` is pinned to `public`**, both by the role
   (`ALTER ROLE ... SET search_path`) and by the connection itself
   (belt-and-suspenders, in case you're using a role that predates running
   that script). This database has a second, unrelated `energy` schema
   with same-named empty decoy tables for every `pw_*` table this project
   uses -- see [`timescaledb/README.md`](../../../timescaledb/README.md)'s
   Gotchas section. Without this pin, an agent's query could silently
   resolve against the wrong, empty schema and confidently report "no
   data" with no error at all.
3. **In-process query validation** (`server.py`): single `SELECT`/`WITH`
   statement only, no comments, no dangerous keywords
   (`pg_sleep`/`dblink`/`pg_read_file`/etc.), and a Postgres
   `statement_timeout` (`QUERY_TIMEOUT_MS`, default 30s) so a slow or
   unbounded query gets killed cleanly instead of tying up a connection.
   This is defense in depth on top of (1), not a substitute for it.

## Files

- `server.py` -- the MCP server
- `Dockerfile` -- container definition
- `readonly_role.sql` -- creates the `mcp_readonly` role (run by hand; safe
  to re-run, including to rotate the password)
- `mcp.env.sample` -- config template
- `powerwall.extend.yml.sample` -- the service snippet to merge in

## Removing it

```bash
docker compose -f powerwall.yml -f powerwall.extend.yml stop powerwall-mcp
docker compose -f powerwall.yml -f powerwall.extend.yml rm -f powerwall-mcp
# Remove the powerwall-mcp service from powerwall.extend.yml by hand, then:
rm mcp.env
```

To also drop the database role (connect as your normal `POSTGRES_USER`,
against the `powerwall` database -- see `readonly_role.sql`'s header for why
that distinction matters):

```sql
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM mcp_readonly;
REVOKE ALL ON SCHEMA public FROM mcp_readonly;
REVOKE ALL ON DATABASE powerwall FROM mcp_readonly;
DROP ROLE IF EXISTS mcp_readonly;
```
