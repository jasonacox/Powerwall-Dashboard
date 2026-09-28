-- Powerwall Dashboard: TimescaleDB schema
--
-- Applied automatically by setup.sh (docker exec ... psql -f schema.sql) and
-- safe to re-run -- every statement is idempotent (IF NOT EXISTS / if_not_exists).
--
-- This only creates the AGGREGATE tables (populated by timescaledb/aggregate/*.sql
-- on a schedule). The raw ingestion tables (http, alerts, weather) are created
-- lazily by Telegraf's outputs.postgresql on first write, then converted to
-- hypertables by the aggregate-cron container's bootstrap step -- see
-- timescaledb/aggregate/bootstrap_raw_tables.sql.
--
-- Table shape follows timescaledb/README.md: wide (one column per field) for
-- fixed, site-wide fields; narrow/long (time, metric_name, value) wherever the
-- field set scales with hardware (per-pack fields) or is controlled by a third
-- party (weather). Narrow tables need zero schema changes regardless of
-- Powerwall count or new upstream fields.

CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Site-wide 1-minute power flow (time-weighted averages applied at ingest,
-- see aggregate_autogen_1m.sql)
CREATE TABLE IF NOT EXISTS pw_autogen_1m (
    time timestamptz NOT NULL,
    home double precision,
    solar double precision,
    from_pw double precision,
    to_pw double precision,
    from_grid double precision,
    to_grid double precision,
    percentage double precision,
    home_current double precision,
    solar_current double precision,
    pw_current double precision,
    grid_current double precision,
    home_voltage double precision,
    solar_voltage double precision,
    pw_voltage double precision,
    grid_voltage double precision,
    PRIMARY KEY (time)
);
SELECT create_hypertable('pw_autogen_1m', 'time', chunk_time_interval => interval '7 days', if_not_exists => true);
-- NULL = live-ingested (the normal case); 'cloud' = backfilled by
-- tools/tesla-history -- see that tool's README for why this exists (lets
-- --remove safely undo only its own imported rows).
ALTER TABLE pw_autogen_1m ADD COLUMN IF NOT EXISTS source text;
ALTER TABLE pw_autogen_1m SET (timescaledb.compress);
SELECT add_compression_policy('pw_autogen_1m', compress_after => interval '7 days', if_not_exists => true);

-- Site-wide hourly energy (boundary-interpolated integration applied at
-- ingest, see aggregate_kwh_1h.sql). Retained permanently. Not compressed --
-- small enough (6 columns, hourly) that compression isn't worth the added
-- complexity on a wide table.
CREATE TABLE IF NOT EXISTS pw_kwh_1h (
    time timestamptz NOT NULL,
    home double precision,
    solar double precision,
    from_pw double precision,
    to_pw double precision,
    from_grid double precision,
    to_grid double precision,
    PRIMARY KEY (time)
);
SELECT create_hypertable('pw_kwh_1h', 'time', chunk_time_interval => interval '7 days', if_not_exists => true);

-- Grid status (min() per bucket -- "was it down at any point"). Not
-- compressed -- same reasoning as pw_kwh_1h.
CREATE TABLE IF NOT EXISTS pw_grid_1m (
    time timestamptz NOT NULL,
    grid_status double precision,
    PRIMARY KEY (time)
);
SELECT create_hypertable('pw_grid_1m', 'time', chunk_time_interval => interval '7 days', if_not_exists => true);
-- See pw_autogen_1m's "source" column comment above.
ALTER TABLE pw_grid_1m ADD COLUMN IF NOT EXISTS source text;

-- Per-pack vitals (frequency/voltage/current/power per Powerwall + island/meter
-- fields). Narrow format scales to any pack count with no DDL change -- see
-- aggregate_vitals_log.sql's regex-filtered unpivot.
CREATE TABLE IF NOT EXISTS pw_vitals_log (
    time timestamptz NOT NULL,
    metric_name text NOT NULL,
    value double precision,
    PRIMARY KEY (time, metric_name)
);
SELECT create_hypertable('pw_vitals_log', 'time', chunk_time_interval => interval '7 days', if_not_exists => true);
ALTER TABLE pw_vitals_log SET (timescaledb.compress, timescaledb.compress_segmentby = 'metric_name');
SELECT add_compression_policy('pw_vitals_log', compress_after => interval '7 days', if_not_exists => true);

-- Powerwall+ string monitoring (per-inverter, per-string current/power/voltage,
-- plus derived per-inverter total power). No hardware to validate this
-- against -- best-effort port, same narrow pattern as vitals since the field
-- count scales with how many strings/inverters are actually installed.
CREATE TABLE IF NOT EXISTS pw_strings_log (
    time timestamptz NOT NULL,
    metric_name text NOT NULL,
    value double precision,
    PRIMARY KEY (time, metric_name)
);
SELECT create_hypertable('pw_strings_log', 'time', chunk_time_interval => interval '7 days', if_not_exists => true);
ALTER TABLE pw_strings_log SET (timescaledb.compress, timescaledb.compress_segmentby = 'metric_name');
SELECT add_compression_policy('pw_strings_log', compress_after => interval '7 days', if_not_exists => true);

-- Backup Switch fan telemetry (target/actual speed per fan). No hardware to
-- validate this against -- best-effort port, same narrow pattern.
CREATE TABLE IF NOT EXISTS pw_fans_log (
    time timestamptz NOT NULL,
    metric_name text NOT NULL,
    value double precision,
    PRIMARY KEY (time, metric_name)
);
SELECT create_hypertable('pw_fans_log', 'time', chunk_time_interval => interval '7 days', if_not_exists => true);
ALTER TABLE pw_fans_log SET (timescaledb.compress, timescaledb.compress_segmentby = 'metric_name');
SELECT add_compression_policy('pw_fans_log', compress_after => interval '7 days', if_not_exists => true);

-- Per-pack POD (charge state / nominal energy) fields, same narrow pattern.
CREATE TABLE IF NOT EXISTS pw_pod_log (
    time timestamptz NOT NULL,
    metric_name text NOT NULL,
    value double precision,
    PRIMARY KEY (time, metric_name)
);
SELECT create_hypertable('pw_pod_log', 'time', chunk_time_interval => interval '7 days', if_not_exists => true);
-- See pw_autogen_1m's "source" column comment above (used for the
-- 'backup_reserve_percent' metric written by tools/tesla-history).
ALTER TABLE pw_pod_log ADD COLUMN IF NOT EXISTS source text;
ALTER TABLE pw_pod_log SET (timescaledb.compress, timescaledb.compress_segmentby = 'metric_name');
SELECT add_compression_policy('pw_pod_log', compress_after => interval '7 days', if_not_exists => true);

-- Per-pack temperature fields, same narrow pattern.
CREATE TABLE IF NOT EXISTS pw_pwtemps_log (
    time timestamptz NOT NULL,
    metric_name text NOT NULL,
    value double precision,
    PRIMARY KEY (time, metric_name)
);
SELECT create_hypertable('pw_pwtemps_log', 'time', chunk_time_interval => interval '7 days', if_not_exists => true);
ALTER TABLE pw_pwtemps_log SET (timescaledb.compress, timescaledb.compress_segmentby = 'metric_name');
SELECT add_compression_policy('pw_pwtemps_log', compress_after => interval '7 days', if_not_exists => true);

-- Alerts: narrow format (dynamic jsonb_each unpivot in aggregate_alerts_log.sql
-- means a new Tesla alert type needs zero code changes). Wider chunk interval
-- and permanent retention (matches InfluxDB's alerts RP -- no retention policy
-- is added for this table, unlike the raw ingestion tables).
CREATE TABLE IF NOT EXISTS pw_alerts_log (
    time timestamptz NOT NULL,
    alert_name text NOT NULL,
    value double precision,
    PRIMARY KEY (time, alert_name)
);
SELECT create_hypertable('pw_alerts_log', 'time', chunk_time_interval => interval '30 days', if_not_exists => true);
ALTER TABLE pw_alerts_log SET (timescaledb.compress, timescaledb.compress_segmentby = 'alert_name');
SELECT add_compression_policy('pw_alerts_log', compress_after => interval '30 days', if_not_exists => true);

-- Weather: narrow format since the field set is controlled by OpenWeatherMap,
-- not this project. text_value holds categorical/string fields (weather_main,
-- weather_icon, name, country, ...) via last(value, time); value holds numerics.
CREATE TABLE IF NOT EXISTS pw_weather_log (
    time timestamptz NOT NULL,
    metric_name text NOT NULL,
    value double precision,
    text_value text,
    PRIMARY KEY (time, metric_name)
);
SELECT create_hypertable('pw_weather_log', 'time', chunk_time_interval => interval '7 days', if_not_exists => true);
ALTER TABLE pw_weather_log SET (timescaledb.compress, timescaledb.compress_segmentby = 'metric_name');
SELECT add_compression_policy('pw_weather_log', compress_after => interval '7 days', if_not_exists => true);

-- Checkpoint table for the one-time InfluxDB -> TimescaleDB historical
-- migration (timescaledb/migrate/*.py). Not a hypertable -- tiny, low churn.
-- "source" identifies which InfluxDB instance a checkpoint came from (see
-- migrate_common.get_config()'s source_key) -- the migration source is a
-- runtime prompt (setup.sh can point it at an external InfluxDB server, not
-- just this stack's own container), so a checkpoint from one source must
-- never be read as "done" for a different source re-run.
CREATE TABLE IF NOT EXISTS migration_progress (
    source_measurement text NOT NULL,
    source text NOT NULL DEFAULT '',
    year integer NOT NULL,
    month integer NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    row_count integer,
    migrated_at timestamptz,
    PRIMARY KEY (source_measurement, source, year, month)
);
