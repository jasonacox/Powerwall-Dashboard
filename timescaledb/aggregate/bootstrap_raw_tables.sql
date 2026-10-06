-- Raw ingestion tables (http, alerts, powerwall_dashboard) are created lazily
-- by Telegraf's outputs.postgresql on its first write -- they don't exist yet
-- on a fresh install, so they can't be set up in timescaledb/schema.sql.
-- powerwall_dashboard is the ver.sh version-stat table (see
-- telegraf-timescale.conf's inputs.exec block). (weather is not one of
-- these -- weather411 writes pw_weather_log directly, no raw table or
-- Telegraf polling involved, see weather/server.py.)
-- Normally telegraf-timescale.conf's create_templates already makes each one
-- a hypertable at the moment Telegraf creates it (see that file), so the
-- create_hypertable call below is a defensive fallback for the rare case that
-- didn't happen. The retention policy always needs to be added here though
-- (create_templates has no equivalent for that). Safe to run every cron
-- cycle -- every statement is idempotent/no-ops once done. Not compressed:
-- short retention, constant insert churn, little benefit.
DO $$
DECLARE
  tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['http', 'alerts', 'powerwall_dashboard'] LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = tbl
    ) THEN
      IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.hypertables
        WHERE hypertable_name = tbl
      ) THEN
        EXECUTE format(
          'SELECT create_hypertable(%L, %L, chunk_time_interval => interval %L, migrate_data => true, if_not_exists => true)',
          tbl, 'time', '1 day'
        );
      END IF;
      EXECUTE format(
        'SELECT add_retention_policy(%L, drop_after => interval %L, if_not_exists => true)',
        tbl, '3 days'
      );
    END IF;
  END LOOP;
END $$;
