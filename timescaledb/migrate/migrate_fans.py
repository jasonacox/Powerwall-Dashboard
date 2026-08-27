#!/usr/bin/env python3
"""
One-time migration: InfluxDB fans.http -> TimescaleDB pw_fans_log
Best-effort port of Backup Switch fan telemetry (no hardware to validate
against -- see timescaledb/README.md). Uses SELECT * and a regex filter
(matching aggregate_fans_log.sql's live pattern) instead of a fixed field list.
"""

import re
from datetime import datetime, timezone

import migrate_common as mc

SOURCE_MEASUREMENT = "fans.http"
DEST_TABLE = "pw_fans_log"

FIELD_PATTERN = re.compile(r"^FAN[1-6]_(target|actual)$")


def main(config=None):
    config = config or mc.get_config()
    earliest_year, earliest_month = mc.find_earliest_month(config, SOURCE_MEASUREMENT)
    print(f"Earliest data found: {earliest_year}-{earliest_month:02d}")

    def fetch_and_pivot(year, month):
        start, end = mc.month_bounds(year, month)
        columns, values = mc.query_influx(config, "*", SOURCE_MEASUREMENT, start, end)
        fan_columns = [c for c in columns if FIELD_PATTERN.search(c)]

        out = []
        for row in values:
            rowdict = dict(zip(columns, row))
            ts = datetime.fromtimestamp(rowdict["time"] / 1e9, tz=timezone.utc)
            for f in fan_columns:
                v = rowdict.get(f)
                if v is not None:
                    out.append((ts, f, v))
        return out

    def insert_rows(cur, rows):
        mc.insert_narrow(cur, DEST_TABLE, "metric_name", rows)

    mc.run_migration(config["pg_dsn"], SOURCE_MEASUREMENT, config["source_key"], earliest_year, earliest_month, fetch_and_pivot, insert_rows)


if __name__ == "__main__":
    main()
