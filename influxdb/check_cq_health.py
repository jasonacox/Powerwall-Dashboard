#!/usr/bin/env python3
"""
Check the health of Continuous Queries in InfluxDB 1.x

Author: Jason A. Cox
GitHub: https://github.com/jasonacox/Powerwall-Dashboard
Date: 2025-05-11

This script checks the health of Continuous Queries (CQs) in an InfluxDB 1.x database by:
  - Parsing the list of continuous queries using `SHOW CONTINUOUS QUERIES`
  - Extracting the target measurement and retention policy from each CQ
  - Determining the GROUP BY time() interval and adjusting the lookback window accordingly
  - Querying each CQ target to see if it has written data recently
  - Reporting which CQs are writing data ("Healthy") and which are not

Features:
  - Automatically adjusts the lookback window based on the CQ's time grouping
  - Color-coded console output for quick status checks
  - Optional CSV export of results
  - Command-line support to specify the InfluxDB host

Requirements:
    pip install requests

Usage:
    python3 check_cq_health.py
    python3 check_cq_health.py --host http://influxdb:8086
    python3 check_cq_health.py --csv

"""

import argparse
import csv
import re
from datetime import datetime
import requests

# Defaults
DEFAULT_INFLUX_HOST = "http://localhost:8086"
DB_NAME = "powerwall"

# ANSI colors for terminal output
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
RESET = "\033[0m"

# Map GROUP BY time() intervals to lookback periods for health checking
LOOKBACK_MAP = {
    "1m": "5m",
    "5m": "15m",
    "15m": "30m",
    "1h": "2h",
    "2h": "4h",
    "1d": "2d",
    "30d": "60d",
    "365d": "400d"
}

def influx_query(query, host):
    """Send a raw query to the InfluxDB host"""
    url = f"{host}/query"
    params = {"q": query}
    if DB_NAME:
        params["db"] = DB_NAME
    resp = requests.get(url, params=params)
    resp.raise_for_status()
    return resp.json()

def get_continuous_queries(host):
    """Return a list of (name, query) tuples for all CQs in the specified database"""
    data = influx_query("SHOW CONTINUOUS QUERIES", host)
    cqs = []
    for result in data.get("results", []):
        for series in result.get("series", []):
            if series.get("name") != DB_NAME:
                continue
            for row in series.get("values", []):
                name, query = row
                cqs.append((name, query))
    return cqs

def extract_target(query):
    """Extract the INTO <target> value from a CQ definition, resolving :MEASUREMENT"""
    match = re.search(r'INTO\s+([^\s]+)', query, re.IGNORECASE)
    if not match:
        return None
    target = match.group(1)

    if ":MEASUREMENT" in target:
        # Try to find the source measurement from an inner SELECT
        from_match = re.search(r'FROM\s+\(?SELECT.*?FROM\s+([a-zA-Z0-9_\.]+)', query, re.IGNORECASE | re.DOTALL)
        if not from_match:
            # Fallback for simpler CQs like "FROM autogen.http"
            from_match = re.search(r'FROM\s+([a-zA-Z0-9_\.]+)', query, re.IGNORECASE)
        if from_match:
            source_measurement = from_match.group(1).split(".")[-1]
            target = target.replace(":MEASUREMENT", source_measurement)
        else:
            return None
    return target

def extract_lookback(query):
    """Determine the lookback window based on the GROUP BY time() interval"""
    match = re.search(r'GROUP BY\s+time\(([^)]+)\)', query, re.IGNORECASE)
    if match:
        duration = match.group(1).strip()
        return LOOKBACK_MAP.get(duration, "10m")
    return "5m"

def has_recent_data(target, lookback, host):
    """Check if recent data exists in the CQ's target measurement within the lookback window"""
    try:
        rp, measurement = target.split(".", 1)
        query = f"SELECT * FROM {rp}.{measurement} WHERE time > now() - {lookback} LIMIT 1"
        data = influx_query(query, host)
        return any("series" in result for result in data["results"])
    except Exception as e:
        print(f"{YELLOW}⚠️  Error checking {target}: {e}{RESET}")
        return False

def main():
    parser = argparse.ArgumentParser(description="Check InfluxDB Continuous Query health")
    parser.add_argument("--host", type=str, default=DEFAULT_INFLUX_HOST, help="InfluxDB host (e.g., http://localhost:8086)")
    parser.add_argument("--csv", action="store_true", help="Export results to CSV")
    args = parser.parse_args()

    influx_host = args.host

    print(f"\n🔍 Checking Continuous Queries in '{DB_NAME}' on host {influx_host}...\n")
    results = []

    for name, query in get_continuous_queries(influx_host):
        target = extract_target(query)
        lookback = extract_lookback(query)
        if not target:
            print(f"{YELLOW}⚠️  Could not parse target for CQ: {name}{RESET}")
            results.append((name, "Unknown", "Parse Error"))
            continue
        healthy = has_recent_data(target, lookback, influx_host)
        status_text = "Healthy" if healthy else "No recent data"
        color = GREEN if healthy else RED
        print(f"{name:<30} → {target:<40} : {color}{status_text}{RESET}  (lookback={lookback})")
        results.append((name, target, status_text))

    if args.csv:
        now = datetime.now().strftime("%Y%m%d_%H%M")
        filename = f"cq_health_{now}.csv"
        with open(filename, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["CQ Name", "Target", "Status"])
            writer.writerows(results)
        print(f"\n📄 CSV report saved to: {filename}")

if __name__ == "__main__":
    main()
