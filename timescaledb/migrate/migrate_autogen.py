#!/usr/bin/env python3
"""
One-time migration: InfluxDB autogen.http -> TimescaleDB pw_autogen_1m
Fields are a fixed, site-wide set (not per-pack), so a plain field list is
fine here -- see migrate_vitals.py/migrate_pod.py/migrate_pwtemps.py for the
dynamic-pivot approach used where fields scale with hardware.
"""

from datetime import datetime, timezone

import migrate_common as mc

SOURCE_MEASUREMENT = "autogen.http"
DEST_TABLE = "pw_autogen_1m"

FIELDS = [
    "home", "solar", "from_pw", "to_pw", "from_grid", "to_grid", "percentage",
    "home_current", "solar_current", "pw_current", "grid_current",
    "home_voltage", "solar_voltage", "pw_voltage", "grid_voltage",
]


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
