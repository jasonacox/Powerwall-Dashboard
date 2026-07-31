# Dashboard Backup

InfluxDB is configured to use a infinite retention policy (see [influxdb.sql](../influxdb/influxdb.sql)).  It uses continuous queries to downsample Powerwall data and preserve disk space.  However, this does not safeguard the data from accidental deletion or corruption.  It is recommend that you set up a backup plan to snapshot the data for disaster recovery.

## Transfer to a New Computer

If you want to create a backup of your Powerwall Dashboard and move it to a new computer. You can follow these steps:

```bash
# Step 1 - Stop Dashboard on old computer
./compose-dash.sh stop

# Step 2- Create a backup
sudo tar -zvcf ../Powerwall-Dashboard.tgz *
cd ..

# Step 3 - Copy the Powerwall-Dashboard.tgz to the new computer

# Stop 4 - Clone Project on new computer
git clone https://github.com/jasonacox/Powerwall-Dashboard.git
cd Powerwall-Dashboard

# Step 5 - Restore backup
sudo tar --no-same-owner -zxvf ../Powerwall-Dashboard.tgz

# Step 6 - Setup
./setup.sh
```

## Backup Plans

Backup the Powerwall-Dashboard folder. In that folder are two important folders:

* influxdb - This is the folder for the database that stores the metrics.
* grafana - This is the folder for the dashboard which holds your setup and customization.

The following shows an example of how to migrate the data (influxdb) from one system to another (see backup.sh):

1. Copy backup.sh.sample to backup.sh (cp backup.sh.sample backup.sh)
2. Edit the line that says DASHBOARD="/home/user/Powerwall-Dashboard" to have your dashboard location.
3. Make the script executable with `chmod +x backup.sh`

## Backup Script Example

```bash
#!/bin/bash
# Daily Backup for Powerwall-Dashboard Data
if [ "$EUID" -ne 0 ]
  then echo "Must run as root"
  exit
fi

# Set values for your environment 
DASHBOARD="/home/user/Powerwall-Dashboard"    # Location of Dashboard to backup
BACKUP_FOLDER="${DASHBOARD}/backups"          # Destination folder for backups
KEEP="5"                                      # Days to keep backup

# Check to see if directory exists
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

# Backup Powerwall-Dashboard Data
echo "Backing up Powerwall-Dashboard Data (influxdb)"
cd  ${DASHBOARD}
tar -Jcvf ${BACKUP_FOLDER}/Powerwall-Dashboard.$STAMP.tar.xz influxdb 

# Cleanup Old Backups
echo "Cleaning up old backups"
rm -rf ${DASHBOARD}/influxdb/backups/*        # Delete InfluxDB snapshots after backup
find ${BACKUP_FOLDER}/Powerwall-Dashboard.*tar.xz -mtime +${KEEP} -type f -delete
echo "Done"
```

## Restore Backup

Naturally, whatever backup plan you decide to do, make sure you test it. Copy the backup to another VM or box, install Powerwall-Dashboard and restore the backup to see if it all comes back up without any data loss.

1. Install a fresh instance of Powerwall-Dashboard per [Setup instructions](https://github.com/jasonacox/Powerwall-Dashboard#setup).
2. Stop containers using convenience script in Powerwall-Dashboard root folder
    ```bash
    ./compose-dash.sh stop
    ```
3. Restore backup files
    ```bash
    # Inside the Powerwall-Dashboard folder, extract the backup archive
    sudo tar --no-same-owner -Jxvf ./backups/Powerwall-Dashboard.xyz.tar.xz
    ```
4. Start containers
    ```bash
    ./compose-dash.sh start
    ```

## TimescaleDB Backup

If you installed the TimescaleDB extension (see `tools/timescaledb/`) alongside InfluxDB, back it up differently than the `influxdb` folder above -- TimescaleDB is a real Postgres-compatible database with an active WAL, so copying `timescaledb-data/` directly while the container is running risks capturing a torn, inconsistent snapshot. Use Postgres's own backup tool instead (`pg_dump`), the same way the InfluxDB approach above uses `influxd backup` rather than copying `influxdb/` directly.

The "Transfer to a New Computer" steps at the top of this file (stop the stack, `tar` everything, restore on the new machine) are still fine for TimescaleDB *as long as the stack is stopped first* -- a cold copy of a stopped database is safe. The daily/scheduled backup below is for backing up TimescaleDB *while it keeps running*.

1. Copy `backup-timescaledb.sh.sample` to `backup-timescaledb.sh` (`cp backup-timescaledb.sh.sample backup-timescaledb.sh`)
2. Edit `DASHBOARD="/home/user/Powerwall-Dashboard"` to your dashboard location.
3. Edit `PG_USER`/`PG_DB` if you changed `POSTGRES_USER`/`POSTGRES_DB` from their defaults in `timescaledb.env`.
4. Make the script executable with `chmod +x backup-timescaledb.sh`

### TimescaleDB Backup Script Example

```bash
#!/bin/bash
# Daily Backup for Powerwall-Dashboard TimescaleDB Data
if [ "$EUID" -ne 0 ]
  then echo "Must run as root"
  exit
fi

# Set values for your environment
DASHBOARD="/home/user/Powerwall-Dashboard"    # Location of Dashboard to backup
BACKUP_FOLDER="${DASHBOARD}/backups"          # Destination folder for backups
KEEP="5"                                      # Days to keep backup

# TimescaleDB connection settings -- must match timescaledb.env
PG_USER="telegraf_powerwall"                  # POSTGRES_USER in timescaledb.env
PG_DB="powerwall"                             # POSTGRES_DB in timescaledb.env

# Check to see if directory exists
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

# Ask TimescaleDB to create a consistent logical backup (pg_dump custom format)
echo "Creating TimescaleDB Backup"
cd ${DASHBOARD}
docker exec -u postgres timescaledb pg_dump -U "${PG_USER}" -d "${PG_DB}" -Fc -f /tmp/powerwall.dump
docker cp timescaledb:/tmp/powerwall.dump ${BACKUP_FOLDER}/timescaledb.$STAMP.dump
docker exec -u postgres timescaledb rm -f /tmp/powerwall.dump

# Cleanup Old Backups
echo "Cleaning up old backups"
find ${BACKUP_FOLDER}/timescaledb.*.dump -mtime +${KEEP} -type f -delete
echo "Done"
```

### Restore TimescaleDB Backup

`pg_restore`'s usual `--clean` option (drop-and-recreate objects in place) does **not** work against TimescaleDB hypertables -- it generates `ALTER TABLE ONLY ... DROP CONSTRAINT`, and TimescaleDB rejects the `ONLY` option on hypertable operations. Drop and recreate the database instead; this was verified end-to-end (backup taken from a live database with real data, restored into a fresh database, hypertable/compression metadata and all rows confirmed identical):

```bash
# 1. Stop the stack (or at least anything writing to TimescaleDB)
./compose-dash.sh stop

# 2. Start just the timescaledb container
docker compose -f powerwall.yml --profile timescaledb up -d timescaledb

# 3. Drop and recreate the database, then re-add the extension
#    (replace telegraf_powerwall/powerwall if you customized these in timescaledb.env)
docker exec -u postgres timescaledb psql -U telegraf_powerwall -d postgres -c "DROP DATABASE IF EXISTS powerwall;"
docker exec -u postgres timescaledb psql -U telegraf_powerwall -d postgres -c "CREATE DATABASE powerwall OWNER telegraf_powerwall;"
docker exec -u postgres timescaledb psql -U telegraf_powerwall -d powerwall -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"

# 4. Copy the backup file into the container and restore
docker cp ./backups/timescaledb.xyz.dump timescaledb:/tmp/restore.dump
docker exec -u postgres timescaledb pg_restore -U telegraf_powerwall -d powerwall --no-owner /tmp/restore.dump

# 5. Start everything else back up
./compose-dash.sh start
```

If you're restoring onto a brand-new install where `./setup.sh` already ran and applied `timescaledb/schema.sql`, step 3 above (drop/recreate the database) is still required -- restoring on top of the already-created schema will fail with "relation already exists" errors, since `pg_restore` recreates the schema itself as part of the dump.
