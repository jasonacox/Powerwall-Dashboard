# TimescaleDB (PostgreSQL) datastore

> **EXPERIMENTAL.** This is an opt-in, community-contributed extension, not
> part of the core supported stack — InfluxDB remains the default, tested
> datastore. See [`tools/timescaledb/`](../tools/timescaledb/) for setup.

A fully deployable additional datastore for Powerwall-Dashboard, using
PostgreSQL/TimescaleDB alongside your existing InfluxDB stack. Install it via
[`tools/timescaledb/setup.sh`](../tools/timescaledb/setup.sh) — a bundled
container or an existing PostgreSQL/TimescaleDB server, dual-write alongside
InfluxDB. It is not part of the main `./setup.sh` flow.

## Architecture

```
pypowerwall (8675) --> telegraf-timescale --> raw tables (http, alerts)
                          (outputs.postgresql)         |
                                                        v
                                             aggregate-cron container
                                             (runs timescaledb/aggregate/*.sql
                                              every 60s)
                                                        |
                                                        v
weather411 (8676) ------------------------>  1-minute/1-hour aggregate tables
  (writes pw_weather_log directly,           (pw_autogen_1m, pw_kwh_1h, pw_grid_1m,
   no Telegraf/raw table/cron involved)        pw_vitals_log, pw_pod_log, pw_pwtemps_log,
                                                pw_alerts_log, pw_weather_log,
                                                pw_strings_log, pw_fans_log)
                                                        |
                                                        v
                                                  Grafana dashboard
```

`telegraf-timescale` is a second, independent Telegraf instance that
duplicates the same pypowerwall polling the stock `telegraf` instance does,
writing to TimescaleDB via `outputs.postgresql` instead of to InfluxDB.
`aggregate-cron` is a lightweight sidecar (stock `postgres:16-alpine` image,
no custom build) that runs the SQL scripts in `aggregate/` on a
schedule — this is the TimescaleDB equivalent of InfluxDB's continuous
queries.

### Datastore selection is an opt-in Compose extend file, not a core stack change

Core `powerwall.yml` is unmodified by this feature — `influxdb`/`telegraf`
always run, exactly as on a stock install. TimescaleDB support ships
entirely through [`tools/timescaledb/powerwall.extend.yml.sample`](../tools/timescaledb/powerwall.extend.yml.sample),
which [`tools/timescaledb/setup.sh`](../tools/timescaledb/setup.sh) copies to
the repo root as `powerwall.extend.yml` (the same mechanism
[`tools/tesla-history`](../tools/tesla-history/) and
[`tools/pgadmin`](../tools/pgadmin/) use) and merges in via
`docker compose -f powerwall.yml -f powerwall.extend.yml`. That file adds the
`timescaledb`/`telegraf-timescale`/`aggregate-cron` services and patches
`grafana`/`weather411` with the additions they need (env vars, a build
override, a startup dependency) — Compose merges partial service definitions
across `-f` files rather than requiring them to be fully redeclared.

This is **dual-write only** — TimescaleDB runs alongside InfluxDB, not instead
of it. There's no supported way to disable InfluxDB through this extension
(unlike the Compose-profile approach an earlier version of this feature used,
which could silently stop `influxdb`/`telegraf` on existing installs during
an upgrade — see `tools/timescaledb/README.md`'s "Running InfluxDB-idle"
section for the manual, non-profile alternative if you want it idle anyway).

### Bundled container vs. an existing server

`telegraf-timescale`/`aggregate-cron`/`grafana`/`weather411` all read
`TIMESCALEDB_HOST`/`TIMESCALEDB_PORT`/`TIMESCALEDB_SSLMODE` from
`timescaledb.env` rather than assuming the `timescaledb` service name, so
they work identically whether that's this stack's own bundled container or a
TimescaleDB/PostgreSQL server you already run (e.g. one already running in a
homelab). `tools/timescaledb/setup.sh` asks which you want:

| Selection | `powerwall.extend.yml` | `timescaledb.env` |
|-----------|--------------------------|--------------------|
| Bundled container (default) | includes the `timescaledb` service | `TIMESCALEDB_HOST=timescaledb`, `TIMESCALEDB_PORT=5432`, `TIMESCALEDB_SSLMODE=disable` |
| Existing server | `timescaledb` service removed | `TIMESCALEDB_HOST`/`PORT`/`SSLMODE` set from your prompted answers |

In external mode, `tools/timescaledb/setup.sh` removes the bundled
`timescaledb` service block from `powerwall.extend.yml` (there's no reason to
run an unused local Postgres container) — see that script for the exact
marker-delimited region it strips.

**Prerequisites for an existing server** (`tools/timescaledb/setup.sh` prints
these at the prompt too):
- TimescaleDB 2.x+ on PostgreSQL 13+ — the bundled image is pinned to
  `timescale/timescaledb:latest-pg16`, which is what's actually tested, but
  nothing in `schema.sql` or the aggregate scripts uses anything newer than
  stable 2.x features.
- The `timescaledb` extension installed on the server and either already
  created in the target database, or creatable by the connecting user (i.e.
  that user is a superuser, or an admin has already run
  `CREATE EXTENSION IF NOT EXISTS timescaledb;`). This rules out managed
  Postgres offerings that don't support the extension at all (e.g. plain AWS
  RDS) — self-hosted/homelab TimescaleDB is the assumed case.
- The connecting user needs privileges to create tables, hypertables, and
  compression policies in the target database.
- Network reachability from this Docker host to `host:port` — same as any
  other container-to-external-service dependency.
- If the server requires TLS, set `TIMESCALEDB_SSLMODE` (in `timescaledb.env`,
  or at the `tools/timescaledb/setup.sh` prompt) to `require`/`verify-ca`/
  `verify-full` as appropriate — the bundled container never speaks TLS, so
  this only matters for external mode.

Switching from bundled to external doesn't touch existing data in either
place — `./timescaledb-data/` (the bundled container's volume) and the
external server's own data are both left alone. Switching from external back
to bundled isn't currently a clean one-command re-toggle — see
`tools/timescaledb/README.md`. `schema.sql` is idempotent and gets
(re-)applied to whichever one is active on every run.

`tools/pgadmin` (optional pgAdmin add-on) has its own `servers.json` with a
hardcoded `Host`/`Port` that needs manual editing to match an external server
— see `tools/pgadmin/README.md`.

### Table shape: wide vs. narrow (long format)

Two shapes exist in the aggregate tier, chosen deliberately per table:

- **Wide** (one column per field): used where the field set is fixed and
  doesn't scale with hardware — `pw_autogen_1m` (site-wide power flow),
  `pw_grid_1m` (grid status), `pw_kwh_1h` (hourly energy).
- **Narrow** (`time, metric_name, value` rows): used where the field set is
  open-ended (weather — a third-party API schema this project doesn't
  control) or scales with per-installation hardware count (per-Powerwall-pack
  fields: vitals, pod, pwtemps; per-alert-type: alerts). A narrow table needs
  zero schema changes regardless of Powerwall count, split-phase vs.
  three-phase wiring, or a new field a third-party API introduces.

The narrow aggregate scripts (`aggregate_vitals_log.sql`,
`aggregate_pod_log.sql`, `aggregate_pwtemps_log.sql`, `aggregate_alerts_log.sql`,
`aggregate_weather_log.sql`) unpivot the *entire* raw row via `to_jsonb(row)`
and keep only keys matching a regex/name-list for that destination, instead of
a hardcoded `PW1/PW2/PW3` column list — this is what makes them work for any
Powerwall count with no code changes. `migrate/migrate_vitals.py`,
`migrate_pod.py`, and `migrate_pwtemps.py` use the same pattern for historical
migration. Rejected alternatives: wide-by-pack (reintroduces the same
N-dependency problem); splitting site-wide/per-pack fields into separate
tables by shape (breaks combining them in one Grafana panel, since "Partition
by values" only works on a single query's output); materialized views for
cross-metric math (their column list is fixed at creation time, same
structural limitation as a wide table). Derived cross-metric values (e.g.
`PW1_pinv_total = VSplit1+VSplit2`) are computed at aggregation/migration time
and inserted as their own `metric_name` row instead.

Narrow tables generally need a Grafana "Partition by values" transformation
(single-query-only limitation, see Gotchas below) to render as multiple
series, plus a display-name cleanup transform since the auto-generated field
name includes a `value ` prefix.

### Raw tables are created by Telegraf, not by schema.sql

`http` and `alerts` don't exist on a fresh install — Telegraf's
`outputs.postgresql` creates them (and each column) lazily on first write.
`telegraf-timescale.conf`'s `create_templates` setting makes that first
creation a hypertable immediately (1-day chunks); `aggregate/bootstrap_raw_tables.sql`
runs every cron cycle as a defensive fallback and to add the 3-day retention
policy (which `create_templates` has no equivalent for). `weather` is not one
of these raw tables — weather411 writes `pw_weather_log` directly (see below),
so there's no raw ingest stage or cron aggregation step for weather at all.

### Compression and retention

Native TimescaleDB compression is enabled on all narrow aggregate tables
(`compress_segmentby` on the metric/alert name column — critical for
compression ratio, grouping same-metric rows for dictionary encoding) and on
`pw_autogen_1m` (no segmentby column available, wide table). `pw_kwh_1h` and
`pw_grid_1m` are deliberately **not** compressed — small enough (few columns,
hourly/minutely) that it isn't worth the complexity. Compression thresholds:
7 days for most tables, 30 days for `pw_alerts_log` (matching its wider chunk
interval, appropriate for sparse event data). Retention: 3 days on the raw
ingestion tables (matching InfluxDB's own raw retention policy), permanent on
every aggregate table.

## Directory guide

- `schema.sql` — aggregate table DDL (hypertables, compression, `migration_progress`).
  Applied automatically by `tools/timescaledb/setup.sh` and by
  `aggregate-cron` on startup; safe to re-run.
- `cron-entrypoint.sh` — the `aggregate-cron` container's entrypoint: applies
  `schema.sql`, then loops every 60s running `aggregate/*.sql`.
- `aggregate/` — recurring cron scripts (raw → 1-minute/1-hour tables), plus
  `bootstrap_raw_tables.sql` (raw table hypertable/retention setup) and
  `kwh_backfill.sql` (manual repair/backfill tool, not part of the cron loop).
- `migrate/` — one-time InfluxDB → TimescaleDB historical migration tooling.
  `run_all.py` runs every script in the right order; `migrate_common.py` has
  the shared connection/config/checkpoint logic. Connection details are never
  hardcoded — see `migrate_common.get_config()`.

Related files elsewhere in the repo: `telegraf-timescale.conf` (repo root),
`timescaledb.env.sample` (repo root), `grafana/provisions/datasources/timescaledb.yml`,
`dashboards/dashboard-timescaledb.json`.

## Historical migration

`tools/timescaledb/setup.sh` offers to run this automatically. To run it
manually: `python3 timescaledb/migrate/run_all.py` (needs `psycopg2`
and `requests`; connection details come from env vars if set, otherwise you're
prompted — see `migrate_common.get_config()`). It's a one-time pull of each
InfluxDB RP's history via the InfluxDB 1.x HTTP query API, walking backward in
month-sized chunks with a `migration_progress` checkpoint table for
resumability (safe to interrupt and re-run).

There's no `migrate_kwh.py` — `pw_kwh_1h`'s history is instead derived from
the already-migrated `pw_autogen_1m` via `aggregate/kwh_backfill.sql`
(`run_all.py` does this automatically after `migrate_autogen.py`), since it's
fully computable from autogen and InfluxDB's own separate `kwh` RP doesn't
need a separate pull.

**Known, accepted limitation:** two accuracy improvements built into live
ingestion — time-weighted averaging in `pw_autogen_1m`, boundary-interpolated
integration in `pw_kwh_1h` (see Decisions below) — can't be applied
retroactively to migrated history, since both require raw samples that no
longer exist in InfluxDB by the time migration runs (InfluxDB's raw retention
is only 3 days). Migrated and newly-ingested data therefore have a small,
real, documented methodological difference at the migration cutover point —
negligible for short ranges, relevant for year-over-year historical analysis.

## Design decisions

**Storage type: `timestamptz`, not `timestamp without time zone`.** All
aggregate tables use `timestamptz`. A naive-UTC design requires every write
producing a real instant to be implicitly cast back to naive using the
session's `TimeZone` setting — invisible in the query text, and breaks
silently if the session default isn't UTC. `timestamptz` stores an
unambiguous instant regardless of session settings, eliminating this failure
class.

**Vitals resolution loss vs. stock InfluxDB (known, accepted).** Stock
InfluxDB's `cq_vitals7` captures `ISLAND_VL1N_Main`/`VL2N_Main`/`VL3N_Main`
(anti-islanding/grid-loss detection fields) at 15-second resolution — finer
than everything else, likely for post-hoc diagnostic review around grid
transitions rather than anything related to the Gateway's own real-time
protective response, which is independent and unaffected either way. This
project captures those same three fields at the same 1-minute resolution as
everything else in `pw_vitals_log`. Deliberate simplification, not
replicated.

**Storage size vs. stock InfluxDB (known tradeoff).** With identical
retention structure on both sides (raw data capped at 3 days, everything else
kept indefinitely), TimescaleDB's on-disk size after compression is
noticeably larger than InfluxDB's for the same history — InfluxDB's
purpose-built TSM storage engine is more space-efficient for this data shape
than TimescaleDB's general-purpose compression achieves here. Compression
(see below) closes most of that gap but not all of it. Budget meaningfully
more disk for the TimescaleDB path than you'd use for InfluxDB with the same
retention.

**Alerts: dynamic unpivot, permanent retention.** `pw_alerts_log` uses a
dynamic `jsonb_each()`-based unpivot rather than a hardcoded column list, so a
genuinely new Tesla alert type requires zero code changes — only Telegraf
auto-creating the new raw column (an already-existing, unrelated mechanism) is
needed. Uses `max()` aggregation (not `avg()`/`last()`), matching stock
InfluxDB's own `cq_alerts`'s `max(*)` semantics — "was this alert active at
any point in the bucket." Permanent retention (matches InfluxDB's alerts RP).

**Weather: narrow format, written directly by weather411 (no Telegraf, no raw
table, no cron).** `pw_weather_log` uses `(time, metric_name, value,
text_value)` — numeric fields in `value`, categorical/string fields
(`weather_main`, `weather_icon`, `name`, `country`, etc.) in `text_value`,
since averaging doesn't apply to text. `weather/server.py` writes one row per
field directly on each OpenWeatherMap fetch (~every 10 minutes internally),
via a `[TimescaleDB]` config section parallel to its existing `[InfluxDB]`
one — the same pattern InfluxDB itself uses (weather411 writes directly there
too; there's no `cq_weather` continuous query). `tools/timescaledb/setup.sh`
enables the `[TimescaleDB]` section without touching `[InfluxDB]`'s. This is
why `tools/timescaledb/powerwall.extend.yml.sample` patches `weather411` to
build locally (`build: ./weather`) instead of using the published
`jasonacox/weather411` image — the added TimescaleDB writer and its
`psycopg2-binary` dependency aren't in that image yet; the patch only applies
for installs that opt into this extension, core `powerwall.yml` still uses
the published image for everyone else.

**kwh: boundary-interpolated integration (a genuine accuracy improvement over
InfluxDB).** `pw_kwh_1h` uses `LAG()`-based trapezoidal integration that
deliberately interpolates energy contribution *across* hour boundaries
(splitting a boundary-spanning trapezoid proportionally between the two hours
it touches). This corrects a confirmed limitation in InfluxDB's own
`integral()` function, which does not interpolate across `GROUP BY time()`
bucket boundaries — the trapezoid spanning each boundary is dropped entirely,
causing systematic undercounting. Gap threshold: any interval between
consecutive `pw_autogen_1m` rows exceeding 5 minutes is treated as a real
outage (contributes 0 energy) rather than bridged as one large trapezoid.

**autogen: time-weighted averaging (not plain `avg()`).** `home`/`solar`/
`from_pw`/`to_pw`/`from_grid`/`to_grid` and current/voltage fields use
duration-weighted averaging (each sample weighted by seconds until the next
sample, clamped to bucket boundaries) rather than plain `avg()`. Root cause
this fixes: pypowerwall is a caching proxy polled independently by
`telegraf-timescale` and (when active) the stock `telegraf`; their polling
phases can be offset enough that a brief transient gets caught by an uneven
number of polls on each side. Plain `avg()` weights sample *count*, not
duration, so an unevenly-multi-polled transient gets uneven weight. Known
limitation: this discrepancy is on the order of low single-digit percent
during transition-heavy periods.

**Generalizing pack count / phase / timezone.** The original build-out of
this feature was done against one specific LAN install (3 Powerwalls,
split-phase, hardcoded hostnames). Turning it into a reusable extension
required removing those assumptions:
- Pack-count hardcoding in `aggregate_vitals_log.sql`/`aggregate_pod_log.sql`/
  `aggregate_pwtemps_log.sql` (and the equivalent migration scripts) replaced
  with the regex/whole-row-unpivot pattern described above.
- Split-phase vs. three-phase needed no code change — L3 fields simply read
  null/0 when absent, and this was already true of the schema.
- The hourly `kwh` aggregation's hardcoded installation-specific timezone
  string is now a psql variable (`-v tz=...`, passed by `cron-entrypoint.sh`
  from the `TZ` env var) instead of a literal string — kept in sync by
  `tz.sh` like every other TZ-sensitive file in this repo.
- Connection details moved from hardcoded LAN hostnames/ports to internal
  Docker Compose service names (`timescaledb`, `pypowerwall`, `weather411`)
  resolved via Docker's own DNS, and to env vars for the migration tool (see
  `migrate_common.get_config()`) instead of assumed addresses. TimescaleDB's
  own host/port/SSL mode are themselves now a variable
  (`TIMESCALEDB_HOST`/`TIMESCALEDB_PORT`/`TIMESCALEDB_SSLMODE` in
  `timescaledb.env`, templated into `telegraf-timescale.conf`,
  `grafana/provisions/datasources/timescaledb.yml`, `cron-entrypoint.sh`, and
  `weather411.conf`) rather than a hardcoded `timescaledb` service name, so
  the same generalized config also supports pointing at a genuinely external
  server — see "Bundled container vs. an existing server" above.
- `migrate_common.find_earliest_month()` queries InfluxDB for the actual
  earliest data point instead of assuming a fixed cutoff year — every
  installation's history starts on a different date.

**TimescaleDB chunk sizing.** A too-small `chunk_time_interval` (e.g. 1 day
on a high-frequency table) produces far more chunks than necessary, measurably
slowing range-scan queries. `schema.sql` uses 7-day chunks for the aggregate
tables (30 days for `pw_alerts_log`) and 1-day chunks for the raw tables
(matching their short 3-day retention). `merge_chunks()` can retroactively fix
a wrongly-chunked table, but requires genuinely temporally adjacent chunks
(`range_end` of one exactly equals `range_start` of the next) — detect true
contiguous runs first (e.g. via `LAG()` comparing `range_start` to the
previous row's `range_end`) before batching.

**Open item: no monthly tier, matching stock's own quirk.** Stock InfluxDB's
`cq_monthly` uses a flat `GROUP BY time(365d)` with no `tz()` clause — not
real calendar months, just a rolling 365-day window from InfluxDB's default
epoch. This project doesn't have a monthly tier at all: every "monthly" view
in the dashboard is computed on the fly from `pw_kwh_1h` via `time_bucket()`
instead, so this was never needed. Whether to add one — and if so, whether to
replicate InfluxDB's non-calendar-month quirk or do real calendar-month
bucketing — is still open.

## Gotchas

Quick-reference technical traps — read before touching any SQL involving
timestamps, InfluxQL, TimescaleDB compression/chunk operations, or the
aggregate scripts.

**Telegraf / raw data**
- `outputs.postgresql` only creates a column the first time it sees a
  non-null value for that field. A raw table's actual column list can be
  narrower than the source API's full field list. Querying a field that's
  never had real data hits `column does not exist`, not a null result. Always
  check `information_schema.columns` against the live table before writing a
  script that references specific columns by name — or better, use the
  whole-row `to_jsonb()` unpivot pattern instead, which sidesteps this
  entirely (see the narrow aggregate scripts).
- Telegraf's JSON parser silently drops string/boolean fields by default.
  Only numeric fields are auto-captured; string fields need explicit
  `json_string_fields = [...]` in the `inputs.http` block, or they never
  reach Postgres at all — no error, just absent. (weather411's direct
  Postgres writer isn't affected by this — it's not going through Telegraf.)
- `outputs.postgresql`'s `create_templates` setting only fires the first time
  Telegraf creates a table — it has no equivalent for adding a retention
  policy, which is why `bootstrap_raw_tables.sql` still needs to run on a
  schedule even with `create_templates` configured.
- pypowerwall is a caching proxy (~5–60s TTL depending on config layer), not a
  live passthrough. This does not by itself cause divergence between two
  independent pollers — the real source of collector-to-collector divergence
  is uneven *sample count* during transients (see "autogen" decision above).

**Running scripts on the host (outside Docker)**
- `timescaledb/migrate/run_all.py` (and the individual `migrate_*.py`
  scripts) need `psycopg2-binary` installed on the host if you run them
  directly with `python3` instead of letting `tools/timescaledb/setup.sh` run
  them in its ephemeral `python:3-alpine` container. `pip install psycopg2-binary
  requests` first, or you'll hit `ModuleNotFoundError: No module named
  'psycopg2'` immediately.
- Likewise, `tools/tesla-history/tesla-history.py` run directly on the host
  needs `psycopg2-binary` installed if `--target timescaledb`/`both` is
  used, in addition to the `pypowerwall`/`python-dateutil`/`influxdb`/
  `httpx`/`h2` dependencies already documented in
  `tools/tesla-history/README.md` — see that file's `pip install` line
  (kept in sync with `tools/tesla-history/Dockerfile`).
- `tesla-history.py`'s TimescaleDB path also shells out to the `psql`
  **binary** (not just the `psycopg2` Python module) to backfill
  `pw_kwh_1h` after every write — see `update_timescaledb()`. If the
  PostgreSQL client isn't installed on the host, that step fails with
  `FileNotFoundError(2, 'No such file or directory')` while everything
  else succeeds (the main write to `pw_autogen_1m`/`pw_grid_1m`/
  `pw_pod_log` already happened by that point — no data is lost, only
  the derived hourly table isn't refreshed for that range yet). Install
  the PostgreSQL client (e.g. `apt install postgresql-client` /
  `apk add postgresql-client`) and re-run for the same date range to
  backfill it. The Docker image already has this — only a bare host
  run needs it.

**Grafana**
- Grafana could render panels with "you do not currently have a default
  database configured for this data source" even though the datasource was
  correctly provisioned with a database, and it did *not* clear on its own —
  confirmed against a real installation, where it recurred on every restart
  and required manually opening the datasource and clicking Save & Test to
  clear (first for some panels, then the rest as they refreshed). Root
  cause: Grafana's postgres datasource plugin has a legacy top-level
  `database` field (what the backend actually uses to run queries) and a
  separate, currently-documented `jsonData.database` field — only
  `jsonData.database` is checked by the *frontend's* client-side validation
  before it'll render a panel, so a provisioning file that only sets the
  top-level field runs queries fine but still shows the "no default
  database" error every time the page loads fresh. Fixed by also setting
  `database` under `jsonData` in `grafana/timescaledb-template.yml`
  (`tools/timescaledb/setup.sh` copies this to
  `grafana/provisions/datasources/timescaledb.yml`), alongside the existing
  top-level `database` field. Verified against a real installation: the
  error no longer appears after a full stack restart, with no manual
  Save & Test needed.
- Separately, `tools/timescaledb/powerwall.extend.yml.sample` patches
  `grafana` with a `depends_on: timescaledb: condition: service_healthy,
  required: false` — `required: false` makes it a no-op in external mode
  (where the extend file has no `timescaledb` service to depend on at all,
  see "Bundled container vs. an existing server" above), but in bundled mode
  it makes Grafana wait for TimescaleDB's `pg_isready` healthcheck before
  starting. Verified via `docker compose config` that this merges cleanly
  with core `powerwall.yml`'s own list-form `depends_on: [influxdb]` on the
  same service. This closes a real (but separate) startup-race window; it
  was not, on its own, the fix for the "no default database" error above.

**Timestamps / timezones**
- `AT TIME ZONE` on an already-`timestamptz` value vs. a naive `timestamp`
  value does *opposite* things. On a naive value it attaches a zone (naive →
  instant); on a `timestamptz` it converts to a different wall-clock
  representation (instant → naive, in that zone). Applying the same
  expression to both types without checking which one you have is a reliable
  way to introduce a silent offset bug.
- `date_trunc()` and bare date-string comparisons against a `timestamptz`
  column both default to the *session's* timezone if no explicit zone is
  given, not UTC. Always use explicit `+00` offsets or
  `date_trunc('unit', ts, 'UTC')` / the 3-arg `time_bucket(width, ts, 'Zone')`
  form for anything DST-sensitive.
- TimescaleDB's `time_bucket()` 2-argument form buckets by UTC calendar
  boundaries, not local ones. Use the 3-argument timezone-aware form
  (`time_bucket('1 day', ts, 'America/Los_Angeles')`, supported since
  TimescaleDB 2.8) for any panel/report that should align to local calendar
  days.
- Grafana's `$__timeFilter()`/`$__timeFrom()`/`$__timeTo()` macros always
  compute bounds in UTC, regardless of the dashboard's Timezone setting. A
  `timestamptz` column with a single `AT TIME ZONE '$tz'` conversion in the
  `SELECT` is the correct pattern.
- A Grafana panel needing a single-row/stat-style result still needs a time
  column, but a real timestamp value causes duplicate/misaligned points if
  computed independently per query. Use `$__timeTo()::timestamptz AS time` —
  the macro is substituted as identical literal text across all targets in
  the same panel, guaranteeing alignment.

**TimescaleDB chunks / compression**
- `merge_chunks()` requires the target chunks to be genuinely temporally
  adjacent — a batching script that groups chunks by row-number/count alone
  will try to merge across real historical gaps and fail with "cannot create
  new chunk partition boundaries."
- A single `ERROR` (not `NOTICE`) partway through a batch
  `SELECT compress_chunk(c) FROM show_chunks(...)` statement aborts the
  *entire* statement, silently leaving every subsequent chunk unprocessed.
  Always use `compress_chunk(c, if_not_exists => true)` for idempotent batch
  compression.
- `INSERT ... ON CONFLICT DO UPDATE` (the upsert pattern used everywhere in
  this project) works correctly against compressed chunks on modern
  TimescaleDB (v2.11+). Some older/archived docs describe versions that
  blocked this — that's out of date.

**Postgres / general**
- A new table is owned by whichever role ran `CREATE TABLE`, not necessarily
  the role your application/cron actually connects as. If those differ, the
  new table needs an explicit `ALTER TABLE ... OWNER TO <service_role>;`
  immediately after creation.
- `GREATEST`/`LEAST` treat `NULL` as "not present," not as the minimum/maximum
  possible value — `GREATEST(NULL, 0)` returns `0`, not `NULL`. This silently
  converts "no reading this cycle" into "a real reading of zero." Use an
  explicit `CASE WHEN x IS NULL THEN NULL ...` when zero and "absent" need to
  stay distinguishable.
- Combining a `jsonb_typeof(...) <> 'null'` null-guard with an `OR`-joined
  regex filter in the same `WHERE` clause needs explicit parentheses —
  `WHERE a AND b OR c` parses as `(a AND b) OR c` (`AND` binds tighter than
  `OR`), silently reintroducing the null-cast crash the guard was meant to
  prevent for whichever branch is `OR`-ed in.
- Docker Compose `profiles:` gating an always-on service's `depends_on`
  target (e.g. `grafana` depending on `influxdb` when only a `timescaledb`
  profile is active) makes `docker compose up` fail outright. An earlier
  version of this feature used Compose profiles for datastore selection and
  hit exactly this; it's part of why the current design (see "Datastore
  selection is an opt-in Compose extend file" above) avoids `profiles:`
  entirely in favor of an extend file that either exists or doesn't, and
  drops hard `depends_on` dependencies where a service should tolerate its
  datasource/target not being up at boot (Grafana/weather411 both do).
- `depends_on: <service>: required: false` still requires that service to be
  *defined* somewhere in the merged compose files — `required: false` only
  makes it optional to be *running*, not optional to exist. A compose file
  referencing an undefined service (even with `required: false`) fails
  `docker compose config`/`up` outright. This is why external mode removes
  the bundled `timescaledb` service's `depends_on` entries along with the
  service itself, rather than leaving them pointing at nothing.

## Powerwall+ strings and Backup Switch fans (best-effort, unvalidated)

Both are ported (`pw_strings_log`/`pw_fans_log`, `aggregate_strings_log.sql`/
`aggregate_fans_log.sql`, `migrate_strings.py`/`migrate_fans.py`, and the
"String Voltage/Current/Power", "Inverter Power", and "Powerwall Temps and
Fans" dashboard panels), but **neither has ever been tested against real PW+
string monitoring or Backup Switch hardware** — there was none available to
validate against. The SQL/field-name patterns were derived from stock
InfluxDB's `cq_strings*`/`cq_inverters*`/`cq_fans` continuous queries and
tested end-to-end with synthetic data matching those field shapes, so the
*mechanism* (dynamic regex unpivot, scales to however many strings/inverters
are actually installed) is solid, but the exact field names/shapes from real
hardware were never cross-checked. If your install has this hardware and the
panels don't render correctly, check `information_schema.columns` on the
`http` table against the regexes in `aggregate_strings_log.sql`/
`aggregate_fans_log.sql` first.

The "Inverter Power" panel replicates stock InfluxDB's own panel-level split
exactly: `InverterN` is the sum of that inverter's first 4 strings' power
(A-D), `InverterN+` is the additional 2 strings (E-F) some configurations
have — not `aggregate_strings_log.sql`'s own precomputed `InverterN` total
(sum of all 6), which is also written to `pw_strings_log` but currently
unused by any panel.

## Version stat panel

The "Powerwall Dashboard" stat panel (bottom of the dashboard) is sourced the
same way as stock InfluxDB: `telegraf-timescale.conf` runs the same
`inputs.exec` block calling `ver.sh` (mounted read-only into the
`telegraf-timescale` service, same as the stock `telegraf` service), writing
into its own lazily-created `powerwall_dashboard` table. That table is
hypertabled/retained by `bootstrap_raw_tables.sql` the same way as `http` and
`alerts` (3-day retention — a fresh row lands every Telegraf interval, so the
"last value" query never actually needs the history).
