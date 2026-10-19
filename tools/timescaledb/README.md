# TimescaleDB (PostgreSQL) Datastore — EXPERIMENTAL

> **Experimental, community-maintained add-on.** InfluxDB remains the default,
> supported datastore. The TimescaleDB dashboard, SQL and tooling here are
> maintained by the community: changes to the InfluxDB dashboards or tools do
> **not** need a matching TimescaleDB change, so this dashboard may lag behind
> or differ from the InfluxDB ones. Please report issues you find.

This add-on stores your Powerwall data in [TimescaleDB](https://www.timescale.com/)
(PostgreSQL with time-series extensions) **in addition to** InfluxDB. Your
existing InfluxDB stack keeps running exactly as before. You get a separate
Grafana dashboard backed by TimescaleDB, and your data in a regular SQL
database you can query with any PostgreSQL tool.

It adds these services through the stack's `powerwall.extend.yml` mechanism:

| Service | What it does |
|---|---|
| `timescaledb` | The database (`timescale/timescaledb`, pinned version). Not exposed outside Docker by default. |
| `telegraf-timescale` | A second Telegraf that polls pypowerwall and weather411, writing raw data to TimescaleDB. The pypowerwall proxy caches responses, so your Powerwall isn't polled twice. |
| `aggregate-cron` | Every 60 seconds, runs the SQL in [`db/aggregate/`](db/aggregate/) to roll raw data up into the 1-minute and 1-hour tables the dashboard uses (the equivalent of InfluxDB's continuous queries). |

It also gives the existing `grafana` service the database connection settings.

## Setup

1. Set up the base stack first, if you haven't: `./setup.sh`.
2. From the repository root, run:

   ```bash
   ./tools/timescaledb/setup.sh
   ```

   This:
   - copies `tools/timescaledb/powerwall.extend.yml.sample` to `powerwall.extend.yml`
   - creates `tools/timescaledb/timescaledb.env` with random passwords and your
     timezone (from the `tz` file)
   - installs the "TimescaleDB (auto provisioned)" Grafana datasource. Grafana
     connects as a separate read-only user (`grafana_reader`), so dashboard
     viewers can't change your data
   - starts the services and waits for the database schema
   - offers to copy your existing InfluxDB history into TimescaleDB (see
     [Importing your InfluxDB history](#importing-your-influxdb-history))
3. In Grafana, go to **Dashboards → New → Import**, upload
   `tools/timescaledb/dashboard-timescaledb.json`, select **TimescaleDB (auto
   provisioned)** as the datasource, and enter your timezone (setup prints it).

`powerwall.extend.yml` and `tools/timescaledb/timescaledb.env` are gitignored,
so `git pull` and `./upgrade.sh` won't overwrite them. Re-running
`./tools/timescaledb/setup.sh` is safe.

**Already have a `powerwall.extend.yml`** (for example for tesla-history)?
Docker Compose only reads one, so setup stops and asks you to copy the
services from `tools/timescaledb/powerwall.extend.yml.sample` into your file by
hand. Then run setup again.

**Changed your timezone** with `./tz.sh`? Re-run `./tools/timescaledb/setup.sh`
to update `timescaledb.env`, and set the dashboard's Timezone variable to match.

## Checking that it's working

```bash
docker ps --filter name=timescale --filter name=aggregate-cron
docker logs aggregate-cron
```

`aggregate-cron` reports **healthy** only if a full aggregation pass succeeded
in the last 5 minutes, so "unhealthy" means the dashboard tables have stopped
updating. Its log shows which script failed.

## Importing your InfluxDB history

Setup asks whether to import your InfluxDB history. You can say no and re-run
setup later. The import:

- copies each InfluxDB retention policy month by month, newest first, then
  rebuilds `pw_kwh_1h` from the imported 1-minute data
- records progress in a `migration_progress` table, so it's safe to stop and
  re-run (finished months are skipped)
- can read from this stack's `influxdb` container (the default) or another
  InfluxDB 1.x server

To run the import again later (for example after an error), re-run
`./tools/timescaledb/setup.sh` and answer **y** when it asks.

**Known difference:** live data uses time-weighted 1-minute averages and
energy integration that splits readings across hour boundaries. That needs
raw samples, which InfluxDB only keeps for 3 days, so imported history uses
InfluxDB's already-averaged data. The totals differ slightly around the
switch-over point.

## Using an existing TimescaleDB server

Instead of the bundled container, you can point the add-on at a
TimescaleDB/PostgreSQL server you already run:

1. Run `./tools/timescaledb/setup.sh` once as normal.
2. Edit `tools/timescaledb/timescaledb.env`: set `TIMESCALEDB_HOST`,
   `TIMESCALEDB_PORT`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, and
   `TIMESCALEDB_SSLMODE` (for example `require` if the server uses TLS).
   `GRAFANA_PG_USER`/`GRAFANA_PG_PASSWORD` are the read-only user Grafana
   connects as; change them if you like.
3. Edit `powerwall.extend.yml` and delete the whole `timescaledb:` service
   block.
4. Remove the bundled container and apply the change:

   ```bash
   docker rm -f timescaledb
   ./compose-dash.sh up -d
   ```

The server needs TimescaleDB 2.x on PostgreSQL 14 or newer, reachable from
this Docker host. The `timescaledb` extension must already be created in the
database, or the user must be allowed to create it. The user also needs
permission to create tables, hypertables and compression policies. The schema
is applied automatically when `aggregate-cron` starts.

`aggregate-cron` also creates the read-only Grafana user on start, which
needs `POSTGRES_USER` to be a superuser or to have `CREATEROLE` and the right
to grant `pg_read_all_data`. If it doesn't, `docker logs aggregate-cron` shows
an error and Grafana can't connect; create the user yourself as an admin
(with the values from `timescaledb.env`):

```sql
CREATE ROLE grafana_reader LOGIN PASSWORD 'GRAFANA_PG_PASSWORD value';
GRANT pg_read_all_data TO grafana_reader;
```

**What the Grafana user can read.** `pg_read_all_data` lets the user read
every database on the server, which is handy if you add Grafana datasources
for your other (non-Powerwall) databases with the same user. The TimescaleDB
datasource itself only ever connects to the Powerwall database. To limit the
user to the Powerwall database instead, run this as an admin while connected
to that database (replace `telegraf_powerwall` with your `POSTGRES_USER`):

```sql
REVOKE pg_read_all_data FROM grafana_reader;
GRANT USAGE ON SCHEMA public TO grafana_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_reader;
ALTER DEFAULT PRIVILEGES FOR ROLE telegraf_powerwall IN SCHEMA public
    GRANT SELECT ON TABLES TO grafana_reader;
```

`aggregate-cron` only grants `pg_read_all_data` when it first creates the
user, so this change is kept when it restarts.

## Accessing the database from the host

The database isn't published outside Docker by default. To connect from the
host (psql, pgAdmin, DBeaver, ...), add a `ports:` entry to the `timescaledb`
service in `powerwall.extend.yml` (a commented example is already there).
Choose a free host port if something else already uses 5432:

```yaml
        ports:
            - "127.0.0.1:5432:5432"
```

Then run `./compose-dash.sh up -d`. The username and password are in
`tools/timescaledb/timescaledb.env`.

## Backup and restore

The InfluxDB backup in [`backups/README.md`](../../backups/README.md) doesn't
cover TimescaleDB, and copying `tools/timescaledb/data/` while the database is
running can produce a broken copy. Use `pg_dump` instead:

```bash
cp tools/timescaledb/backup-timescaledb.sh.sample backups/backup-timescaledb.sh
chmod +x backups/backup-timescaledb.sh
# edit DASHBOARD (and PG_USER/PG_DB if you changed them) at the top
```

Copying the whole folder to a new computer, as described in `backups/README.md`,
is fine **if the stack is stopped first**.

To restore, drop and recreate the database (`pg_restore --clean` does not work
with TimescaleDB hypertables), and wrap `pg_restore` in TimescaleDB's
`timescaledb_pre_restore()` and `timescaledb_post_restore()` calls:

```bash
docker stop aggregate-cron telegraf-timescale grafana
docker exec -u postgres timescaledb psql -U telegraf_powerwall -d postgres -c "DROP DATABASE IF EXISTS powerwall;"
docker exec -u postgres timescaledb psql -U telegraf_powerwall -d postgres -c "CREATE DATABASE powerwall OWNER telegraf_powerwall;"
docker exec -u postgres timescaledb psql -U telegraf_powerwall -d powerwall -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
docker exec -u postgres timescaledb psql -U telegraf_powerwall -d powerwall -c "SELECT timescaledb_pre_restore();"
docker cp ./backups/timescaledb.YYYY-MM-DD.dump timescaledb:/tmp/restore.dump
docker exec -u postgres timescaledb pg_restore -U telegraf_powerwall -d powerwall --no-owner /tmp/restore.dump
docker exec -u postgres timescaledb psql -U telegraf_powerwall -d powerwall -c "SELECT timescaledb_post_restore();"
docker exec timescaledb rm -f /tmp/restore.dump
./compose-dash.sh up -d
```

(Replace `telegraf_powerwall`/`powerwall` if you changed `POSTGRES_USER`/`POSTGRES_DB`.)

## Removing the add-on

1. Delete the TimescaleDB services (`timescaledb`, `telegraf-timescale`,
   `aggregate-cron`) and the `grafana:` patch from `powerwall.extend.yml`, or
   delete the file if nothing else is in it.
2. Then:

   ```bash
   docker rm -f timescaledb telegraf-timescale aggregate-cron
   rm grafana/provisions/datasources/timescaledb.yml
   ./compose-dash.sh up -d
   ```

3. Optionally delete your data and settings, and delete the TimescaleDB
   dashboard in Grafana. The data folder is owned by the database container's
   user, so this needs `sudo`:

   ```bash
   sudo rm -rf tools/timescaledb/data
   rm tools/timescaledb/timescaledb.env
   ```

InfluxDB and its data are never touched.

## Gotchas

- **Disk space:** even with compression, TimescaleDB uses noticeably more disk
  than InfluxDB for the same history.
- **Powerwall+ strings and Backup Switch fans** panels have only been tested
  with synthetic data, not real hardware. If they look wrong on your system,
  compare the `http` table's columns with the patterns in
  `db/aggregate/aggregate_strings_log.sql` / `aggregate_fans_log.sql`.
- **Missing weather:** weather data comes from weather411's `/all` endpoint.
  If weather411 has no OpenWeatherMap key, the weather panels stay empty
  (nothing else is affected).
- **Writing your own SQL:** the raw tables (`http`, `alerts`, `weather`,
  `powerwall_dashboard`) store `time` as UTC `timestamp without time zone` and
  keep 3 days. The `pw_*` tables use `timestamptz` and keep everything. Telegraf
  only creates a raw column once it has seen a non-null value, so not every
  field exists on every system.
- **Re-aggregating a range:** `db/aggregate/kwh_backfill.sql` rebuilds
  `pw_kwh_1h` from `pw_autogen_1m` for a date range (see its header for usage).

## Files

| Path | Purpose |
|---|---|
| `setup.sh` | Interactive setup (safe to re-run) |
| `powerwall.extend.yml.sample` | Services added to the stack |
| `timescaledb.env.sample` | Database connection settings template |
| `telegraf-timescale.conf` | Telegraf config for the second collector |
| `grafana-datasource.yml` | Grafana datasource, copied into `grafana/provisions/datasources/` |
| `dashboard-timescaledb.json` | Grafana dashboard |
| `db/schema.sql` | Aggregate table definitions, applied by `aggregate-cron` on start |
| `db/cron-entrypoint.sh` | `aggregate-cron`'s loop |
| `db/aggregate/` | Aggregation SQL run every minute (plus `kwh_backfill.sql`, run by hand) |
| `migrate/` | InfluxDB history import |
| `backup-timescaledb.sh.sample` | `pg_dump` backup script |
