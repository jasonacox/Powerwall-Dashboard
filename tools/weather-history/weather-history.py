#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
 Command line tool to retrieve weather history data by date/time period from
 OpenWeatherMap One Call API 3.0 and import into InfluxDB of Powerwall-Dashboard.

 Author: Michael Birse (for Powerwall-Dashboard by Jason A. Cox)
 For more information see https://github.com/jasonacox/Powerwall-Dashboard

 Overview:
    Historical weather data from OpenWeatherMap can be imported into your
    Powerwall Dashboard graphs by subscribing to the "One Call by Call" plan.

    This is a paid subscription plan with OpenWeatherMap, however allows for
    up to 1,000 API calls per day for free.

    Subscribe to "One Call by Call" here: https://openweathermap.org/api

    If you wish to use the service for free, or control your spend amount, edit
    your "calls per day" limit at the link below (set to 1,000 for free use):
    https://home.openweathermap.org/subscriptions

    Once subscribed to "One Call by Call", the same API key as used by
    Weather411 can be used here (note, plan activation may take some time).

 Usage:
    * Subscribe to the OpenWeatherMap "One Call by Call" plan here:
        https://openweathermap.org/api

    * Set your "calls per day" limit at the link below (set to 1,000 for free use):
        https://home.openweathermap.org/subscriptions

    * Install the required python modules:
        pip install python-dateutil influxdb

    * To use this script:

    - First use / run setup to create or update configuration:
        (creates the config file without retrieving history data)
            python3 weather-history.py --setup

    - Import history data from OpenWeatherMap for start/end date range:
        (by default, searches InfluxDB for data gaps and fills gaps only)
            python3 weather-history.py --start "YYYY-MM-DD hh:mm:ss" --end "YYYY-MM-DD hh:mm:ss"

    - Or, to run in test mode first (will not import data), use --test option:
        python3 weather-history.py --start "YYYY-MM-DD hh:mm:ss" --end "YYYY-MM-DD hh:mm:ss" --test

    - Convenience date options available (e.g. cron usage):
        python3 weather-history.py --today
            and/or
        python3 weather-history.py --yesterday

    - Something went wrong? Use --remove option to remove data imported with this tool:
        (data logged by Powerwall-Dashboard will not be affected)
            python3 weather-history.py --start "YYYY-MM-DD hh:mm:ss" --end "YYYY-MM-DD hh:mm:ss" --remove

    - For more usage options, run without arguments or --help:
        python3 weather-history.py --help
"""
import sys
import os
import argparse
import configparser
import requests
from urllib3 import Retry
import time
from datetime import datetime, timedelta
try:
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
W411CONFIG = f"{SCRIPTPATH}/../../weather/weather411.conf"

# Parse command line arguments
parser = argparse.ArgumentParser(description='Import weather history data from OpenWeatherMap One Call API 3.0 into InfluxDB')
parser.add_argument('-s', '--setup', action='store_true', help='run setup to create or update configuration only (do not get history)')
parser.add_argument('-t', '--test', action='store_true', help='enable test mode (do not import into InfluxDB)')
parser.add_argument('-d', '--debug', action='store_true', help='enable debug output (print raw responses from OpenWeatherMap)')
group = parser.add_argument_group('advanced options')
group.add_argument('--config', help=f'specify an alternate config file (default: {CONFIGNAME})')
group.add_argument('--w411conf', help='specify Weather411 config file to set defaults from during setup')
group.add_argument('--force', action='store_true', help='force import for date/time range (skip search for data gaps)')
group.add_argument('--remove', action='store_true', help='remove imported data from InfluxDB for date/time range')
group = parser.add_argument_group('date/time range options')
group.add_argument('--start', help='start date and time ("YYYY-MM-DD hh:mm:ss")')
group.add_argument('--end', help='end date and time ("YYYY-MM-DD hh:mm:ss")')
group.add_argument('--today', action='store_true', help='set start/end range to "today"')
group.add_argument('--yesterday', action='store_true', help='set start/end range to "yesterday"')
args = parser.parse_args()

# Check for invalid argument combinations
if len(sys.argv) == 1:
    parser.print_help(sys.stderr)
    sys.exit()
if (args.start or args.end) and (args.today or args.yesterday):
    parser.error("arguments --start and --end cannot be used with --today or --yesterday")
if (args.start and not args.end) or (args.end and not args.start):
    parser.error("both arguments --start and --end are required")
if not args.setup and not ((args.start and args.end) or (args.today or args.yesterday)):
    parser.error("missing arguments: --start/end or --today/yesterday")

print("-" * 51)
print("Weather History Import Tool for Powerwall-Dashboard")
print("-" * 51)

# Use alternate config files if specified
if args.config:
    CONFIGNAME = CONFIGFILE = args.config
if args.w411conf:
    W411CONFIG = args.w411conf

# Load Configuration File
configloaded = False
config = configparser.ConfigParser(allow_no_value=True)
if not os.path.exists(CONFIGFILE) and "/" not in CONFIGFILE:
    # Look for config file in script location if not found
    CONFIGFILE = f"{SCRIPTPATH}/{CONFIGFILE}"
if os.path.exists(CONFIGFILE):
    try:
        config.read(CONFIGFILE)

        # Get OpenWeatherMap Settings
        OWKEY = config.get('OpenWeatherMap', 'APIKEY')
        OWLAT = config.get('OpenWeatherMap', 'LAT')
        OWLON = config.get('OpenWeatherMap', 'LON')
        OWUNITS = config.get('OpenWeatherMap', 'UNITS')
        OWGAP = config.getint('OpenWeatherMap', 'GAP', fallback=30)
        TIMEOUT = config.getint('OpenWeatherMap', 'TIMEOUT', fallback=10)

        if OWGAP < 10:
            OWGAP = 10

        # Get InfluxDB Settings
        IHOST = config.get('InfluxDB', 'HOST')
        IPORT = config.getint('InfluxDB', 'PORT', fallback=8086)
        IUSER = config.get('InfluxDB', 'USER', fallback='')
        IUSER = config.get('InfluxDB', 'USERNAME', fallback=IUSER)
        IPASS = config.get('InfluxDB', 'PASS', fallback='')
        IPASS = config.get('InfluxDB', 'PASSWORD', fallback=IPASS)
        IDB = config.get('InfluxDB', 'DB')
        IFIELD = config.get('InfluxDB', 'FIELD')
        ITZ = config.get('InfluxDB', 'TZ')
        configloaded = True
    except Exception as err:
        sys.exit(f"ERROR: Config file '{CONFIGNAME}' - {err}")
if args.setup or not configloaded:
    if not configloaded:
        # Config not found - prompt user for configuration and save settings
        print(f"\nConfig file '{CONFIGNAME}' not found\n")

        while True:
            response = input("Do you want to create the config now? [Y/n] ").strip().lower()
            if response == "n":
                sys.exit()
            elif response in ("y", ""):
                break

        # Attempt to load defaults from Weather411 configuration file
        if os.path.exists(W411CONFIG):
            try:
                w411conf = configparser.ConfigParser(allow_no_value=True)
                w411conf.read(W411CONFIG)

                # Get OpenWeatherMap Settings
                OWKEY = w411conf.get('OpenWeatherMap', 'APIKEY', fallback=None)
                OWLAT = w411conf.get('OpenWeatherMap', 'LAT', fallback=None)
                OWLON = w411conf.get('OpenWeatherMap', 'LON', fallback=None)
                OWUNITS = w411conf.get('OpenWeatherMap', 'UNITS', fallback=None)
                OWGAP = w411conf.getint('OpenWeatherMap', 'GAP', fallback=None)
                TIMEOUT = w411conf.getint('OpenWeatherMap', 'TIMEOUT', fallback=10)

                if OWGAP is not None and OWGAP < 10:
                    OWGAP = 10

                # Get InfluxDB Settings
                IHOST = w411conf.get('InfluxDB', 'HOST', fallback=None)
                IPORT = w411conf.getint('InfluxDB', 'PORT', fallback=None)
                IUSER = w411conf.get('InfluxDB', 'USER', fallback=None)
                IUSER = w411conf.get('InfluxDB', 'USERNAME', fallback=IUSER)
                IPASS = w411conf.get('InfluxDB', 'PASS', fallback=None)
                IPASS = w411conf.get('InfluxDB', 'PASSWORD', fallback=IPASS)
                IDB = w411conf.get('InfluxDB', 'DB', fallback=None)
                IFIELD = w411conf.get('InfluxDB', 'FIELD', fallback=None)
                ITZ = w411conf.get('InfluxDB', 'TZ', fallback=None)

                if IHOST is not None and IHOST == "influxdb":
                    IHOST = "localhost"
            except:
                pass
            else:
                print(f"\nLoaded [defaults] from '{os.path.abspath(W411CONFIG)}'...")
                configloaded = True
    else:
        print(f"\nLoaded [defaults] from '{os.path.abspath(CONFIGNAME)}'...")

    print(
"""
OpenWeatherMap Setup
--------------------
Historical weather data from OpenWeatherMap can be imported into your
Powerwall Dashboard graphs by subscribing to the "One Call by Call" plan.

This is a paid subscription plan with OpenWeatherMap, however allows for
up to 1,000 API calls per day for free.

Subscribe to "One Call by Call" here: https://openweathermap.org/api

If you wish to use the service for free, or control your spend amount, edit
your "calls per day" limit at the link below (set to 1,000 for free use):
https://home.openweathermap.org/subscriptions

Once subscribed to "One Call by Call", the same API key as used by
Weather411 can be used here (note, plan activation may take some time).
""")

    while True:
        if configloaded and OWKEY:
            response = input(f"API Key: [{OWKEY}] ").strip()
        else:
            response = input("API Key: ").strip()
        if configloaded and OWKEY and response == "":
            break
        elif response != "":
            OWKEY = response
            break

    while True:
        if configloaded and OWLAT:
            response = input(f"Latitude: [{OWLAT}] ").strip()
        else:
            response = input("Latitude: ").strip()
        if configloaded and OWLAT and response == "":
            break
        elif response != "":
            OWLAT = response
            break

    while True:
        if configloaded and OWLON:
            response = input(f"Longitude: [{OWLON}] ").strip()
        else:
            response = input("Longitude: ").strip()
        if configloaded and OWLON and response == "":
            break
        elif response != "":
            OWLON = response
            break

    while True:
        if configloaded and OWUNITS:
            response = input(f"Units - M)etric, I)mperial or S)tandard: [{OWUNITS[0].upper()}] ").strip().lower()
        else:
            response = input("Units - M)etric, I)mperial or S)tandard: [M] ").strip().lower()
        if configloaded and OWUNITS and response == "":
            break
        elif response in ("m", ""):
            OWUNITS = "metric"
            break
        elif response == "i":
            OWUNITS = "imperial"
            break
        elif response == "s":
            OWUNITS = "standard"
            break

    while True:
        if configloaded and OWGAP:
            response = input(f"Retrieve weather history every (minutes): [{OWGAP}] ").strip()
        else:
            response = input("Retrieve weather history every (minutes): [30] ").strip()
        if configloaded and OWGAP and response == "":
            break
        elif response == "":
            OWGAP = 30
            break
        else:
            try:
                if int(response) >= 10:
                    OWGAP = int(response)
                    break
                else:
                    print("\nERROR: Minimum interval gap is 10 minutes\n")
            except:
                print("\nERROR: Invalid number\n")

    print("\nInfluxDB Setup")
    print("-" * 14)

    if configloaded and IHOST:
        response = input(f"Host: [{IHOST}] ").strip().lower()
    else:
        response = input("Host: [localhost] ").strip().lower()
    if configloaded and IHOST and response == "":
        pass
    elif response == "":
        IHOST = "localhost"
    else:
        IHOST = response

    while True:
        if configloaded and IPORT:
            response = input(f"Port: [{IPORT}] ").strip()
        else:
            response = input("Port: [8086] ").strip()
        if configloaded and IPORT and response == "":
            break
        elif response == "":
            IPORT = 8086
            break
        else:
            try:
                IPORT = int(response)
                break
            except:
                print("\nERROR: Invalid number\n")

    if configloaded and IUSER:
        response = input(f"User: [{IUSER}] ").strip()
    else:
        response = input("User (leave blank if not used): [blank] ").strip()
    if configloaded and IUSER and response == "":
        pass
    else:
        if response == "blank":
            IUSER = ""
        else:
            IUSER = response

    if configloaded and IPASS:
        response = input(f"Pass: [{IPASS}] ").strip()
    else:
        response = input("Pass (leave blank if not used): [blank] ").strip()
    if configloaded and IPASS and response == "":
        pass
    else:
        if response == "blank":
            IPASS = ""
        else:
            IPASS = response

    if configloaded and IDB:
        response = input(f"Database: [{IDB}] ").strip().lower()
    else:
        response = input("Database: [powerwall] ").strip().lower()
    if configloaded and IDB and response == "":
        pass
    elif response == "":
        IDB = "powerwall"
    else:
        IDB = response

    if configloaded and IFIELD:
        response = input(f"Field: [{IFIELD}] ").strip().lower()
    else:
        response = input("Field: [weather] ").strip().lower()
    if configloaded and IFIELD and response == "":
        pass
    elif response == "":
        IFIELD = "weather"
    else:
        IFIELD = response

    while True:
        if configloaded and ITZ:
            response = input(f"Timezone: [{ITZ}] ").strip()
        else:
            response = input("Timezone (e.g. America/Los_Angeles): ").strip()
        if configloaded and ITZ and response == "":
            if tz.gettz(ITZ) is None:
                print("Invalid timezone\n")
            else:
                break
        elif response != "":
            if tz.gettz(response) is None:
                print("Invalid timezone\n")
            else:
                ITZ = response
                break

    # Set config values
    config.optionxform = str
    config['OpenWeatherMap'] = {}
    config['OpenWeatherMap']['APIKEY'] = OWKEY
    config['OpenWeatherMap']['LAT'] = OWLAT
    config['OpenWeatherMap']['LON'] = OWLON
    config['OpenWeatherMap']['UNITS'] = OWUNITS
    config['OpenWeatherMap']['GAP'] = str(OWGAP)

    if not configloaded:
        TIMEOUT = 10
    elif TIMEOUT != 10:
        config['OpenWeatherMap']['TIMEOUT'] = str(TIMEOUT)

    config['InfluxDB'] = {}
    config['InfluxDB']['HOST'] = IHOST
    config['InfluxDB']['PORT'] = str(IPORT)
    config['InfluxDB']['USER'] = IUSER
    config['InfluxDB']['PASS'] = IPASS
    config['InfluxDB']['DB'] = IDB
    config['InfluxDB']['FIELD'] = IFIELD
    config['InfluxDB']['TZ'] = ITZ

    try:
        # Write config file
        with open(CONFIGFILE, 'w') as configfile:
            config.write(configfile)
    except Exception as err:
        sys.exit(f"\nERROR: Failed to save config to '{CONFIGNAME}' - {err}")

    print(f"\nConfig saved to '{CONFIGNAME}'\n")

    if args.setup:
        sys.exit()

    while True:
        response = input("Do you want to retrieve weather history now? [Y/n] ").strip().lower()
        if response == "n":
            sys.exit()
        elif response in ("y", ""):
            print("-" * 51)
            break

# Global Variables
onecall = f"https://api.openweathermap.org/data/3.0/onecall/timemachine?lat={OWLAT}&lon={OWLON}&units={OWUNITS}&appid={OWKEY}"
stdcall = f"https://api.openweathermap.org/data/2.5/weather?lat={OWLAT}&lon={OWLON}&units={OWUNITS}&appid={OWKEY}"
weatherdata = []
weathergaps = None
currdata = None
finished = False

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

def lprmap(data, key, value, valtype=None):
    """
    Return mapped Line Protocol formatted key/value pair string, if value found in data
    """
    if value in data:
        if valtype == 'float':
            v = float(data[value])
        elif valtype == 'int':
            v = int(data[value])
        elif valtype == 'str':
            v = str(data[value])
        else:
            v = data[value]
        return f",{key}={lpr(v)}"
    return ""

# OpenWeatherMap Functions
def get_weather_history(start, end):
    """
    Retrieve weather history data between start and end date/time

    Adds data points to 'weatherdata' in InfluxDB Line Protocol format with tag source='timemachine'
    """
    global currdata, finished

    print(f"Retrieving data for gap: [{start.astimezone(influxtz)}] - [{end.astimezone(influxtz)}] ({str(end - start)}s)")

    if not currdata:
        # Retrieve current weather data via standard API call
        try:
            url = stdcall
            response = session.get(url, timeout=TIMEOUT)
            if response.status_code == 200:
                currdata = response.json()
                if args.debug:
                    print(f"Request: {url}")
                    print(f"Replied: {response.json()}")
            else:
                sys.exit(f"\nERROR: Bad response from OpenWeatherMap for {url} - {response.reason}: {response.text}")
        except Exception as err:
            sys.exit(f"\nERROR: Failed to retrieve history data - {err}")

    # Retrieve weather history data for each gap interval from start to end period
    interval = timedelta(minutes=OWGAP)
    halted = False
    curr = start
    while curr <= end:
        print(f"* Loading data for time: [{curr.astimezone(influxtz)}]")
        try:
            url = f"{onecall}&dt={int(curr.timestamp())}"
            response = session.get(url, timeout=TIMEOUT)
            if response.status_code == 200:
                raw = response.json()
                if args.debug:
                    print(f"Request: {url}")
                    print(f"Replied: {response.json()}")

                # Create data point field key/value pairs in Line Protocol format
                fields = ""
                fields += lprmap(raw, 'tz', 'timezone_offset', 'int')
                fields += lprmap(currdata, 'id', 'id', 'int')
                fields += lprmap(currdata, 'name', 'name', 'str')
                if "sys" in currdata:
                    fields += lprmap(currdata['sys'], 'country', 'country', 'str')
                if "data" in raw and len(raw['data']) > 0:
                    data = raw['data'][0]
                    fields += lprmap(data, 'dt', 'dt', 'int')
                    fields += lprmap(data, 'temperature', 'temp', 'float')
                    fields += lprmap(data, 'feels_like', 'feels_like', 'float')
                    fields += lprmap(data, 'temp_min', 'temp', 'float')
                    fields += lprmap(data, 'temp_max', 'temp', 'float')
                    fields += lprmap(data, 'pressure', 'pressure', 'int')
                    fields += lprmap(data, 'humidity', 'humidity', 'int')
                    fields += lprmap(data, 'visibility', 'visibility', 'int')
                    fields += lprmap(data, 'wind_speed', 'wind_speed', 'float')
                    fields += lprmap(data, 'wind_deg', 'wind_deg', 'int')
                    fields += lprmap(data, 'wind_gust', 'wind_gust', 'float')
                    fields += lprmap(data, 'clouds', 'clouds', 'int')
                    fields += lprmap(data, 'sunrise', 'sunrise', 'int')
                    fields += lprmap(data, 'sunset', 'sunset', 'int')
                    if "weather" in data and len(data['weather']) > 0:
                        fields += lprmap(data['weather'][0], 'weather_id', 'id', 'int')
                        fields += lprmap(data['weather'][0], 'weather_main', 'main', 'str')
                        fields += lprmap(data['weather'][0], 'weather_description', 'description', 'str')
                        fields += lprmap(data['weather'][0], 'weather_icon', 'icon', 'str')
                    if "rain" in data:
                        fields += lprmap(data['rain'], 'rain_1h', '1h', 'float')
                        fields += lprmap(data['rain'], 'rain_3h', '3h', 'float')
                    if "snow" in data:
                        fields += lprmap(data['snow'], 'snow_1h', '1h', 'float')
                        fields += lprmap(data['snow'], 'snow_3h', '3h', 'float')
                else:
                    # No valid data - increment time to next interval and continue
                    curr += interval
                    continue

                # Save data point values
                point = f"{IFIELD},source=timemachine {fields[1:]} {int(curr.timestamp())}"
                weatherdata.append(point)
                if args.debug:
                    print(f"Datapnt: {point}")

            elif response.status_code == 429:
                print("\nCalls per day limit reached - continue tomorrow or edit your limits at: https://home.openweathermap.org/subscriptions")
                finished = True
                return
            else:
                sys.exit(f"\nERROR: Bad response from OpenWeatherMap for {url} - {response.reason}: {response.text}")
        except KeyboardInterrupt:
            print()
            while True:
                try:
                    response = input("Program halted - R)esume, Q)uit (write data), or A)bort: [R/Q/A] ").strip().lower()
                except KeyboardInterrupt:
                    print()
                else:
                    if response == "r":
                        halted = True
                        break
                    elif response == "q":
                        finished = True
                        return
                    elif response == "a":
                        sys.exit()
        except Exception as err:
            sys.exit(f"\nERROR: Failed to retrieve history data - {err}")

        if not halted:
            # Increment time to next interval
            curr += interval
        else:
            halted = False

# InfluxDB Functions
def search_influx(start, end):
    """
    Search InfluxDB for missing data points between start and end date/time

    Returns a list of start/end datetime ranges
    """
    print(f"Searching InfluxDB for data gaps >= {OWGAP} minutes")

    # Create query and set gap detection threshold
    query = f"SELECT dt FROM autogen.{IFIELD} WHERE time >= '{start.isoformat()}' AND time <= '{end.isoformat()}'"
    maxgap = timedelta(minutes=OWGAP)

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
            if duration > maxgap + timedelta(seconds=10):
                endpoint = timestamp
                print(f"* Found data gap: [{startpoint.astimezone(influxtz)}] - [{endpoint.astimezone(influxtz)}] ({str(duration)}s)")

                # Ensure period falls between existing data points
                if (startfound and startpoint == start) or startpoint > start:
                    startpoint += maxgap

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
            if duration > maxgap + timedelta(seconds=10):
                endpoint = end
                print(f"* Found data gap: [{startpoint.astimezone(influxtz)}] - [{endpoint.astimezone(influxtz)}] ({str(duration)}s)")

                # Add missing data period to list
                period = {}
                period['start'] = startpoint + maxgap
                period['end'] = endpoint
                datagap.append(period)
    else:
        # No points found - entire start/end range is a data gap
        duration = end - start
        if duration > maxgap + timedelta(seconds=10):
            print(f"* Found data gap: [{start.astimezone(influxtz)}] - [{end.astimezone(influxtz)}] ({str(duration)}s)")

            # Add missing data period to list
            period = {}
            period['start'] = start
            period['end'] = end
            datagap.append(period)

    return datagap

def remove_influx(start, end):
    """
    Remove imported data from InfluxDB (removes data points tagged with source='timemachine')
    """
    print("Removing imported data from InfluxDB")

    # Query definitions (sanity check data points before and after delete)
    where = f"WHERE source='timemachine' AND time >= '{start.isoformat()}' AND time <= '{end.isoformat()}'"
    select = f"SELECT * FROM autogen.{IFIELD} {where}"
    delete = f"DELETE FROM {IFIELD} {where}"

    try:
        # Execute query for weather data
        query = select
        result = client.query(query)

        # Get number of data points returned
        ptsfound = len(list(result.get_points()))

        if ptsfound == 0:
            print("* No data points found\n")
            return

        for point in result.get_points():
            if args.debug:
                print(f"Remove data point: {point}")

        if args.test:
            print(f"* {ptsfound} data points to be removed (*** skipped - test mode enabled ***)\n")
            return

        # Delete data points where source='timemachine'
        query = delete
        client.query(query)

        # Execute query after delete for weather data
        query = select
        result = client.query(query)

        # Get number of data points returned (should be zero)
        ptsfoundnow = len(list(result.get_points()))

        # Total number of data points removed
        print(f"* {ptsfound - ptsfoundnow} of {ptsfound} data points removed\n")

    except Exception as err:
        sys.exit(f"ERROR: Failed to execute InfluxDB query: {query}; {err}")

def write_influx():
    """
    Write 'weatherdata' Line Protocol format data points to InfluxDB
    """
    if args.test:
        print("Writing to InfluxDB (*** skipped - test mode enabled ***)")
        return

    print("Writing to InfluxDB")
    try:
        client.write_points(weatherdata, time_precision='s', batch_size=10000, protocol='line')
    except Exception as err:
        sys.exit(f"ERROR: Failed to write to InfluxDB: {err}")

# MAIN
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

# Get timezones
influxtz = tz.gettz(ITZ)
utctz = tz.tzutc()

# Check InfluxDB timezone is valid
if influxtz is None:
    sys.exit(f"ERROR: Invalid timezone - {ITZ}")

# Check start/end datetimes are valid for the configured timezone and convert to aware datetime
start = check_datetime(s, 'start', influxtz).astimezone(utctz)
end = check_datetime(e, 'end', influxtz).astimezone(utctz)

if start >= end:
    sys.exit("ERROR: End date/time must be after start date/time")

print(f"Running for period: [{start.astimezone(influxtz)}] - [{end.astimezone(influxtz)}] ({str(end - start)}s)\n")

# Limit end to current time less gap interval
currtime = datetime.now(tz=influxtz).astimezone(utctz).replace(microsecond=0)
if end > currtime - timedelta(minutes=OWGAP):
    end = currtime - timedelta(minutes=OWGAP)
if start >= end:
    sys.exit("ERROR: No data available for this date/time range")

try:
    # Connect to InfluxDB
    client = InfluxDBClient(host=IHOST, port=IPORT, username=IUSER, password=IPASS, database=IDB)
except Exception as err:
    sys.exit(f"ERROR: Failed to connect to InfluxDB: {err}")

if args.remove:
    # Remove imported data from InfluxDB between start and end date/time
    remove_influx(start, end)
    print("Done.")
    sys.exit()

# Create session object for http connection re-use
session = requests.Session()
adapter = requests.adapters.HTTPAdapter(max_retries=Retry(total=5, status_forcelist=(500, 502, 503, 504), backoff_factor=1))
session.mount('https://', adapter)
if TIMEOUT < 1:
    TIMEOUT = None

if args.force:
    # Retrieve history data between start and end date/time (skip search for gaps)
    get_weather_history(start, end)
    print()
else:
    # Search InfluxDB for weather data gaps
    weathergaps = search_influx(start, end)
    print() if weathergaps else print("* None found\n")

    if not weathergaps:
        print("Done.")
        sys.exit()

    if weathergaps:
        # Retrieve weather history data for each gap period
        for period in weathergaps:
            get_weather_history(period['start'], period['end'])
            if finished:
                break
        print()

if not weatherdata:
    sys.exit("ERROR: No data returned for this date/time range")

# Write data points to InfluxDB
write_influx()
print("Done.")
