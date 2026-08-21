-- Powerwall-Dashboard TimescaleDB MCP server: read-only database role.
--
-- This is the REAL safety boundary for the MCP server, not the in-process
-- query validation in server.py -- that validation is defense in depth, this
-- role is what actually stops a write/DDL statement from being possible at
-- all, regardless of what the LLM asks for.
--
-- Run this ONCE against your TimescaleDB database before starting the MCP
-- server, as the stack's normal admin user (POSTGRES_USER in
-- timescaledb.env). Connect using the SAME host/port/user/db this stack's
-- own containers use (TIMESCALEDB_HOST/PORT/POSTGRES_USER/POSTGRES_DB in
-- timescaledb.env) -- do NOT rely on `docker exec timescaledb`'s own
-- baked-in environment for this, even against the bundled container. If
-- your TimescaleDB server hosts more than one database (e.g. you pointed
-- setup.sh at an existing Postgres server you already use for other
-- things), the container's default POSTGRES_USER/POSTGRES_DB env vars are
-- almost certainly NOT the Powerwall app's role/database, and running this
-- script while implicitly connected to the wrong database will silently
-- grant privileges on the WRONG schema -- GRANT/ALTER DEFAULT PRIVILEGES
-- are scoped to whatever database you're connected to, not the "powerwall"
-- name that appears in the DATABASE-level grant below. From the repo root,
-- with timescaledb.env sourced:
--
--   set -a; . ./timescaledb.env; set +a
--   docker exec -i aggregate-cron sh -c \
--     'PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$TIMESCALEDB_HOST" -p "$TIMESCALEDB_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
--     < tools/timescaledb/mcp/readonly_role.sql
--
-- (aggregate-cron already has the right TIMESCALEDB_HOST/PORT/POSTGRES_*
-- env either way, bundled or external, so routing the connection through
-- it sidesteps this whole class of mistake.)
--
-- Then set MCP_ROLE_PASSWORD below to something real, or just edit the
-- CREATE ROLE line's PASSWORD before running this, and put the same value
-- in mcp.env as MCP_DB_PASSWORD.
--
-- Safe to re-run: CREATE ROLE ... IF NOT EXISTS isn't a thing in Postgres,
-- so this uses a DO block to make role creation idempotent; the GRANTs
-- themselves are already idempotent.

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'mcp_readonly') THEN
        CREATE ROLE mcp_readonly WITH LOGIN PASSWORD 'CHANGE_ME';
    END IF;
END
$$;

-- Pin this role's search_path to `public` only. This database has a second,
-- unrelated `energy` schema with same-named empty decoy tables for every
-- pw_* table this project uses (see timescaledb/README.md's "Gotchas"
-- section) -- without this, an unqualified query under the database's
-- default search_path (public, energy) could silently resolve against the
-- wrong, empty schema and return "no data" with no error at all. Pinning it
-- per-role means this holds even if the database-level default ever changes
-- back.
ALTER ROLE mcp_readonly SET search_path = public;

-- No write/DDL privileges of any kind -- only CONNECT + SELECT.
GRANT CONNECT ON DATABASE powerwall TO mcp_readonly;
GRANT USAGE ON SCHEMA public TO mcp_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO mcp_readonly;

-- Cover tables created AFTER this script runs too (e.g. if you re-apply
-- timescaledb/schema.sql later, or Telegraf lazily creates a new raw table
-- the first time it sees a field it hasn't before). Only applies to objects
-- the role that creates them owns -- if POSTGRES_USER is the one running
-- schema.sql/receiving Telegraf's writes, run this as that same user (which
-- this whole script already assumes).
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO mcp_readonly;

-- Explicitly confirm no write privileges exist (belt-and-suspenders -- these
-- should already be absent for a role that was never granted them, but this
-- makes the intent unambiguous to anyone reading this script later).
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public FROM mcp_readonly;
REVOKE CREATE ON SCHEMA public FROM mcp_readonly;
