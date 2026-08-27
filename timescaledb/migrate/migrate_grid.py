#!/usr/bin/env python3
"""
One-time migration: InfluxDB grid.http -> TimescaleDB pw_grid_1m

Note: there is no migrate_kwh.py -- pw_kwh_1h's history is derived instead
from the already-migrated pw_autogen_1m via
timescaledb/aggregate/kwh_backfill.sql (run that after this script and
migrate_autogen.py), since kwh is fully computable from autogen and doesn't
need its own InfluxDB pull.
"""

from datetime import datetime, timezone

import migrate_common as mc

SOURCE_MEASUREMENT = "grid.http"
DEST_TABLE = "pw_grid_1m"

FIELDS = ["grid_status"]


def main(config=None):
    config = config or mc.get_config()
    earliest_year, earliest_month = mc.find_earliest_month(config, SOURCE_MEASUREMENT)
    print(f"Earliest data found: {earliest_year}-{earliest_month:02d}")

    def fetch_and_pivot(year, month):
        start, end = mc.month_bounds(year, month)
        columns, values = mc.query_influx(config, ",".join(FIELDS), SOURCE_MEASUREMENT, start, end)
        out = []
        for row in values:
            rowdict = dict(zip(columns, row))
            ts = datetime.fromtimestamp(rowdict["time"] / 1e9, tz=timezone.utc)
            out.append([ts] + [rowdict.get(f) for f in FIELDS])
        return out

    def insert_rows(cur, rows):
        mc.insert_wide(cur, DEST_TABLE, FIELDS, rows)

    mc.run_migration(config["pg_dsn"], SOURCE_MEASUREMENT, config["source_key"], earliest_year, earliest_month, fetch_and_pivot, insert_rows)


if __name__ == "__main__":
    main()
