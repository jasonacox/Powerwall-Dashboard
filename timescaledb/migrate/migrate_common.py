"""
Shared helpers for the one-time InfluxDB -> TimescaleDB historical migration
scripts (migrate_*.py in this directory).

Connection details are never hardcoded (see timescaledb/README.md):
the TimescaleDB side always comes from this stack's own env vars (these
scripts run inside the compose network, where POSTGRES_USER/PASSWORD/DB,
PGHOST/PGPORT, and PGSSLMODE are already correct -- setup.sh sets these from
timescaledb.env, pointing at either the bundled container or an existing
server); the InfluxDB side defaults to this stack's own "influxdb" service
but can be overridden via env vars or an interactive prompt, since a user may
be migrating from a different/external InfluxDB instance.
"""

import os
import sys
import requests
import psycopg2
import psycopg2.extras
from datetime import datetime, timezone


def _prompt(label, default):
    if not sys.stdin.isatty():
        return default
    raw = input(f"{label} [{default}]: ").strip()
    return raw or default


def get_config():
    influx_host = os.environ.get("INFLUX_HOST") or _prompt("InfluxDB host", "influxdb")
    influx_port = os.environ.get("INFLUX_PORT") or _prompt("InfluxDB port", "8086")
    influx_db = os.environ.get("INFLUX_DB") or _prompt("InfluxDB database", "powerwall")
    influx_user = os.environ.get("INFLUX_USER", "")
    influx_password = os.environ.get("INFLUX_PASSWORD", "")

    pg_host = os.environ.get("PGHOST", "timescaledb")
    pg_port = os.environ.get("PGPORT", "5432")
    pg_db = os.environ.get("POSTGRES_DB", "powerwall")
    pg_user = os.environ.get("POSTGRES_USER", "telegraf_powerwall")
    pg_password = os.environ.get("POSTGRES_PASSWORD", "")
    pg_sslmode = os.environ.get("PGSSLMODE", "disable")

    return {
        "influx_url": f"http://{influx_host}:{influx_port}/query",
        "influx_db": influx_db,
        "influx_user": influx_user,
        "influx_password": influx_password,
        "pg_dsn": f"host={pg_host} port={pg_port} dbname={pg_db} user={pg_user} password={pg_password} sslmode={pg_sslmode}",
        # Identifies which InfluxDB instance this run is reading from, so a
        # migration checkpoint from one source is never mistaken for "done"
        # against a different source (see migration_progress in schema.sql).
        "source_key": f"{influx_host}:{influx_port}/{influx_db}",
    }


def month_chunks_descending(earliest_year, earliest_month):
    """Yield (year, month) tuples from the current month back to earliest_year/earliest_month."""
    now = datetime.now(timezone.utc)
    y, m = now.year, now.month
    while (y, m) >= (earliest_year, earliest_month):
        yield y, m
        m -= 1
        if m == 0:
            m = 12
            y -= 1


def month_bounds(year, month):
    start = datetime(year, month, 1, tzinfo=timezone.utc)
    if month == 12:
        end = datetime(year + 1, 1, 1, tzinfo=timezone.utc)
    else:
        end = datetime(year, month + 1, 1, tzinfo=timezone.utc)
    return start, end


def query_influx(config, select_clause, source_measurement, start, end, timeout=180):
    """Run one InfluxQL query, return (columns, rows) or ([], []) if no data."""
    q = (
        f"SELECT {select_clause} FROM {source_measurement} "
        f"WHERE time >= '{start.isoformat()}' AND time < '{end.isoformat()}'"
    )
    params = {"db": config["influx_db"], "q": q, "epoch": "ns"}
    if config["influx_user"]:
        params["u"] = config["influx_user"]
        params["p"] = config["influx_password"]
    resp = requests.get(config["influx_url"], params=params, timeout=timeout)
    resp.raise_for_status()
    data = resp.json()

    results = data.get("results", [{}])[0]
    if "error" in results:
        raise RuntimeError(f"InfluxDB error: {results['error']}")
    series = results.get("series")
    if not series:
        return [], []
    return series[0]["columns"], series[0]["values"]


def find_earliest_month(config, source_measurement):
    """
    Query InfluxDB for the actual earliest point in source_measurement,
    instead of assuming a fixed cutoff year -- every installation's history
    starts at a different date, so don't bake in as-built assumptions.
    Falls back to 10 years back if the measurement is empty
    (nothing to migrate, the walk-back loop will just find 0 rows every
    month and finish immediately).
    """
    params = {"db": config["influx_db"], "q": f"SELECT * FROM {source_measurement} LIMIT 1", "epoch": "ns"}
    if config["influx_user"]:
        params["u"] = config["influx_user"]
        params["p"] = config["influx_password"]
    resp = requests.get(config["influx_url"], params=params, timeout=30)
    resp.raise_for_status()
    results = resp.json().get("results", [{}])[0]
    series = results.get("series")
    now = datetime.now(timezone.utc)
    if not series:
        return now.year - 10, 1
    columns = series[0]["columns"]
    row = series[0]["values"][0]
    ts = datetime.fromtimestamp(dict(zip(columns, row))["time"] / 1e9, tz=timezone.utc)
    return ts.year, ts.month


def already_done(cur, source_measurement, source_key, year, month):
    cur.execute(
        "SELECT status FROM migration_progress WHERE source_measurement=%s AND source=%s AND year=%s AND month=%s",
        (source_measurement, source_key, year, month),
    )
    row = cur.fetchone()
    return row is not None and row[0] == "done"


def mark_progress(cur, source_measurement, source_key, year, month, status, row_count=None):
    cur.execute(
        """
        INSERT INTO migration_progress (source_measurement, source, year, month, status, row_count, migrated_at)
        VALUES (%s, %s, %s, %s, %s, %s, now())
        ON CONFLICT (source_measurement, source, year, month) DO UPDATE SET
          status = EXCLUDED.status, row_count = EXCLUDED.row_count, migrated_at = EXCLUDED.migrated_at
        """,
        (source_measurement, source_key, year, month, status, row_count),
    )


def insert_wide(cur, dest_table, columns, rows):
    """rows: list of tuples matching (time, *columns), upserted by time.

    Fill-gaps-only, same as tesla-history.py's write_timescaledb(): COALESCE
    keeps the existing value on conflict rather than overwriting it. This
    table can already have live-ingested data for the same timestamps the
    migration is walking back over (e.g. if TimescaleDB was set up and has
    been running for a while before a user goes back to migrate older
    InfluxDB history) -- a plain EXCLUDED.col overwrite would silently
    replace that live data with the InfluxDB-derived value, making a re-run
    of the migration unsafe. This makes it safe to run at any time, not just
    during initial setup.
    """
    if not rows:
        return
    cols = ["time"] + columns
    set_clause = ", ".join(f"{c} = COALESCE({dest_table}.{c}, EXCLUDED.{c})" for c in columns)
    sql = (
        f"INSERT INTO {dest_table} ({','.join(cols)}) VALUES %s "
        f"ON CONFLICT (time) DO UPDATE SET {set_clause}"
    )
    psycopg2.extras.execute_values(cur, sql, rows, page_size=1000)


def insert_narrow(cur, dest_table, name_col, rows):
    """rows: list of (time, name, value) tuples."""
    if not rows:
        return
    sql = (
        f"INSERT INTO {dest_table} (time, {name_col}, value) VALUES %s "
        f"ON CONFLICT (time, {name_col}) DO NOTHING"
    )
    psycopg2.extras.execute_values(cur, sql, rows, page_size=5000)


def insert_narrow_text(cur, dest_table, rows):
    """rows: list of (time, metric_name, value, text_value) tuples."""
    if not rows:
        return
    sql = (
        f"INSERT INTO {dest_table} (time, metric_name, value, text_value) VALUES %s "
        f"ON CONFLICT (time, metric_name) DO NOTHING"
    )
    psycopg2.extras.execute_values(cur, sql, rows, page_size=5000)


def run_migration(pg_dsn, source_measurement, source_key, earliest_year, earliest_month, fetch_and_pivot, insert_rows):
    """
    Generic backward-walking, checkpointed migration driver shared by every
    migrate_*.py script. fetch_and_pivot(year, month) -> rows;
    insert_rows(cur, rows) -> None.
    """
    conn = psycopg2.connect(pg_dsn)
    conn.autocommit = False

    for year, month in month_chunks_descending(earliest_year, earliest_month):
        with conn.cursor() as cur:
            if already_done(cur, source_measurement, source_key, year, month):
                print(f"[skip] {year}-{month:02d} already migrated")
                continue

        try:
            print(f"[fetch] {year}-{month:02d} ...", end=" ", flush=True)
            rows = fetch_and_pivot(year, month)
            print(f"{len(rows)} rows")

            with conn.cursor() as cur:
                insert_rows(cur, rows)
                mark_progress(cur, source_measurement, source_key, year, month, "done", len(rows))
            conn.commit()
            print(f"[done]  {year}-{month:02d}")

        except Exception as e:
            conn.rollback()
            with conn.cursor() as cur:
                mark_progress(cur, source_measurement, source_key, year, month, "failed")
            conn.commit()
            print(f"[FAIL]  {year}-{month:02d}: {e}", file=sys.stderr)

    conn.close()
