#!/bin/bash
#
# EXPERIMENTAL: Interactive setup for the TimescaleDB (PostgreSQL) datastore
# extension. Adds TimescaleDB as a second, parallel datastore alongside your
# existing InfluxDB stack -- InfluxDB is never changed or disabled by this
# script. See README.md in this directory for details and removal.
#
# Run from the repository root: ./tools/timescaledb/setup.sh
# Safe to re-run (e.g. after changing your timezone with ./tz.sh).

set -e

echo "==========================================================="
echo " TimescaleDB (PostgreSQL) datastore extension -- EXPERIMENTAL"
echo "==========================================================="
echo ""
echo "This adds TimescaleDB as an ADDITIONAL datastore alongside InfluxDB."
echo "It does not disable or affect your existing InfluxDB setup."
echo ""

# Set Globals
TSDB_DIR="tools/timescaledb"
TIMESCALEDB_ENV_FILE="${TSDB_DIR}/timescaledb.env"
EXTEND_FILE="powerwall.extend.yml"
EXTEND_SAMPLE="${TSDB_DIR}/powerwall.extend.yml.sample"
GF_DATASOURCE="grafana/provisions/datasources/timescaledb.yml"

if [ ! -f VERSION ] || [ ! -f "${EXTEND_SAMPLE}" ]; then
    echo "ERROR: Run this from the repository root:"
    echo "   ./tools/timescaledb/setup.sh"
    echo ""
    exit 1
fi

# This script only adds TimescaleDB on top of an existing stack -- it doesn't
# set up InfluxDB/Grafana/pypowerwall from scratch.
for f in compose.env grafana.env tz; do
    if [ ! -f "${f}" ]; then
        echo "ERROR: ${f} not found."
        echo "Run ./setup.sh first to set up the base stack, then re-run this script."
        echo ""
        exit 1
    fi
done

# Create powerwall.extend.yml (or ask for a hand-merge if one already exists)
if [ -f "${EXTEND_FILE}" ]; then
    if grep -q "^    telegraf-timescale:" "${EXTEND_FILE}"; then
        echo "${EXTEND_FILE} already has the TimescaleDB services -- leaving it as-is."
    else
        echo "You already have a ${EXTEND_FILE} (e.g. for tesla-history)."
        echo "docker compose only reads one ${EXTEND_FILE}, so merge the services from"
        echo "   ${EXTEND_SAMPLE}"
        echo "into it by hand, then re-run this script."
        echo ""
        exit 1
    fi
else
    cp "${EXTEND_SAMPLE}" "${EXTEND_FILE}"
    echo "Created ${EXTEND_FILE} from ${EXTEND_SAMPLE}."
fi

# Create the env file with a random password if missing
if [ ! -f "${TIMESCALEDB_ENV_FILE}" ]; then
    cp "${TIMESCALEDB_ENV_FILE}.sample" "${TIMESCALEDB_ENV_FILE}"
    if command -v openssl > /dev/null 2>&1; then
        TSDB_PASSWORD=$(openssl rand -hex 16)
    else
        TSDB_PASSWORD=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
    fi
    sed -i.bak "s@^POSTGRES_PASSWORD=.*@POSTGRES_PASSWORD=${TSDB_PASSWORD}@" "${TIMESCALEDB_ENV_FILE}"
    rm -f "${TIMESCALEDB_ENV_FILE}.bak"
    echo "Created ${TIMESCALEDB_ENV_FILE} with a random POSTGRES_PASSWORD."
fi

# Keep TZ in sync with the stack's timezone
TZ_VALUE=$(cat tz)
sed -i.bak "s@^TZ=.*@TZ=${TZ_VALUE}@" "${TIMESCALEDB_ENV_FILE}"
rm -f "${TIMESCALEDB_ENV_FILE}.bak"
echo "Timezone: ${TZ_VALUE}"

# Install the Grafana datasource BEFORE starting the services -- Grafana only
# reads provisioning files at startup.
cp "${TSDB_DIR}/grafana-datasource.yml" "${GF_DATASOURCE}"
echo "Installed Grafana TimescaleDB datasource."

echo ""
echo "Starting TimescaleDB extension services..."
./compose-dash.sh up -d

# aggregate-cron applies the schema on startup; wait for it before offering
# the migration (which writes into those tables).
echo "Waiting for the TimescaleDB schema to be ready..."
TRIES=0
until [ "$(docker exec aggregate-cron sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" PGSSLMODE="$TIMESCALEDB_SSLMODE" psql -h "$TIMESCALEDB_HOST" -p "$TIMESCALEDB_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT to_regclass('"'"'public.migration_progress'"'"') IS NOT NULL"' 2>/dev/null)" == "t" ]; do
    TRIES=$((TRIES + 1))
    if [ "${TRIES}" -gt 60 ]; then
        echo ""
        echo "ERROR: Schema still not ready after 5 minutes. Check the logs:"
        echo "   docker logs aggregate-cron"
        echo "   docker logs timescaledb"
        exit 1
    fi
    printf '.'
    sleep 5
done
echo " ready!"

echo ""
echo "TimescaleDB can optionally import your InfluxDB history."
read -r -p "Migrate existing InfluxDB data into TimescaleDB now? [y/N] " response
case "${response}" in
    [yY]|[yY][eE][sS])
        read -r -p "InfluxDB host or IP [influxdb]: " input
        MIGRATE_INFLUX_HOST="${input:-influxdb}"
        read -r -p "InfluxDB port [8086]: " input
        MIGRATE_INFLUX_PORT="${input:-8086}"
        read -r -p "InfluxDB database name [powerwall]: " input
        MIGRATE_INFLUX_DB="${input:-powerwall}"
        read -r -p "InfluxDB username (leave blank if none): " input
        MIGRATE_INFLUX_USER="${input}"
        MIGRATE_INFLUX_PASSWORD=""
        if [ -n "${MIGRATE_INFLUX_USER}" ]; then
            read -r -s -p "InfluxDB password: " input
            echo ""
            MIGRATE_INFLUX_PASSWORD="${input}"
        fi

        TSDB_HOST=$(grep -E '^TIMESCALEDB_HOST=' "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
        TSDB_PORT=$(grep -E '^TIMESCALEDB_PORT=' "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
        TSDB_SSLMODE=$(grep -E '^TIMESCALEDB_SSLMODE=' "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
        NETWORK=$(docker inspect aggregate-cron --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')
        echo "Running migration (this can take a while for large histories)..."
        # Credentials go through a temp --env-file (deleted right after) rather
        # than -e on the command line, so the InfluxDB password doesn't show
        # up in `docker inspect`/`ps` output.
        INFLUX_MIGRATE_ENV=$(mktemp)
        chmod 600 "${INFLUX_MIGRATE_ENV}"
        {
            echo "INFLUX_HOST=${MIGRATE_INFLUX_HOST}"
            echo "INFLUX_PORT=${MIGRATE_INFLUX_PORT}"
            echo "INFLUX_DB=${MIGRATE_INFLUX_DB}"
            echo "INFLUX_USER=${MIGRATE_INFLUX_USER}"
            echo "INFLUX_PASSWORD=${MIGRATE_INFLUX_PASSWORD}"
        } > "${INFLUX_MIGRATE_ENV}"
        # -it only when attached to a real terminal
        TTY_FLAGS="-i"
        [ -t 0 ] && TTY_FLAGS="-it"
        docker run --rm ${TTY_FLAGS} \
            --network "${NETWORK}" \
            -v "$(pwd)/${TSDB_DIR}/migrate:/timescaledb/migrate:ro" \
            -v "$(pwd)/${TSDB_DIR}/db:/timescaledb/db:ro" \
            --env-file "${TIMESCALEDB_ENV_FILE}" \
            --env-file "${INFLUX_MIGRATE_ENV}" \
            -e PGHOST="${TSDB_HOST}" \
            -e PGPORT="${TSDB_PORT}" \
            -e PGSSLMODE="${TSDB_SSLMODE}" \
            python:3.12-alpine sh -c "apk add --no-cache --quiet postgresql-client && pip install --quiet psycopg2-binary==2.9.* requests==2.* && python3 /timescaledb/migrate/run_all.py"
        rm -f "${INFLUX_MIGRATE_ENV}"
        echo "Migration complete."
        ;;
    *)
        echo "Skipping migration. Re-run this script any time to be asked again."
        ;;
esac

echo ""
echo "-----------------------------------------"
echo "TimescaleDB extension setup complete."
echo ""
echo "Import ${PWD}/${TSDB_DIR}/dashboard-timescaledb.json in Grafana"
echo "(Dashboards -> New -> Import), select \"TimescaleDB (auto provisioned)\""
echo "for its datasource, and enter ${TZ_VALUE} for Timezone."
echo "-----------------------------------------"
