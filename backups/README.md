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

The backup script creates a consistent snapshot of:
1. **InfluxDB** — uses `influxd backup` to create a proper snapshot (not a copy of live data files)
2. **Grafana** — uses `sqlite3 .backup` for a consistent copy of `grafana.db` (falls back to direct copy if sqlite3 is not installed on the host: `sudo apt install sqlite3`)
3. **Configuration files** — all `.env`, `.conf`, and `.yml` files needed to restore your setup

The following shows an example of how to set up automated backups (see backup.sh):

1. Copy backup.sh.sample to backup.sh (cp backup.sh.sample backup.sh)
2. Edit the line that says DASHBOARD="/home/user/Powerwall-Dashboard" to have your dashboard location.
3. Make the script executable with `chmod +x backup.sh`
4. Add to crontab for daily backups: `0 2 * * * /home/user/Powerwall-Dashboard/backups/backup.sh`

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

# ... (see backup.sh.sample for full script)

# The improved backup script:
# 1. Creates an InfluxDB snapshot via influxd backup (avoids "file changed" errors)
# 2. Creates a consistent Grafana DB copy via sqlite3 .backup
# 3. Backs up all config files (compose.env, pypowerwall.env, telegraf.local, etc.)
```

## Restore Backup

Naturally, whatever backup plan you decide to do, make sure you test it. Copy the backup to another VM or box, install Powerwall-Dashboard and restore the backup to see if it all comes back up without any data loss.

### Using the restore script (recommended)

A companion `restore.sh.sample` is provided to automate the restore process. It handles permissions, pre-restore safety copies, and the correct InfluxDB restore sequence.

1. Copy restore.sh.sample to restore.sh (cp restore.sh.sample restore.sh)
2. Make the script executable with `chmod +x restore.sh`
3. Run as root:
    ```bash
    # Restore from the most recent backup archive
    sudo ./restore.sh

    # Or specify a specific archive
    sudo ./restore.sh /path/to/Powerwall-Dashboard.2026-01-15.tar.xz
    ```

The restore script will:
1. **Auto-detect** the Powerwall-Dashboard directory by locating `compose-dash.sh`
2. **Stop all containers** before touching data
3. **Restore InfluxDB** from the `influxd backup -portable` snapshot, moving existing data aside first (not deleted — you get a rollback path)
4. **Restore Grafana** database and provisioning files with correct ownership
5. **Restore configuration files**, rewriting `PWD_USER` in `compose.env` to match this host's actual user and docker group
6. **Restart the stack** and print a list of pre-restore backup paths to clean up once confirmed

### Manual restore from a backup script archive

The backup script creates an archive with this structure:

```
influxdb/          # InfluxDB snapshot files (from influxd backup)
grafana/           # grafana.db (consistent copy) + provisions
config/            # configuration files (.env, .conf, .yml)
```

To restore manually from a backup script archive:

1. Install a fresh instance of Powerwall-Dashboard per [Setup instructions](https://github.com/jasonacox/Powerwall-Dashboard#setup), then start it once so the `influxdb` container is running and the default `powerwall` database exists.
2. Stop **telegraf and grafana** only — keep `influxdb` running so `docker exec` works:
    ```bash
    docker compose stop telegraf grafana
    ```
3. Restore backup files
    ```bash
    # Set your dashboard location
    DASHBOARD="/home/user/Powerwall-Dashboard"

    # Extract the backup archive to a temporary location
    mkdir -p /tmp/pwd-restore
    sudo tar --no-same-owner -Jxvf "${DASHBOARD}/backups/Powerwall-Dashboard.xyz.tar.xz" -C /tmp/pwd-restore

    # Restore InfluxDB snapshot (files are in influxdb/ from the portable backup)
    mkdir -p "${DASHBOARD}/influxdb/backups"
    sudo cp -a /tmp/pwd-restore/influxdb/. "${DASHBOARD}/influxdb/backups/"
    # Drop the existing database — influxd restore refuses to restore into an
    # existing database (setup.sh creates an empty powerwall DB):
    docker exec influxdb influx -database powerwall -execute "DROP DATABASE powerwall"
    # Restore using -portable to match the backup format:
    docker exec influxdb influxd restore -portable /var/lib/influxdb/backups
    # Re-create continuous queries (influxd restore does not reliably restore CQs):
    grep '^CREATE CONTINUOUS QUERY' "${DASHBOARD}/influxdb/influxdb.sql" \
      | docker exec -i influxdb influx -database powerwall

    # Restore Grafana
    sudo cp -a /tmp/pwd-restore/grafana/grafana.db "${DASHBOARD}/grafana/"
    sudo cp -a /tmp/pwd-restore/grafana/provisions/. "${DASHBOARD}/grafana/provisions/" 2>/dev/null

    # Restore config files
    sudo cp -a /tmp/pwd-restore/config/. "${DASHBOARD}/"

    # Clean up
    sudo rm -rf /tmp/pwd-restore
    ```
4. Start containers
    ```bash
    ./compose-dash.sh start
    ```

### Using a full directory backup (transfer method)

If you used the full tar method from the [Transfer to a New Computer](#transfer-to-a-new-computer) section above, simply extract over the fresh clone:

```bash
sudo tar --no-same-owner -zxvf ../Powerwall-Dashboard.tgz
./setup.sh
```
