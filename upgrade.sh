#!/bin/bash

# Stop on Errors
set -e

# Because this file can be upgrade, don't use it to run the upgrade
if [ "$0" == "upgrade.sh" ]
  then
    # Grab latest upgrade script from github and run it
    curl -L --output tmp.sh https://raw.githubusercontent.com/jasonacox/Powerwall-Dashboard/main/upgrade.sh
    exec bash tmp.sh upgrade
fi

echo "Upgrade Powerwall-Dashboard"
echo "---------------------------"
echo "This script will upgrade you to the latest version without"
echo "removing existing data. A backup is still recommended."
echo ""

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

# Set Timezone 
echo ""
echo "Setting Timezone back to ${TZ}..."
./tz.sh "${TZ}"

# Update Influxdb
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
