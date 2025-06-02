#!/usr/bin/env python3
"""
InfluxDB Viewer Tool

This script provides a command-line and interactive shell interface for exploring and querying an InfluxDB database.

Features:
- List retention policies, measurements, and fields in an InfluxDB database.
- Query the last hour of data for a specific field in a measurement.
- Interactive shell mode for navigating retention policies and measurements like directories and files.
- Supports 'cat' and 'tail' commands to display recent data.
- Allows specifying the InfluxDB host and database via command-line switches.
- If no arguments are provided, launches the interactive shell by default.

Requirements:
- pip install requests

Usage examples:
python viewer.py
python viewer.py --host myhost --db mydb shell
python viewer.py list [measurement]
python viewer.py measurements
python viewer.py retention
python viewer.py <field> <measurement>

Author: Jason Cox - github.com/jasonacox/Powerwall-Dashboard
Date: June 2025
"""

import sys
import requests
import datetime
import argparse

INFLUXDB_URL = "http://localhost:8086/query"
DATABASE = "powerwall"


def get_last_hour_data(field, measurement):
    now = datetime.datetime.utcnow()
    one_hour_ago = now - datetime.timedelta(hours=1)
    query = f"SELECT {field} FROM {measurement} WHERE time > '{one_hour_ago.isoformat()}Z'"
    params = {
        'db': DATABASE,
        'q': query,
        'epoch': 's'
    }
    try:
        response = requests.get(INFLUXDB_URL, params=params, timeout=10)
    except requests.exceptions.Timeout:
        print("Error: Connection to InfluxDB timed out.")
        sys.exit(1)
    if response.status_code != 200:
        print(f"Error querying InfluxDB: {response.status_code} {response.text}")
        sys.exit(1)
    data = response.json()
    if 'results' in data and data['results'] and 'series' in data['results'][0]:
        points = data['results'][0]['series'][0]['values']
        columns = data['results'][0]['series'][0]['columns']
        print(f"Last hour of data for field '{field}' from measurement '{measurement}':")
        print(columns)
        for point in points:
            # Convert first column (timestamp) to readable local date/time if it's an integer
            ts = point[0]
            if isinstance(ts, int) or (isinstance(ts, float) and ts == int(ts)):
                try:
                    # Use local timezone conversion
                    dt_local = datetime.datetime.fromtimestamp(ts)
                    ts_str = dt_local.strftime('%Y-%m-%d %H:%M:%S %Z')
                except Exception:
                    ts_str = str(ts)
            else:
                ts_str = str(ts)
            print([ts_str] + point[1:])
    else:
        print(f"No data found for field '{field}' in measurement '{measurement}' in the last hour.")


def list_fields(measurement):
    query = f"SHOW FIELD KEYS FROM {measurement}"
    params = {
        'db': DATABASE,
        'q': query
    }
    try:
        response = requests.get(INFLUXDB_URL, params=params, timeout=10)
    except requests.exceptions.Timeout:
        print("Error: Connection to InfluxDB timed out.")
        sys.exit(1)
    if response.status_code != 200:
        print(f"Error querying InfluxDB: {response.status_code} {response.text}")
        sys.exit(1)
    data = response.json()
    if 'results' in data and data['results'] and 'series' in data['results'][0]:
        fields = data['results'][0]['series'][0]['values']
        print(f"Available fields in measurement '{measurement}':")
        for field in fields:
            print(f"- {field[0]}")
    else:
        print(f"No fields found for measurement '{measurement}'.")


def list_measurements():
    query = "SHOW MEASUREMENTS"
    params = {
        'db': DATABASE,
        'q': query
    }
    try:
        response = requests.get(INFLUXDB_URL, params=params, timeout=10)
    except requests.exceptions.Timeout:
        print("Error: Connection to InfluxDB timed out.")
        sys.exit(1)
    if response.status_code != 200:
        print(f"Error querying InfluxDB: {response.status_code} {response.text}")
        sys.exit(1)
    data = response.json()
    if 'results' in data and data['results'] and 'series' in data['results'][0]:
        measurements = data['results'][0]['series'][0]['values']
        print("Available measurements:")
        for m in measurements:
            print(f"- {m[0]}")
    else:
        print("No measurements found in the database.")


def list_retention_policies():
    query = f"SHOW RETENTION POLICIES ON {DATABASE}"
    params = {'db': DATABASE, 'q': query}
    try:
        response = requests.get(INFLUXDB_URL, params=params, timeout=10)
    except requests.exceptions.Timeout:
        print("Error: Connection to InfluxDB timed out.")
        sys.exit(1)
    if response.status_code != 200:
        print(f"Error querying InfluxDB: {response.status_code} {response.text}")
        sys.exit(1)
    data = response.json()
    if 'results' in data and data['results'] and 'series' in data['results'][0]:
        policies = data['results'][0]['series'][0]['values']
        print("Available retention policies:")
        for policy in policies:
            print(f"- {policy[0]}")
    else:
        print("No retention policies found in the database.")


def shell_mode():
    print("Welcome to InfluxDB Shell Mode! Type 'help' for commands.\n")
    current_retention = None
    current_measurement = None
    def get_measurement_names():
        query = "SHOW MEASUREMENTS"
        params = {'db': DATABASE, 'q': query}
        response = requests.get(INFLUXDB_URL, params=params, timeout=10)
        data = response.json()
        return [m[0] for m in data['results'][0]['series'][0]['values']] if 'results' in data and data['results'] and 'series' in data['results'][0] else []
    def get_retention_policy_names():
        query = f"SHOW RETENTION POLICIES ON {DATABASE}"
        params = {'db': DATABASE, 'q': query}
        response = requests.get(INFLUXDB_URL, params=params, timeout=10)
        data = response.json()
        if 'results' in data and data['results'] and 'series' in data['results'][0]:
            return [policy[0] for policy in data['results'][0]['series'][0]['values']]
        return []
    while True:
        if current_retention and not current_measurement:
            prompt = f"influxdb:{current_retention}$ "
        elif current_retention and current_measurement:
            prompt = f"influxdb:{current_retention}.{current_measurement}$ "
        else:
            prompt = "influxdb$ "
        try:
            cmd = input(prompt).strip()
        except (EOFError, KeyboardInterrupt):
            print("\nExiting shell mode.")
            break
        if cmd in ("exit", "quit"):
            print("Exiting shell mode.")
            break
        elif cmd == "help":
            print("Commands:")
            print("  ls                List retention policies, measurements, or fields")
            print("  cd [name]         Enter a retention policy or measurement (or '..' to go up)")
            print("  cat [field]       Show last hour of data for a field (must be inside a measurement)")
            print("  exit, quit        Exit shell mode")
            print("  help              Show this help message\n")
        elif cmd == "ls":
            if not current_retention:
                # List retention policies
                list_retention_policies()
            elif current_retention and not current_measurement:
                # List all measurements (no filtering by retention policy)
                measurements = get_measurement_names()
                if measurements:
                    print("Available measurements:")
                    for meas in sorted(measurements):
                        print(f"- {meas}")
                else:
                    print("No measurements found in the database.")
            elif current_retention and current_measurement:
                # List fields in this measurement
                list_fields(f"{current_retention}.{current_measurement}")
        elif cmd.startswith("cd"):
            arg = cmd[2:].strip()
            if arg == "" or arg == "/":
                current_retention = None
                current_measurement = None
            elif arg == "..":
                if current_measurement:
                    current_measurement = None
                elif current_retention:
                    current_retention = None
            elif "." in arg:
                # If user specifies a dot name, treat as retention.measurement
                rp, meas = arg.split(".", 1)
                retention_policies = get_retention_policy_names()
                measurements = get_measurement_names()
                if rp in retention_policies and meas in measurements:
                    current_retention = rp
                    current_measurement = meas
                else:
                    if rp not in retention_policies:
                        print(f"Retention policy '{rp}' not found.")
                    elif meas not in measurements:
                        print(f"Measurement '{meas}' not found.")
            elif not current_retention:
                # Enter retention policy (use actual retention policy list)
                retention_policies = get_retention_policy_names()
                if arg in retention_policies:
                    current_retention = arg
                else:
                    print(f"Retention policy '{arg}' not found.")
            elif current_retention and not current_measurement:
                # Enter measurement (from all measurements)
                measurements = get_measurement_names()
                if arg in measurements:
                    current_measurement = arg
                else:
                    print(f"Measurement '{arg}' not found.")
            else:
                print("Usage: cd [name]")
        elif cmd.startswith("cat ") or cmd.startswith("tail "):
            if not (current_retention and current_measurement):
                print("You must 'cd' into a retention policy and measurement first.")
                continue
            field = cmd.split(" ", 1)[1].strip() if " " in cmd else ""
            if not field:
                print("Usage: cat [field] or tail [field]")
                continue
            get_last_hour_data(field, f"{current_retention}.{current_measurement}")
        elif cmd == "":
            continue
        else:
            print(f"Unknown command: {cmd}. Type 'help' for a list of commands.")


def main():
    parser = argparse.ArgumentParser(description="Query InfluxDB for the last hour of data for a field.")
    parser.add_argument('--host', default='localhost', help="InfluxDB host (default: localhost)")
    parser.add_argument('--db', default='powerwall', help="InfluxDB database name (default: powerwall)")
    parser.add_argument('field', nargs='?', help="Field to query, or 'list' to list fields, or 'measurements' to list measurements, or 'shell' for interactive mode.")
    parser.add_argument('measurement', nargs='?', default='raw.http', help="Measurement (table) name. Defaults to 'raw.http'.")
    args = parser.parse_args()

    global INFLUXDB_URL, DATABASE
    INFLUXDB_URL = f"http://{args.host}:8086/query"
    DATABASE = args.db

    if args.field is None:
        # If no field is specified, automatically run shell mode
        shell_mode()
        sys.exit(0)
    if args.field.lower() == "measurements":
        list_measurements()
        sys.exit(0)
    if args.field.lower() == "list":
        list_fields(args.measurement)
        sys.exit(0)
    if args.field.lower() == "shell":
        shell_mode()
        sys.exit(0)
    if args.field.lower() == "retention":
        list_retention_policies()
        sys.exit(0)
    get_last_hour_data(args.field, args.measurement)

if __name__ == "__main__":
    main()
