#!/usr/bin/env python3
"""
One-time migration: InfluxDB alerts.alerts -> TimescaleDB pw_alerts_log
Uses SELECT * (not a hardcoded field list) since alert types are not a
fixed, known set. Strips the "max_" prefix that cq_alerts's max(*)
aggregation adds to every field name, so migrated alert_name values match
live-ingested ones exactly (e.g. "FWUpdateSucceeded", not "max_FWUpdateSucceeded").
"""

from datetime import datetime, timezone

import migrate_common as mc

SOURCE_MEASUREMENT = "alerts.alerts"
DEST_TABLE = "pw_alerts_log"


def main(config=None):
    config = config or mc.get_config()
    earliest_year, earliest_month = mc.find_earliest_month(config, SOURCE_MEASUREMENT)
    print(f"Earliest data found: {earliest_year}-{earliest_month:02d}")

    def fetch_and_pivot(year, month):
        start, end = mc.month_bounds(year, month)
        columns, values = mc.query_influx(config, "*", SOURCE_MEASUREMENT, start, end)
        # Only columns with the max_ prefix are real alert fields -- this
        # automatically excludes time and any tags (month, year, etc.)
        # without needing to know their names in advance.
        alert_columns = [c for c in columns if c.startswith("max_")]

        out = []
        for row in values:
            rowdict = dict(zip(columns, row))
            ts = datetime.fromtimestamp(rowdict["time"] / 1e9, tz=timezone.utc)
            for col in alert_columns:
                v = rowdict.get(col)
                if v is not None:
                    out.append((ts, col[len("max_"):], v))
        return out

    def insert_rows(cur, rows):
        mc.insert_narrow(cur, DEST_TABLE, "alert_name", rows)

    mc.run_migration(config["pg_dsn"], SOURCE_MEASUREMENT, config["source_key"], earliest_year, earliest_month, fetch_and_pivot, insert_rows)


if __name__ == "__main__":
    main()
