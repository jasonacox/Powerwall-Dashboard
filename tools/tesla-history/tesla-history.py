#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
 Command line tool to retrieve Powerwall history data by date/time period from
 Tesla Owner API (Tesla cloud) and import into InfluxDB of Powerwall-Dashboard.

 Author: Michael Birse (for Powerwall-Dashboard by Jason A. Cox)
 For more information see https://github.com/jasonacox/Powerwall-Dashboard

 Usage:
    * Install the required python modules:
        pip install python-dateutil teslapy influxdb

    * To use this script:

    - First use / login to Tesla account only:
        (creates config, saves auth token, and displays energy site details)
            python3 tesla-history.py --login

    - Import history data from Tesla cloud for start/end date range:
        (by default, searches InfluxDB for data gaps and fills gaps only)
            python3 tesla-history.py --start "YYYY-MM-DD hh:mm:ss" --end "YYYY-MM-DD hh:mm:ss"

    - Or, to run in test mode first (will not import data), use --test option:
        python3 tesla-history.py --start "YYYY-MM-DD hh:mm:ss" --end "YYYY-MM-DD hh:mm:ss" --test

    - Convenience date options available (e.g. cron usage):
        python3 tesla-history.py --today
            and/or
        python3 tesla-history.py --yesterday

    - Something went wrong? Use --remove option to remove data imported with this tool:
        (data logged by Powerwall-Dashboard will not be affected)
            python3 tesla-history.py --start "YYYY-MM-DD hh:mm:ss" --end "YYYY-MM-DD hh:mm:ss" --remove

    - For more usage options, run without arguments or --help:
        python3 tesla-history.py --help
"""
import sys
import os
import argparse
import configparser
import time
from datetime import datetime, timedelta
try:
    from dateutil.relativedelta import relativedelta
    from dateutil.parser import isoparse
    from dateutil import tz
except:
    sys.exit("ERROR: Missing python dateutil module. Run 'pip install python-dateutil'.")
try:
    import teslapy
except:
    sys.exit("ERROR: Missing python teslapy module. Run 'pip install teslapy'.")
try:
    from influxdb import InfluxDBClient
except:
    sys.exit("ERROR: Missing python influxdb module. Run 'pip install influxdb'.")

SCRIPTPATH = os.path.dirname(os.path.realpath(sys.argv[0]))
SCRIPTNAME = os.path.basename(sys.argv[0]).split('.')[0]
CONFIGNAME = CONFIGFILE = f"{SCRIPTNAME}.conf"
AUTHFILE = f"{SCRIPTNAME}.auth"

# Parse command line arguments
parser = argparse.ArgumentParser(description='Import Powerwall history data from Tesla Owner API (Tesla cloud) into InfluxDB')
parser.add_argument('-l', '--login', action="store_true", help='login to Tesla account only and save auth token (do not get history)')
parser.add_argument('-t', '--test', action="store_true", help='enable test mode (do not import into InfluxDB)')
parser.add_argument('-d', '--debug', action="store_true", help='enable debug output (print raw responses from Tesla cloud)')
group = parser.add_argument_group('advanced options')
group.add_argument('--config', help=f'specify an alternate config file (default: {CONFIGNAME})')
group.add_argument('--site', type=int, help='site id (required for Tesla accounts with multiple energy sites)')
group.add_argument('--ignoretz', action="store_true", help='ignore timezone difference between Tesla cloud and InfluxDB')
group.add_argument('--force', action="store_true", help='force import for date/time range (skip search for data gaps)')
group.add_argument('--remove', action="store_true", help='remove imported data from InfluxDB for date/time range')
group = parser.add_argument_group('date/time range options')
group.add_argument('--start', help='start date and time ("YYYY-MM-DD hh:mm:ss")')
group.add_argument('--end', help='end date and time ("YYYY-MM-DD hh:mm:ss")')
group.add_argument('--today', action="store_true", help='set start/end range to "today"')
group.add_argument('--yesterday', action="store_true", help='set start/end range to "yesterday"')
args = parser.parse_args()

# Check for invalid argument combinations
if len(sys.argv) == 1:
    parser.print_help(sys.stderr)
    sys.exit()
if (args.start or args.end) and (args.today or args.yesterday):
    parser.error("arguments --start and --end cannot be used with --today or --yesterday")
if (args.start and not args.end) or (args.end and not args.start):
    parser.error("both arguments --start and --end are required")
if not args.login and not ((args.start and args.end) or (args.today or args.yesterday)):
    parser.error("missing arguments: --start/end or --today/yesterday")

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

        # Get Tesla Settings
        TUSER = config.get('Tesla', 'USER')
        TAUTH = config.get('Tesla', 'AUTH')
        TDELAY = config.getint('Tesla', 'DELAY', fallback=1)

        if "/" not in TAUTH:
            TAUTH = f"{SCRIPTPATH}/{TAUTH}"

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
    print(f"\nConfig file '{CONFIGNAME}' not found\n")

    while True:
        response = input("Do you want to create the config now? [Y/n] ")
        if response.lower() == "n":
            sys.exit()
        elif response.lower() in ("y", ""):
            break

    print("\nTesla Account Setup")
    print("-" * 19)

    while True:
        response = input("Email address: ")
        if "@" not in response:
            print("Invalid email address\n")
        else:
            TUSER = response.strip()
            break

    while True:
        response = input(f"Save auth token to: [{AUTHFILE}] ")
        if response.strip() == "":
            TAUTH = AUTHFILE
        else:
            TAUTH = response.strip()
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
    config['Tesla'] = {}
    config['Tesla']['USER'] = TUSER
    config['Tesla']['AUTH'] = TAUTH
    config['InfluxDB'] = {}
    config['InfluxDB']['HOST'] = IHOST
    config['InfluxDB']['PORT'] = IPORT
    config['InfluxDB']['USER'] = IUSER
    config['InfluxDB']['PASS'] = IPASS
    config['InfluxDB']['DB'] = IDB
    config['InfluxDB']['TZ'] = ITZ
    TDELAY = 1

    try:
        # Write config file
        with open(CONFIGFILE, 'w') as configfile:
            config.write(configfile)
    except Exception as err:
        sys.exit(f"\nERROR: Failed to save config to '{CONFIGNAME}' - {err}")

    print(f"\nConfig saved to '{CONFIGNAME}'\n")

# Global Variables
powerdata = []
eventdata = []
power = None
soe = None
backup = None
dayloaded = None
eventsloaded = False

# Helper Functions
def check_datetime(dt, name, newtz):
    """
    Check start/end datetimes are valid due to possible DST changes - exit with error if checks fail
        * Naive datetimes will be checked both for existence and ambiguity based on 'newtz'
        * Aware datetimes will be checked for existence only (user included offset due to ambiguity)

    Args:
        dt      = datetime instance to check
        name    = friendly name of argument we are checking
        newtz   = timezone to set naive datetime to

    Returns an aware datetime with original timezone or 'newtz' if a naive datetime was passed
    """
    naive = False
    if dt.utcoffset() is None:
        naive = True
        dt = dt.replace(tzinfo=newtz)

    if not tz.datetime_exists(dt):
        sys.exit(f'ERROR: {name.title()} date/time "{dt.strftime("%Y-%m-%d %H:%M:%S")}" does not exist for timezone {dt.tzname()} (DST change?)')

    if naive and tz.datetime_ambiguous(dt):
        sys.exit(f'ERROR: Ambiguous {name} date/time "{dt.strftime("%Y-%m-%d %H:%M:%S")}" for timezone {dt.tzname()} (DST change?)\n\n'
                f'Re-run with desired timezone offset:\n'
                f'   --{name} "{dt.replace(fold=0)}"\n'
                f'or\n'
                f'   --{name} "{dt.replace(fold=1)}"'
        )
    return dt

# Tesla Functions
def tesla_login(email):
    """
    Attempt to login to Tesla cloud account and display energy site details

    Returns a list of Tesla Energy sites if successful
    """
    print("-" * 40)
    print(f"Tesla account: {email}")
    print("-" * 40)

    # Create retry instance for use after successful login
    retry = teslapy.Retry(total=2, status_forcelist=(500, 502, 503, 504), backoff_factor=10)

    # Create Tesla instance
    tesla = teslapy.Tesla(email, cache_file=TAUTH)

    if not tesla.authorized:
        # Login to Tesla account and cache token
        state = tesla.new_state()
        code_verifier = tesla.new_code_verifier()

        try:
            print("Open the below address in your browser to login.\n")
            print(tesla.authorization_url(state=state, code_verifier=code_verifier))
        except Exception as err:
            sys.exit(f"ERROR: Connection failure - {err}")

        print("\nAfter login, paste the URL of the 'Page Not Found' webpage below.\n")

        tesla.close()
        tesla = teslapy.Tesla(email, retry=retry, state=state, code_verifier=code_verifier, cache_file=TAUTH)

        if not tesla.authorized:
            try:
                tesla.fetch_token(authorization_response=input("Enter URL after login: "))
                print("-" * 40)
            except Exception as err:
                sys.exit(f"ERROR: Login failure - {err}")
    else:
        # Enable retries
        tesla.close()
        tesla = teslapy.Tesla(email, retry=retry, cache_file=TAUTH)

    sitelist = {}
    try:
        # Get list of Tesla Energy sites
        for battery in tesla.battery_list():
            try:
                # Retrieve site id and name, site timezone and install date
                siteid = battery['energy_site_id']
                if args.debug: print(f"Get SITE_CONFIG for Site ID {siteid}")
                data = battery.api('SITE_CONFIG')
                if args.debug: print(data)
                if isinstance(data, teslapy.JsonDict) and 'response' in data:
                    sitename = data['response']['site_name']
                    sitetimezone = data['response']['installation_time_zone']
                    siteinstdate = isoparse(data['response']['installation_date'])
                else:
                    sys.exit(f"ERROR: Failed to retrieve SITE_CONFIG - unknown response: {data}")
            except Exception as err:
                sys.exit(f"ERROR: Failed to retrieve SITE_CONFIG - {err}")

            try:
                # Retrieve site current time
                if args.debug: print(f"Get SITE_DATA for Site ID {siteid}")
                data = battery.api('SITE_DATA')
                if args.debug: print(data)
                if isinstance(data, teslapy.JsonDict) and 'response' in data:
                    sitetime = isoparse(data['response']['timestamp'])
                else:
                    sitetime = "No 'live status' returned"
            except Exception as err:
                sys.exit(f"ERROR: Failed to retrieve SITE_DATA - {err}")

            # Add site if site id not already in the list
            if siteid not in sitelist:
                sitelist[siteid] = {}
                sitelist[siteid]['battery'] = battery
                sitelist[siteid]['name'] = sitename
                sitelist[siteid]['timezone'] = sitetimezone
                sitelist[siteid]['instdate'] = siteinstdate
                sitelist[siteid]['time'] = sitetime
    except Exception as err:
        sys.exit(f"ERROR: Failed to retrieve PRODUCT_LIST - {err}")

    # Print list of sites
    for siteid in sitelist:
        if (args.site is None) or (args.site not in sitelist) or (siteid == args.site):
            print(f"      Site ID: {siteid}")
            print(f"    Site name: {sitelist[siteid]['name']}")
            print(f"     Timezone: {sitelist[siteid]['timezone']}")
            print(f"    Installed: {sitelist[siteid]['instdate']}")
            print(f"  System time: {sitelist[siteid]['time']}")
            print("-" * 40)

    return sitelist

def get_power_history(start, end):
    """
    Retrieve power history data between start and end date/time

    Adds data points to 'powerdata' in InfluxDB Line Protocol format with tag source='cloud'
    """
    global dayloaded, power, soe

    print(f"Retrieving data for gap: [{start.astimezone(influxtz)}] - [{end.astimezone(influxtz)}] ({str(end - start)}s)")

    # Set time to end of day for daily calendar history data retrieval
    day = start.astimezone(sitetz).replace(hour=23, minute=59, second=59, tzinfo=None)
    endday = end.astimezone(sitetz).replace(hour=23, minute=59, second=59, tzinfo=None)

    # Loop through each day to retrieve daily 'power' and 'soe' history data
    while day <= endday:
        # Get this day's history if not already loaded
        if day != dayloaded:
            print(f"* Loading daily history: [{day.strftime('%Y-%m-%d')}]")
            time.sleep(TDELAY)
            try:
                # Retrieve current day 'power' history ('power' data returned in 5 minute intervals)
                power = battery.get_calendar_history_data(kind='power', end_date=day.replace(tzinfo=sitetz).isoformat())
                if args.debug: print(power)
                """ Example 'time_series' response:
                {
                    "timestamp": "2022-04-18T12:10:00+10:00",
                    "solar_power": 7522,
                    "battery_power": -4750,
                    "grid_power": -1675.8333333333333,
                    "grid_services_power": 0,
                    "generator_power": 0
                }
                """
                # Retrieve current day 'soe' history ('soe' data returned in 15 minute intervals)
                soe = battery.get_calendar_history_data(kind='soe', end_date=day.replace(tzinfo=sitetz).isoformat())
                if args.debug: print(soe)
                """ Example 'time_series' response:
                {
                    "timestamp": "2022-04-18T12:00:00+10:00",
                    "soe": 67
                }
                """
            except Exception as err:
                sys.exit(f"ERROR: Failed to retrieve history data - {err}")

            dayloaded = day

        if power:
            for d in power['time_series']:
                timestamp = isoparse(d['timestamp']).astimezone(utctz)
                # Save data point when within start/end range only
                if timestamp >= start and timestamp <= end:
                    # Calculate power usage values
                    home = d['solar_power'] + d['battery_power'] + d['grid_power']
                    solar = d['solar_power']
                    from_pw = d['battery_power'] if d['battery_power'] > 0 else 0
                    to_pw = -d['battery_power'] if d['battery_power'] < 0 else 0
                    from_grid = d['grid_power'] if d['grid_power'] > 0 else 0
                    to_grid = -d['grid_power'] if d['grid_power'] < 0 else 0

                    # Save data point values
                    point = f"http,source=cloud,month={timestamp.astimezone(influxtz).strftime('%b')},year={timestamp.astimezone(influxtz).year} home={home},solar={solar},from_pw={from_pw},to_pw={to_pw},from_grid={from_grid},to_grid={to_grid} "
                    point += str(int(timestamp.timestamp()))
                    powerdata.append(point)

        if soe:
            for d in soe['time_series']:
                timestamp = isoparse(d['timestamp']).astimezone(utctz)
                # Save data point when within start/end range only
                if timestamp >= start and timestamp <= end:
                    # Apply reverse scale to battery percentage for consistency with InfluxDB data
                    percentage = (d['soe'] + (5 / 0.95)) * 0.95

                    # Save data point values
                    point = f"http,source=cloud,month={timestamp.astimezone(influxtz).strftime('%b')},year={timestamp.astimezone(influxtz).year} percentage={percentage} "
                    point += str(int(timestamp.timestamp()))
                    powerdata.append(point)

        # Increment to next day
        day += timedelta(days=1)

def get_backup_history(start, end):
    """
    Retrieve backup event history between start and end date/time

    Adds data points to 'eventdata' in InfluxDB Line Protocol format with tag source='cloud'
    """
    global eventsloaded, backup

    if not eventsloaded:
        print("Retrieving backup event history")
        time.sleep(TDELAY)
        try:
            # Retrieve full backup event history
            backup = battery.get_history_data(kind='backup')
            if args.debug: print(backup)
            """ Example 'events' response (event duration in ms):
            {
                "timestamp": "2022-04-19T20:55:53+10:00",
                "duration": 3862580
            }
            """
        except Exception as err:
            sys.exit(f"ERROR: Failed to retrieve history data - {err}")

        eventsloaded = True

    print(f"* Creating grid status data: [{start.astimezone(influxtz)}] - [{end.astimezone(influxtz)}] ({str(end - start)}s)")

    # Create baseline grid_status=1 points aligned to minute intervals for full start/end range
    gridstatus = []
    timestamp = start.replace(second=0)
    while timestamp <= end:
        gridpoint = {}
        gridpoint['time'] = timestamp
        gridpoint['grid_status'] = 1
        gridstatus.append(gridpoint)
        timestamp += timedelta(minutes=1)

    if backup:
        for d in backup['events']:
            # Determine backup event start/end time
            eventstart = isoparse(d['timestamp']).astimezone(utctz)
            duration = timedelta(seconds=round(d['duration'] / 1000))
            eventend = eventstart + duration

            event = f"* Found backup event period: [{eventstart.astimezone(influxtz)}] - [{eventend.astimezone(influxtz)}] ({str(duration)}s)"
            printed = False

            # Align points to minute intervals
            eventstart = eventstart.replace(second=0)
            eventend = eventend.replace(second=0)

            # Set grid_status=0 for points found within backup event period
            for gridpoint in gridstatus:
                if gridpoint['time'] >= eventstart and gridpoint['time'] <= eventend:
                    gridpoint['grid_status'] = 0

                    if not printed:
                        print(event)
                        printed = True

    # Create event data for import to InfluxDB
    for gridpoint in gridstatus:
        timestamp = gridpoint['time']
        grid_status = gridpoint['grid_status']

        # Save data point values
        point = f"http,source=cloud,month={timestamp.astimezone(influxtz).strftime('%b')},year={timestamp.astimezone(influxtz).year} grid_status={grid_status} "
        point += str(int(timestamp.timestamp()))
        eventdata.append(point)

# InfluxDB Functions
def search_influx(start, end, datatype):
    """
    Search InfluxDB for missing data points between start and end date/time

    Returns a list of start/end datetime ranges for the 'datatype' ('power' or 'grid')
    """
    print(f"Searching InfluxDB for data gaps ({datatype})")

    # Create query for the data type specified and set gap detection threshold
    if 'power' in datatype:
        query = f"SELECT home FROM autogen.http WHERE time >= '{start.isoformat()}' AND time <= '{end.isoformat()}'"
        maxgap = timedelta(minutes=5)
    elif 'grid' in datatype:
        query = f"SELECT grid_status FROM grid.http WHERE time >= '{start.isoformat()}' AND time <= '{end.isoformat()}'"
        maxgap = timedelta(minutes=1)

    try:
        # Execute query
        result = client.query(query)
    except Exception as err:
        sys.exit(f"ERROR: Failed to execute InfluxDB query: {query}; {err}")

    datagap = []
    startpoint = start
    startfound = False

    if result:
        # Measure time difference between each data point
        for point in result.get_points():
            timestamp = isoparse(point['time']).astimezone(utctz)

            if timestamp == start:
                startfound = True

            # Check if time since previous point exceeds maximum gap
            duration = timestamp - startpoint
            if duration > maxgap:
                endpoint = timestamp
                print(f"* Found data gap: [{startpoint.astimezone(influxtz)}] - [{endpoint.astimezone(influxtz)}] ({str(duration)}s)")

                # Ensure period falls between existing data points
                if (startfound and startpoint == start) or startpoint > start:
                    startpoint += timedelta(minutes=1)

                # Add missing data period to list
                period = {}
                period['start'] = startpoint
                period['end'] = endpoint - timedelta(seconds=1)
                datagap.append(period)

            # Move start point time to current point
            startpoint = timestamp
        else:
            # Check last data point to end date/time
            duration = end - startpoint
            if duration > maxgap:
                endpoint = end
                print(f"* Found data gap: [{startpoint.astimezone(influxtz)}] - [{endpoint.astimezone(influxtz)}] ({str(duration)}s)")

                # Add missing data period to list
                period = {}
                period['start'] = startpoint + timedelta(minutes=1)
                period['end'] = endpoint
                datagap.append(period)
    else:
        # No points found - entire start/end range is a data gap
        duration = end - start
        if duration > maxgap:
            print(f"* Found data gap: [{start.astimezone(influxtz)}] - [{end.astimezone(influxtz)}] ({str(duration)}s)")

            # Add missing data period to list
            period = {}
            period['start'] = start
            period['end'] = end
            datagap.append(period)

    return datagap

def remove_influx(start, end):
    """
    Remove imported data from InfluxDB (removes data points tagged with source='cloud')
    """
    print("Removing imported data from InfluxDB")

    # Query definitions (sanity check data points before and after delete)
    power = f"SELECT * FROM autogen.http WHERE source='cloud' AND time >= '{start.isoformat()}' AND time <= '{end.isoformat()}'"
    grid = f"SELECT * FROM grid.http WHERE source='cloud' AND time >= '{start.isoformat()}' AND time <= '{end.isoformat()}'"
    delete = f"DELETE FROM http WHERE source='cloud' AND time >= '{start.isoformat()}' AND time <= '{end.isoformat()}'"

    periods = []
    startpoint = None

    try:
        # Execute query for power usage data
        query = power
        result = client.query(query)

        # Get number of data points returned
        ptspower = len(list(result.get_points()))

        # Create list of start/end periods for InfluxDB update after delete
        if ptspower > 0:
            for point in result.get_points():
                if args.debug: print(f"Remove data point: {point}")
                timestamp = isoparse(point['time']).astimezone(utctz)

                if startpoint is None:
                    startpoint = endpoint = timestamp

                duration = timestamp - endpoint
                if duration <= timedelta(minutes=5):
                    # Extend end time of period
                    endpoint = timestamp
                else:
                    # Add data period to list
                    period = {}
                    period['start'] = startpoint
                    period['end'] = endpoint
                    periods.append(period)

                    # Move point times to current
                    startpoint = endpoint = timestamp
            else:
                # Add last data point to list
                period = {}
                period['start'] = startpoint
                period['end'] = endpoint
                periods.append(period)

        # Execute query for grid status data
        query = grid
        result = client.query(query)

        # Get number of data points returned
        ptsgrid = len(list(result.get_points()))

        # Total number of data points to be removed
        ptstotal = ptspower + ptsgrid

        if ptstotal == 0:
            print("* No data points found\n")
            return

        for point in result.get_points():
            if args.debug: print(f"Remove data point: {point}")

        if args.test:
            print(f"* {ptstotal} data points to be removed (*** skipped - test mode enabled ***)\n")
            return

        # Delete data points where source='cloud'
        query = delete
        client.query(query)

        # Execute query after delete for power usage data
        query = power
        result = client.query(query)

        # Get number of data points returned
        ptspowernow = len(list(result.get_points()))

        # Execute query after delete for grid status data
        query = grid
        result = client.query(query)

        # Get number of data points returned
        ptsgridnow = len(list(result.get_points()))

        # Total number of data points after delete (should be zero)
        ptstotalnow = ptspowernow + ptsgridnow
        print(f"* {ptstotal - ptstotalnow} of {ptstotal} data points removed\n")

        if periods:
            # Update InfluxDB analysis data after delete
            update_influx(periods=periods)

    except Exception as err:
        sys.exit(f"ERROR: Failed to execute InfluxDB query: {query}; {err}")

def write_influx():
    """
    Write 'powerdata' and 'eventdata' Line Protocol format data points to InfluxDB
    """
    if args.test:
        print("Writing to InfluxDB (*** skipped - test mode enabled ***)")
        return

    print("Writing to InfluxDB")
    try:
        client.write_points(powerdata, time_precision='s', batch_size=10000, protocol='line')
        client.write_points(eventdata, time_precision='s', batch_size=10000, retention_policy='grid', protocol='line')
    except Exception as err:
        sys.exit(f"ERROR: Failed to write to InfluxDB: {err}")

def update_influx(start=None, end=None, periods=None):
    """
    Update analysis data retention policies (kwh, daily, monthly) from newly imported data
        * Queries will be limited to ranges which include new data points only

    Args:
        start/end   = Single start and end date/time range to run queries for
            or
        periods     = List of start and end date/time ranges to run queries for
    """
    if args.test:
        print("Updating InfluxDB (*** skipped - test mode enabled ***)")
        return

    print("Updating InfluxDB")

    # Create list of hourly/daily/monthly time periods to run queries for
    hourly = []
    daily = []
    monthly = []

    if periods is not None:
        # If passed a list of start/end ranges, set start/end to first item
        start = periods[0]['start']
        end = periods[0]['end']

    # Set hour/day/month start and end periods aligned to group by time ranges
    starthour = start.replace(minute=0, second=0)
    endhour = end.replace(minute=0, second=0) + timedelta(hours=1)
    startday = start.astimezone(influxtz).replace(hour=0, minute=0, second=0, tzinfo=None)
    endday = end.astimezone(influxtz).replace(hour=0, minute=0, second=0, tzinfo=None) + timedelta(days=1)
    startmonth = start.astimezone(influxtz).replace(day=1, hour=0, minute=0, second=0)
    endmonth = end.astimezone(influxtz) + relativedelta(months=1, day=1, hour=0, minute=0, second=0)

    if periods is not None:
        for p in periods[1:]:
            # Get next start and end period time ranges
            nextstarthour = p['start'].astimezone(utctz).replace(minute=0, second=0)
            nextendhour = p['end'].astimezone(utctz).replace(minute=0, second=0) + timedelta(hours=1)
            nextstartday = p['start'].astimezone(influxtz).replace(hour=0, minute=0, second=0, tzinfo=None)
            nextendday = p['end'].astimezone(influxtz).replace(hour=0, minute=0, second=0, tzinfo=None) + timedelta(days=1)
            nextstartmonth = p['start'].astimezone(influxtz).replace(day=1, hour=0, minute=0, second=0)
            nextendmonth = p['end'].astimezone(influxtz) + relativedelta(months=1, day=1, hour=0, minute=0, second=0)

            if nextstarthour <= endhour:
                # Extend time range to include this period
                endhour = nextendhour
            else:
                # Add period to list
                period = {}
                period['start'] = starthour.astimezone(influxtz)
                period['end'] = endhour.astimezone(influxtz)
                hourly.append(period)

                # Skip to next hour
                starthour = nextstarthour
                endhour = nextendhour

            if nextstartday <= endday:
                # Extend time range to include this period
                endday = nextendday
            else:
                # Add period to list
                period = {}
                period['start'] = startday.replace(tzinfo=influxtz)
                period['end'] = endday.replace(tzinfo=influxtz)
                daily.append(period)

                # Skip to next day
                startday = nextstartday
                endday = nextendday

            if nextstartmonth <= endmonth:
                # Extend time range to include this period
                endmonth = nextendmonth
            else:
                # Add period to list
                period = {}
                period['start'] = startmonth
                period['end'] = endmonth
                monthly.append(period)

                # Skip to next month
                startmonth = nextstartmonth
                endmonth = nextendmonth

    # Add last period to list
    period = {}
    period['start'] = starthour.astimezone(influxtz)
    period['end'] = endhour.astimezone(influxtz)
    hourly.append(period)

    period = {}
    period['start'] = startday.replace(tzinfo=influxtz)
    period['end'] = endday.replace(tzinfo=influxtz)
    daily.append(period)

    period = {}
    period['start'] = startmonth
    period['end'] = endmonth
    monthly.append(period)

    # Execute queries for each date/time period
    try:
        for period in hourly:
            # Update hourly analysis data
            query = "SELECT integral(home)/1000/3600 AS home, integral(solar)/1000/3600 AS solar, integral(from_pw)/1000/3600 AS from_pw, integral(to_pw)/1000/3600 AS to_pw, integral(from_grid)/1000/3600 AS from_grid, integral(to_grid)/1000/3600 AS to_grid "
            query += f"INTO kwh.:MEASUREMENT FROM autogen.http WHERE time >= '{period['start'].isoformat()}' AND time < '{period['end'].isoformat()}' "
            query += f"GROUP BY time(1h), month, year tz('{ITZ}')"
            client.query(query)

        for period in daily:
            # Update daily analysis data
            query = "SELECT sum(home) AS home, sum(solar) AS solar, sum(from_pw) AS from_pw, sum(to_pw) AS to_pw, sum(from_grid) AS from_grid, sum(to_grid) AS to_grid "
            query += f"INTO daily.:MEASUREMENT FROM kwh.http WHERE time >= '{period['start'].isoformat()}' AND time < '{period['end'].isoformat()}' "
            query += f"GROUP BY time(1d), month, year tz('{ITZ}')"
            client.query(query)

        for period in monthly:
            # Update monthly analysis data
            query = "SELECT sum(home) AS home, sum(solar) AS solar, sum(from_pw) AS from_pw, sum(to_pw) AS to_pw, sum(from_grid) AS from_grid, sum(to_grid) AS to_grid "
            query += f"INTO monthly.:MEASUREMENT FROM daily.http WHERE time >= '{period['start'].isoformat()}' AND time < '{period['end'].isoformat()}' "
            query += f"GROUP BY time(365d), month, year"
            client.query(query)
    except Exception as err:
        sys.exit(f"ERROR: Failed to execute InfluxDB query: {query}; {err}")

# MAIN

# Login and get list of Tesla Energy sites
sitelist = tesla_login(TUSER)

# Check for energy sites
if len(sitelist) == 0:
    sys.exit("ERROR: No Tesla Energy sites found")
if len(sitelist) > 1 and args.site is None:
    sys.exit('ERROR: Multiple Tesla Energy sites found - select site with option --site "Site ID"')

# Get site from sitelist
if args.site is None:
    site = sitelist[list(sitelist.keys())[0]]
else:
    if args.site in sitelist:
        site = sitelist[args.site]
    else:
        sys.exit(f'ERROR: Site ID "{args.site}" not found')

# Exit if login option given
if args.login:
    sys.exit()

if args.start and args.end:
    try:
        # Get start and end date/time
        s = isoparse(args.start)
        e = isoparse(args.end)
    except Exception as err:
        sys.exit(f"ERROR: Invalid date - {err}")
else:
    if args.today:
        # Set start and end date/time to today
        s = datetime.today().replace(hour=0, minute=0, second=0, microsecond=0)
        e = datetime.today().replace(hour=23, minute=59, second=59, microsecond=0)
    if args.yesterday:
        if args.today:
            # Set date/time range for both today and yesterday
            s -= timedelta(days=1)
        else:
            # Set start and end date/time to yesterday
            s = datetime.today().replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=1)
            e = datetime.today().replace(hour=23, minute=59, second=59, microsecond=0) - timedelta(days=1)

# Get site battery and timezones
battery = site['battery']
sitetimezone = site['timezone']
sitetz = tz.gettz(sitetimezone)
influxtz = tz.gettz(ITZ)
utctz = tz.tzutc()

# Check InfluxDB and site timezones are valid
if influxtz is None:
    sys.exit(f"ERROR: Invalid timezone - {ITZ}")
if sitetz is None:
    sys.exit(f"ERROR: Invalid timezone - {sitetimezone}")
if influxtz != sitetz and not args.ignoretz:
    sys.exit(f'ERROR: InfluxDB timezone "{ITZ}" does not match site timezone "{sitetimezone}"')

# Check start/end datetimes are valid for the configured timezone and convert to aware datetime
start = check_datetime(s, 'start', influxtz).astimezone(utctz)
end = check_datetime(e, 'end', influxtz).astimezone(utctz)

if start >= end:
    sys.exit("ERROR: End date/time must be after start date/time")

print(f"Running for period: [{start.astimezone(influxtz)}] - [{end.astimezone(influxtz)}] ({str(end - start)}s)\n")

# Limit start/end between install date and site current time
if isinstance(site['time'], str):
    sitetime = datetime.now(tz=influxtz).astimezone(utctz).replace(microsecond=0)
else:
    sitetime = site['time'].astimezone(utctz)
siteinstdate = site['instdate'].astimezone(utctz)
if start < siteinstdate:
    start = siteinstdate
if end > sitetime - timedelta(minutes=2):
    end = sitetime - timedelta(minutes=2)
if start >= end:
    sys.exit("ERROR: No data available for this date/time range")

try:
    # Connect to InfluxDB
    client = InfluxDBClient(host=IHOST, port=IPORT, username=IUSER, password=IPASS, database=IDB)
except Exception as err:
    sys.exit(f"ERROR: Failed to connect to InfluxDB: {err}")

powergaps = gridgaps = None

if args.remove:
    # Remove imported data from InfluxDB between start and end date/time
    remove_influx(start, end)
    print("Done.")
    sys.exit()
elif args.force:
    # Retrieve history data between start and end date/time (skip search for gaps)
    get_power_history(start, end)
    print()
    get_backup_history(start, end)
    print()
else:
    # Search InfluxDB for power usage data gaps
    powergaps = search_influx(start, end, 'power usage')
    print() if powergaps else print("* None found\n")

    # Search InfluxDB for grid status data gaps
    gridgaps = search_influx(start, end, 'grid status')
    print() if gridgaps else print("* None found\n")

    if not (powergaps or gridgaps):
        print("Done.")
        sys.exit()

    if powergaps:
        # Retrieve power history data for each gap period
        for period in powergaps:
            get_power_history(period['start'], period['end'])
        print()

    if gridgaps:
        # Retrieve backup event history for each gap period
        for period in gridgaps:
            get_backup_history(period['start'], period['end'])
        print()

if not (powerdata or eventdata):
    sys.exit("ERROR: No data returned for this date/time range")

# Write data points to InfluxDB
write_influx()

if powerdata:
    # Update InfluxDB analysis data
    update_influx(start, end, powergaps)

print("Done.")
