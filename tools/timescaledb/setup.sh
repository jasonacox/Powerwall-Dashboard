#!/bin/bash
#
# EXPERIMENTAL: Interactive setup for the TimescaleDB (PostgreSQL) datastore
# extension. Adds TimescaleDB as a second, parallel write path alongside your
# existing InfluxDB stack -- InfluxDB is never disabled by this script. See
# ../../timescaledb/README.md for the architecture and README.md (in this
# directory) for more on setup/removal.
#
# Run from the repository root: ./tools/timescaledb/setup.sh

set -e

echo "==========================================================="
echo " TimescaleDB (PostgreSQL) datastore extension -- EXPERIMENTAL"
echo "==========================================================="
echo ""
echo "This adds TimescaleDB as an ADDITIONAL datastore alongside InfluxDB."
echo "It does not disable or affect your existing InfluxDB setup."
echo ""

# Set Globals
COMPOSE_ENV_FILE="compose.env"
INFLUXDB_ENV_FILE="influxdb.env"
GF_ENV_FILE="grafana.env"
TIMESCALEDB_ENV_FILE="timescaledb.env"
EXTEND_FILE="powerwall.extend.yml"
EXTEND_SAMPLE="tools/timescaledb/powerwall.extend.yml.sample"

if [ ! -f VERSION ]; then
    echo "ERROR: Missing VERSION file. Run this from the repository root:"
    echo "   ./tools/timescaledb/setup.sh"
    echo ""
    exit 1
fi

# Verify the base stack has already been set up -- this script only adds
# TimescaleDB on top of it, it doesn't stand up InfluxDB/Grafana/pypowerwall
# from scratch.
for f in "${COMPOSE_ENV_FILE}" "${GF_ENV_FILE}" "${INFLUXDB_ENV_FILE}" weather/weather411.conf tz; do
    if [ ! -f "${f}" ]; then
        echo "ERROR: ${f} not found."
        echo "Run ./setup.sh first to set up the base stack, then re-run this script."
        echo ""
        exit 1
    fi
done

# Create/merge powerwall.extend.yml
if [ -f "${EXTEND_FILE}" ]; then
    if grep -q "^    telegraf-timescale:$" "${EXTEND_FILE}" 2>/dev/null; then
        echo "powerwall.extend.yml already has the TimescaleDB services -- leaving it as-is."
        echo "(Delete/edit it by hand first if you want to re-run this step from scratch.)"
    else
        echo "You already have a powerwall.extend.yml (e.g. for tesla-history or pgadmin)."
        echo "docker compose only reads a single powerwall.extend.yml, so the TimescaleDB"
        echo "services need to be merged into it by hand instead of overwriting the file."
        echo ""
        echo "The services/patches to add are in: ${EXTEND_SAMPLE}"
        echo "Merge them into ${EXTEND_FILE}, then re-run this script to continue setup."
        echo ""
        exit 1
    fi
else
    cp "${EXTEND_SAMPLE}" "${EXTEND_FILE}"
    echo "Created ${EXTEND_FILE} from ${EXTEND_SAMPLE}."
fi

# Create TimescaleDB env file if missing
if [ ! -f "${TIMESCALEDB_ENV_FILE}" ]; then
    cp "${TIMESCALEDB_ENV_FILE}.sample" "${TIMESCALEDB_ENV_FILE}"
    if command -v openssl > /dev/null 2>&1; then
        TSDB_PASSWORD=$(openssl rand -hex 16)
    else
        TSDB_PASSWORD=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
    fi
    sed -i.bak "s@^POSTGRES_PASSWORD=.*@POSTGRES_PASSWORD=${TSDB_PASSWORD}@g" "${TIMESCALEDB_ENV_FILE}"
    echo "Created ${TIMESCALEDB_ENV_FILE} with a random POSTGRES_PASSWORD."
fi

# Bundled container vs. an existing server
CURRENT_TSDB_MODE="bundled"
grep -q "^# EXTMODE-BUNDLED-ONLY-START$" "${EXTEND_FILE}" 2>/dev/null || CURRENT_TSDB_MODE="external"

echo ""
echo "Select TimescaleDB server:"
echo ""
case "${CURRENT_TSDB_MODE}" in
    "external") echo "Current: [2] Existing server" ;;
    *) echo "Current: [1] Bundled container" ;;
esac
echo ""
echo " 1 - Bundled container  (this stack runs its own TimescaleDB) - Default"
echo " 2 - Existing server    (connect to a TimescaleDB/PostgreSQL server you already run)"
echo ""
while :; do
    read -r -p "Select [1/2] (leave blank to keep current): " response
    if [ -z "${response}" ]; then
        TSDB_MODE="${CURRENT_TSDB_MODE}"
        break
    elif [ "${response}" == "1" ]; then
        TSDB_MODE="bundled"
        break
    elif [ "${response}" == "2" ]; then
        TSDB_MODE="external"
        break
    else
        continue
    fi
done

if [ "${TSDB_MODE}" == "external" ]; then
    echo ""
    echo "Prerequisites for an existing server (see ../../timescaledb/README.md):"
    echo " - TimescaleDB 2.x+ (PostgreSQL 13+), with the timescaledb extension"
    echo "   already installed and either already created, or creatable by the"
    echo "   user below (i.e. that user is a superuser, or an admin has already"
    echo "   run CREATE EXTENSION IF NOT EXISTS timescaledb;)"
    echo " - The user below needs privileges to create tables/hypertables/"
    echo "   compression policies in the target database"
    echo " - Reachable on the network from this Docker host"
    echo ""
    CUR_HOST=$(grep -E "^TIMESCALEDB_HOST=" "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
    [ "${CUR_HOST}" == "timescaledb" ] && CUR_HOST=""
    CUR_PORT=$(grep -E "^TIMESCALEDB_PORT=" "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
    CUR_DB=$(grep -E "^POSTGRES_DB=" "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
    CUR_USER=$(grep -E "^POSTGRES_USER=" "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
    CUR_SSLMODE=$(grep -E "^TIMESCALEDB_SSLMODE=" "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
    [ "${CUR_SSLMODE}" == "disable" ] && CUR_SSLMODE="prefer"

    TSDB_HOST=""
    while [ -z "${TSDB_HOST}" ]; do
        read -r -p "TimescaleDB host or IP${CUR_HOST:+ [${CUR_HOST}]}: " input
        TSDB_HOST="${input:-${CUR_HOST}}"
    done
    read -r -p "TimescaleDB port [${CUR_PORT:-5432}]: " input
    TSDB_PORT="${input:-${CUR_PORT:-5432}}"
    read -r -p "Database name [${CUR_DB:-powerwall}]: " input
    TSDB_DBNAME="${input:-${CUR_DB:-powerwall}}"
    read -r -p "Username [${CUR_USER:-telegraf_powerwall}]: " input
    TSDB_USERNAME="${input:-${CUR_USER:-telegraf_powerwall}}"
    CUR_PASSWORD=$(grep -E "^POSTGRES_PASSWORD=" "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
    TSDB_PASSWORD_EXT=""
    while [ -z "${TSDB_PASSWORD_EXT}" ]; do
        read -r -s -p "Password (leave blank to keep current, if any): " input
        echo ""
        if [ -n "${input}" ]; then
            TSDB_PASSWORD_EXT="${input}"
        elif [ -n "${CUR_PASSWORD}" ]; then
            TSDB_PASSWORD_EXT="${CUR_PASSWORD}"
        else
            echo "Password is required the first time you set up an existing server."
        fi
    done
    read -r -p "SSL mode [${CUR_SSLMODE}] (disable/allow/prefer/require/verify-ca/verify-full): " input
    TSDB_SSLMODE="${input:-${CUR_SSLMODE}}"

    sed -i.bak \
        -e "s@^TIMESCALEDB_HOST=.*@TIMESCALEDB_HOST=${TSDB_HOST}@g" \
        -e "s@^TIMESCALEDB_PORT=.*@TIMESCALEDB_PORT=${TSDB_PORT}@g" \
        -e "s@^TIMESCALEDB_SSLMODE=.*@TIMESCALEDB_SSLMODE=${TSDB_SSLMODE}@g" \
        -e "s@^POSTGRES_DB=.*@POSTGRES_DB=${TSDB_DBNAME}@g" \
        -e "s@^POSTGRES_USER=.*@POSTGRES_USER=${TSDB_USERNAME}@g" \
        -e "s@^POSTGRES_PASSWORD=.*@POSTGRES_PASSWORD=${TSDB_PASSWORD_EXT}@g" \
        "${TIMESCALEDB_ENV_FILE}"

    # Remove the bundled-only timescaledb service + its depends_on entries
    # from the extend file -- an external server means this stack shouldn't
    # run its own local TimescaleDB container at all.
    if grep -q "^# EXTMODE-BUNDLED-ONLY-START$" "${EXTEND_FILE}"; then
        sed -i.bak '/# EXTMODE-BUNDLED-ONLY-START/,/# EXTMODE-BUNDLED-ONLY-END/d' "${EXTEND_FILE}"
        echo "Removed the bundled timescaledb service from ${EXTEND_FILE} (external mode)."
    fi
else
    sed -i.bak \
        -e "s@^TIMESCALEDB_HOST=.*@TIMESCALEDB_HOST=timescaledb@g" \
        -e "s@^TIMESCALEDB_PORT=.*@TIMESCALEDB_PORT=5432@g" \
        -e "s@^TIMESCALEDB_SSLMODE=.*@TIMESCALEDB_SSLMODE=disable@g" \
        "${TIMESCALEDB_ENV_FILE}"

    # Switching back to bundled from a previous external-mode run: the
    # bundled-only blocks were deleted from powerwall.extend.yml, and
    # stitching them back in place (service block + 3 separate depends_on
    # sub-blocks) isn't safely reversible by text surgery once the
    # surrounding content may have been hand-edited. Ask instead.
    if ! grep -q "^# EXTMODE-BUNDLED-ONLY-START$" "${EXTEND_FILE}"; then
        echo ""
        echo "Switching from external back to bundled mode requires the TimescaleDB"
        echo "services to be re-added to ${EXTEND_FILE}."
        echo "If you haven't hand-edited that file beyond this script's own changes,"
        echo "the simplest path is to remove the TimescaleDB-related services from it"
        echo "(or delete the whole file, if TimescaleDB is the only thing in it) and"
        echo "re-run this script, which will recreate it fresh from:"
        echo "   ${EXTEND_SAMPLE}"
        echo ""
        exit 1
    fi
fi
echo ""
echo "TimescaleDB server: ${TSDB_MODE}"
echo "-----------------------------------------"
echo ""

# Add/sync weather411's [TimescaleDB] section (never touches [InfluxDB])
if [ -f weather/weather411.conf ]; then
    if ! grep -q "^\[TimescaleDB\]" weather/weather411.conf; then
        sed -n '/^\[TimescaleDB\]/,/^$/p' weather/weather411.conf.sample >> weather/weather411.conf
    fi
    TSDB_HOST=$(grep -E "^TIMESCALEDB_HOST=" "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
    TSDB_PORT=$(grep -E "^TIMESCALEDB_PORT=" "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
    TSDB_USER=$(grep -E "^POSTGRES_USER=" "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
    TSDB_PASS=$(grep -E "^POSTGRES_PASSWORD=" "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
    TSDB_DB=$(grep -E "^POSTGRES_DB=" "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
    TSDB_SSLMODE=$(grep -E "^TIMESCALEDB_SSLMODE=" "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
    awk -v host="${TSDB_HOST}" -v port="${TSDB_PORT}" \
        -v user="${TSDB_USER}" -v pass="${TSDB_PASS}" -v db="${TSDB_DB}" \
        -v sslmode="${TSDB_SSLMODE}" '
        /^\[TimescaleDB\]/ { section="timescaledb" }
        /^\[/ && !/^\[TimescaleDB\]/ {
            if (section=="timescaledb" && !seen_sslmode) { print "SSLMODE = " sslmode; seen_sslmode=1 }
            section=""
        }
        section=="timescaledb" && /^ENABLE =/ { $0 = "ENABLE = yes" }
        section=="timescaledb" && /^HOST =/ { $0 = "HOST = " host }
        section=="timescaledb" && /^PORT =/ { $0 = "PORT = " port }
        section=="timescaledb" && /^DB =/ { $0 = "DB = " db }
        section=="timescaledb" && /^USER =/ { $0 = "USER = " user }
        section=="timescaledb" && /^PASSWORD =/ { $0 = "PASSWORD = " pass }
        section=="timescaledb" && /^SSLMODE =/ { $0 = "SSLMODE = " sslmode; seen_sslmode=1 }
        { print }
        END { if (section=="timescaledb" && !seen_sslmode) print "SSLMODE = " sslmode }
    ' weather/weather411.conf > weather/weather411.conf.new && mv weather/weather411.conf.new weather/weather411.conf
    echo "Updated weather/weather411.conf's [TimescaleDB] section."
fi

# Bring the extension up
echo ""
echo "Starting TimescaleDB extension services..."
./compose-dash.sh up -d

TSDB_HOST=$(grep -E '^TIMESCALEDB_HOST=' "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
TSDB_PORT=$(grep -E '^TIMESCALEDB_PORT=' "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
TSDB_SSLMODE=$(grep -E '^TIMESCALEDB_SSLMODE=' "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
TSDB_USER=$(grep -E '^POSTGRES_USER=' "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
TSDB_PASS=$(grep -E '^POSTGRES_PASSWORD=' "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)
TSDB_DBNAME=$(grep -E '^POSTGRES_DB=' "${TIMESCALEDB_ENV_FILE}" | cut -d= -f2)

echo "Waiting for TimescaleDB (${TSDB_HOST}:${TSDB_PORT}) to be reachable..."
until docker exec -e PGHOST="${TSDB_HOST}" -e PGPORT="${TSDB_PORT}" -e PGSSLMODE="${TSDB_SSLMODE}" \
    aggregate-cron pg_isready -U "${TSDB_USER}" -d "${TSDB_DBNAME}" > /dev/null 2>&1; do
    printf '.'
    sleep 5
done
echo " up!"
sleep 2
echo "Setup TimescaleDB schema... ('already exists' notices are harmless)"
docker cp timescaledb/schema.sql aggregate-cron:/schema.sql
docker exec -e PGHOST="${TSDB_HOST}" -e PGPORT="${TSDB_PORT}" -e PGSSLMODE="${TSDB_SSLMODE}" \
    -e PGPASSWORD="${TSDB_PASS}" aggregate-cron sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /schema.sql'

echo ""
echo "TimescaleDB can optionally import InfluxDB history."
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

        NETWORK=$(docker inspect aggregate-cron --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')
        echo "Running migration (this can take a while for large histories)..."
        # Credentials go through a temp --env-file (deleted right after) rather
        # than -e on the command line, so the InfluxDB password doesn't sit in
        # plaintext in `docker inspect`/`ps` output.
        INFLUX_MIGRATE_ENV=$(mktemp)
        chmod 600 "${INFLUX_MIGRATE_ENV}"
        {
            echo "INFLUX_HOST=${MIGRATE_INFLUX_HOST}"
            echo "INFLUX_PORT=${MIGRATE_INFLUX_PORT}"
            echo "INFLUX_DB=${MIGRATE_INFLUX_DB}"
            echo "INFLUX_USER=${MIGRATE_INFLUX_USER}"
            echo "INFLUX_PASSWORD=${MIGRATE_INFLUX_PASSWORD}"
        } > "${INFLUX_MIGRATE_ENV}"
        # -it only when attached to a real terminal, so this doesn't fail
        # when run non-interactively (e.g. piped/scripted).
        TTY_FLAGS="-i"
        [ -t 0 ] && TTY_FLAGS="-it"
        docker run --rm ${TTY_FLAGS} \
            --network "${NETWORK}" \
            -v "$(pwd)/timescaledb:/timescaledb:ro" \
            --env-file "${TIMESCALEDB_ENV_FILE}" \
            --env-file "${INFLUX_MIGRATE_ENV}" \
            -e PGHOST="${TSDB_HOST}" \
            -e PGPORT="${TSDB_PORT}" \
            -e PGSSLMODE="${TSDB_SSLMODE}" \
            -e TZ="$(cat tz)" \
            python:3-alpine sh -c "apk add --no-cache --quiet postgresql-client && pip install --quiet psycopg2-binary==2.9.* requests==2.* && python3 /timescaledb/migrate/run_all.py"
        rm -f "${INFLUX_MIGRATE_ENV}"
        echo "Migration complete."
        ;;
    *)
        echo "Skipping migration. Run this script again any time to be asked again."
        ;;
esac

# Copy the Grafana TimescaleDB datasource template into place
if [ -f grafana/timescaledb-template.yml ]; then
    cp grafana/timescaledb-template.yml grafana/provisions/datasources/timescaledb.yml
    echo "Installed Grafana TimescaleDB datasource."
fi

echo ""
echo "-----------------------------------------"
echo "TimescaleDB extension setup complete."
echo ""
echo "Import ${PWD}/dashboards/dashboard-timescaledb.json in Grafana"
echo "(Dashboard/New -> Import dashboard) and select \"TimescaleDB (auto"
echo "provisioned)\" for its datasource."
echo ""
echo "Restart weather411 to pick up its new config:"
echo "   docker restart weather411"
echo "-----------------------------------------"
