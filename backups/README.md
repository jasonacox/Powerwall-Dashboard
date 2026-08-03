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
1. **InfluxDB** — uses `influxd backup -portable` to create a proper online snapshot (not a copy of live data files), plus an export of the live continuous queries
2. **Grafana** — uses `sqlite3 .backup` for a consistent copy of `grafana.db` (falls back to direct copy if sqlite3 is not installed on the host: `sudo apt install sqlite3`), plus provisioning files
3. **Configuration files** — all `.env`, `.conf`, and `.yml` files needed to restore your setup
4. **Weather service** — `weather/weather411.conf` (if present)
5. **Tesla cloud tokens** — the `.auth/` directory (if present), so cloud-mode installs migrate without re-authenticating

> **Security note:** backup archives contain credentials (`.env` files, Tesla tokens). The script creates them with mode 600 — keep them protected, especially if you copy them off-machine.

The following shows an example of how to set up automated backups (see backup.sh):

1. Copy backup.sh.sample to backup.sh (cp backup.sh.sample backup.sh)
2. Make the script executable with `chmod +x backup.sh` (the script auto-detects the dashboard location by finding `compose-dash.sh`)
3. Add to crontab for daily backups: `0 2 * * * /home/user/Powerwall-Dashboard/backups/backup.sh`

The `influxdb` container must be running when the backup runs — the snapshot is taken online with no downtime.

> **Large datasets:** both `backup.sh` and `restore.sh` stage data in a temporary directory (`mktemp -d`, usually under `/tmp`). If your InfluxDB history is large (multi-GB) and `/tmp` is a RAM-backed tmpfs, staging there can exhaust memory. Both scripts check available space first — backup aborts and restore warns — and you can point staging at a disk with more room: `sudo TMPDIR=/path/with/space ./backup.sh`

## Backup Script Example

The full script is in `backup.sh.sample`. To set up automated daily backups:

1. `cp backup.sh.sample backup.sh && chmod +x backup.sh`
2. Add to crontab: `0 2 * * * /home/user/Powerwall-Dashboard/backups/backup.sh`

The script auto-detects the dashboard location from its own path (must live in `Powerwall-Dashboard/backups/`). It creates an InfluxDB snapshot, backs up Grafana, captures config files, weather/Alexa settings, and Tesla cloud tokens, then prunes archives older than 5 days. Archives are mode 600 (they contain credentials).

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
2. **Check staging disk space** and warn before extracting a large archive into a location that can't hold it (use `sudo TMPDIR=/path/with/space ./restore.sh` to relocate staging)
3. **Stop all containers** before touching data
4. **Restore InfluxDB** from the `influxd backup -portable` snapshot, moving existing data aside first (not deleted — you get a rollback path), then re-create continuous queries from the archive (with `influxdb.sql` as fallback)
5. **Restore Grafana** database and provisioning files with correct ownership
6. **Restore configuration files**, rewriting `PWD_USER` in `compose.env` to match this host's actual user and primary group (same `uid:gid` convention as `setup.sh`). Project files managed by git (`powerwall.yml`, `telegraf.conf`, `influxdb.conf`, `VERSION`) are kept in the archive for reference but are NOT restored over the current checkout — this prevents an older backup from downgrading the stack or breaking future upgrades.
7. **Restore weather411.conf and .auth tokens** (when present in the archive — older archives without them restore fine)
8. **Recreate the stack** (`compose-dash.sh up -d`, so restored settings take effect) and print a list of pre-restore backup paths to clean up once confirmed

### Manual restore from a backup script archive

The backup script creates an archive with this structure:

```
influxdb/          # InfluxDB portable snapshot + continuous_queries.txt
grafana/           # grafana.db (consistent copy) + provisions
config/            # configuration files (.env, .conf, .yml)
weather/           # weather411.conf (if present)
auth/              # .auth Tesla cloud tokens (if present)
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

    # Restore config files (exclude git-managed project files - restoring an
    # older powerwall.yml/telegraf.conf/VERSION would downgrade the stack and
    # cause git pull conflicts on future upgrades)
    for f in /tmp/pwd-restore/config/* /tmp/pwd-restore/config/.*.env; do
      case "$(basename "$f")" in
        powerwall.yml|telegraf.conf|influxdb.conf|VERSION|_config.yml) continue ;;
      esac
      [ -f "$f" ] && sudo cp -a "$f" "${DASHBOARD}/"
    done

    # Restore weather411 config and Tesla cloud tokens (newer archives)
    [ -f /tmp/pwd-restore/weather/weather411.conf ] && sudo cp -a /tmp/pwd-restore/weather/weather411.conf "${DASHBOARD}/weather/"
    [ -d /tmp/pwd-restore/auth ] && sudo mkdir -p "${DASHBOARD}/.auth" && sudo cp -a /tmp/pwd-restore/auth/. "${DASHBOARD}/.auth/"

    # Clean up
    sudo rm -rf /tmp/pwd-restore
    ```
4. Recreate containers so restored settings take effect ('start' alone would
   resume the old containers with stale configuration)
    ```bash
    ./compose-dash.sh up -d
    ```

### Using a full directory backup (transfer method)

If you used the full tar method from the [Transfer to a New Computer](#transfer-to-a-new-computer) section above, simply extract over the fresh clone:

```bash
sudo tar --no-same-owner -zxvf ../Powerwall-Dashboard.tgz
./setup.sh
```
