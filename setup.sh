#!/bin/bash
#
# Interactive Setup Script for Powerwall Dashboard
# by Jason Cox - 21 Jan 2022

# Stop on Errors
set -e

# Set Globals
COMPOSE_ENV_FILE="compose.env"
INFLUXDB_ENV_FILE="influxdb.env"
TELEGRAF_LOCAL="telegraf.local"
PW_ENV_FILE="pypowerwall.env"
GF_ENV_FILE="grafana.env"

if [ ! -f VERSION ]; then
    echo "ERROR: Missing VERSION file. Setup must run from installation directory."
    echo ""
    exit 1
fi
VERSION=`cat VERSION`

echo "Powerwall Dashboard (v${VERSION}) - SETUP"
echo "-----------------------------------------"

# Verify not running as root
if [ "$EUID" -eq 0 ]; then
    echo "ERROR: Running this as root will cause permission issues."
    echo ""
    echo "Please ensure your local user is in the docker group and run without sudo."
    echo "   sudo usermod -aG docker \$USER"
    echo "   $0"
    echo ""
    exit 1
fi

# Verify user in docker group (not required for Windows Git Bash)
if ! type winpty > /dev/null 2>&1; then
    if ! $(id -Gn 2>/dev/null | grep -qE " docker( |$)"); then
        echo "WARNING: You do not appear to be in the docker group."
        echo ""
        echo "Please ensure your local user is in the docker group and run without sudo."
        echo "   sudo usermod -aG docker \$USER"
        echo "   $0"
        echo ""
        read -r -p "Setup - Proceed? [y/N] " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
        then
            echo ""
        else
            echo "Cancel"
            exit 1
        fi
    fi
fi

# Windows Git Bash docker exec compatibility fix
if type winpty > /dev/null 2>&1; then
    shopt -s expand_aliases
    alias docker="winpty -Xallow-non-tty -Xplain docker"
fi

# Service Running Helper Function
running() {
    local url=${1:-http://localhost:80}
    local code=${2:-200}
    local status=$(curl --head --location --connect-timeout 5 --write-out %{http_code} --silent --output /dev/null ${url})
    [[ $status == ${code} ]]
}

# Docker Dependency Check
if ! docker info > /dev/null 2>&1; then
    echo "ERROR: docker is not available or not running."
    echo "This script requires docker, please install and try again."
    exit 1
fi
if ! docker-compose version > /dev/null 2>&1; then
    if ! docker compose version > /dev/null 2>&1; then
        echo "ERROR: docker-compose is not available or not running."
        echo "This script requires docker-compose or docker compose."
        echo "Please install and try again."
        exit 1
    fi
fi

# Check PW_ENV_FILE for existing configuration
if [ ! -f ${PW_ENV_FILE} ]; then
    choice=""
    config="None"
elif grep -qE "^PW_HOST=.+" "${PW_ENV_FILE}"; then
    choice="[1] "
    config="Local Access"
else
    choice="[2] "
    config="Tesla Cloud"
fi

# Prompt for configuration
echo "Select configuration mode:"
echo ""
echo "Current: ${config}"
echo ""
echo " 1 - Local Access (Powerwall 1, 2, or + using extended data from Tesla Gateway on LAN) - Default"
echo " 2 - Tesla Cloud  (Solar-only, Powerwall 1, 2, +, or 3 using data from Tesla Cloud)"
echo ""
while :; do
    read -r -p "Select mode: ${choice}" response
    if [ "${response}" == "1" ]; then
        selected="Local Access"
    elif [ "${response}" == "2" ]; then
        selected="Tesla Cloud"
    elif [ -z "${response}" ] && [ ! -z "${choice}" ]; then
        selected="${config}"
    else
        continue
    fi
    if [ ! -z "${choice}" ] && [ "${selected}" != "${config}" ]; then
        echo ""
        read -r -p "You are already using the ${config} configuration, are you sure you wish to change? [y/N] " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
        then
            config="${selected}"
            rm ${PW_ENV_FILE}
            echo ""
            break
        else
            echo "Cancel"
            exit 1
        fi
    else
        config="${selected}"
        echo ""
        break
    fi
done

# Create default docker compose env file if needed.
if [ ! -f ${COMPOSE_ENV_FILE} ]; then
    cp "${COMPOSE_ENV_FILE}.sample" "${COMPOSE_ENV_FILE}"
fi

# Check if running as non-default user (not required for Windows Git Bash)
if ! type winpty > /dev/null 2>&1; then
    notset=0
    if [ -z "${PWD_USER}" ]; then
        PWD_USER="1000:1000"
        notset=1
    fi
    if [ "${PWD_USER}" == "1000:1000" ]; then
        desc="normal default"
        name="Default"
    else
        desc="configured user"
        name="  Saved"
    fi
    CURRENT_USER="$(id -u):$(id -g)"
    if [ "${CURRENT_USER}" != "${PWD_USER}" ]; then
        echo "WARNING: Your current user uid/gid does not match the ${desc}."
        echo ""
        echo "Current - ${CURRENT_USER}"
        echo "${name} - ${PWD_USER}"
        echo ""
        echo "Do you wish to configure the dashboard to run as the current user?"
        echo "(this is typically required to avoid permission issues)"
        echo ""
        read -r -p "Run as current user? (${CURRENT_USER}) [Y/n] " response
        if [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
            echo ""
            echo "No problem. If you have permission issues, edit ${COMPOSE_ENV_FILE} or re-run setup."
            echo ""
        else
            # Update PWD_USER and save to docker compose env file
            if [ $notset -eq 1 ]; then
                if grep -q "^#PWD_USER=" "${COMPOSE_ENV_FILE}"; then
                    sed -i.bak "s@^#PWD_USER=.*@PWD_USER=\"${CURRENT_USER}\"@g" "${COMPOSE_ENV_FILE}"
                else
                    echo -e "\nPWD_USER=\"${CURRENT_USER}\"" >> "${COMPOSE_ENV_FILE}"
                fi
            else
                sed -i.bak "s@^PWD_USER=.*@PWD_USER=\"${CURRENT_USER}\"@g" "${COMPOSE_ENV_FILE}"
            fi
            echo ""
        fi
    fi
fi

# Check for RPi Issue with Buster
if [[ -f "/etc/os-release" ]]; then
    OS_VER=`grep PRETTY /etc/os-release | cut -d= -f2 | cut -d\" -f2`
    if [[ "$OS_VER" == "Raspbian GNU/Linux 10 (buster)" ]]
    then
        echo "WARNING: You are running ${OS_VER}"
        echo "    This OS version has a bug in the libseccomp2 library that"
        echo "    causes the pypowerwall container to fail."
        echo "    See details: https://github.com/jasonacox/Powerwall-Dashboard/issues/56"
        echo ""
        read -r -p "Setup - Proceed? [y/N] " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
        then
            echo ""
        else
            echo "Cancel"
            exit 1
        fi
    fi
fi

CURRENT=`cat tz`

echo "Timezone (leave blank for ${CURRENT})"
read -p 'Enter Timezone: ' TZ
echo ""

# Powerwall Credentials
if [ -f ${PW_ENV_FILE} ]; then
    echo "Current Credentials:"
    echo ""
    cat ${PW_ENV_FILE}
    echo ""
    read -r -p "Update these credentials? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        rm ${PW_ENV_FILE}
        echo ""
    else
        echo "Using existing ${PW_ENV_FILE}."
    fi
fi

# Create Powerwall Settings
if [ ! -f ${PW_ENV_FILE} ]; then
    if [ "${config}" == "Local Access" ]; then
        echo "Enter credentials for Powerwall..."
        while [ -z "${PASSWORD}" ]; do
            read -p 'Password: ' PASSWORD
        done
        while [ -z "${EMAIL}" ]; do
            read -p 'Email: ' EMAIL
        done
        read -p 'IP Address (leave blank to scan network): ' IP
    else
        echo "Enter email address for Tesla Account..."
        while [ -z "${EMAIL}" ]; do
            read -p 'Email: ' EMAIL
        done
    fi
    echo "PW_EMAIL=${EMAIL}" > ${PW_ENV_FILE}
    echo "PW_PASSWORD=${PASSWORD}" >> ${PW_ENV_FILE}
    echo "PW_HOST=${IP}" >> ${PW_ENV_FILE}
    echo "PW_TIMEZONE=America/Los_Angeles" >> ${PW_ENV_FILE}
    echo "TZ=America/Los_Angeles" >> ${PW_ENV_FILE}
    echo "PW_DEBUG=no" >> ${PW_ENV_FILE}
    echo "PW_STYLE=grafana-dark" >> ${PW_ENV_FILE}
fi

# Create default telegraf local file if needed.
if [ ! -f ${TELEGRAF_LOCAL} ]; then
    cp "${TELEGRAF_LOCAL}.sample" "${TELEGRAF_LOCAL}"
fi

# Create InfluxDB env file if missing (required in 3.0.7)
if [ ! -f ${INFLUXDB_ENV_FILE} ]; then
    cp "${INFLUXDB_ENV_FILE}.sample" "${INFLUXDB_ENV_FILE}"
fi

# Create Grafana Settings if missing (required in 2.4.0)
if [ ! -f ${GF_ENV_FILE} ]; then
    cp "${GF_ENV_FILE}.sample" "${GF_ENV_FILE}"
fi

echo ""
if [ -z "${TZ}" ]; then
    echo "Using ${CURRENT} timezone..."
    ./tz.sh "${CURRENT}"
else
    echo "Setting ${TZ} timezone..."
    ./tz.sh "${TZ}"
fi
echo "-----------------------------------------"
echo ""

# Optional - Setup Weather Data
if [ -f weather.sh ]; then
    ./weather.sh setup
fi

# Build Docker in current environment
./compose-dash.sh up -d
echo "-----------------------------------------"

# Run Local Access mode network scan
if [ "${config}" == "Local Access" ] && ! grep -qE "^PW_HOST=.+" "${PW_ENV_FILE}"; then
    echo "Running network scan... (press Ctrl-C to interrupt)"
    docker exec -it pypowerwall python3 -m pypowerwall scan -ip=$(ip route get 8.8.8.8 | awk '{ print $NF }')
    echo "-----------------------------------------"
    echo "Enter address for Powerwall... (or leave blank to switch to Tesla Cloud mode)"
    read -p 'IP Address: ' IP
    echo ""
    if [ -z "${IP}" ]; then
        config="Tesla Cloud"
    fi
    sed -i.bak "s@^PW_HOST=.*@PW_HOST=${IP}@g" "${PW_ENV_FILE}"
    ./compose-dash.sh up -d
    echo "-----------------------------------------"
fi

# Run Tesla Cloud mode setup
if [ "${config}" == "Tesla Cloud" ]; then
    docker exec -it pypowerwall python3 -m pypowerwall setup -email=$(grep -E "^PW_EMAIL=.+" "${PW_ENV_FILE}" | cut -d= -f2)
    echo "Restarting..."
    docker restart pypowerwall
    echo "-----------------------------------------"
fi

# Set up Influx
echo "Waiting for InfluxDB to start..."
until running http://localhost:8086/ping 204 2>/dev/null; do
    printf '.'
    sleep 5
done
echo " up!"
sleep 2
echo "Setup InfluxDB Data..."
docker exec --tty influxdb sh -c "influx -import -path=/var/lib/influxdb/influxdb.sql"
sleep 2
# Execute Run-Once queries for initial setup.
cd influxdb
for f in run-once*.sql; do
    if [ ! -f "${f}.done" ]; then
        echo "Executing single run query $f file..."
        docker exec --tty influxdb sh -c "influx -import -path=/var/lib/influxdb/${f}"
        echo "OK" > "${f}.done"
    fi
done
cd ..

# Restart weather411 to force a sample
if [ -f weather/weather411.conf ]; then
    echo "Fetching local weather..."
    docker restart weather411
fi

# Display Final Instructions
if ! grep -qE "^PW_HOST=.+" "${PW_ENV_FILE}"
then
    DASHBOARD="'dashboard.json' or 'dashboard-solar-only.json'"
else
    DASHBOARD="'dashboard.json'"
fi
cat << EOF
------------------[ Final Setup Instructions ]-----------------

Open Grafana at http://localhost:9000/ ... use admin/admin for login.

Follow these instructions for *Grafana Setup*:

* From 'Configuration\Data Sources' add 'InfluxDB' database with:
  - Name: 'InfluxDB'
  - URL: 'http://influxdb:8086'
  - Database: 'powerwall'
  - Min time interval: '5s'
  - Click "Save & test" button

* From 'Configuration\Data Sources' add 'Sun and Moon' database with:
  - Name: 'Sun and Moon'
  - Enter your latitude and longitude (tool here: https://bit.ly/3wYNaI1 )
  - Click "Save & test" button

* From 'Dashboard\Browse', select 'New/Import', browse to ${PWD}/dashboards
  and upload ${DASHBOARD}.

EOF
