#!/usr/bin/env python3
"""
InfluxDB Viewer Tool

This script provides a command-line and interactive shell interface for exploring and querying an InfluxDB database.

Features:
- List retention policies, measurements, and fields in an InfluxDB database.
- Query the last hour of data for a specific field in a measurement.
- Interactive shell mode for navigating retention policies and measurements like directories and files.
- Supports 'cat' and 'tail' commands to display recent data.
- Allows specifying the InfluxDB host, database, username, and password via command-line switches.
- If no arguments are provided, launches the interactive shell by default.
- Tab completion for commands, retention policies, measurements, and fields in shell mode.
- Optionally specify the number of data points to show with 'tail' (default 10).
- No authentication is used by default, but you can provide --user and --password if needed.

Requirements:
- pip install requests

Usage examples:
python viewer.py
python viewer.py --host myhost --db mydb shell
python viewer.py --user myuser --password mypass shell
python viewer.py list [measurement]
python viewer.py measurements
python viewer.py retention
python viewer.py <field> <measurement>

Shell mode commands:
  ls                List retention policies, measurements, or fields
  ls -l             List with details: measurements show field count, fields show entry count
  cd [name]         Enter a retention policy or measurement (or '..' to go up)
  cat [field]       Show last hour of data for a field (must be inside a measurement)
  tail [field] [n]  Show last n data points for a field (default n=10)
  exit, quit        Exit shell mode
  help, ?           Show this help message

Tab completion is available for commands, retention policies, measurements, and fields.

Author: Jason Cox - github.com/jasonacox/Powerwall-Dashboard
Date: June 2025
"""

import sys
import requests
import datetime
import argparse
import readline

INFLUXDB_URL = "http://localhost:8086/query"
DATABASE = "powerwall"


def get_last_hour_data(field, measurement):
    """
    Query and print the last hour of data for a specific field in a measurement.
    If no data is found, prompt the user to fetch the last 10 data points instead.
    Args:
        field (str): The field to query.
        measurement (str): The measurement (table) to query from.
    """
    now = datetime.datetime.utcnow()
    one_hour_ago = now - datetime.timedelta(hours=1)
    query = f"SELECT {field} FROM {measurement} WHERE time > '{one_hour_ago.isoformat()}Z'"
    params = {
        'db': DATABASE,
        'q': query,
        'epoch': 's'
    }
    if 'INFLUXDB_AUTH' in globals() and INFLUXDB_AUTH:
        params.update(INFLUXDB_AUTH)
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
        # Prompt user to fetch last 10 data points
        try:
            answer = input("Would you like to fetch the last 10 data points instead? [y/N]: ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            answer = ''
        if answer == 'y' or answer == 'yes':
            get_last_n_data(field, measurement, 10)

def get_last_n_data(field, measurement, n=10):
    """
    Query and print the last n data points for a specific field in a measurement.
    Args:
        field (str): The field to query.
        measurement (str: The measurement (table) to query from.
        n (int): Number of data points to retrieve (default 10).
    """
    query = f"SELECT {field} FROM {measurement} ORDER BY time DESC LIMIT {n}"
    params = {
        'db': DATABASE,
        'q': query,
        'epoch': 's'
    }
    if 'INFLUXDB_AUTH' in globals() and INFLUXDB_AUTH:
        params.update(INFLUXDB_AUTH)
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
        print(f"Last {n} data points for field '{field}' from measurement '{measurement}':")
        print(columns)
        for point in points:
            ts = point[0]
            if isinstance(ts, int) or (isinstance(ts, float) and ts == int(ts)):
                try:
                    dt_local = datetime.datetime.fromtimestamp(ts)
                    ts_str = dt_local.strftime('%Y-%m-%d %H:%M:%S %Z')
                except Exception:
                    ts_str = str(ts)
            else:
                ts_str = str(ts)
            print([ts_str] + point[1:])
    else:
        print(f"No data found for field '{field}' in measurement '{measurement}'.")

def get_number(field, measurement):
    """
    Query and return the number of data points for a specific field in a measurement.
    Args:
        field (str): The field to query.
        measurement (str): The measurement (table) to query from.
    Returns:
        int: Number of data points for the field, or 0 if none found.
    """
    query = f'SELECT COUNT("{field}") FROM {measurement}'
    params = {
        'db': DATABASE,
        'q': query,
        'epoch': 's'
    }
    if 'INFLUXDB_AUTH' in globals() and INFLUXDB_AUTH:
        params.update(INFLUXDB_AUTH)
    try:
        response = requests.get(INFLUXDB_URL, params=params, timeout=15)
    except requests.exceptions.Timeout:
        print("Error: Connection to InfluxDB timed out.")
        sys.exit(1)
    if response.status_code != 200:
        print(f"Error querying InfluxDB: {response.status_code} {response.text}")
        sys.exit(1)
    data = response.json()
    # print(data)  # Uncomment for debugging
    if 'results' in data and data['results'] and 'series' in data['results'][0]:
        series = data['results'][0]['series'][0]
        columns = series['columns']
        values = series['values'][0]
        # Typical columns: ['time', 'count'] or ['time', 'count_field']
        if 'count' in columns:
            idx = columns.index('count')
            return int(values[idx])
        # Try count_field
        for i, k in enumerate(columns):
            if k == f'count_{field}' and isinstance(values[i], (int, float)):
                return int(values[i])
        # Fallback: use first count_ column after 'time'
        for i, k in enumerate(columns):
            if k.startswith('count') and i > 0 and isinstance(values[i], (int, float)):
                return int(values[i])
    return 0

def get_all(field, measurement):
    """
    Query and return all data points for a specific field in a measurement.
    Args:
        field (str): The field to query.
        measurement (str): The measurement (table) to query from.
    Returns:
        list: List of data points (each as a list), or empty list if none found.
    """
    query = f"SELECT {field} FROM {measurement}"
    params = {
        'db': DATABASE,
        'q': query,
        'epoch': 's'
    }
    if 'INFLUXDB_AUTH' in globals() and INFLUXDB_AUTH:
        params.update(INFLUXDB_AUTH)
    try:
        response = requests.get(INFLUXDB_URL, params=params, timeout=30)
    except requests.exceptions.Timeout:
        print("Error: Connection to InfluxDB timed out.")
        sys.exit(1)
    if response.status_code != 200:
        print(f"Error querying InfluxDB: {response.status_code} {response.text}")
        sys.exit(1)
    data = response.json()
    if 'results' in data and data['results'] and 'series' in data['results'][0]:
        points = data['results'][0]['series'][0]['values']
        return points
    else:
        return []

def list_fields(measurement):
    """
    List all available fields in a given measurement, with details in ls -l style.
    Args:
        measurement (str): The measurement to list fields from.
    """
    query = f"SHOW FIELD KEYS FROM {measurement}"
    params = {
        'db': DATABASE,
        'q': query
    }
    if 'INFLUXDB_AUTH' in globals() and INFLUXDB_AUTH:
        params.update(INFLUXDB_AUTH)
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
        columns = data['results'][0]['series'][0]['columns']
        print(f"Available fields in measurement '{measurement}':")
        print(f"{'Field':<32} {'Type':<12} {'Description':<20}")
        print("-"*64)
        for field in fields:
            # field[0] = field name, field[1] = type, field[2] = description (if present)
            name = field[0]
            ftype = field[1] if len(field) > 1 else ''
            desc = field[2] if len(field) > 2 else ''
            print(f"{name:<32} {ftype:<12} {desc:<20}")
    else:
        print(f"No fields found for measurement '{measurement}'.")


def list_measurements():
    """
    List all measurements (tables) in the current InfluxDB database, with details in ls -l style.
    """
    query = "SHOW MEASUREMENTS"
    params = {
        'db': DATABASE,
        'q': query
    }
    if 'INFLUXDB_AUTH' in globals() and INFLUXDB_AUTH:
        params.update(INFLUXDB_AUTH)
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
        print(f"{'Measurement':<32} {'Entries':>10}")
        print("-"*44)
        for m in measurements:
            name = m[0]
            # Query count for each measurement (may be slow for many measurements)
            count_query = f"SELECT COUNT(*) FROM \"{name}\""
            count_params = {'db': DATABASE, 'q': count_query}
            if 'INFLUXDB_AUTH' in globals() and INFLUXDB_AUTH:
                count_params.update(INFLUXDB_AUTH)
            try:
                count_resp = requests.get(INFLUXDB_URL, params=count_params, timeout=10)
                count_data = count_resp.json()
                if 'results' in count_data and count_data['results'] and 'series' in count_data['results'][0]:
                    series = count_data['results'][0]['series'][0]
                    # Sum all field counts for this measurement
                    counts = [v for k, v in zip(series['columns'], series['values'][0]) if k.startswith('count_') and isinstance(v, int)]
                    total = sum(counts) if counts else 0
                else:
                    total = 0
            except Exception:
                total = '?'
            print(f"{name:<32} {total:>10}")
    else:
        print("No measurements found in the database.")


def list_retention_policies():
    """
    List all retention policies in the current InfluxDB database, with details in ls -l style.
    """
    query = f"SHOW RETENTION POLICIES ON {DATABASE}"
    params = {'db': DATABASE, 'q': query}
    if 'INFLUXDB_AUTH' in globals() and INFLUXDB_AUTH:
        params.update(INFLUXDB_AUTH)
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
        columns = data['results'][0]['series'][0]['columns']
        print("Available retention policies:")
        print(f"{'Name':<20} {'Duration':<12} {'ShardGroup':<12} {'ReplicaN':<8} {'Default':<8}")
        print("-"*64)
        for policy in policies:
            # columns: name, duration, shardGroupDuration, replicaN, default
            name = policy[0]
            duration = policy[1]
            shard = policy[2]
            replica = policy[3]
            default = str(policy[4])
            print(f"{name:<20} {duration:<12} {shard:<12} {replica:<8} {default:<8}")
    else:
        print("No retention policies found in the database.")


def shell_mode():
    """
    Launch the interactive shell mode for browsing and querying InfluxDB.
    Provides navigation and data inspection commands with tab completion.
    """
    print("Welcome to InfluxDB Shell Mode! Type 'help' for commands.\n")
    current_retention = None
    current_measurement = None
    # Setup tab completion for shell mode
    def get_field_names(measurement):
        try:
            query = f"SHOW FIELD KEYS FROM {measurement}"
            params = {'db': DATABASE, 'q': query}
            if 'INFLUXDB_AUTH' in globals() and INFLUXDB_AUTH:
                params.update(INFLUXDB_AUTH)
            response = requests.get(INFLUXDB_URL, params=params, timeout=10)
            data = response.json()
            if 'results' in data and data['results'] and 'series' in data['results'][0]:
                return [f[0] for f in data['results'][0]['series'][0]['values']]
        except Exception:
            pass
        return []

    def completer(text, state):
        buffer = readline.get_line_buffer()
        line = buffer.lstrip()
        tokens = line.split()
        options = []
        if not tokens:
            # Suggest commands
            options = ['ls', 'cd', 'cat', 'tail', 'exit', 'quit', 'help', '?']
        elif tokens[0] == 'cd':
            if len(tokens) == 1:
                # Suggest retention policies or measurements
                if not current_retention:
                    options = get_retention_policy_names()
                else:
                    options = get_measurement_names()
            elif len(tokens) == 2:
                arg = tokens[1]
                if not current_retention:
                    options = [rp for rp in get_retention_policy_names() if rp.startswith(arg)]
                else:
                    options = [m for m in get_measurement_names() if m.startswith(arg)]
        elif tokens[0] in ('cat', 'tail'):
            if current_retention and current_measurement:
                measurement = f"{current_retention}.{current_measurement}"
                fields = get_field_names(measurement)
                if len(tokens) == 1:
                    options = fields
                elif len(tokens) == 2:
                    arg = tokens[1]
                    options = [f for f in fields if f.startswith(arg)]
        else:
            # Suggest commands
            options = [c for c in ['ls', 'cd', 'cat', 'tail', 'exit', 'quit', 'help', '?'] if c.startswith(tokens[0])]
        matches = [o for o in options if o.startswith(text)]
        if state < len(matches):
            return matches[state]
        return None

    readline.set_completer(completer)
    readline.parse_and_bind('tab: menu-complete')
    readline.parse_and_bind('set show-all-if-ambiguous off')
    readline.set_completion_display_matches_hook(lambda *args: None)
    def get_measurement_names():
        query = "SHOW MEASUREMENTS"
        params = {'db': DATABASE, 'q': query}
        if 'INFLUXDB_AUTH' in globals() and INFLUXDB_AUTH:
            params.update(INFLUXDB_AUTH)
        response = requests.get(INFLUXDB_URL, params=params, timeout=10)
        data = response.json()
        return [m[0] for m in data['results'][0]['series'][0]['values']] if 'results' in data and data['results'] and 'series' in data['results'][0] else []
    def get_retention_policy_names():
        query = f"SHOW RETENTION POLICIES ON {DATABASE}"
        params = {'db': DATABASE, 'q': query}
        if 'INFLUXDB_AUTH' in globals() and INFLUXDB_AUTH:
            params.update(INFLUXDB_AUTH)
        response = requests.get(INFLUXDB_URL, params=params, timeout=10)
        data = response.json()
        if 'results' in data and data['results'] and 'series' in data['results'][0]:
            return [policy[0] for policy in data['results'][0]['series'][0]['values']]
        return []
    def get_field_names(measurement):
        try:
            query = f"SHOW FIELD KEYS FROM {measurement}"
            params = {'db': DATABASE, 'q': query}
            if 'INFLUXDB_AUTH' in globals() and INFLUXDB_AUTH:
                params.update(INFLUXDB_AUTH)
            response = requests.get(INFLUXDB_URL, params=params, timeout=10)
            data = response.json()
            if 'results' in data and data['results'] and 'series' in data['results'][0]:
                return [f[0] for f in data['results'][0]['series'][0]['values']]
        except Exception:
            pass
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
        elif cmd == "help" or cmd == "?":
            print("Commands:")
            print("  ls                List retention policies, measurements, or fields")
            print("  ls -l             Long listing: measurements show field count; fields show entry count")
            print("  cd [name]         Enter a retention policy or measurement (or '..' to go up)")
            print("  cat [field]       Show last hour of data for a field (must be inside a measurement)")
            print("  tail [field] [n]  Show last n data points for a field (default n=10)")
            print("  exit, quit        Exit shell mode")
            print("  help, ?           Show this help message\n")
        elif cmd.startswith("ls"):
            long_listing = cmd.strip() == "ls -l"
            if not current_retention:
                # List retention policies
                list_retention_policies()
            elif current_retention and not current_measurement:
                # List all measurements (no filtering by retention policy)
                measurements = get_measurement_names()
                if measurements:
                    if long_listing:
                        print(f"{'Measurement':<32} {'Fields':>8}")
                        print("-"*41)
                        for name in sorted(measurements):
                            # Query number of fields for each measurement
                            field_query = f"SHOW FIELD KEYS FROM {current_retention}.{name}"
                            field_params = {'db': DATABASE, 'q': field_query}
                            if 'INFLUXDB_AUTH' in globals() and INFLUXDB_AUTH:
                                field_params.update(INFLUXDB_AUTH)
                            try:
                                field_resp = requests.get(INFLUXDB_URL, params=field_params, timeout=10)
                                field_data = field_resp.json()
                                if 'results' in field_data and field_data['results'] and 'series' in field_data['results'][0]:
                                    fields = field_data['results'][0]['series'][0]['values']
                                    nfields = len(fields)
                                else:
                                    nfields = 0
                            except Exception:
                                nfields = '?'
                            print(f"{name:<32} {nfields:>8}")
                    else:
                        # Print as a single column table
                        print(f"{'Measurement':<32}")
                        print("-"*32)
                        for name in sorted(measurements):
                            print(f"{name:<32}")
                else:
                    print("No measurements found in the database.")
            elif current_retention and current_measurement:
                # List fields in this measurement
                if long_listing:
                    # List fields with count for each field using get_number
                    measurement = f"{current_retention}.{current_measurement}"
                    query = f"SHOW FIELD KEYS FROM {measurement}"
                    params = {'db': DATABASE, 'q': query}
                    if 'INFLUXDB_AUTH' in globals() and INFLUXDB_AUTH:
                        params.update(INFLUXDB_AUTH)
                    try:
                        response = requests.get(INFLUXDB_URL, params=params, timeout=10)
                        data = response.json()
                        if 'results' in data and data['results'] and 'series' in data['results'][0]:
                            fields = data['results'][0]['series'][0]['values']
                            print(f"{'Field':<32} {'Type':<12} {'Count':>10}")
                            print("-"*56)
                            for field in fields:
                                name = field[0]
                                ftype = field[1] if len(field) > 1 else ''
                                count_val = get_number(name, measurement)
                                print(f"{name:<32} {ftype:<12} {count_val:>10}")
                        else:
                            print(f"No fields found for measurement '{measurement}'.")
                    except Exception:
                        print(f"Error retrieving fields for measurement '{measurement}'.")
                else:
                    list_fields(f"{current_retention}.{current_measurement}")
            print()
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
        elif cmd.startswith("cat ") or cmd.startswith("more "):
            if not (current_retention and current_measurement):
                print("You must 'cd' into a retention policy and measurement first.")
                continue
            field = cmd.split(" ", 1)[1].strip() if " " in cmd else ""
            if not field:
                print("Usage: cat [field]")
                continue
            get_last_hour_data(field, f"{current_retention}.{current_measurement}")
            print()
        elif cmd.startswith("tail "):
            if not (current_retention and current_measurement):
                print("You must 'cd' into a retention policy and measurement first.")
                continue
            parts = cmd.split()
            if len(parts) < 2:
                print("Usage: tail [field] [count]")
                continue
            field = parts[1]
            n = 10
            if len(parts) > 2:
                try:
                    n = int(parts[2])
                except ValueError:
                    print("Count must be an integer. Using default of 10.")
            get_last_n_data(field, f"{current_retention}.{current_measurement}", n)
            print()
        elif cmd == "":
            continue
        else:
            print(f"Unknown command: {cmd}. Type 'help' for a list of commands.")


def main():
    """
    Parse command-line arguments and run the appropriate InfluxDB viewer mode or query.
    """
    parser = argparse.ArgumentParser(description="Query InfluxDB for the last hour of data for a field.")
    parser.add_argument('--host', default='localhost', help="InfluxDB host (default: localhost)")
    parser.add_argument('--db', default='powerwall', help="InfluxDB database name (default: powerwall)")
    parser.add_argument('--user', default=None, help="InfluxDB username (optional)")
    parser.add_argument('--password', default=None, help="InfluxDB password (optional)")
    parser.add_argument('field', nargs='?', help="Field to query, or 'list' to list fields, or 'measurements' to list measurements, or 'shell' for interactive mode.")
    parser.add_argument('measurement', nargs='?', default='raw.http', help="Measurement (table) name. Defaults to 'raw.http'.")
    args = parser.parse_args()

    global INFLUXDB_URL, DATABASE
    INFLUXDB_URL = f"http://{args.host}:8086/query"
    DATABASE = args.db

    # Prepare auth params if user and password are provided
    global INFLUXDB_AUTH
    INFLUXDB_AUTH = {}
    if args.user:
        INFLUXDB_AUTH['u'] = args.user
    if args.password:
        INFLUXDB_AUTH['p'] = args.password

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
