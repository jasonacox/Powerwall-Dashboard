#!/usr/bin/env python
"""
Polls the InfluxDB database for energy values and prints them to the console.

Requires the InfluxDB Python client library:
    pip install influxdb

Usage:
    energy.py -s <start_time> -e <end_time> -h <host> -p <port> 
              -u <username> -w <password> -d <database> -j
    where:
        <start_time> and <end_time> are in the format "YYYY-MM-DDTHH:MM:SSZ"
        <host> is the InfluxDB host (default is "localhost")
    e.g. python energy.py -s "2025-01-01T00:00:00Z" -e "2025-01-31T23:59:59Z" -h "localhost"

The script will print the energy values for the specified time range.

By: Jason Cox
Date: 1 March 2025
github.com/jasonacox/Powerwall-Dashboard

"""
import sys
import getopt
from influxdb import InfluxDBClient
import json

# Defaults
host = "localhost"
port = 8086
username = None
password = None
database = "powerwall"
start_time = None
end_time = None
json_output = False

# Process command line arguments
def usage():
    print("Usage: python energy.py -s <start_time> -e <end_time> -h <host> -p <port> -u <username> -w <password> -d <database> -j")
    print("   -s <start_time>  Start time in the format 'YYYY-MM-DDTHH:MM:SSZ'")
    print("   -e <end_time>    End time in the format 'YYYY-MM-DDTHH:MM:SSZ'")
    print("   -h <host>        InfluxDB host (default is 'localhost')")
    print("   -p <port>        InfluxDB port (default is 8086)")
    print("   -u <username>    InfluxDB username")
    print("   -w <password>    InfluxDB password")
    print("   -d <database>    InfluxDB database (default is 'powerwall')")
    print("   -j               Output JSON format")
    sys.exit(2)

try:
    opts, args = getopt.getopt(sys.argv[1:], "s:e:h:p:u:w:d:j")
except getopt.GetoptError:
    usage()

for opt, arg in opts:
    if opt == '-s':
        start_time = arg
    elif opt == '-e':
        end_time = arg
    elif opt == '-h':
        host = arg
    elif opt == '-p':
        port = int(arg)
    elif opt == '-u':
        username = arg
    elif opt == '-w':
        password = arg
    elif opt == '-d':
        database = arg
    elif opt == '-j':
        json_output = True

# Print Header
if not json_output:
    print("Energy Calculator")
    print("-----------------")
    # Ask user for start and end time if not provided
    if not start_time:
        start_time = "2025-01-01T00:00:00Z"
        user = input(f"Enter start time [{start_time}]: ")
        if user:
            start_time = user
    else:
        print(f"Start time: {start_time}")
    if not end_time:
        end_time = "2025-01-31T23:59:59Z"
        user = input(f"Enter end time [{end_time}]: ")
        if user:
            end_time = user
    else:
        print(f"End time: {end_time}")
    print("")
else:
    # Ensure start and end time are provided
    if not start_time or not end_time:
        print("Error: Start and end time must be provided for JSON output")
        sys.exit(2)

# Create an InfluxDB client
if not json_output:
    print(f"Connecting to InfluxDB at {host}:{port} as {username} using database {database}...")
try:
    client = InfluxDBClient(host, port, username, password, database)
    client.ping()
except:
    print(f"Error: Could not connect to InfluxDB at {host}:{port} as {username} using database {database}")
    sys.exit(2)

# Define the query
def get_energy_values(start_time, end_time):
    query = f"""
    SELECT integral(home)/1000/3600 AS home,
           integral(solar)/1000/3600 AS solar,
           integral(from_pw)/1000/3600 AS from_pw,
           integral(to_pw)/1000/3600 AS to_pw,
           integral(from_grid)/1000/3600 AS from_grid,
           integral(to_grid)/1000/3600 AS to_grid
    FROM powerwall.autogen.http
    WHERE time >= '{start_time}' AND time <= '{end_time}'
    """
    return query

# Execute the query
if not json_output:
    print("")
    print(f"Querying energy values from {start_time} to {end_time}...")
try:
    result = client.query(get_energy_values(start_time, end_time))
except Exception as e:
    print(f"Error: Could not query InfluxDB: {e}")
    sys.exit(2)

# Print the results
if json_output:
    output = {}
    # Convert the result to JSON
    for record in result.get_points():
        output = {
            "home": record['home'],
            "solar": record['solar'],
            "from_pw": record['from_pw'],
            "to_pw": record['to_pw'],
            "from_grid": record['from_grid'],
            "to_grid": record['to_grid'],
            "unit": "kWh"
        }
    print(json.dumps(output, indent=4))
else:
    print("")
    print("Energy values:")
    print("")
    print(f"{'Home':<15}{'Solar':<15}{'PW In':<15}{'PW Out':<15}{'Grid In':<15}{'Grid Out':<15}")
    print("-" * 90)
    for record in result.get_points():
        def format_value(value):
            if value < 1000:
                return f"{value:.2f} kWh"
            else:
                return f"{value / 1000:.2f} MWh"

        home = format_value(record['home'])
        solar = format_value(record['solar'])
        from_pw = format_value(record['from_pw'])
        to_pw = format_value(record['to_pw'])
        from_grid = format_value(record['from_grid'])
        to_grid = format_value(record['to_grid'])

        print(f"{home:<15}{solar:<15}{from_pw:<15}{to_pw:<15}{from_grid:<15}{to_grid:<15}")

    print("")
