#!/usr/bin/env python3
"""
One-time migration: InfluxDB autogen.weather -> TimescaleDB pw_weather_log
Field set is fixed (controlled by OpenWeatherMap's schema at the time this
project was built, not per-installation hardware), so a plain field list is
fine here.
"""

from datetime import datetime, timezone

import migrate_common as mc

SOURCE_MEASUREMENT = "autogen.weather"
DEST_TABLE = "pw_weather_log"

NUMERIC_FIELDS = [
    "clouds", "dt", "feels_like", "humidity", "id", "pressure",
    "rain_1h", "rain_3h", "snow_1h", "snow_3h", "sunrise", "sunset",
    "temp_max", "temp_min", "temperature", "tz", "visibility",
    "weather_id", "wind_deg", "wind_gust", "wind_speed",
]
TEXT_FIELDS = ["country", "name", "weather_description", "weather_icon", "weather_main"]
ALL_FIELDS = NUMERIC_FIELDS + TEXT_FIELDS


def main(config=None):
    config = config or mc.get_config()
    earliest_year, earliest_month = mc.find_earliest_month(config, SOURCE_MEASUREMENT)
    print(f"Earliest data found: {earliest_year}-{earliest_month:02d}")

    def fetch_and_pivot(year, month):
        start, end = mc.month_bounds(year, month)
        quoted_fields = ",".join(f'"{f}"' for f in ALL_FIELDS)
        columns, values = mc.query_influx(config, quoted_fields, SOURCE_MEASUREMENT, start, end)

        out = []
        for row in values:
            rowdict = dict(zip(columns, row))
            ts = datetime.fromtimestamp(rowdict["time"] / 1e9, tz=timezone.utc)

            for f in NUMERIC_FIELDS:
                v = rowdict.get(f)
                if v is not None:
                    out.append((ts, f, v, None))

            for f in TEXT_FIELDS:
                v = rowdict.get(f)
                if v is not None:
                    out.append((ts, f, None, v))
        return out

    def insert_rows(cur, rows):
        mc.insert_narrow_text(cur, DEST_TABLE, rows)

    mc.run_migration(config["pg_dsn"], SOURCE_MEASUREMENT, config["source_key"], earliest_year, earliest_month, fetch_and_pivot, insert_rows)


if __name__ == "__main__":
    main()
