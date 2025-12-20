#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
 Command line tool to retrieve Powerwall or Solar history data by date/time period from
 Tesla Owner API (Tesla cloud) and import into InfluxDB of Powerwall-Dashboard.

 Author: Michael Birse (for Powerwall-Dashboard by Jason A. Cox)
 For more information see https://github.com/jasonacox/Powerwall-Dashboard

 Usage:
    * Install the required python modules (not required if run from docker):
        pip install python-dateutil pypowerwall influxdb

    * Or, if running as a docker container, replace below examples with:
        docker exec -it tesla-history python3 tesla-history.py [arguments]

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

    - Run as a daemon service (continually poll for history data):
        (docker container runs in daemon mode)
            python3 tesla-history.py --daemon

    - Example when running docker container to retrieve history for today and yesterday:
        docker exec -it tesla-history python3 tesla-history.py --today --yesterday

    - Something went wrong? Use --remove option to remove data imported with this tool:
        (data logged by Powerwall-Dashboard will not be affected)
            python3 tesla-history.py --start "YYYY-MM-DD hh:mm:ss" --end "YYYY-MM-DD hh:mm:ss" --remove

    - For more usage options, run without arguments or --help:
        python3 tesla-history.py --help
"""
import sys
import os
import signal
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
    from pypowerwall.cloud.teslapy import Tesla, Retry, JsonDict, Battery, SolarPanel
except:
    sys.exit("ERROR: Missing python pypowerwall module. Run 'pip install pypowerwall'.")
try:
    from influxdb import InfluxDBClient
except:
    sys.exit("ERROR: Missing python influxdb module. Run 'pip install influxdb'.")

BUILD = "0.1.5"
VERBOSE = True
SCRIPTPATH = os.path.dirname(os.path.realpath(sys.argv[0]))
SCRIPTNAME = os.path.basename(sys.argv[0]).split('.')[0]
CONFIGNAME = CONFIGFILE = f"{SCRIPTNAME}.conf"
AUTHFILE = f"{SCRIPTNAME}.auth"

# Parse command line arguments
parser = argparse.ArgumentParser(description='Import Powerwall or Solar history data from Tesla Owner API (Tesla cloud) into InfluxDB')
parser.add_argument('-l', '--login', action="store_true", help='login to Tesla account only and save auth token (do not get history)')
parser.add_argument('-t', '--test', action="store_true", help='enable test mode (do not import into InfluxDB)')
parser.add_argument('-d', '--debug', action="store_true", help='enable debug output (print raw responses from Tesla cloud)')
group = parser.add_argument_group('advanced options')
group.add_argument('--config', help=f'specify an alternate config file (default: {CONFIGNAME})')
group.add_argument('--site', type=int, help='site id (required for Tesla accounts with multiple energy sites)')
group.add_argument('--reserve', type=int, help='also search for backup reserve percent data gaps and set to value')
group.add_argument('--force', action="store_true", help='force import for date/time range (skip search for data gaps)')
group.add_argument('--remove', action="store_true", help='remove imported data from InfluxDB for date/time range')
group.add_argument('--daemon', action="store_true", help='run as a daemon service (continually poll for history data)')
group.add_argument('--setup', action="store_true", help=argparse.SUPPRESS)
group.add_argument('--timezone', help=argparse.SUPPRESS)
group.add_argument('--version', action="store_true", help=argparse.SUPPRESS)
group = parser.add_argument_group('date/time range options')
group.add_argument('--start', help='start date and time ("YYYY-MM-DD hh:mm:ss")')
group.add_argument('--end', help='end date and time ("YYYY-MM-DD hh:mm:ss")')
group.add_argument('--today', action="store_true", help='set start/end range to "today"')
group.add_argument('--yesterday', action="store_true", help='set start/end range to "yesterday"')
args = parser.parse_args()

if args.version:
    print(f"{BUILD}")
    sys.exit()

def sys_exit(error=None, halt=True):
    """
    Wrapper for sys.exit() for daemon mode support
        * when running interactively, exit as normal with sys.exit()
        * when running as a daemon, either go to sleep or return

    Args:
        error   = output error message to stderr
        halt    = if true and running as a daemon, go to sleep forever, otherwise return if false
    """
    if args.daemon:
        sys.stdout.flush()
        if error is not None:
            sys.stderr.write(error)
        if halt:
            sys.stderr.write("... Fix and restart.\n")
            sys.stderr.flush()
            while True:
                try:
                    time.sleep(3600)
                except (KeyboardInterrupt, SystemExit):
                    server_exit()
        else:
            sys.stderr.write("\n")
            sys.stderr.flush()
            return
    else:
        if error is not None:
            sys.stderr.write(f"{error}\n")
        sys.exit()

def server_exit():
    """
    Print server shutdown notice and exit
    """
    sys.stdout.flush()
    sys.stderr.write(f" ! {SCRIPTNAME} Server Exit\n")
    sys.stderr.write("* Stopping\n")
    sys.stderr.flush()
    args.daemon = False
    sys.exit()

def sig_exit(signum, frame):
    """
    Raise SystemExit when signal caught
    """
    raise SystemExit

# Register signal handler to exit gracefully on SIGTERM
signal.signal(signal.SIGTERM, sig_exit)

# Check for invalid argument combinations
if args.daemon:
    sys.stdout.flush()
    sys.stderr.write(f"{SCRIPTNAME} Server [{BUILD}]\n")
    if len(sys.argv) != 2:
        sys_exit("ERROR: argument --daemon cannot accept other arguments")
else:
    if len(sys.argv) == 1:
        parser.print_help(sys.stderr)
        sys_exit()
    if (args.start or args.end) and (args.today or args.yesterday):
        parser.error("arguments --start and --end cannot be used with --today or --yesterday")
    if (args.start and not args.end) or (args.end and not args.start):
        parser.error("both arguments --start and --end are required")
    if not (args.login or args.setup) and not ((args.start and args.end) or (args.today or args.yesterday)):
        parser.error("missing arguments: --start/end or --today/yesterday")
    if args.reserve is not None and (args.reserve < 0 or args.reserve > 100):
        parser.error(f"argument --reserve: invalid value: '{args.reserve}'")

if args.config:
    # Use alternate config file if specified
    CONFIGNAME = CONFIGFILE = args.config

# Get config file from environment variable if defined
CONFIGNAME = CONFIGFILE = os.getenv('TESLA_CONF', CONFIGNAME)

# Load Configuration File
config = configparser.ConfigParser(allow_no_value=True)
if not os.path.exists(CONFIGFILE) and "/" not in CONFIGFILE:
    # Look for config file in script location if not found
    CONFIGFILE = f"{SCRIPTPATH}/{CONFIGFILE}"
if args.setup and os.path.exists(CONFIGFILE):
    # Prompt user to overwrite config when running setup
    print(f"\nExisting config found '{CONFIGNAME}'\n")
    while True:
        response = input("Overwrite existing settings? [y/N] ").strip().lower()
        if response == "y":
            try:
                os.remove(CONFIGFILE)
                break
            except Exception as err:
                sys_exit(f"\nERROR: Failed to remove config '{CONFIGNAME}' - {repr(err)}")
        elif response in ("n", ""):
            break
if os.path.exists(CONFIGFILE):
    try:
        config.read(CONFIGFILE)

        # Get Tesla Settings
        TUSER = config.get('Tesla', 'USER')
        TAUTH = os.getenv('TESLA_AUTH', config.get('Tesla', 'AUTH'))
        TDELAY = config.getint('Tesla', 'DELAY', fallback=1)

        if "/" not in TAUTH:
            TAUTH = f"{SCRIPTPATH}/{TAUTH}"

        # Get InfluxDB Settings
        IHOST = os.getenv('INFLUX_HOST', config.get('InfluxDB', 'HOST'))
        IPORT = int(os.getenv('INFLUX_PORT', config.getint('InfluxDB', 'PORT')))
        IUSER = config.get('InfluxDB', 'USER', fallback='')
        IPASS = config.get('InfluxDB', 'PASS', fallback='')
        IDB = config.get('InfluxDB', 'DB')
        ITZ = config.get('InfluxDB', 'TZ')

        # Get settings when running as a daemon
        if args.daemon:
            WAIT = config.getint('daemon', 'WAIT', fallback=5)
            HIST = config.getint('daemon', 'HIST', fallback=60)
            RETRY = config.getint('daemon', 'RETRY', fallback=30)
            SITE = config.getint('daemon', 'SITE', fallback=None)
            LOG = config.get('daemon', 'LOG', fallback='no')
            DEBUG = config.get('daemon', 'DEBUG', fallback='no')
            TEST = config.get('daemon', 'TEST', fallback='no')
            RESERVE = config.getint('daemon', 'RESERVE', fallback=None)

            if WAIT < 5:
                WAIT = 5
            if HIST <= WAIT:
                HIST = WAIT + 5
            if RETRY < 1:
                RETRY = 1
            if SITE is not None:
                args.site = SITE
            if LOG.lower() != "yes":
                VERBOSE = False
            if DEBUG.lower() == "yes":
                VERBOSE = True
                args.debug = True
            if TEST.lower() == "yes":
                args.test = True
            if RESERVE is not None and RESERVE >= 0 and RESERVE <= 100:
                args.reserve = RESERVE
    except Exception as err:
        sys_exit(f"ERROR: Config file '{CONFIGNAME}' - {repr(err)}")
else:
    if args.setup:
        # Create config with default values without prompting when running setup
        print(f"\nCreating config file '{CONFIGNAME}'")
    else:
        # Config not found - prompt user for configuration and save settings
        print(f"\nConfig file '{CONFIGNAME}' not found\n")

    if args.daemon:
        sys_exit("ERROR: No config file")

    if not args.setup:
        while True:
            response = input("Do you want to create the config now? [Y/n] ").strip().lower()
            if response == "n":
                sys_exit()
            elif response in ("y", ""):
                break

    print("\nTesla Account Setup")
    print("-" * 19)

    while True:
        response = input("Email address: ").strip()
        if "@" not in response:
            print("Invalid email address\n")
        else:
            TUSER = response
            break

    if not args.setup:
        # Prompt user for all other configuration settings when running interactively
        response = input(f"Save auth token to: [{AUTHFILE}] ").strip()
        if response == "":
            TAUTH = AUTHFILE
        else:
            TAUTH = response

        print("\nInfluxDB Setup")
        print("-" * 14)

        response = input("Host: [localhost] ").strip().lower()
        if response == "":
            IHOST = "localhost"
        else:
            IHOST = response

        while True:
            response = input("Port: [8086] ").strip()
            if response == "":
                IPORT = 8086
            else:
                try:
                    IPORT = int(response)
                except:
                    print("\nERROR: Invalid number\n")
                    continue
            break

        response = input("User (leave blank if not used): [blank] ").strip()
        IUSER = response

        response = input("Pass (leave blank if not used): [blank] ").strip()
        IPASS = response

        response = input("Database: [powerwall] ").strip()
        if response == "":
            IDB = "powerwall"
        else:
            IDB = response

    if args.setup and args.timezone not in (None, "") and tz.gettz(args.timezone) is not None:
        # Get timezone if passed when running setup
        ITZ = args.timezone
    else:
        while True:
            response = input("Timezone (e.g. America/Los_Angeles): ").strip()
            if response != "":
                ITZ = response
                if tz.gettz(ITZ) is None:
                    print("Invalid timezone\n")
                    continue
                break

    if args.setup:
        # Set config defaults when running setup
        TAUTH = AUTHFILE
        IHOST = "localhost"
        IPORT = 8086
        IUSER = ""
        IPASS = ""
        IDB = "powerwall"

    # Set other config defaults
    TDELAY = 1
    WAIT = 5
    HIST = 60
    RETRY = 30

    # Save config values to file
    config.optionxform = str
    config['Tesla'] = {}
    config['Tesla']['# Tesla Account e-mail address and Auth token file'] = None
    config['Tesla']['USER'] = TUSER
    config['Tesla']['AUTH'] = TAUTH
    config['Tesla']['# Delay between API requests (seconds)'] = None
    config['Tesla']['DELAY'] = str(TDELAY)
    config['InfluxDB'] = {}
    config['InfluxDB']['# InfluxDB server settings'] = None
    config['InfluxDB']['HOST'] = IHOST
    config['InfluxDB']['PORT'] = str(IPORT)
    config['InfluxDB']['# Auth (leave blank if not used)'] = None
    config['InfluxDB']['USER'] = IUSER
    config['InfluxDB']['PASS'] = IPASS
    config['InfluxDB']['# Database name and timezone'] = None
    config['InfluxDB']['DB'] = IDB
    config['InfluxDB']['TZ'] = ITZ
    config['daemon'] = {}
    config['daemon']['; Config options when running as a daemon (i.e. docker container)'] = None
    config['daemon']['# Minutes to wait between poll requests'] = None
    config['daemon']['WAIT'] = str(WAIT)
    config['daemon']['# Minutes of history to retrieve for each poll request'] = None
    config['daemon']['HIST'] = str(HIST)
    config['daemon']['# Seconds to wait before retry on errors'] = None
    config['daemon']['RETRY'] = str(RETRY)
    config['daemon']['# Enable log output for each poll request'] = None
    config['daemon']['LOG'] = "no"
    config['daemon']['# Enable debug output (print raw responses from Tesla cloud)'] = None
    config['daemon']['DEBUG'] = "no"
    config['daemon']['# Enable test mode (disable writing to InfluxDB)'] = None
    config['daemon']['TEST'] = "no"
    config['daemon']['# If multiple Tesla Energy sites exist, uncomment below and enter Site ID'] = None
    config['daemon']['# SITE = 123456789'] = None

    try:
        # Write config file
        with open(CONFIGFILE, 'w') as configfile:
            config.write(configfile)
    except Exception as err:
        sys_exit(f"\nERROR: Failed to save config to '{CONFIGNAME}' - {repr(err)}")

    print(f"\nConfig saved to '{CONFIGNAME}'\n")

    if args.setup:
        # Set auth file from environment variable if defined
        TAUTH = os.getenv('TESLA_AUTH', TAUTH)

# Global Variables
powerdata = []
backupdata = []
eventdata = []
reservedata = []
powergaps = None
gridgaps = None
reservegaps = None
sitetz = None
tzname = None
tzoffset = False
power = None
soe = None
dayloaded = None
eventsloaded = False
reserveloaded = False
fetcherr = False
queryerr = False
writeerr = False
influxtz = tz.gettz(ITZ)
utctz = tz.tzutc()

# Check InfluxDB timezone is valid
if influxtz is None:
    sys_exit(f"ERROR: Invalid timezone - {ITZ}")

if args.daemon:
    sys.stdout.flush()
    sys.stderr.write(f"* Configuration Loaded [{os.path.realpath(CONFIGFILE)}]\n")
    sys.stderr.write(f" + Server - Wait: {WAIT}m, Hist: {HIST}m, Retry: {RETRY}s, Log: {LOG}, Debug: {DEBUG}, Test: {TEST}\n")
    sys.stderr.write(f" + Tesla - User: {TUSER}, Auth: [{os.path.realpath(TAUTH)}]")
    if TDELAY != 1:
        sys.stderr.write(f", Delay: {TDELAY}s")
    if RESERVE is not None:
        sys.stderr.write(f", Reserve: {RESERVE}")
    if SITE is not None:
        sys.stderr.write(f", Site: {SITE}")
    sys.stderr.write(f"\n + InfluxDB - Host: {IHOST}, Port: {IPORT}, DB: {IDB}, Timezone: {ITZ}")
    if IUSER != "":
        sys.stderr.write(f", User: {IUSER}, Pass: {IPASS}")
    sys.stderr.write("\n")
    sys.stderr.flush()

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
        sys_exit(f'ERROR: {name.title()} date/time "{dt.strftime("%Y-%m-%d %H:%M:%S")}" does not exist for timezone {dt.tzname()} (DST change?)')

    if naive and tz.datetime_ambiguous(dt):
        sys_exit(f'ERROR: Ambiguous {name} date/time "{dt.strftime("%Y-%m-%d %H:%M:%S")}" for timezone {dt.tzname()} (DST change?)\n\n'
                f'Re-run with desired timezone offset:\n'
                f'   --{name} "{dt.replace(fold=0)}"\n'
                f'or\n'
                f'   --{name} "{dt.replace(fold=1)}"'
        )
    return dt

def get_start_end():
    """
    Returns start and end datetimes based on possible argument combinations
    """
    if args.start and args.end:
        try:
            # Get start and end date/time
            s = isoparse(args.start)
            e = isoparse(args.end)
        except Exception as err:
            sys_exit(f"ERROR: Invalid date - {repr(err)}")
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

    # Check start/end datetimes are valid for the configured timezone and convert to aware datetime
    start = check_datetime(s, 'start', influxtz).astimezone(utctz)
    end = check_datetime(e, 'end', influxtz).astimezone(utctz)

    if start >= end:
        sys_exit("ERROR: End date/time must be after start date/time")

    return start, end

def lookup(data, keylist):
    """
    Search data for list of keys and return the first matching key's value if found, otherwise return None
    """
    for key in keylist:
        if key in data:
            return data[key]
    return None

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
    retry = Retry(total=2, status_forcelist=(500, 502, 503, 504), backoff_factor=10)

    # Create Tesla instance
    tesla = Tesla(email, cache_file=TAUTH)

    if not tesla.authorized:
        if args.daemon:
            sys_exit("ERROR: Tesla auth token invalid or missing. Run interactively with --login option to create")

        # Login to Tesla account and cache token
        state = tesla.new_state()
        code_verifier = tesla.new_code_verifier()

        try:
            print("Open the below address in your browser to login.\n")
            print(tesla.authorization_url(state=state, code_verifier=code_verifier))
        except Exception as err:
            sys_exit(f"ERROR: Connection failure - {repr(err)}")

        print("\nAfter login, paste the URL of the 'Page Not Found' webpage below.\n")

        tesla.close()
        tesla = Tesla(email, retry=retry, state=state, code_verifier=code_verifier, cache_file=TAUTH)

        if not tesla.authorized:
            try:
                tesla.fetch_token(authorization_response=input("Enter URL after login: "))
                print("-" * 40)
            except Exception as err:
                sys_exit(f"ERROR: Login failure - {repr(err)}")
    else:
        # Enable retries
        tesla.close()
        tesla = Tesla(email, retry=retry, cache_file=TAUTH)

    sitelist = {}
    try:
        # Get list of Tesla Energy sites
        for site in tesla.battery_list() + tesla.solar_list():
            if args.debug:
                print(site)

            # Retrieve site id and name
            siteid = lookup(site, ['energy_site_id'])
            sitename = lookup(site, ['site_name'])
            sitetimezone = None
            siteinstdate = None

            if siteid is None:
                print("ERROR: Failed to retrieve Site ID")
                continue
            try:
                # Retrieve site name, site timezone and install date
                if args.debug:
                    print(f"Get SITE_CONFIG for Site ID {siteid}")
                data = site.api('SITE_CONFIG')
                if args.debug:
                    print(data)
                if isinstance(data, JsonDict) and 'response' in data:
                    d = data['response']
                    if sitename is None:
                        sitename = lookup(d, ['site_name'])
                    sitetimezone = get_timezone(d)[1]
                    try:
                        siteinstdate = isoparse(lookup(d, ['installation_date']))
                    except:
                        siteinstdate = datetime.fromtimestamp(0)
            except Exception as err:
                print(f"WARNING: Failed to retrieve SITE_CONFIG - {err}")

            # Determine type of Tesla Energy site
            if isinstance(site, Battery):
                try:
                    sitetype = f"Powerwall x{data['response']['battery_count']}"
                except:
                    sitetype = "Powerwall"
            elif isinstance(site, SolarPanel):
                sitetype = "Solar"

            try:
                # Retrieve site current time
                if args.debug:
                    print(f"Get SITE_DATA for Site ID {siteid}")
                data = site.api('SITE_DATA')
                if args.debug:
                    print(data)
                sitetime = isoparse(data['response']['timestamp'])
            except:
                sitetime = "No 'live status' returned"

            # Add site if site id not already in the list
            if siteid not in sitelist:
                sitelist[siteid] = {}
                sitelist[siteid]['site'] = site
                sitelist[siteid]['type'] = sitetype
                sitelist[siteid]['name'] = sitename
                sitelist[siteid]['timezone'] = sitetimezone
                sitelist[siteid]['instdate'] = siteinstdate
                sitelist[siteid]['time'] = sitetime
    except Exception as err:
        sys_exit(f"ERROR: Failed to retrieve PRODUCT_LIST - {repr(err)}")

    # Print list of sites
    for siteid in sitelist:
        if (args.site is None) or (args.site not in sitelist) or (siteid == args.site):
            print(f"      Site ID: {siteid}")
            print(f"    Site type: {sitelist[siteid]['type']}")
            print(f"    Site name: {sitelist[siteid]['name']}")
            print(f"     Timezone: {sitelist[siteid]['timezone']}")
            print(f"    Installed: {sitelist[siteid]['instdate']}")
            print(f"  System time: {sitelist[siteid]['time']}")
            print("-" * 40)

    return sitelist

def get_timezone(data):
    """
    Get timezone from response data based on a timezone name or offset

    Returns timezone object, name, and offset flag
    """
    tzdata = lookup(data, ['installation_time_zone', 'time_zone_offset'])

    if type(tzdata) is int:
        # Get timezone from timezone offset
        tzinfo = tz.tzoffset(None, tzdata * 60)
        offset = datetime.now(tz=tzinfo).strftime('%z')
        tzdata = f"UTC{offset[:3]}:{offset[3:]}"
        tzoffset = True
    else:
        # Get timezone from timezone name
        if tzdata is not None:
            tzinfo = tz.gettz(tzdata)
        else:
            tzinfo = None
        tzoffset = False

    return tzinfo, tzdata, tzoffset

def get_power_history(start, end):
    """
    Retrieve power history data between start and end date/time

    Adds data points to 'powerdata' in InfluxDB Line Protocol format with tag source='cloud'
    """
    global fetcherr, sitetz, tzname, tzoffset, dayloaded, power, soe

    if sitetz is None:
        try:
            if args.debug:
                print("Get timezone from CALENDAR_HISTORY_DATA")

            # Retrieve current history data to determine site timezone
            data = site.get_calendar_history_data(kind='power', end_date=sitetime.replace(second=59).isoformat())

            # Attempt to get history data for alternative dates if no data was returned for current time
            if not data:
                data = site.get_calendar_history_data(kind='power', end_date=(sitetime - timedelta(days=1)).replace(second=59).isoformat())
            if not data:
                data = site.get_calendar_history_data(kind='power', end_date=(sitetime - timedelta(days=2)).replace(second=59).isoformat())
            if not data:
                data = site.get_calendar_history_data(kind='power', end_date=end.replace(second=59).isoformat())
            if not data:
                data = site.get_calendar_history_data(kind='power', end_date=start.replace(second=59).isoformat())
            if not data:
                if args.debug:
                    print(f"No history returned, setting timezone to {ITZ}")
                sitetz = influxtz
                tzname = ITZ
            else:
                if args.debug:
                    print(data)

                # Get timezone name or offset from history data
                sitetz, tzname, tzoffset = get_timezone(data)

                if sitetz is None:
                    sys_exit(f"ERROR: Invalid timezone for history data - {tzname}")

        except Exception as err:
            sys_exit(f"ERROR: Failed to retrieve timezone from history data - {repr(err)}")

    if VERBOSE:
        print(f"Retrieving data for gap: [{start.astimezone(influxtz)}] - [{end.astimezone(influxtz)}] ({str(end - start)}s)")

    # Set time to end of day for daily calendar history data retrieval
    day = start.astimezone(sitetz).replace(hour=23, minute=59, second=59, tzinfo=None)
    endday = end.astimezone(sitetz).replace(hour=23, minute=59, second=59, tzinfo=None)

    # Loop through each day to retrieve daily 'power' and 'soe' history data
    nextstart = start
    while day <= endday:
        # Get this day's history if not already loaded
        if day != dayloaded:
            if VERBOSE:
                print(f"* Loading daily history: [{day.strftime('%Y-%m-%d')}] ({tzname})")
            time.sleep(TDELAY)
            try:
                # Retrieve current day 'power' history ('power' data returned in 5 minute intervals)
                power = site.get_calendar_history_data(kind='power', end_date=day.replace(tzinfo=sitetz).isoformat())
                if args.debug:
                    print(power)
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
                # Check history data for timezone changes
                if power:
                    # Get timezone name or offset from history data
                    histtz, tzdata, tzoffset = get_timezone(power)

                    if histtz is None:
                        sys_exit(f"ERROR: Invalid timezone for history data - {tzdata}")

                    if sitetz != histtz:
                        # Update site timezone if mismatch found and re-run from next start day
                        sitetz = histtz
                        tzname = tzdata
                        day = nextstart.astimezone(sitetz).replace(hour=23, minute=59, second=59, tzinfo=None)
                        endday = end.astimezone(sitetz).replace(hour=23, minute=59, second=59, tzinfo=None)
                        continue

                if isinstance(site, Battery):
                    # Retrieve current day 'soe' history ('soe' data returned in 15 minute intervals)
                    soe = site.get_calendar_history_data(kind='soe', end_date=day.replace(tzinfo=sitetz).isoformat())
                    if args.debug:
                        print(soe)
                    """ Example 'time_series' response:
                    {
                        "timestamp": "2022-04-18T12:00:00+10:00",
                        "soe": 67
                    }
                    """
                if args.daemon and fetcherr:
                    fetcherr = False
                    sys.stdout.flush()
                    sys.stderr.write(" + Retrieve history data succeeded\n")
                    sys.stderr.flush()
            except Exception as err:
                sys_exit(f"ERROR: Failed to retrieve history data - {repr(err)}", halt=False)
                if args.daemon:
                    fetcherr = True
                    sys.stderr.write(f" ! Retrieve history data failed, retrying in {RETRY} seconds\n")
                    sys.stderr.flush()
                return

            dayloaded = day

        if power:
            # Check if solar only site returns grid power values
            if isinstance(site, SolarPanel):
                gridpower = False
                for d in power['time_series']:
                    if d['grid_power'] != 0:
                        gridpower = True
                        break

            for d in power['time_series']:
                timestamp = isoparse(d['timestamp']).astimezone(utctz)
                nextstart = timestamp + timedelta(minutes=5)

                # Check if solar only site timezone is using an offset and replace with InfluxDB timezone
                if isinstance(site, SolarPanel) and tzoffset:
                    timestamp = isoparse(d['timestamp']).replace(tzinfo=influxtz).astimezone(utctz)

                # Save data point when within start/end range only
                if timestamp >= start and timestamp <= end:
                    # Calculate power usage values
                    home = d['solar_power'] + d['battery_power'] + d['grid_power']
                    solar = d['solar_power']
                    from_pw = d['battery_power'] if d['battery_power'] > 0 else 0
                    to_pw = -d['battery_power'] if d['battery_power'] < 0 else 0
                    from_grid = d['grid_power'] if d['grid_power'] > 0 else 0
                    to_grid = -d['grid_power'] if d['grid_power'] < 0 else 0

                    if isinstance(site, SolarPanel) and not gridpower:
                        # Set home to zero when grid power not available for solar only sites
                        home = 0

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
    global fetcherr, eventsloaded

    if not eventsloaded:
        startdate = start
        enddate = datetime.now(tz=influxtz).replace(hour=23, minute=59, second=59, microsecond=0)
        printed = False

        while enddate > startdate:
            if VERBOSE and not printed:
                print("Retrieving backup event history")
                printed = True

            time.sleep(TDELAY)
            try:
                # Retrieve full backup event history
                backup = site.get_calendar_history_data(kind='backup', period='lifetime', end_date=enddate.isoformat())
                if args.debug:
                    print(backup)
                """ Example 'events' response (event duration in ms):
                {
                    "timestamp": "2022-04-19T20:55:53+10:00",
                    "duration": 3862580
                }
                """
                if args.daemon and fetcherr:
                    fetcherr = False
                    sys.stdout.flush()
                    sys.stderr.write(" + Retrieve history data succeeded\n")
                    sys.stderr.flush()
            except Exception as err:
                sys_exit(f"ERROR: Failed to retrieve history data - {repr(err)}", halt=False)
                if args.daemon:
                    fetcherr = True
                    sys.stderr.write(f" ! Retrieve history data failed, retrying in {RETRY} seconds\n")
                    sys.stderr.flush()
                return

            if backup:
                backupdata.append(backup)
                enddate = isoparse(backup['next_end_date']) if 'next_end_date' in backup else startdate
            else:
                break

        eventsloaded = True

    if VERBOSE:
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

    for backup in backupdata:
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
                        if VERBOSE:
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

def set_reserve_history(start, end):
    """
    Create backup reserve percent history between start and end date/time

    Adds data points to 'reservedata' in InfluxDB Line Protocol format with tag source='cloud'
    """
    global reserveloaded

    if not reserveloaded:
        if VERBOSE:
            print(f"Setting missing backup reserve percent history to '{args.reserve}'")
        reserveloaded = True

    if VERBOSE:
        print(f"* Creating reserve pct data: [{start.astimezone(influxtz)}] - [{end.astimezone(influxtz)}] ({str(end - start)}s)")

    # Create baseline backup_reserve_percent=RESERVE points aligned to minute intervals for full start/end range
    reservepct = []
    timestamp = start.replace(second=0)
    while timestamp <= end:
        respoint = {}
        respoint['time'] = timestamp
        respoint['backup_reserve_percent'] = float(args.reserve)
        reservepct.append(respoint)
        timestamp += timedelta(minutes=1)

    # Create backup reserve percent data for import to InfluxDB
    for respoint in reservepct:
        timestamp = respoint['time']
        backup_reserve_percent = respoint['backup_reserve_percent']

        # Save data point values
        point = f"http,source=cloud,month={timestamp.astimezone(influxtz).strftime('%b')},year={timestamp.astimezone(influxtz).year} backup_reserve_percent={backup_reserve_percent} "
        point += str(int(timestamp.timestamp()))
        reservedata.append(point)

# InfluxDB Functions
def search_influx(start, end, datatype):
    """
    Search InfluxDB for missing data points between start and end date/time

    Returns a list of start/end datetime ranges for the 'datatype' ('power' or 'grid' or 'reserve')
    """
    global queryerr

    if VERBOSE:
        print(f"Searching InfluxDB for data gaps ({datatype})")

    # Create query for the data type specified and set gap detection threshold
    if 'power' in datatype:
        query = f"SELECT home FROM autogen.http WHERE time >= '{start.isoformat()}' AND time <= '{end.isoformat()}'"
        mingap = timedelta(minutes=5)
    elif 'grid' in datatype:
        query = f"SELECT grid_status FROM grid.http WHERE time >= '{start.isoformat()}' AND time <= '{end.isoformat()}'"
        mingap = timedelta(minutes=1)
    elif 'reserve' in datatype:
        query = f"SELECT backup_reserve_percent FROM pod.http WHERE time >= '{start.isoformat()}' AND time <= '{end.isoformat()}'"
        mingap = timedelta(minutes=1)

    try:
        # Execute query
        result = client.query(query)

        if args.daemon and queryerr:
            queryerr = False
            sys.stdout.flush()
            sys.stderr.write(" + InfluxDB query succeeded\n")
            sys.stderr.flush()
    except Exception as err:
        sys_exit(f"ERROR: Failed to execute InfluxDB query: {query}; {repr(err)}", halt=False)
        if args.daemon:
            queryerr = True
            sys.stderr.write(f" ! InfluxDB query failed, retrying in {RETRY} seconds\n")
            sys.stderr.flush()
        return None

    datagap = []
    startpoint = start
    startfound = False

    if result:
        # Measure time difference between each data point
        for point in result.get_points():
            timestamp = isoparse(point['time']).astimezone(utctz)

            if timestamp == start:
                startfound = True

            # Check if time since previous point exceeds minimum gap
            duration = timestamp - startpoint
            if duration > mingap:
                endpoint = timestamp
                if VERBOSE:
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
            if duration > mingap:
                endpoint = end
                if VERBOSE:
                    print(f"* Found data gap: [{startpoint.astimezone(influxtz)}] - [{endpoint.astimezone(influxtz)}] ({str(duration)}s)")

                # Add missing data period to list
                period = {}
                period['start'] = startpoint + timedelta(minutes=1)
                period['end'] = endpoint
                datagap.append(period)
    else:
        # No points found - entire start/end range is a data gap
        duration = end - start
        if duration > mingap:
            if VERBOSE:
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
    global queryerr

    if not args.daemon:
        print("Removing imported data from InfluxDB")

    # Query definitions (sanity check data points before and after delete)
    power = f"SELECT * FROM autogen.http WHERE source='cloud' AND time >= '{start.isoformat()}' AND time <= '{end.isoformat()}'"
    grid = f"SELECT * FROM grid.http WHERE source='cloud' AND time >= '{start.isoformat()}' AND time <= '{end.isoformat()}'"
    reserve = f"SELECT * FROM pod.http WHERE source='cloud' AND time >= '{start.isoformat()}' AND time <= '{end.isoformat()}'"
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
                if args.debug:
                    print(f"Remove data point: {point}")
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

        # Execute query for backup reserve percent data
        query = reserve
        result = client.query(query)

        # Get number of data points returned
        ptsreserve = len(list(result.get_points()))

        # Total number of data points to be removed
        ptstotal = ptspower + ptsgrid + ptsreserve

        if ptstotal == 0:
            if not args.daemon:
                print("* No data points found")
            return

        for point in result.get_points():
            if args.debug:
                print(f"Remove data point: {point}")

        if args.test:
            if not args.daemon:
                print(f"* {ptstotal} data points to be removed (*** skipped - test mode enabled ***)")
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

        # Execute query after delete for backup reserve percent data
        query = reserve
        result = client.query(query)

        # Get number of data points returned
        ptsreservenow = len(list(result.get_points()))

        # Total number of data points after delete (should be zero)
        ptstotalnow = ptspowernow + ptsgridnow + ptsreservenow
        if not args.daemon:
            print(f"* {ptstotal - ptstotalnow} of {ptstotal} data points removed")

        if periods and not args.daemon:
            # Update InfluxDB analysis data after delete
            update_influx(periods=periods)

        if args.daemon and queryerr:
            queryerr = False
            sys.stdout.flush()
            sys.stderr.write(" + InfluxDB query succeeded\n")
            sys.stderr.flush()
    except Exception as err:
        sys_exit(f"ERROR: Failed to execute InfluxDB query: {query}; {repr(err)}", halt=False)
        if args.daemon:
            queryerr = True
            sys.stderr.write(f" ! InfluxDB query failed, retrying in {RETRY} seconds\n")
            sys.stderr.flush()

def write_influx():
    """
    Write 'powerdata', 'eventdata' and 'reservedata' Line Protocol format data points to InfluxDB
    """
    global writeerr

    if args.test:
        if VERBOSE:
            print("Writing to InfluxDB (*** skipped - test mode enabled ***)")
        return

    if VERBOSE:
        print("Writing to InfluxDB")
    try:
        client.write_points(powerdata, time_precision='s', batch_size=10000, protocol='line')
        client.write_points(eventdata, time_precision='s', batch_size=10000, retention_policy='grid', protocol='line')
        client.write_points(reservedata, time_precision='s', batch_size=10000, retention_policy='pod', protocol='line')

        if args.daemon and writeerr:
            writeerr = False
            sys.stdout.flush()
            sys.stderr.write(" + InfluxDB write succeeded\n")
            sys.stderr.flush()
    except Exception as err:
        sys_exit(f"ERROR: Failed to write to InfluxDB: {repr(err)}", halt=False)
        if args.daemon:
            writeerr = True
            sys.stderr.write(f" ! InfluxDB write failed, retrying in {RETRY} seconds\n")
            sys.stderr.flush()

def update_influx(start=None, end=None, periods=None):
    """
    Update analysis data retention policies (kwh, daily, monthly) from newly imported data
        * Queries will be limited to ranges which include new data points only

    Args:
        start/end   = Single start and end date/time range to run queries for
            or
        periods     = List of start and end date/time ranges to run queries for
    """
    global queryerr

    if args.test:
        if VERBOSE:
            print("Updating InfluxDB (*** skipped - test mode enabled ***)")
        return

    if VERBOSE:
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

        if args.daemon and queryerr:
            queryerr = False
            sys.stdout.flush()
            sys.stderr.write(" + InfluxDB query succeeded\n")
            sys.stderr.flush()
    except Exception as err:
        sys_exit(f"ERROR: Failed to execute InfluxDB query: {query}; {repr(err)}", halt=False)
        if args.daemon:
            queryerr = True
            sys.stderr.write(f" ! InfluxDB query failed, retrying in {RETRY} seconds\n")
            sys.stderr.flush()

# MAIN

# Create InfluxDB client instance
client = InfluxDBClient(host=IHOST, port=IPORT, username=IUSER, password=IPASS, database=IDB)

if args.remove and not (args.login or args.setup):
    # Get start/end datetimes from command line arguments
    start, end = get_start_end()
    print(f"Removing imported data for period: [{start.astimezone(influxtz)}] - [{end.astimezone(influxtz)}] ({str(end - start)}s)\n")

    # Remove imported data from InfluxDB between start and end date/time
    remove_influx(start, end)
    print("\nDone.")
    sys_exit()

# Login and get list of Tesla Energy sites
sitelist = tesla_login(TUSER)

# Check for energy sites
if len(sitelist) == 0:
    sys_exit("ERROR: No Tesla Energy sites found")
if len(sitelist) > 1 and args.site is None:
    if args.setup:
        # Prompt user to enter site if multiple sites found when running setup
        print("Multiple Tesla Energy sites found...")
        while True:
            response = input("Enter Site ID: ").strip()
            if response != "":
                try:
                    SITE = int(response)
                except:
                    print("Invalid Site ID\n")
                    continue
                if SITE not in sitelist:
                    print(f"Site ID '{SITE}' not found\n")
                    continue
                break
        print("-" * 40)
        config['daemon'].pop('# SITE = 123456789')
        config['daemon']['SITE'] = str(SITE)
        try:
            # Write config file
            with open(CONFIGFILE, 'w') as configfile:
                config.write(configfile)
        except Exception as err:
            sys_exit(f"\nERROR: Failed to save config to '{CONFIGNAME}' - {repr(err)}")
        sys_exit()

    if args.daemon:
        sys_exit('ERROR: Multiple Tesla Energy sites found - edit config to select "Site ID"')
    else:
        sys_exit('ERROR: Multiple Tesla Energy sites found - select site with option --site "Site ID"')

# Get site from sitelist
if args.site is None:
    siteinfo = sitelist[list(sitelist.keys())[0]]
else:
    if args.site in sitelist:
        siteinfo = sitelist[args.site]
    else:
        sys_exit(f'ERROR: Site ID "{args.site}" not found')

# Exit if login or setup option given
if args.login or args.setup:
    sys_exit()

if args.daemon:
    # Set initial start/end datetimes when running as a daemon
    end = datetime.now(tz=influxtz).astimezone(utctz).replace(microsecond=0) - timedelta(minutes=WAIT + 2)
    start = end - timedelta(minutes=HIST)
else:
    # Get start/end datetimes from command line arguments
    start, end = get_start_end()
    print(f"Running for period: [{start.astimezone(influxtz)}] - [{end.astimezone(influxtz)}] ({str(end - start)}s)\n")

# Get site current time
if type(siteinfo['time']) is str:
    sitetime = datetime.now(tz=influxtz).astimezone(utctz).replace(microsecond=0)
else:
    sitetime = siteinfo['time'].astimezone(utctz)

if not args.daemon:
    # Limit start/end between install date and site current time
    siteinstdate = siteinfo['instdate'].astimezone(utctz)
    if start < siteinstdate:
        start = siteinstdate
    if end > sitetime - timedelta(minutes=2):
        end = sitetime - timedelta(minutes=2)
    if start >= end:
        sys_exit("ERROR: No data available for this date/time range")

# Get site info
site = siteinfo['site']

if args.force:
    # Retrieve power history data between start and end date/time (skip search for gaps)
    get_power_history(start, end)
    print()

    if isinstance(site, Battery):
        # Retrieve backup history data between start and end date/time (skip search for gaps)
        get_backup_history(start, end)
        print()

        if args.reserve is not None:
            # Set backup reserve percent history data
            set_reserve_history(start, end)
            print()
elif args.daemon:
    try:
        print("* Server Started")
        print(f" + Retrieving {HIST} minutes of history every {WAIT} minutes")
        sys.stdout.flush()
        while True:
            currentts = datetime.now(tz=influxtz).astimezone(utctz).replace(microsecond=0) - timedelta(minutes=2)
            # Check if wait time passed
            if currentts >= end + timedelta(minutes=WAIT):
                # Update start/end range to get history data to current time
                end = currentts
                start = end - timedelta(minutes=HIST)
            else:
                time.sleep(1)
                continue

            # Re-initialise globals
            powerdata.clear()
            backupdata.clear()
            eventdata.clear()
            reservedata.clear()
            dayloaded = None
            eventsloaded = False
            reserveloaded = False

            # Retrieve power history data
            get_power_history(start, end)

            if isinstance(site, Battery):
                # Retrieve backup history data
                get_backup_history(start, end)

                if args.reserve is not None:
                    # Set backup reserve percent history data
                    set_reserve_history(start, end)

            if powerdata or eventdata or reservedata:
                if powerdata:
                    # Remove previously written data points
                    if VERBOSE:
                        print("Clearing InfluxDB data")
                    remove_influx(start, end)

                # Write new data points to InfluxDB
                write_influx()

                if powerdata:
                    # Update InfluxDB analysis data
                    update_influx(start, end)

            if fetcherr or queryerr or writeerr:
                # If an error occurred, reset the end time to wait for the configured retry delay
                end = datetime.now(tz=influxtz).astimezone(utctz).replace(microsecond=0) - timedelta(minutes=2) + timedelta(minutes=-WAIT, seconds=RETRY)

            sys.stdout.flush()
    except (KeyboardInterrupt, SystemExit):
        server_exit()
else:
    # Search InfluxDB for power usage data gaps
    powergaps = search_influx(start, end, 'power usage')
    print() if powergaps else print("* None found\n")

    if isinstance(site, Battery):
        # Search InfluxDB for grid status data gaps
        gridgaps = search_influx(start, end, 'grid status')
        print() if gridgaps else print("* None found\n")

        if args.reserve is not None:
            # Search InfluxDB for backup reserve percent data gaps
            reservegaps = search_influx(start, end, 'backup reserve percent')
            print() if reservegaps else print("* None found\n")

    if not (powergaps or gridgaps or reservegaps):
        print("Done.")
        sys_exit()

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

    if reservegaps:
        # Set backup reserve percent history for each gap period
        for period in reservegaps:
            set_reserve_history(period['start'], period['end'])
        print()

if not (powerdata or eventdata or reservedata):
    sys_exit("ERROR: No data returned for this date/time range")

# Write data points to InfluxDB
write_influx()

if powerdata:
    # Update InfluxDB analysis data
    update_influx(start, end, powergaps)

print("Done.")
