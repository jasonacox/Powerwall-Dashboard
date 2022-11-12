#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
 Command line tool to search for incorrect month tags of InfluxDB
 and correct the data for your configured timezone.

 Author: Michael Birse (for Powerwall-Dashboard by Jason A. Cox)
 For more information see https://github.com/jasonacox/Powerwall-Dashboard

 Background:
    Prior to Powerwall-Dashboard v2.6.3, "month" tags of InfluxDB data were
    based on UTC only, resulting in data points with incorrect month tags for
    the local timezone.

    This script will search InfluxDB for incorrect month tags for your
    configured timezone and correct the data. A backup is recommended.

 Usage:
    * Install the required python modules:
        pip install python-dateutil influxdb

    * Run this script:
        python3 fixmonthtags.py

    The script will run interactively and prompt you to:
        - configure your InfluxDB database settings and timezone
        - search the database for incorrect month tags
        - correct the data if incorrect month tags are found

    * For additional usage options:
        python3 fixmonthtags.py --help
"""
import sys
import os
import argparse
import configparser
try:
    from dateutil.relativedelta import relativedelta
    from dateutil.parser import isoparse
    from dateutil import tz
except:
    sys.exit("ERROR: Missing python dateutil module. Run 'pip install python-dateutil'.")
try:
    from influxdb import InfluxDBClient
except:
    sys.exit("ERROR: Missing python influxdb module. Run 'pip install influxdb'.")

SCRIPTPATH = os.path.dirname(os.path.realpath(sys.argv[0]))
SCRIPTNAME = os.path.basename(sys.argv[0]).split('.')[0]
CONFIGNAME = CONFIGFILE = f"{SCRIPTNAME}.conf"

# Parse command line arguments
parser = argparse.ArgumentParser(description='Fix incorrect month tags of InfluxDB')
parser.add_argument('--config', help=f'specify an alternate config file (default: {CONFIGNAME})')
parser.add_argument('--rebuild', action="store_true", help='force rebuild of analysis data')
args = parser.parse_args()

print("Fix incorrect month tags of InfluxDB")
print("------------------------------------")
print("This script will search InfluxDB for incorrect month tags for your")
print("configured timezone and correct the data. A backup is recommended.\n")
print("You will be asked for confirmation before any data corrections are made.\n")

if args.config:
    # Use alternate config file if specified
    CONFIGNAME = CONFIGFILE = args.config

# Load Configuration File
config = configparser.ConfigParser(allow_no_value=True)
if not os.path.exists(CONFIGFILE) and "/" not in CONFIGFILE:
    # Look for config file in script location if not found
    CONFIGFILE = f"{SCRIPTPATH}/{CONFIGFILE}"
if os.path.exists(CONFIGFILE):
    try:
        config.read(CONFIGFILE)

        # Get InfluxDB Settings
        IHOST = config.get('InfluxDB', 'HOST')
        IPORT = config.get('InfluxDB', 'PORT')
        IUSER = config.get('InfluxDB', 'USER', fallback='')
        IPASS = config.get('InfluxDB', 'PASS', fallback='')
        IDB = config.get('InfluxDB', 'DB')
        ITZ = config.get('InfluxDB', 'TZ')
    except Exception as err:
        sys.exit(f"ERROR: Config file '{CONFIGNAME}' - {err}")
else:
    # Config not found - prompt user for configuration and save settings
    print(f"Config file '{CONFIGNAME}' not found\n")

    while True:
        response = input("Do you want to create the config now? [Y/n] ")
        if response.lower() == "n":
            sys.exit()
        elif response.lower() in ("y", ""):
            break

    print("\nInfluxDB Setup")
    print("-" * 14)

    while True:
        response = input("Host: [localhost] ")
        if response.strip() == "":
            IHOST = "localhost"
        else:
            IHOST = response.strip()
        break

    while True:
        response = input("Port: [8086] ")
        if response.strip() == "":
            IPORT = "8086"
        else:
            IPORT = response.strip()
        break

    response = input("User (leave blank if not used): [blank] ")
    IUSER = response.strip()

    response = input("Pass (leave blank if not used): [blank] ")
    IPASS = response.strip()

    while True:
        response = input("Database: [powerwall] ")
        if response.strip() == "":
            IDB = "powerwall"
        else:
            IDB = response.strip()
        break

    while True:
        response = input("Timezone (e.g. America/Los_Angeles): ")
        if response.strip() != "":
            ITZ = response.strip()
            if tz.gettz(ITZ) is None:
                print("Invalid timezone\n")
                continue
            break

    # Set config values
    config.optionxform = str
    config['InfluxDB'] = {}
    config['InfluxDB']['HOST'] = IHOST
    config['InfluxDB']['PORT'] = IPORT
    config['InfluxDB']['USER'] = IUSER
    config['InfluxDB']['PASS'] = IPASS
    config['InfluxDB']['DB'] = IDB
    config['InfluxDB']['TZ'] = ITZ

    try:
        # Write config file
        with open(CONFIGFILE, 'w') as configfile:
            config.write(configfile)
    except Exception as err:
        print(f"\nERROR: Failed to save config to '{CONFIGNAME}' - {err}\n")
    else:
        print(f"\nConfig saved to '{CONFIGNAME}'\n")

# Global Variables
start = end = None
datapoints = {}
rplist = []
taglist = []
months = []

# Helper Functions
def lpr(value):
    """
    Return Line Protocol formatted string for InfluxDB field values based on the data type
    """
    if type(value) is int:
        rv = f"{value}i"
    elif type(value) is str:
        rv = value.replace('"', '\\"')
        rv = f'"{rv}"'
    else:
        rv = str(value)
    return rv

def esc(value):
    """
    Return Line Protocol escaped string for InfluxDB tag key/values and field keys
    """
    return str(value).replace(',', '\\,').replace('=', '\\=').replace(' ', '\\ ')

# InfluxDB Functions
def search_influx(remove=False):
    """
    Search InfluxDB for incorrect month tags for the configured timezone
        * Adds corrected data points for each retention policy to 'datapoints'

    Args:
        remove  = If True, removes previously found data points with incorrect month tags
    """
    global start, end

    if start is None:
        try:
            # Find first and last data points
            query = "SELECT * FROM http LIMIT 1"
            firstpoint = client.query(query)
            query = "SELECT * FROM http ORDER BY time DESC LIMIT 1"
            lastpoint = client.query(query)
        except Exception as err:
            sys.exit(f"ERROR: Failed to execute InfluxDB query: {query}; {err}")

        try:
            start = isoparse(list(firstpoint.get_points())[0]['time']).astimezone(influxtz)
            end = isoparse(list(lastpoint.get_points())[0]['time']).astimezone(influxtz)
        except Exception:
            sys.exit("ERROR: No data points found")

    if not rplist:
        try:
            # Get list of retention policies
            query = "SHOW RETENTION POLICIES"
            result = client.query(query)
            for rp in result.get_points():
                rplist.append(rp['name'])
        except Exception as err:
            sys.exit(f"ERROR: Failed to execute InfluxDB query: {query}; {err}")

    if not taglist:
        try:
            # Get list of tag keys
            query = "SHOW TAG KEYS FROM http"
            result = client.query(query)
            for tag in result.get_points():
                taglist.append(tag['tagKey'])
        except Exception as err:
            sys.exit(f"ERROR: Failed to execute InfluxDB query: {query}; {err}")

    startmonth = start.replace(day=1, hour=0, minute=0, second=0)
    endmonth = end + relativedelta(months=1, day=1, hour=0, minute=0, second=0)

    # Loop through each month to search tags by month
    month = startmonth
    while month < endmonth:
        nextmonth = month + relativedelta(months=1, day=1, hour=0, minute=0, second=0)

        if remove and month not in months:
            # Increment to next month if there were no wrong tags found within current month
            month += relativedelta(months=1, day=1, hour=0, minute=0, second=0)
            continue

        for rp in rplist:
            if rp in ('kwh', 'daily', 'monthly'):
                continue
            try:
                if not remove:
                    # Find points within current month where month tag does not match localized month
                    query = f"SELECT * FROM {rp}.http WHERE month != '{month.strftime('%b')}' AND time >= '{month.isoformat()}' AND time < '{nextmonth.isoformat()}'"
                    result = client.query(query)
                else:
                    # Remove points within current month for all retention policies where month tag does not match localized month
                    query = f"DELETE FROM http WHERE month != '{month.strftime('%b')}' AND time >= '{month.isoformat()}' AND time < '{nextmonth.isoformat()}'"
                    client.query(query)
                    break
            except Exception as err:
                sys.exit(f"ERROR: Failed to execute InfluxDB query: {query}; {err}")

            pts = len(list(result.get_points()))
            if pts > 0:
                if month not in months:
                    # Save month where incorrect tags found
                    print(f"* Found incorrect month tags in {month.strftime('%b %Y')}")
                    months.append(month)

                for point in result.get_points():
                    timestamp = isoparse(point['time']).astimezone(influxtz)
                    tags = ""
                    data = ""
                    for key, value in point.items():
                        if key == 'time' or value is None:
                            continue
                        if key in taglist:
                            if key not in ('month', 'year'):
                                # Save other tag values
                                tags += f",{esc(key)}={esc(value)}"
                        else:
                            # Save data values
                            data += f",{esc(key)}={lpr(value)}"

                    # Save the corrected data point values
                    newpoint = f"http,month={timestamp.strftime('%b')},year={timestamp.year}{tags} {data[1:]} {str(int(timestamp.timestamp()))}"
                    if rp not in datapoints:
                        datapoints[rp] = []
                    datapoints[rp].append(newpoint)

        # Increment to next month
        month += relativedelta(months=1, day=1, hour=0, minute=0, second=0)

def write_influx():
    """
    Replace incorrect data points with the corrected data for each retention policy
    """
    print("Writing corrected data")
    try:
        # Write corrected data points
        for rp, points in datapoints.items():
            client.write_points(points, time_precision='s', batch_size=10000, retention_policy=rp, protocol='line')
    except Exception as err:
        sys.exit(f"ERROR: Failed to write to InfluxDB: {err}")

    # Remove incorrect data points
    search_influx(remove=True)

def update_influx():
    """
    Update analysis data retention policies (kwh, daily, monthly)
        * Full rebuild required due to potential non-hourly timezone offsets
    """
    print("Updating analysis data")
    try:
        # Drop/create retention policies to clear previous data
        query = f"DROP RETENTION POLICY kwh ON {IDB}"
        client.query(query)
        query = f"DROP RETENTION POLICY daily ON {IDB}"
        client.query(query)
        query = f"DROP RETENTION POLICY monthly ON {IDB}"
        client.query(query)
        query = f"CREATE RETENTION POLICY kwh ON {IDB} duration INF replication 1"
        client.query(query)
        query = f"CREATE RETENTION POLICY daily ON {IDB} duration INF replication 1"
        client.query(query)
        query = f"CREATE RETENTION POLICY monthly ON {IDB} duration INF replication 1"
        client.query(query)

        # Update hourly analysis data
        query = "SELECT integral(home)/1000/3600 AS home, integral(solar)/1000/3600 AS solar, integral(from_pw)/1000/3600 AS from_pw, integral(to_pw)/1000/3600 AS to_pw, integral(from_grid)/1000/3600 AS from_grid, integral(to_grid)/1000/3600 AS to_grid "
        query += "INTO kwh.:MEASUREMENT FROM autogen.http "
        query += f"GROUP BY time(1h), month, year tz('{ITZ}')"
        client.query(query)

        # Update daily analysis data
        query = "SELECT sum(home) AS home, sum(solar) AS solar, sum(from_pw) AS from_pw, sum(to_pw) AS to_pw, sum(from_grid) AS from_grid, sum(to_grid) AS to_grid "
        query += "INTO daily.:MEASUREMENT FROM kwh.http "
        query += f"GROUP BY time(1d), month, year tz('{ITZ}')"
        client.query(query)

        # Update monthly analysis data
        query = "SELECT sum(home) AS home, sum(solar) AS solar, sum(from_pw) AS from_pw, sum(to_pw) AS to_pw, sum(from_grid) AS from_grid, sum(to_grid) AS to_grid "
        query += "INTO monthly.:MEASUREMENT FROM daily.http "
        query += "GROUP BY time(365d), month, year"
        client.query(query)
    except Exception as err:
        sys.exit(f"ERROR: Failed to execute InfluxDB query: {query}; {err}")

# MAIN

# Check InfluxDB timezone is valid
influxtz = tz.gettz(ITZ)
if influxtz is None:
    sys.exit(f"ERROR: Invalid timezone - {ITZ}")

try:
    # Connect to InfluxDB
    client = InfluxDBClient(host=IHOST, port=IPORT, username=IUSER, password=IPASS, database=IDB)
except Exception as err:
    sys.exit(f"ERROR: Failed to connect to InfluxDB: {err}")

while True:
    # Prompt to search for incorrect month tags
    response = input("Do you want to search now? [Y/n] ")
    if response.lower() == "n":
        sys.exit()
    elif response.lower() in ("y", ""):
        print()
        break

# Search for incorrect month tags
print(f"Searching InfluxDB for incorrect month tags for timezone {ITZ}")
search_influx()

if not datapoints:
    # Exit if no wrong tags were found
    print("* None found\n")
    if args.rebuild:
        # Update analysis data if rebuild option was given
        update_influx()
        print("Done.")
    sys.exit()

while True:
    # Prompt to correct the month tags
    response = input("\nDo you want to correct the month tags? [y/N] ")
    if response.lower() in ("n", ""):
        if args.rebuild:
            # Update analysis data if rebuild option was given
            print()
            update_influx()
            print("Done.")
        sys.exit()
    elif response.lower() == "y":
        print("\nThis may take some time, please be patient...\n")
        break

# Write corrected data
write_influx()
# Update analysis data
update_influx()
print("Done.")
