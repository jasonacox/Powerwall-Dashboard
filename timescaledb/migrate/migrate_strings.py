#!/usr/bin/env python3
"""
One-time migration: InfluxDB strings.http -> TimescaleDB pw_strings_log
Best-effort port of Powerwall+ string monitoring (no PW+ hardware to validate
against -- see timescaledb/README.md). Uses SELECT * and a regex filter
(matching aggregate_strings_log.sql's live pattern) instead of a fixed field
list, so this works for any number of installed strings/inverters. Also
computes the derived per-inverter total power, matching aggregate_strings_log.sql.
"""

import re
from datetime import datetime, timezone

import migrate_common as mc

SOURCE_MEASUREMENT = "strings.http"
DEST_TABLE = "pw_strings_log"

FIELD_PATTERN = re.compile(r"^[A-F][1-5]?_(Current|Power|Voltage)$")
POWER_PATTERN = re.compile(r"^([A-F])([1-5]?)_Power$")
# Matches aggregate_strings_log.sql's inverter numbering: unsuffixed -> Inverter1,
# suffix "1" -> Inverter2, ... suffix "5" -> Inverter6.
SUFFIX_TO_INVERTER = {"": "Inverter1", "1": "Inverter2", "2": "Inverter3",
                       "3": "Inverter4", "4": "Inverter5", "5": "Inverter6"}
LETTERS = "ABCDEF"


def main(config=None):
    config = config or mc.get_config()
    earliest_year, earliest_month = mc.find_earliest_month(config, SOURCE_MEASUREMENT)
    print(f"Earliest data found: {earliest_year}-{earliest_month:02d}")

    def fetch_and_pivot(year, month):
        start, end = mc.month_bounds(year, month)
        columns, values = mc.query_influx(config, "*", SOURCE_MEASUREMENT, start, end)
        string_columns = [c for c in columns if FIELD_PATTERN.search(c)]

        out = []
        for row in values:
            rowdict = dict(zip(columns, row))
            ts = datetime.fromtimestamp(rowdict["time"] / 1e9, tz=timezone.utc)

            for f in string_columns:
                v = rowdict.get(f)
                if v is not None:
                    out.append((ts, f, v))

            for suffix, inverter in SUFFIX_TO_INVERTER.items():
                power_fields = [f"{letter}{suffix}_Power" for letter in LETTERS]
                values_for_inverter = [rowdict.get(f) for f in power_fields]
                if all(v is not None for v in values_for_inverter):
                    out.append((ts, inverter, sum(values_for_inverter)))

        return out

    def insert_rows(cur, rows):
        mc.insert_narrow(cur, DEST_TABLE, "metric_name", rows)

    mc.run_migration(config["pg_dsn"], SOURCE_MEASUREMENT, config["source_key"], earliest_year, earliest_month, fetch_and_pivot, insert_rows)


if __name__ == "__main__":
    main()
