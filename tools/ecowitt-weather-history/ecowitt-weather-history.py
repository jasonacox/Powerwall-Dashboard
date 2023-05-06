#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
 Command line tool to retrieve weather history data by date/time period from
 Ecowitt API and import into InfluxDB of Powerwall-Dashboard.

 Author: BJReplay
 Based on work by Michael Birse (for Powerwall-Dashboard by Jason A. Cox)
 For more information see https://github.com/jasonacox/Powerwall-Dashboard

 Overview:
    Historical weather data from Ecowitt API can be imported into your
    Powerwall Dashboard graphs by repeatedly calling the historical API with a short time range and a short interval.

 Usage:
    * Subscribe to the Ecowitt API as described here
        https://github.com/jasonacox/Powerwall-Dashboard/tree/main/weather/contrib/ecowitt#ecowitt-local-weather-server

    * Install the required python modules:
        pip install python-dateutil influxdb

    * To use this script:

    - First use / run setup to create or update configuration:
        (creates the config file without retrieving history data)
            python3 ecowitt-weather-history.py --setup

    - Import history data from Ecowitt API for start/end date range:
        (by default, searches InfluxDB for data gaps and fills gaps only)
            python3 ecowitt-weather-history.py --start "YYYY-MM-DD" --end "YYYY-MM-DD"

    - Or, to run in test mode first (will not import data), use --test option:
        python3 ecowitt-weather-history.py --start "YYYY-MM-DD" --end "YYYY-MM-DD" --test

    - Convenience date options available (e.g. cron usage):
        python3 ecowitt-weather-history.py --today
            and/or
        python3 ecowitt-weather-history.py --yesterday

    - Something went wrong? Use --remove option to remove data imported with this tool:
        (data logged by Powerwall-Dashboard will not be affected)
            python3 ecowitt-weather-history.py --start "YYYY-MM-DD" --end "YYYY-MM-DD" --remove

    - For more usage options, run without arguments or --help:
        python3 ecowitt-weather-history.py --help
"""
import sys
import os
import argparse
import configparser
import requests
from urllib3 import Retry
import time
import json
import traceback
from datetime import datetime, timedelta, date
from collections import namedtuple
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
ECOCONFIG = f"{SCRIPTPATH}/../../weather/contrib/ecowitt/ecowitt.conf"

# Parse command line arguments
parser = argparse.ArgumentParser(description='Import weather history data from Ecowitt API into InfluxDB')
parser.add_argument('-s', '--setup', action='store_true', help='run setup to create or update configuration only (do not get history)')
parser.add_argument('-t', '--test', action='store_true', help='enable test mode (do not import into InfluxDB)')
parser.add_argument('-d', '--debug', action='store_true', help='enable debug output (print raw responses from Ecowitt API)')
group = parser.add_argument_group('advanced options')
group.add_argument('--config', help=f'specify an alternate config file (default: {CONFIGNAME})')
group.add_argument('--ecoconf', help='specify ecowitt config file to set defaults from during setup')
group.add_argument('--force', action='store_true', help='force import for date/time range (skip search for data gaps)')
group.add_argument('--remove', action='store_true', help='remove imported data from InfluxDB for date/time range')
group = parser.add_argument_group('date/time range options')
group.add_argument('--start', help='start date and time ("YYYY-MM-DD")')
group.add_argument('--end', help='end date and time ("YYYY-MM-DD")')
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
if args.ecoconf:
    ECOCONFIG = args.ecoconf

# Load Configuration File
configloaded = False
config = configparser.ConfigParser(allow_no_value=True)
if not os.path.exists(CONFIGFILE) and "/" not in CONFIGFILE:
    # Look for config file in script location if not found
    CONFIGFILE = f"{SCRIPTPATH}/{CONFIGFILE}"
if os.path.exists(CONFIGFILE):
    try:
        config.read(CONFIGFILE)

        # Ecowitt
        ECOKEY = config.get('Ecowitt', 'APIKEY')
        ECOAPP = config.get('Ecowitt', 'APPKEY')
        ECOUNITS = config.get('Ecowitt', 'UNITS', fallback='M')
        ECOMAC = config.get('Ecowitt', 'MAC')
        TIMEOUT = config.getint('Ecowitt', 'TIMEOUT', fallback=10)

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

        # Attempt to load defaults from ecowitt configuration file
        if os.path.exists(ECOCONFIG):
            try:
                ecoconf = configparser.ConfigParser(allow_no_value=True)
                ecoconf.read(ECOCONFIG)

                # Get Ecowitt API Settings
                ECOKEY = ecoconf.get('Ecowitt', 'APIKEY', fallback=None)
                ECOAPP = ecoconf.get('Ecowitt', 'APPKEY', fallback=None)
                ECOUNITS = ecoconf.get('Ecowitt', 'UNITS', fallback=None)
                ECOMAC = ecoconf.get('Ecowitt', 'MAC', fallback=None)
                TIMEOUT = ecoconf.getint('Ecowitt', 'TIMEOUT', fallback=10)

                # Get InfluxDB Settings
                IHOST = ecoconf.get('InfluxDB', 'HOST', fallback=None)
                IPORT = ecoconf.getint('InfluxDB', 'PORT', fallback=None)
                IUSER = ecoconf.get('InfluxDB', 'USER', fallback=None)
                IUSER = ecoconf.get('InfluxDB', 'USERNAME', fallback=IUSER)
                IPASS = ecoconf.get('InfluxDB', 'PASS', fallback=None)
                IPASS = ecoconf.get('InfluxDB', 'PASSWORD', fallback=IPASS)
                IDB = ecoconf.get('InfluxDB', 'DB', fallback=None)
                IFIELD = ecoconf.get('InfluxDB', 'FIELD', fallback=None)
                ITZ = ecoconf.get('InfluxDB', 'TZ', fallback=None)

                if IHOST is not None and IHOST == "influxdb":
                    IHOST = "localhost"
            except:
                pass
            else:
                print(f"\nLoaded [defaults] from '{os.path.abspath(ECOCONFIG)}'...")
                configloaded = True
    else:
        print(f"\nLoaded [defaults] from '{os.path.abspath(CONFIGNAME)}'...")

    print(
"""
Ecowitt API Setup
--------------------
Historical weather data from Ecowitt API can be imported into your
Powerwall Dashboard.

""")

    while True:
        if configloaded and ECOKEY:
            response = input(f"API Key: [{ECOKEY}] ").strip()
        else:
            response = input("API Key: ").strip()
        if configloaded and ECOKEY and response == "":
            break
        elif response != "":
            ECOKEY = response
            break

    while True:
        if configloaded and ECOAPP:
            response = input(f"APP Key: [{ECOAPP}] ").strip()
        else:
            response = input("APP Key: ").strip()
        if configloaded and ECOAPP and response == "":
            break
        elif response != "":
            ECOAPP = response
            break

    while True:
        if configloaded and ECOMAC:
            response = input(f"MAC: [{ECOMAC}] ").strip()
        else:
            response = input("MAC: ").strip()
        if configloaded and ECOMAC and response == "":
            break
        elif response != "":
            ECOMAC = response
            break

    while True:
        if configloaded and ECOUNITS:
            response = input(f"Units - M)etric, I)mperial[{ECOUNITS[0].upper()}] ").strip().lower()
        else:
            response = input("Units - M)etric or I)mperial [M] ").strip().lower()
        if configloaded and ECOUNITS and response == "":
            break
        elif response in ("m", ""):
            ECOUNITS = "metric"
            break
        elif response == "i":
            ECOUNITS = "imperial"
            break

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
    while True:
        if configloaded and TIMEOUT:
            response = input(f"Timeout: [{TIMEOUT}] ").strip()
        else:
            response = input("Timeout: [10] ").strip()
        if configloaded and TIMEOUT and response == "":
            break
        elif response == "":
            TIMEOUT = 10
            break
        else:
            try:
                TIMEOUT = int(response)
                break
            except:
                print("\nERROR: Invalid number\n")



    # Set config values
    config.optionxform = str
    config['Ecowitt'] = {}
    config['Ecowitt']['APIKEY'] = ECOKEY
    config['Ecowitt']['APPKEY'] = ECOAPP
    config['Ecowitt']['MAC'] = ECOMAC
    config['Ecowitt']['UNITS'] = ECOUNITS

    if TIMEOUT != 10:
        config['Ecowitt']['TIMEOUT'] = str(TIMEOUT)

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
ecoapi = f"https://api.ecowitt.net/api/v3/device/history?application_key={ECOAPP}&api_key={ECOKEY}&mac={ECOMAC}&cycle_type=auto&call_back=indoor,outdoor,solar_and_uvi,rainfall,wind,pressure,co2_aqi_combo,pm25_aqi_combo,pm10_aqi_combo"
if ECOUNITS == 'metric':
    ecoapi = ecoapi + "&temp_unitid=1&pressure_unitid=3&wind_speed_unitid=7&rainfall_unitid=12&solar_irradiance_unitid=16"
elif ECOUNITS == 'imperial':
    ecoapi = ecoapi + "&temp_unitid=2&pressure_unitid=4&wind_speed_unitid=9rainfall_unitid=13&solar_irradiance_unitid=16"


weatherdata = []
weathergaps = None
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

def lprmap(data, group, key, value, valtype=None, searchfor=None):
    """
    Return mapped Line Protocol formatted key/value pair string, if value found in data
    """
    if searchfor == None:
        searchfor=key
    try:
        newval = data[group][searchfor]["list"]
        if valtype == 'float':
            v = float(newval[value])
        elif valtype == 'int':
            v = int(newval[value])
        elif valtype == 'str':
            v = str(newval[value])
        else:
            v = newval[value]
        return f",{key}={lpr(v)}"
    except:
        return ""

def getdays(startime):
    """
    * 5 minutes resolution data within the past 90days, each data request time span should not be longer than a complete day；
    * 30 minutes resolution data within the past 365days, each data request time span should not be longer than a complete week；
    * 240 minutes resolution data within the past 730days, each data request time span should not be longer than a complete month；
    * 24hours resolution data since 2019.1.1, each data request time span should not be longer than a complete year;

    """
    if startime > currtime - timedelta(days=-90):
        numdays = 1
    elif startime > currtime - timedelta(days=-365) and startime <= currtime - timedelta(days=-90):
        numdays = 7
    elif startime > currtime - timedelta(days=-730) and startime <= currtime - timedelta(days=-365):
        numdays = 30
    else:
        numdays = 365
    return numdays

# Ecowitt API Functions
def get_weather_history(start, end):
    """
    Retrieve weather history data between start and end date/time

    Adds data points to 'weatherdata' in InfluxDB Line Protocol format with tag source='timemachine'
    """
    global finished

    print(f"Retrieving data for gap: [{start.astimezone(influxtz)}] - [{end.astimezone(influxtz)}] ({str(end - start)}s)")

    # Retrieve weather history data for each day from start to end period
    halted = False
    curr = start
    interval = timedelta(days=getdays(curr))

    while curr <= end:
        print(f"* Loading data for time: [{curr.astimezone(influxtz)}]")
        try:
            dtstart = curr.date()
            dtend = dtstart
            dtend += interval
            url = f"{ecoapi}&start_date={dtstart}%2000:00:00&end_date={dtend}%2023:59:59"
            response = session.get(url, timeout=TIMEOUT)
            if response.status_code == 200:
                raw = response.json()
                if args.debug:
                    print(f"Request: {url}")
                    print(f"Replied: {raw}")
                # Create data point field key/value pairs in Line Protocol format
                fields = ""
                if "data" in raw and len(raw["data"]) > 0 and "outdoor" in raw["data"] and len(raw["data"]["outdoor"]) > 0:
                    data = raw["data"]
                    timestamps = list(data["outdoor"]["temperature"]["list"].keys())
                    print(f"** Found {len(timestamps)} results")
                    for i in timestamps:
                        # outdoor
                        fields += lprmap(data,"outdoor",'temperature', i, 'float')
                        fields += lprmap(data,"outdoor",'feels_like', i, 'float')
                        fields += lprmap(data,"outdoor",'app_temp', i, 'float')
                        fields += lprmap(data,"outdoor",'dew_point', i, 'float')
                        fields += lprmap(data,"outdoor",'humidity', i, 'int')
                        # indoor
                        if "indoor" in data and len(data["indoor"]) > 0:
                            fields += lprmap(data, "indoor", 'inside_temp', i, 'float', 'temperature')
                            fields += lprmap(data, "indoor", 'inside_humidity', i, 'int', 'humidity')
                        # solar_and_uvi
                        if "solar_and_uvi" in data and len(data["solar_and_uvi"]) > 0:
                            fields += lprmap(data,"solar_and_uvi",'solar', i, 'float')
                            fields += lprmap(data,"solar_and_uvi",'uvi', i, 'int')
                        # rainfall
                        if "rainfall" in data and len(data["rainfall"]) > 0:
                            fields += lprmap(data,"rainfall",'rain_1h', i, 'float', 'hourly')
                            fields += lprmap(data,"rainfall",'rain_24h', i, 'float', 'daily')
                        # wind
                        if "wind" in data and len(data["wind"]) > 0:
                            fields += lprmap(data,"wind",'wind_speed', i, 'float')
                            fields += lprmap(data,"wind",'wind_gust', i, 'float')
                            fields += lprmap(data,"wind",'wind_deg', i, 'int', 'wind_direction')
                        # pressure
                        if "pressure" in data and len(data["pressure"]) > 0:
                            fields += lprmap(data,"pressure",'absolute', i, 'float')
                        # co2_aqi_combo
                        if "co2_aqi_combo" in data and len(data["co2_aqi_combo"]) > 0:
                            fields += lprmap(data,"co2_aqi_combo",'co2', i, 'float')
                        # pm25_aqi_combo
                        if "pm25_aqi_combo" in data and len(data["pm25_aqi_combo"]) > 0:
                            fields += lprmap(data,"pm25_aqi_combo",'pm25', i, 'float')
                        # pm10_aqi_combo
                        if "pm10_aqi_combo" in data and len(data["pm10_aqi_combo"]) > 0:
                            fields += lprmap(data,"pm10_aqi_combo",'pm10', i, 'float')
                        # Save data point values
                        point = f"{IFIELD},source=timemachine {fields[1:]} {int(i)}"
                        weatherdata.append(point)
                        if args.debug:
                            print(f"Datapnt: {point}")
                    write_influx()
                    weatherdata.clear()
                else:
                    # No valid data - increment time to next interval and continue
                    if args.debug:
                        print(f"No Data Found for request: {url}")
                        print(f"Replied: {raw}")
                    curr += interval
                    interval = timedelta(days=getdays(curr))

                    continue
            else:
                sys.exit(f"\nERROR: Bad response from Ecowitt API for {url} - {response.reason}: {response.text}")
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
            traceback.print_exc()
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
    Gap detection is based on these rules:
    * if the time period is within the last 90 days, it looks for gaps of 5 minutes;
    * if the time period is between 90 days and 365 days, it looks for gaps of 30 minutes;
    * if the time period is between 365 days and 730 days, it looks for gaps of 240 minutes;
    * if the time period is between 730 days and 2019-01-01, it looks for gaps of 1,440 minutes;
    """
    print(f"Searching InfluxDB for data gaps")

    # Create query and set gap detection threshold
    query = f"SELECT temperature FROM autogen.{IFIELD} WHERE time >= '{start.isoformat()}' AND time <= '{end.isoformat()}'"
    if start > currtime - timedelta(days=-90):
        maxgapminutes = 5
    elif start > currtime - timedelta(days=-365) and start <= currtime - timedelta(days=-90):
        maxgapminutes = 30
    elif start > currtime - timedelta(days=-730) and start <= currtime - timedelta(days=-365):
        maxgapminutes = 240
    else:
        maxgapminutes = 1440

    maxgap = timedelta(minutes=maxgapminutes)

    try:
        # Execute query
        result = client.query(query)
    except Exception as err:
        sys.exit(f"ERROR: Failed to execute InfluxDB query: {query}; {err}")

    if args.debug:
        print(result)

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
if end > currtime:
    end = currtime
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

print("Done.")
