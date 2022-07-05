#!/bin/bash
#
# Interactive Setup Script for Powerwall Dashboard
# by Jason Cox - 21 Jan 2022

# Stop on Errors
set -e

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
    echo "ERROR: docker is not available or not runnning."
    echo "This script requires docker, please install and try again."
    exit 1
fi
if ! docker-compose version > /dev/null 2>&1; then
    echo "ERROR: docker-compose is not available or not runnning."
    echo "This script requires docker-compose, please install and try again."
    exit 1
fi

PW_ENV_FILE="pypowerwall.env"
GF_ENV_FILE="grafana.env"
CURRENT=`cat tz`

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
    echo "PW_TIMEZONE=America/Los_Angeles" >> ${PW_ENV_FILE}
    echo "PW_DEBUG=no" >> ${PW_ENV_FILE}
fi

# Create Grafana Settings if missing (required in 2.4.0)
if [ ! -f ${GF_ENV_FILE} ]; then
    cp "${GF_ENV_FILE}.sample" "${GF_ENV_FILE}"
fi

echo ""
if [ -z "${TZ}" ]; then 
    echo "Using ${CURRENT} timezone..."; 
    ./tz.sh "${CURRENT}";
else 
    echo "Setting ${TZ} timezone..."; 
    ./tz.sh "${TZ}"; 
fi
echo "-----------------------------------------"

# Build Docker
echo "Running Docker-Compose..."
docker-compose -f powerwall.yml up -d
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
docker exec -it influxdb influx -import -path=/var/lib/influxdb/influxdb.sql
sleep 2

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

* From 'Dashboard\Manage' (or 'Dashboard\Browse'), select 'Import', and upload 'dashboard.json' from
EOF
pwd
