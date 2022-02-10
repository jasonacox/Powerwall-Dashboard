#!/bin/bash
#
# Interactive Setup Script for powerwall_monitor
# by Jason Cox - 21 Jan 2022

echo "Powerwall Monitor - SETUP"
echo "-----------------------------------------"

# Replace Credentials 
echo "Enter credentials for Powerwall..."
read -p 'Password: ' PASSWORD
read -p 'Email: ' EMAIL
read -p 'IP Address: ' IP
read -p 'Timezone (default America/Los_Angeles): ' TZ

echo ""
echo "Updating..."
sed -i .bak "s/password/${PASSWORD}/g" powerwall.yml
sed -i .bak "s/email@example.com/${EMAIL}/g" powerwall.yml
sed -i .bak "s/192.168.91.1/${IP}/g" powerwall.yml
if [ -z "${TZ}" ]; then echo "Using default TZ"; else ./tz.sh "${TZ}"; fi
echo "-----------------------------------------"

# Build Docker
echo "Running Docker-Compose..."
docker-compose -f powerwall.yml up -d
echo "-----------------------------------------"

# Set up Influx
echo "Setting up InfluxDB..."
echo "Waiting for start..."
sleep 5
echo "Setup InfluxDB Data..."
docker exec -it influxdb influx -import -path=/var/lib/influxdb/influxdb.sql
sleep 5

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