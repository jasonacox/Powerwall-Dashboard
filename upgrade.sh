#!/bin/bash

# Stop on Errors
set -e

# Set Globals
VERSION="2.7.0"
CURRENT="Unknown"
COMPOSE_ENV_FILE="compose.env"
TELEGRAF_LOCAL="telegraf.local"
if [ -f VERSION ]; then
    CURRENT=`cat VERSION`
fi

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
echo ""
git stash
git pull --rebase
echo ""

# Create Grafana Settings if missing (required in 2.4.0)
if [ ! -f grafana.env ]; then
    cp "grafana.env.sample" "grafana.env"
fi

# Check for latest Grafana settings (required in 2.6.2)
if ! grep -q "yesoreyeram-boomtable-panel-1.5.0-alpha.3.zip" grafana.env; then
  echo "Your Grafana envrionmental settings are outdated."
    read -r -p "Upgrade grafana.env? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
    then
        cp "grafana.env" "grafana.env.bak"
        cp "grafana.env.sample" "grafana.env"
        echo "Updated"
        docker stop grafana
        docker rm grafana
    else
        echo "No Change"
    fi
fi

# Silently create default docker compose env file if needed.
if [ ! -f ${COMPOSE_ENV_FILE} ]; then
    cp "${COMPOSE_ENV_FILE}.sample" "${COMPOSE_ENV_FILE}"
fi

# Create default telegraf local file if needed.
if [ ! -f ${TELEGRAF_LOCAL} ]; then
    cp "${TELEGRAF_LOCAL}.sample" "${TELEGRAF_LOCAL}"
fi

# Check to see if Weather Data is Available
if [ ! -f weather/weather411.conf ]; then
    echo "This version (${VERSION}) allows you to add local weather data."
    echo ""
    # Optional - Setup Weather Data
    if [ -f weather.sh ]; then
        ./weather.sh setup
    else
        echo "However, you are missing the weather.sh setup file. Skipping..."
        echo ""
    fi
fi

# Check to see that TZ is set in pypowerwall
if ! grep -q "TZ=" pypowerwall.env; then
    echo "Your pypowerwall envrionmental settings are missing TZ."
    echo "Adding..."
    echo "TZ=America/Los_Angeles" >> pypowerwall.env
fi

# Make sure stack is running
echo ""
echo "Start Powerwall-Dashboard stack..."
./compose-dash.sh up -d

# Set Timezone 
echo ""
echo "Setting Timezone back to ${TZ}..."
./tz.sh "${TZ}"

# Update Influxdb
echo ""
echo "Waiting for InfluxDB to start..."
until running http://localhost:8086/ping 204 2>/dev/null; do
    printf '.'
    sleep 5
done
echo " up!"
sleep 2
echo ""
echo "Add downsample continuous queries to InfluxDB..."
docker exec --tty influxdb sh -c "influx -import -path=/var/lib/influxdb/influxdb.sql"

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

# Delete weather411 for Upgrade
echo ""
echo "Delete and Upgrade weather411 to Latest"
docker stop weather411
docker rm weather411
docker images | grep weather411 | awk '{print $3}' | xargs docker rmi -f

# Restart Stack
echo ""
echo "Restarting Powerwall-Dashboard stack..."
./compose-dash.sh up -d

# Display Final Instructions
cat << EOF

---------------[ Update Dashboard ]---------------
Open Grafana at http://localhost:9000/ 

From 'Dashboard/Browse', select 'New/Import', and
upload 'dashboard.json' from the path below.  

Please note, you may need to select data sources
for 'InfluxDB' and 'Sun and Moon' via the 
dropdowns and use 'Import (Overwrite)' button.  

Use dashboard.json located in: ${PWD}

EOF

# Clean up temporary upgrade script
rm -f tmp.sh
