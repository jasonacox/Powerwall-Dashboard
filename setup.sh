#!/bin/bash
#
# Interactive Setup Script for Powerwall Dashboard
# by Jason Cox - 21 Jan 2022

echo "Powerwall Dashboard - SETUP"
echo "-----------------------------------------"

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

ENV_FILE="pypowerwall.env"

read -p 'Timezone (default America/Los_Angeles): ' TZ

# Replace Credentials 
if grep -q changeme ${ENV_FILE}; then
    echo "Enter credentials for Powerwall..."
    read -p 'Password: ' PASSWORD
    read -p 'Email: ' EMAIL
    read -p 'IP Address: ' IP
    echo "PW_EMAIL=${EMAIL}" > ${ENV_FILE}
    echo "PW_PASSWORD=${PASSWORD}" >> ${ENV_FILE}
    echo "PW_HOST=${IP}" >> ${ENV_FILE}
    echo "PW_TIMEZONE=${TZ}" >> ${ENV_FILE}
    echo "PW_DEBUG=no" >> ${ENV_FILE}
else
    echo "Using existing pypowerwall.env file."
fi

echo ""
if [ -z "${TZ}" ]; then echo "Using default TZ"; else ./tz.sh "${TZ}"; fi
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
  - Enter your latitude and longitude (some browsers will use your location)
  - Click "Save & test" button

* From 'Dashboard\Manage' (or 'Dashboard\Browse'), select 'Import', and upload 'dashboard.json' from
EOF
pwd
