# TimescaleDB (PostgreSQL) datastore extension

> **EXPERIMENTAL.** This is an opt-in, community-contributed extension, not
> part of the core supported stack. InfluxDB remains the default, tested
> datastore for Powerwall-Dashboard. Expect rough edges, and please report
> issues rather than assuming they're expected.

Adds TimescaleDB as a **second, parallel** datastore alongside your existing
InfluxDB stack -- pypowerwall data gets written to both. InfluxDB, `telegraf`,
and the rest of the core stack are never disabled or modified by this
extension. See [`../../timescaledb/README.md`](../../timescaledb/README.md)
for the architecture, design decisions, and troubleshooting ("Gotchas")
reference.

This is not wired into the main `./setup.sh`; it's an opt-in add-on via the
stack's existing `powerwall.extend.yml` mechanism (the same one
[`tools/tesla-history`](../tesla-history/) and [`tools/pgadmin`](../pgadmin/)
use).

## Setup

1. Run the base stack setup first if you haven't already: `./setup.sh`.
2. From the repository root:
   ```bash
   ./tools/timescaledb/setup.sh
   ```
   This creates/merges `powerwall.extend.yml` (see below if you already have
   one for another add-on), creates `timescaledb.env` with a random database
   password, asks whether to use this stack's own bundled TimescaleDB
   container or an existing PostgreSQL/TimescaleDB server you already run,
   starts the new services, applies the database schema, and offers to
   migrate your existing InfluxDB history into TimescaleDB.
3. Import `dashboards/dashboard-timescaledb.json` into Grafana (Dashboard/New
   -> Import dashboard) and select "TimescaleDB (auto provisioned)" for its
   datasource.

`powerwall.extend.yml` and `timescaledb.env` are both gitignored, so your
local copies survive `git pull` / `setup.sh` re-runs.

### If you already have a `powerwall.extend.yml`

`docker compose` only reads a single `powerwall.extend.yml`. If you already
have one (e.g. for `tesla-history` or `pgadmin`), `tools/timescaledb/setup.sh`
detects it and tells you to merge the services from
`tools/timescaledb/powerwall.extend.yml.sample` into it by hand instead of
overwriting the file.

## Bundled vs. an existing server

Re-run `tools/timescaledb/setup.sh` any time to switch between a bundled
TimescaleDB container and an existing server, or to update connection
details. Note: switching from **external back to bundled** currently isn't a
clean automatic re-merge (the bundled service block gets removed from
`powerwall.extend.yml` in external mode, and safely reinserting it into a
possibly hand-edited file isn't something this script attempts) -- the script
will tell you to remove the TimescaleDB entries from `powerwall.extend.yml`
(or delete the file, if TimescaleDB is the only thing in it) and re-run to
recreate it fresh.

## Running InfluxDB-idle (no fully-integrated "TimescaleDB-only" mode)

This extension is dual-write only -- there's no supported way to disable
InfluxDB through `setup.sh`/`powerwall.extend.yml`. If you want InfluxDB and
`telegraf` idle (e.g. to stop double-polling pypowerwall), stop them directly:

```bash
./tools/timescaledb/stop-influxdb.sh
```

This is **not sticky**: `influxdb`/`telegraf` are ordinary, unconditional
services in `powerwall.yml` with `restart: unless-stopped`, so the next
`./setup.sh` or `./upgrade.sh` run (both end in `docker compose up -d`, which
reconciles every declared service back to running) will start them again.
Re-run the script above afterward if you want them to stay stopped. Existing
InfluxDB data is never touched either way.

## Backup and restore

TimescaleDB is a real Postgres-compatible database with an active WAL, so
copying `timescaledb-data/` directly while the container is running risks
capturing a torn, inconsistent snapshot -- unlike the InfluxDB backup covered
in [`backups/README.md`](../../backups/README.md), which doesn't apply here.
Use Postgres's own backup tool instead (`pg_dump`).

The "Transfer to a New Computer" steps in `backups/README.md` (stop the
stack, `tar` everything, restore on the new machine) are still fine for
TimescaleDB *as long as the stack is stopped first* -- a cold copy of a
stopped database is safe. The steps below are for backing up TimescaleDB
*while it keeps running*.

1. Copy the sample script into `backups/` (matching where the InfluxDB
   backup script lives, for consistency with any cron setup you may already
   have):
   ```bash
   cp tools/timescaledb/backup-timescaledb.sh.sample backups/backup-timescaledb.sh
   ```
2. Edit `DASHBOARD="/home/user/Powerwall-Dashboard"` to your dashboard location.
3. Edit `PG_USER`/`PG_DB` if you changed `POSTGRES_USER`/`POSTGRES_DB` from
   their defaults in `timescaledb.env`.
4. Make it executable: `chmod +x backups/backup-timescaledb.sh`.

### Restoring a TimescaleDB backup

`pg_restore`'s usual `--clean` option (drop-and-recreate objects in place)
does **not** work against TimescaleDB hypertables -- it generates
`ALTER TABLE ONLY ... DROP CONSTRAINT`, and TimescaleDB rejects the `ONLY`
option on hypertable operations. Drop and recreate the database instead; this
was verified end-to-end (backup taken from a live database with real data,
restored into a fresh database, hypertable/compression metadata and all rows
confirmed identical):

```bash
# 1. Stop the stack (or at least anything writing to TimescaleDB)
./compose-dash.sh stop

# 2. Start just the timescaledb container
docker compose -f powerwall.yml -f powerwall.extend.yml up -d timescaledb

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

If you're restoring onto a brand-new install where `tools/timescaledb/setup.sh`
already ran and applied `timescaledb/schema.sql`, step 3 above (drop/recreate
the database) is still required -- restoring on top of the already-created
schema will fail with "relation already exists" errors, since `pg_restore`
recreates the schema itself as part of the dump.

## Removing the extension

```bash
./compose-dash.sh down timescaledb telegraf-timescale aggregate-cron
rm grafana/provisions/datasources/timescaledb.yml
# Then remove the TimescaleDB services/patches from powerwall.extend.yml by
# hand (or delete the file, if TimescaleDB is the only thing in it), and:
rm timescaledb.env
rm -rf timescaledb-data/   # only if you want the bundled container's data gone too
rm -f backups/backup-timescaledb.sh   # if you set up scheduled backups
```
