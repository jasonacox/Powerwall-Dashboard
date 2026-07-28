#!/usr/bin/env python3
"""
 Export grid outage times from InfluxDB

 Outputs a CSV with columns: StartTime, EndTime, DurationMinutes, StatusValue

 Author: Adapted from tools/export/export.py
"""
import csv
from datetime import datetime, timedelta, timezone
import sys
import zoneinfo

try:
    from influxdb import InfluxDBClient
except ImportError:
    sys.exit("ERROR: Missing python influxdb module. Run 'pip install influxdb'.")

# InfluxDB Settings
INFLUXDB_HOST = "localhost"
INFLUXDB_PORT = "8086"
INFLUXDB_USER = ""
INFLUXDB_PASS = ""
INFLUXDB_DB = "powerwall"
TZ = zoneinfo.ZoneInfo("America/New_York")
OUTPUT_FILE = "outages.csv"


def parse_ts(raw):
    """Parse timestamp string from InfluxDB into timezone-aware datetime."""
    if isinstance(raw, datetime):
        return raw
    s = raw.replace("Z", "+00:00")
    return datetime.fromisoformat(s).astimezone(TZ)


def query_outages(start, end):
    """
    Pull grid_status from the 'grid' retention policy and detect outage
    intervals.  Returns a list of dicts with keys:
        start, end, duration (timedelta), status_value
    """
    client = InfluxDBClient(INFLUXDB_HOST, INFLUXDB_PORT, INFLUXDB_USER, INFLUXDB_PASS, INFLUXDB_DB)

    query = (
        'SELECT "grid_status" FROM "grid"."http" '
        'WHERE "grid_status" <= 0 AND time >= \'%s\' AND time <= \'%s\' '
        'ORDER BY time ASC'
    ) % (start, end)

    print(f"Querying InfluxDB ...", flush=True)
    result = client.query(query)

    points = list(result.get_points())
    if not points:
        print("No outage data found for the requested period.")
        return []

    # Sort and convert timestamps
    points.sort(key=lambda p: p["time"])

    # Merge consecutive minute-level readings into intervals
    outages = []
    interval_start = None
    last_ts = None
    lowest_status = None

    for point in points:
        ts = parse_ts(point["time"])
        status = int(point["grid_status"])

        if lowest_status is None or status < lowest_status:
            lowest_status = status

        if interval_start is None:
            interval_start = ts
            last_ts = ts
        elif (ts - last_ts).total_seconds() > 120:
            outages.append({
                "start": interval_start,
                "end": last_ts + timedelta(minutes=1),
                "status_value": lowest_status,
            })
            interval_start = ts
            last_ts = ts
            lowest_status = status
        else:
            last_ts = ts

    if interval_start is not None:
        outages.append({
            "start": interval_start,
            "end": last_ts + timedelta(minutes=1),
            "status_value": lowest_status,
        })

    return outages


def write_csv(outages, outfile):
    """Write outage intervals to CSV."""
    with open(outfile, "w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["StartTime", "EndTime", "DurationMinutes", "StatusValue"])

        for o in outages:
            dur = o["end"] - o["start"]
            dur_min = round(dur.total_seconds() / 60, 1)
            writer.writerow([
                o["start"].strftime("%Y-%m-%d %H:%M:%S"),
                o["end"].strftime("%Y-%m-%d %H:%M:%S"),
                dur_min,
                o["status_value"],
            ])


def main():
    s = e = None

    if len(sys.argv) == 1:
        print(f"Usage: {sys.argv[0]} [today|yesterday|all] or [YYYY-mm-dd] [YYYY-mm-dd]")
        print("  today      - export today's outages")
        print("  yesterday  - export yesterday's outages")
        print("  all        - export all recorded outages")
        print("  YYYY-mm-dd - export single day")
        print("  YYYY-mm-dd YYYY-mm-dd - export date range")
        sys.exit(1)

    today = datetime.now(TZ).date()

    if sys.argv[1].lower() == "today":
        s = today
        e = today + timedelta(days=1)
    elif sys.argv[1].lower() == "yesterday":
        s = today - timedelta(days=1)
        e = today
    elif sys.argv[1].lower() == "all":
        s = datetime(2018, 1, 1, tzinfo=TZ)
        e = today + timedelta(days=1)
    else:
        if len(sys.argv) == 2:
            s = datetime.strptime(sys.argv[1], "%Y-%m-%d")
            s = s.replace(tzinfo=TZ)
            e = s + timedelta(days=1)
        else:
            s = datetime.strptime(sys.argv[1], "%Y-%m-%d")
            e = datetime.strptime(sys.argv[2], "%Y-%m-%d")
            s = s.replace(tzinfo=TZ)
            e = e.replace(tzinfo=TZ) + timedelta(days=1)

    start_str = s.strftime("%Y-%m-%d")
    end_str = e.strftime("%Y-%m-%d")

    if e == s + timedelta(days=1):
        print(f"Exporting outages [{start_str}] -> {OUTPUT_FILE}")
    else:
        print(f"Exporting outages [{start_str} to {end_str}] -> {OUTPUT_FILE}")

    outages = query_outages(start_str, end_str)
    if outages:
        write_csv(outages, OUTPUT_FILE)
        print(f"\nFound {len(outages)} outage(s) -> written to {OUTPUT_FILE}")
        for o in outages:
            dur = o["end"] - o["start"]
            print(f"  {o['start'].strftime('%Y-%m-%d %H:%M')} - "
                  f"{o['end'].strftime('%H:%M')} ({dur.total_seconds()/60:.0f} min)")
    else:
        print("No outages found.")


if __name__ == "__main__":
    main()
