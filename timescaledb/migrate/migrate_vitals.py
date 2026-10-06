#!/usr/bin/env python3
"""
One-time migration: InfluxDB vitals.http -> TimescaleDB pw_vitals_log
Uses SELECT * and a regex filter (matching aggregate_vitals_log.sql's live
pattern) instead of a hardcoded PW1/PW2/PW3 field list, so this works for any
Powerwall count. Also computes the derived PWn_pinv_total = VSplit1 + VSplit2
field for whatever pack numbers actually appear in the data, matching
aggregate_vitals_log.sql's live behavior.
"""

import re
from datetime import datetime, timezone

import migrate_common as mc

SOURCE_MEASUREMENT = "vitals.http"
DEST_TABLE = "pw_vitals_log"

FIELD_PATTERN = re.compile(r"^(ISLAND_|METER_[XYZ]_)|_(PINV_Fout|PINV_VSplit[12]|v_out|f_out|i_out|p_out|q_out)$")
VSPLIT1_PATTERN = re.compile(r"^(PW\d+)_PINV_VSplit1$")


def main(config=None):
    config = config or mc.get_config()
    earliest_year, earliest_month = mc.find_earliest_month(config, SOURCE_MEASUREMENT)
    print(f"Earliest data found: {earliest_year}-{earliest_month:02d}")

    def fetch_and_pivot(year, month):
        start, end = mc.month_bounds(year, month)
        columns, values = mc.query_influx(config, "*", SOURCE_MEASUREMENT, start, end)
        vitals_columns = [c for c in columns if FIELD_PATTERN.search(c)]

        out = []
        for row in values:
            rowdict = dict(zip(columns, row))
            ts = datetime.fromtimestamp(rowdict["time"] / 1e9, tz=timezone.utc)

            for f in vitals_columns:
                v = rowdict.get(f)
                if v is not None:
                    out.append((ts, f, v))

            for f in vitals_columns:
                m = VSPLIT1_PATTERN.match(f)
                if not m:
                    continue
                pack = m.group(1)
                v1 = rowdict.get(f)
                v2 = rowdict.get(f"{pack}_PINV_VSplit2")
                if v1 is not None and v2 is not None:
                    out.append((ts, f"{pack}_pinv_total", v1 + v2))

        return out

    def insert_rows(cur, rows):
        mc.insert_narrow(cur, DEST_TABLE, "metric_name", rows)

    mc.run_migration(config["pg_dsn"], SOURCE_MEASUREMENT, config["source_key"], earliest_year, earliest_month, fetch_and_pivot, insert_rows)


if __name__ == "__main__":
    main()
