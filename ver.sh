#!/bin/bash
# This script reads the version of Powerwall Dashboard and timestamp

# Check to see if /etc/telegraf/VERSION exists otherwise use ./VERSION
VER_FILE="/etc/telegraf/VERSION"
if [ ! -f "$VER_FILE" ]; then
  VER_FILE="./VERSION"
fi

# Check to see if the file exists
if [ ! -f "$VER_FILE" ]; then
    echo "powerwall_dashboard version=0,file_ts=\"\""
    exit 0
fi

version=$(cat $VER_FILE)
timestamp=$(date -r $VER_FILE +"%Y-%m-%d")  # Get file modification date

echo "powerwall_dashboard version=\"${version}\",file_ts=\"${timestamp}\""
