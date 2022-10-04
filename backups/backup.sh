#!/bin/bash
#
# Backup Script for Powerwall Dashboard
#   https://github.com/jasonacox/Powerwall-Dashboard
#   by Jason Cox - 27 Feb 2022 

# Daily Backup for Powerwall-Dashboard
if [ "$EUID" -ne 0 ]
  then echo "Must run as root"
  exit
fi

# Set values for your environment 
DASHBOARD="/home/user/Powerwall-Dashboard" # Location of Dashboard to backup
BACKUP_FOLDER="${DASHBOARD}/backups"          # Destination folder for backups
KEEP="5"                                      # Days to keep backup

# Check to see if direcotry exists
if [ ! -d "${DASHBOARD}" ]; then
  echo "Dashboard directory ${DASHBOARD} does not exist."
  exit
fi
if [ ! -d "${BACKUP_FOLDER}" ]; then
  echo "Backup directory ${BACKUP_FOLDER} does not exist."
  exit
fi

# Timestamp for Backup Filename
STAMP=$(date '+%Y-%m-%d')

# Optional: Ask InfluxDB to create a snapshot backup 
echo "Creating InfluxDB Backup"
cd ${DASHBOARD}
mkdir -p influxdb/backups
chmod g+w influxdb/backups
docker exec influxdb influxd backup -database powerwall /var/lib/influxdb/backups

# Backup Powerwall-Dashboard
echo "Backing up Powerwall-Dashboard (influxdb grafana)"
cd  ${DASHBOARD}
tar -zcvf ${BACKUP_FOLDER}/Powerwall-Dashboard.$STAMP.tgz influxdb grafana 

# Cleanup Old Backups
echo "Cleaning up old backups"
rm -rf ${DASHBOARD}/influxdb/backups/*        # Delete InfluxDB snapshots after backup
find ${BACKUP_FOLDER}/Powerwall-Dashboard.*tgz -mtime +${KEEP} -type f -delete
echo "Done"
