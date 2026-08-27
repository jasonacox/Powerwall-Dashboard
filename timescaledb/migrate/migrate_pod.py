#!/usr/bin/env python3
"""
One-time migration: InfluxDB pod.http -> TimescaleDB pw_pod_log
Uses SELECT * and a regex filter (matching aggregate_pod_log.sql's live
pattern) instead of a hardcoded PW1/PW2/PW3 field list, so this works for any
Powerwall count.
"""

import re
from datetime import datetime, timezone

import migrate_common as mc

SOURCE_MEASUREMENT = "pod.http"
DEST_TABLE = "pw_pod_log"

FIXED_FIELDS = {"backup_reserve_percent", "nominal_full_pack_energy", "nominal_energy_remaining"}
PACK_FIELD_PATTERN = re.compile(r"_POD_nom_(energy_remaining|full_pack_energy)$")


def main(config=None):
    config = config or mc.get_config()
    earliest_year, earliest_month = mc.find_earliest_month(config, SOURCE_MEASUREMENT)
    print(f"Earliest data found: {earliest_year}-{earliest_month:02d}")

    def fetch_and_pivot(year, month):
        start, end = mc.month_bounds(year, month)
        columns, values = mc.query_influx(config, "*", SOURCE_MEASUREMENT, start, end)
        pod_columns = [c for c in columns if c in FIXED_FIELDS or PACK_FIELD_PATTERN.search(c)]

        out = []
        for row in values:
            rowdict = dict(zip(columns, row))
            ts = datetime.fromtimestamp(rowdict["time"] / 1e9, tz=timezone.utc)
            for f in pod_columns:
                v = rowdict.get(f)
                if v is not None:
                    out.append((ts, f, v))
        return out

    def insert_rows(cur, rows):
        mc.insert_narrow(cur, DEST_TABLE, "metric_name", rows)

    mc.run_migration(config["pg_dsn"], SOURCE_MEASUREMENT, config["source_key"], earliest_year, earliest_month, fetch_and_pivot, insert_rows)


if __name__ == "__main__":
    main()
