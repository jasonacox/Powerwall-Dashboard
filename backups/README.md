# Dashboard Backup

InfluxDB is configured to use a 25-year retention policy (see [influxdb.sql](../influxdb/influxdb.sql)).  It uses continuous queries to downsample Powerwall data and preserve disk space.  However, this does not safeguard the data from accidental deletion or corruption.  It is recommend that you set up a backup plan to snapshot the data for disaster recovery.

## Backup Plans

Backup the Powerwall-Dashboard folder. In that folder are two important folders:

* influxdb - This is the folder for the database that stores the metrics.
* grafana - This is the folder for the dashboard which holds your setup and customization.

## Backup Example

```bash
#!/bin/bash
# Daily Backup for Powerwall-Dashboard
if [ "$EUID" -ne 0 ]
  then echo "Must run as root"
  exit
fi

# Set values for your environment 
BACKUP_FOLDER="/backup"                       # Destination folder for backups
DASHBOARD="/home/user/Powerwall-Dashboard"    # Location of Dashboard to backup
KEEP="5"                                      # Days to keep backup

# Timestamp for Backup Filename
STAMP=$(date '+%Y-%m-%d')

# Optional: Ask InfluxDB to create a snapshot backup 
echo "Creating InfluxDB Backup"
cd ${DASHBOARD}
mkdir -p influxdb/backups
chmod g+w influxdb/backups
docker exec -it influxdb influxd backup -database powerwall /var/lib/influxdb/backups

# Backup Powerwall-Dashboard
echo "Backing up Powerwall-Dashboard (influxdb grafana)"
cd  ${DASHBOARD}
tar -zcvf ${BACKUP_FOLDER}/Powerwall-Dashboard.$STAMP.tgz influxdb grafana 

# Cleanup Old Backups
echo "Cleaning up old backups"
find ${BACKUP_FOLDER}/Powerwall-Dashboard.*tgz -mtime +${KEEP} -type f -delete
echo "Done"
```

## Restore Backup

Naturally, whatever backup plan you decide to do, make sure you test it. Copy the backup to another VM or box, install Powerwall-Dashboard and restore the backup to see if it all comes back up without any data loss.

1. Install a fresh instance of Powerwall-Dashboard per [Setup instructions](https://github.com/jasonacox/Powerwall-Dashboard#setup).
2. Stop containers
    ```bash
    docker-compose -f powerwall.yml stop
    ```
3. Restore backup files
    ```bash
    # From Powerwall-Dashboard folder 
    tar -zxvf /backup/Powerwall-Dashboard.xyz.tgz
    ```
4. Start containers
    ```bash
    docker-compose -f powerwall.yml start
    ```
