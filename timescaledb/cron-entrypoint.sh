#!/bin/sh
# Entrypoint for the aggregate-cron sidecar container.
# Applies timescaledb/schema.sql once, then loops forever: run the raw-table
# hypertable bootstrap (safe no-op once done) and every aggregate_*.sql script
# on a 1-minute cadence. kwh_backfill.sql is a manual repair tool, not part of
# this loop -- see its own header comment.
set -u

TZ_VALUE="${TZ:-UTC}"
PGHOST="${TIMESCALEDB_HOST:-timescaledb}"
PGPORT="${TIMESCALEDB_PORT:-5432}"
export PGPASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
export PGSSLMODE="${TIMESCALEDB_SSLMODE:-disable}"

SQL_DIR="/timescaledb"
AGG_DIR="${SQL_DIR}/aggregate"

psql_run() {
    psql -h "$PGHOST" -p "$PGPORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
         -v ON_ERROR_STOP=1 -v tz="$TZ_VALUE" -q "$@"
}

echo "aggregate-cron: waiting for TimescaleDB at ${PGHOST}:${PGPORT}..."
until psql_run -c 'SELECT 1' >/dev/null 2>&1; do
    sleep 2
done
echo "aggregate-cron: TimescaleDB is up."

echo "aggregate-cron: applying schema (idempotent)..."
psql_run -f "${SQL_DIR}/schema.sql" || echo "aggregate-cron: [warn] schema.sql reported errors above"

echo "aggregate-cron: starting cron loop (every 60s)..."
while true; do
    psql_run -f "${AGG_DIR}/bootstrap_raw_tables.sql" \
        || echo "aggregate-cron: [error] bootstrap_raw_tables.sql failed"

    for f in "${AGG_DIR}"/aggregate_*.sql; do
        psql_run -f "$f" || echo "aggregate-cron: [error] $(basename "$f") failed"
    done

    sleep 60
done
