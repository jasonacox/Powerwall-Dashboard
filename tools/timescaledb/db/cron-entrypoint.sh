#!/bin/sh
# Entrypoint for the aggregate-cron sidecar container.
# Applies schema.sql once (idempotent), then loops forever: run the raw-table
# hypertable bootstrap and every aggregate_*.sql script on a 1-minute cadence.
# kwh_backfill.sql is a manual repair tool, not part of this loop -- see its
# own header comment.
#
# After every pass where all scripts succeeded, /tmp/last_ok is touched; the
# container healthcheck fails if that file is more than 5 minutes old, so a
# silently failing aggregation shows up as "unhealthy".
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
until psql_run -f "${SQL_DIR}/schema.sql"; do
    echo "aggregate-cron: [error] schema.sql failed, retrying in 60s"
    sleep 60
done

echo "aggregate-cron: starting cron loop (every 60s)..."
while true; do
    ok=1
    if ! psql_run -f "${AGG_DIR}/bootstrap_raw_tables.sql"; then
        echo "aggregate-cron: [error] bootstrap_raw_tables.sql failed"
        ok=0
    fi

    for f in "${AGG_DIR}"/aggregate_*.sql; do
        if ! psql_run -f "$f"; then
            echo "aggregate-cron: [error] $(basename "$f") failed"
            ok=0
        fi
    done

    [ "$ok" = 1 ] && touch /tmp/last_ok

    sleep 60
done
