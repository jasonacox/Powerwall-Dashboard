#!/bin/bash
#
# Interactive Setup Script for Powerwall Dashboard
# by Jason Cox - 21 Jan 2022

# Stop on Errors
set -e

# Change to setup directory
cd $(dirname "$0")
VERSION=`git describe --tag --long --dirty=-custom`

echo "Powerwall Dashboard (${VERSION}) - SETUP"
echo "-----------------------------------------"

# Verify not running as root
if [ "$EUID" -eq 0 ]; then 
  echo "ERROR: Running this as root will cause permission issues."
  echo ""
  echo "Please ensure your local user in in the docker group and run without sudo."
  echo "   sudo usermod -aG docker \$USER"
  echo "   $0"
  echo ""
  exit 1
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

PW_ENV_FILE="pypowerwall.env"
COMPOSE_ENV_FILE="compose.env"
TELEGRAF_LOCAL="telegraf.local"
GF_ENV_FILE="grafana.env"

# If tz file exists use its value
if [ -f tz ]; then
    CURRENT=`cat tz`
else
    # Try to infer TZ from system
    if [ -L /etc/localtime ]; then
        CURRENT=$(realpath --relative-base=/usr/share/zoneinfo /etc/localtime)
    fi
    # TODO: add other infer methods for systems not using /etc/localtime link
fi
if [ -z "${CURRENT}" ]; then
    # Use a default
    CURRENT="America/Los_Angeles"
fi

echo "Timezone (leave blank for ${CURRENT})"
read -p 'Enter Timezone: ' TZ
echo ""

# Powerwall Credentials 
if [ -f ${PW_ENV_FILE} ]; then
    echo "Current Powerwall Credentials:"
    echo ""
    cat ${PW_ENV_FILE}
    echo ""
    read -r -p "Update these credentials? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        rm ${PW_ENV_FILE}
    else
        echo "Using existing ${PW_ENV_FILE}."
    fi
fi

# Create Powerwall Settings
if [ ! -f ${PW_ENV_FILE} ]; then
    echo "Enter credentials for Powerwall..."
    read -p 'Password: ' PASSWORD
    read -p 'Email: ' EMAIL
    read -p 'IP Address: ' IP
    echo "PW_EMAIL=${EMAIL}" > ${PW_ENV_FILE}
    echo "PW_PASSWORD=${PASSWORD}" >> ${PW_ENV_FILE}
    echo "PW_HOST=${IP}" >> ${PW_ENV_FILE}
    echo "PW_TIMEZONE=${TZ:-$CURRENT}" >> ${PW_ENV_FILE}
    echo "TZ=${TZ:-$CURRENT}" >> ${PW_ENV_FILE}
    echo "PW_DEBUG=no" >> ${PW_ENV_FILE}
fi

# Create Grafana Settings if missing (required in 2.4.0)
if [ ! -f ${GF_ENV_FILE} ]; then
    cp "${GF_ENV_FILE}.sample" "${GF_ENV_FILE}"
fi

# Create default docker compose env file if needed.
if [ ! -f ${COMPOSE_ENV_FILE} ]; then
    cp "${COMPOSE_ENV_FILE}.sample" "${COMPOSE_ENV_FILE}"
fi

# Create default telegraf local file if needed.
if [ ! -f ${TELEGRAF_LOCAL} ]; then
    cp "${TELEGRAF_LOCAL}.sample" "${TELEGRAF_LOCAL}"
fi

echo ""
if [ -z "${TZ}" ]; then 
    echo "Using ${CURRENT} timezone..."; 
    ./tz.sh -y "${CURRENT}";
else 
    echo "Setting ${TZ} timezone..."; 
    ./tz.sh -y "${TZ}"; 
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

# Set up Influx
echo "Waiting for InfluxDB to start..."
until running http://localhost:8086/ping 204 2>/dev/null; do
    printf '.'
    sleep 5
done
echo " up!"
sleep 2
echo "Setup InfluxDB Data for Powerwall..."
docker exec --tty influxdb sh -c "influx -import -path=/var/lib/influxdb/influxdb.sql"
sleep 2
# Execute Run-Once queries for initial setup.
cd influxdb
for f in run-once*.sql; do 
    if [ ! -f "${f}.done" ]; then
        echo "Executing single run query $f file..."; 
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

# Record installed version
echo "$VERSION" > VERSION

# Display Final Instructions
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

* From 'Dashboard\Browse', select 'New/Import', and upload 'dashboard.json' from
  the ${PWD}/dashboards folder.
  
EOF
