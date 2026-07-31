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

## Removing the extension

```bash
./compose-dash.sh down timescaledb telegraf-timescale aggregate-cron
rm grafana/provisions/datasources/timescaledb.yml
# Then remove the TimescaleDB services/patches from powerwall.extend.yml by
# hand (or delete the file, if TimescaleDB is the only thing in it), and:
rm timescaledb.env
rm -rf timescaledb-data/   # only if you want the bundled container's data gone too
```
