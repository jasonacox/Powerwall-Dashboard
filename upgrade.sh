#!/bin/bash

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

# Pull from Github
echo "Pull influxdb.sql, dashboard.json, telegraf.conf, and other changes..."
git pull 

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

# Restart Stack
echo "Restarting Powerwall-Dashboard stack..."
docker-compose -f powerwall.yml up -d

# Display Final Instructions
cat << EOF
------------------[ Update Dashboard ]-----------------
Open Grafana at http://localhost:9000/ 

* From 'Dashboard\Manage' (or 'Dashboard\Browse'), select 'Import', and upload 'dashboard.json' from
EOF
pwd

echo ""
echo "Done"
