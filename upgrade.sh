#!/bin/bash

# Stop on Errors
set -e

# Set Globals
VERSION="2.4.3"
CURRENT="Unknown"
if [ -f VERSION ]; then
    CURRENT=`cat VERSION`
fi

# Service Running Helper Function
running() {
    local url=${1:-http://localhost:80}
    local code=${2:-200}
    local status=$(curl --head --location --connect-timeout 5 --write-out %{http_code} --silent --output /dev/null ${url})
    [[ $status == ${code} ]]
}

# Because this file can be upgrade, don't use it to run the upgrade
if [ "$0" != "tmp.sh" ]; then
    # Grab latest upgrade script from github and run it
    curl -sL --output tmp.sh https://raw.githubusercontent.com/jasonacox/Powerwall-Dashboard/main/upgrade.sh
    exec bash tmp.sh upgrade
fi

# Check to see if an upgrade is available
if [ "$VERSION" == "$CURRENT" ]; then
    echo "WARNING: You already have the latest version (v${VERSION})."
    echo ""
fi

echo "Upgrade Powerwall-Dashboard from ${CURRENT} to ${VERSION}"
echo "---------------------------------------------------------------------"
echo "This script will attempt to upgrade you to the latest version without"
echo "removing existing data. A backup is still recommended."
echo ""

# Stop upgrade if the installation is key files are missing
ENV_FILE="pypowerwall.env"
if [ ! -f ${ENV_FILE} ]; then
    echo "ERROR: Missing ${ENV_FILE} - This means you have not run 'setup.sh' or"
    echo "       you have an older version that cannot be updated automatically."
    echo "       Run 'git pull' and resolve any conflicts then run the 'setup.sh'"
    echo "       script to re-enter your Powerwall credentials."
    echo ""
    echo "Exiting"
    exit 1
fi

# Verify Upgrade
read -r -p "Upgrade - Proceed? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
    echo ""
else
    echo "Cancel"
    exit 
fi

# Remember Timezome and Reset to Default
echo "Resetting Timezone to Default..."
DEFAULT="America/Los_Angeles"
TZ=`cat tz`
if [ -z "${TZ}" ]; then 
    TZ="America/Los_Angeles"
fi
./tz.sh "${DEFAULT}"

# Pull from Github
echo ""
echo "Pull influxdb.sql, dashboard.json, telegraf.conf, and other changes..."
git pull 

# Create Grafana Settings if missing (required in 2.4.0)
if [ ! -f grafana.env ]; then
    cp "grafana.env.sample" "grafana.env"
fi

# Make sure stack is running
echo "Start Powerwall-Dashboard stack..."
docker-compose -f powerwall.yml up -d

# Set Timezone 
echo ""
echo "Setting Timezone back to ${TZ}..."
./tz.sh "${TZ}"

# Update Influxdb
echo "Waiting for InfluxDB to start..."
until running http://localhost:8086/ping 204 2>/dev/null; do
    printf '.'
    sleep 5
done
echo " up!"
sleep 2
echo ""
echo "Add downsample continuous queries to InfluxDB..."
docker exec -it influxdb influx -import -path=/var/lib/influxdb/influxdb.sql

# Delete pyPowerwall for Upgrade
echo ""
echo "Delete and Upgrade pyPowerwall to Latest"
docker stop pypowerwall
docker rm pypowerwall
docker images | grep pypowerwall | awk '{print $3}' | xargs docker rmi -f

# Delete telegraf for Upgrade
echo ""
echo "Delete and Upgrade telegraf to Latest"
docker stop telegraf
docker rm telegraf
docker images | grep telegraf | awk '{print $3}' | xargs docker rmi -f

# Restart Stack
echo "Restarting Powerwall-Dashboard stack..."
docker-compose -f powerwall.yml up -d

# Display Final Instructions
cat << EOF

---------------[ Update Dashboard ]---------------
Open Grafana at http://localhost:9000/ 

From 'Dashboard\Manage' (or 'Dashboard\Browse'), 
select 'Import', and upload 'dashboard.json' from
EOF
pwd

echo ""
echo "Done"

# Clean up temporary upgrade script
rm -f tmp.sh
