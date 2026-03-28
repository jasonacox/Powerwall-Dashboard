#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Command line tool to publish daily solar stats to PVoutput.org.

Set up as a cronjob or use to mass publish several days.

Author: Jason A. Cox
For more information see https://github.com/jasonacox/Powerwall-Dashboard

Usage:
    - `python3 pvoutput.py today`            Send today's data
    - `python3 pvoutput.py yesterday`        Send yesterday's data
    - `python3 pvoutput.py range START [END]` Send data for START..END (YYYY-mm-dd). If END is
        omitted, it defaults to today.
    - `-h, --help`                           Show help
    - `-v, --version`                        Show script version

Configuration:
    Most global settings can be overridden with environment variables:
        - PVOUTPUT_API_SYSTEM_ID, PVOUTPUT_API_KEY, PVOUTPUT_API_HOST
        - INFLUXDB_HOST, INFLUXDB_PORT, INFLUXDB_USER, INFLUXDB_PASS, INFLUXDB_DB, INFLUXDB_TZ
        - PVOUTPUT_WEATHER_UNITS (metric|imperial|standard)
        - PVOUTPUT_MAX_RETRIES, PVOUTPUT_BACKOFF_FACTOR
        - PVOUTPUT_RATE_LIMIT_WAIT=1  Force rate-limit waiting in any mode (default: only
          enabled automatically for 'range' and interactive modes; disabled for cron-safe
          modes 'today' and 'yesterday')

Dependencies:
    - `influxdb` Python package (install with `pip install influxdb`)

If no command-line option is provided the script will prompt interactively
for a start and end date to send.
"""
import datetime
from datetime import date, timedelta
import urllib.request, urllib.parse, urllib.error
import http.client
import time
import socket
import os
import sys
try:
    from influxdb import InfluxDBClient
except:
    sys.exit("ERROR: Missing python influxdb module. Run 'pip install influxdb'.")

# PVoutput API Credentials (can be overridden with environment variables)
API_SYSTEM_ID = os.environ.get('PVOUTPUT_API_SYSTEM_ID', "SYSTEM_ID_FROM_PVOUTPUT.ORG")
API_KEY = os.environ.get('PVOUTPUT_API_KEY', "API_KEY_FROM_PVOUTPUT.ORG")
API_HOST = os.environ.get('PVOUTPUT_API_HOST', "pvoutput.org")

# InfluxDB Settings (override via env: INFLUXDB_HOST, INFLUXDB_PORT, ...)
INFLUXDB_HOST = os.environ.get('INFLUXDB_HOST', "localhost")
INFLUXDB_PORT = int(os.environ.get('INFLUXDB_PORT', "8086"))
INFLUXDB_USER = os.environ.get('INFLUXDB_USER', "")
INFLUXDB_PASS = os.environ.get('INFLUXDB_PASS', "")
INFLUXDB_DB = os.environ.get('INFLUXDB_DB', "powerwall")
INFLUXDB_TZ = os.environ.get('INFLUXDB_TZ', "America/Los_Angeles")

# Weather Settings
WEATHER_UNITS = os.environ.get('PVOUTPUT_WEATHER_UNITS', "metric")  # metric, imperial or standard

# Retry/backoff defaults (can be overridden via env)
MAX_RETRIES = int(os.environ.get('PVOUTPUT_MAX_RETRIES', '3'))
BACKOFF_FACTOR = float(os.environ.get('PVOUTPUT_BACKOFF_FACTOR', '1'))

# Wait on rate limit (403): only safe for interactive/range use, not cron.
# Set PVOUTPUT_RATE_LIMIT_WAIT=1 to force-enable, or it is auto-enabled for 'range'.
RATE_LIMIT_WAIT = os.environ.get('PVOUTPUT_RATE_LIMIT_WAIT', '0') == '1'

# Script version
VERSION = "2.0"

# Helper Functions
def make_request(method, path, params=None, max_retries=None, backoff_factor=None):
    """Make an HTTP request to PVOutput with retry/backoff on transient errors.

    Retries on network exceptions and on server-side or rate-limit responses
    (HTTP 5xx and 429). By default the function uses the module-level
    `MAX_RETRIES` and `BACKOFF_FACTOR` values (which can themselves be set
    via the `PVOUTPUT_MAX_RETRIES` and `PVOUTPUT_BACKOFF_FACTOR` environment
    variables). If `max_retries` or `backoff_factor` are provided they override
    the environment defaults for that call.

    403 rate-limit handling ("Exceeded 60 requests per hour"):
      - If `RATE_LIMIT_WAIT` is True (set automatically for 'range' and interactive
        modes, or via PVOUTPUT_RATE_LIMIT_WAIT=1), the function waits until the top
        of the next clock hour and retries automatically.
      - Otherwise (cron-safe modes 'today'/'yesterday') it logs the error and returns
        immediately so the cron job is not left hanging.

    Returns the final `http.client.HTTPResponse` object or raises the last
    exception if retries are exhausted.
    """
    # Use module-level defaults if not provided
    if max_retries is None:
        max_retries = MAX_RETRIES
    if backoff_factor is None:
        backoff_factor = BACKOFF_FACTOR

    retry_statuses = {429, 500, 502, 503, 504}
    attempt = 0
    while True:
        attempt += 1
        try:
            conn = http.client.HTTPConnection(API_HOST, timeout=10)
            headers = {
                    'Content-type': 'application/x-www-form-urlencoded',
                    'Accept': 'text/plain',
                    'X-Pvoutput-Apikey': API_KEY,
                    'X-Pvoutput-SystemId': API_SYSTEM_ID
                    }
            conn.request(method, path, params, headers)
            response = conn.getresponse()

            # Read body so we can inspect it and the connection stays clean
            try:
                body = response.read()
            except Exception:
                body = b''

            # 403 with rate-limit message
            if response.status == 403 and b'Exceeded' in body:
                if RATE_LIMIT_WAIT:
                    now = datetime.datetime.now()
                    next_hour = (now + datetime.timedelta(hours=1)).replace(minute=0, second=5, microsecond=0)
                    wait = max(1, (next_hour - now).seconds)
                    print(f"Rate limit hit (403): {body.decode(errors='replace')}")
                    print(f"Waiting {wait}s until next hour ({next_hour.strftime('%H:%M:%S')}) before retrying...")
                    time.sleep(wait)
                    conn.close()
                    continue  # retry indefinitely until it succeeds
                else:
                    print("Rate limit hit (403) - skipping wait (not in range/interactive mode).")
                    response._body = body
                    return response

            # If we get a retryable status and we have attempts left, wait and retry
            if response.status in retry_statuses and attempt < max_retries:
                wait = backoff_factor * (2 ** (attempt - 1))
                print(f"Request returned {response.status}, retrying in {wait}s... (attempt {attempt}/{max_retries})")
                time.sleep(wait)
                conn.close()
                continue

            # Attach body to response so callers can still read it
            response._body = body
            return response

        except (http.client.HTTPException, OSError, socket.error) as exc:
            if attempt < max_retries:
                wait = backoff_factor * (2 ** (attempt - 1))
                print(f"Network error ({exc}), retrying in {wait}s... (attempt {attempt}/{max_retries})")
                time.sleep(wait)
                continue
            raise
    
# PVoutput API Fields - Daily Values
""" PVoutput Data Fields

    Param	Field	           Req  Format      Unit        Example
  * d	    Date	           Yes  yyyymmdd	date	    20210228
  * g	    Generated	        No  number	    watt hours	3271
  * e	    Exported	        No	number	    watt hours	1928
    pp	    Peak Power	        No	number	    watts	    2802
    pt	    Peak Time	        No	hh:mm	    time	    13:15
    cd	    Condition	        No	text	
    tm	    Min Temp	        No	decimal	    celsius	    10.2
    tx	    Max Temp	        No	decimal	    celsius	    21.2
    cm	    Comments	        No	text		Free text
  * ip	    Import Peak	        No	number	    watt hours	1234
    io	    Import Off Peak	    No	number	    watt hours	
    is	    Import Shoulder	    No	number	    watt hours	
    ih	    Import High     	No	number	    watt hours	
  * c	    Consumption	        No	number  	watt hours	1234
    ep	    Export Peak	        No	number	    watt hours	
    eo	    Export Off-Peak	    No	number	    watt hours	
    es	    Export Shoulder	    No	number	    watt hours	
    eh	    Export High     	No	number	    watt hours	
"""
def push_daily(date,  generated=None, exported=None, consumed=None, imported=None, tm=None, tx=None):
    """Push daily aggregated values to PVOutput.

    Parameters:
        date (str): date as yyyymmdd
        generated (int): generated Wh
        exported (int): exported Wh
        consumed (int): consumed Wh
        imported (int): imported Wh (ip field)
        tm (float): min temperature (C)
        tx (float): max temperature (C)
    """
    path = '/service/r2/addoutput.jsp'
    params = {
            'd': date,
            }
    if generated:
        params['g'] = generated
    if exported:
        params['e'] = exported
    if consumed:
        params['c'] = consumed
    if imported:
        params['ip'] = imported  # using import peak - TODO expand for TOU
    if tm:
        params['tm'] = tm
    if tx:
        params['tx'] = tx

    params = urllib.parse.urlencode(params)

    response = make_request('POST', path, params)

    body = getattr(response, '_body', b'')
    if response.status == 400:
        raise ValueError(body)
    if response.status != 200:
        raise Exception(body)

# InfluxDB
def get_influx(start=None, end=None):
    """
    Pull Generation and Exported Energy Data from InfluxDB between the
    dates 'start' and 'end' (format: YYYY-mm-dd)

    Returns array = generated, exported
    """
    host = INFLUXDB_HOST
    port = INFLUXDB_PORT
    user = INFLUXDB_USER
    password = INFLUXDB_PASS
    dbname = INFLUXDB_DB

    # Connect to influxDB
    client = InfluxDBClient(host, port, user, password, dbname)
    timeFilter = "time > '%s' AND time < '%s' tz('%s')" % (start, end, INFLUXDB_TZ)

    # Solar Data
    query = 'SELECT sum("solar") * 1000 AS "generated", sum("to_grid") * 1000 AS "exported", sum("home") * 1000 AS "consumed", sum("from_grid") * 1000 AS "imported"  FROM "kwh"."http" WHERE %s' % (timeFilter)
    g = e = c = i = None
    result = client.query(query)
    for point in result.get_points():
        g = int(point['generated'])
        e = int(point['exported'])
        c = int(point['consumed'])
        i = int(point['imported'])

    # Weather Data
    query = 'SELECT min("temperature") AS "tm", max("temperature") AS "tx" FROM "autogen"."weather" WHERE %s' % (timeFilter)
    tm = tx = None
    result = client.query(query)
    for point in result.get_points():
        tm = float(point['tm'])
        tx = float(point['tx'])
    # Convert to Metric
    if (WEATHER_UNITS == "imperial"):
        if tm is not None:
            tm = (5.0/9.0)*(tm-32.0)
        if tx is not None:
            tx = (5.0/9.0)*(tx-32.0)
    if (WEATHER_UNITS == "standard"):
        if tm is not None:
            tm = tm - 273.15
        if tx is not None:
            tx = tx - 273.15

    # Return Data
    return([g,e,c,i,tm,tx])

# MAIN

s = e = None  # start and end

def print_usage():
    print("pvoutput.py - publish daily solar stats to PVOutput.org")
    print("")
    print("Usage:")
    print("  python pvoutput.py today")
    print("  python pvoutput.py yesterday")
    print("  python pvoutput.py range START [END]    (dates in YYYY-mm-dd format; END defaults to today)")
    print("")
    print("Options:")
    print("  -h, --help       Show this help message")
    print("  -v, --version    Show script version (currently %s)" % VERSION)
    print("")

# Command line arguments for presets
if len(sys.argv) >= 2:
    # Global flags
    if sys.argv[1] in ('-h', '--help'):
        print_usage()
        sys.exit(0)
    if sys.argv[1] in ('-v', '--version', '-V'):
        print(VERSION)
        sys.exit(0)

    cmd = sys.argv[1].lower()
    if cmd == 'today':
        s = date.today()
        e = date.today() + timedelta(days=1)
    elif cmd == 'yesterday':
        s = date.today() - timedelta(days=1)
        e = date.today()
    elif cmd == 'range':
        # Usage: range START [END]
        # START and END format: YYYY-mm-dd. If END omitted, assume today.
        RATE_LIMIT_WAIT = True  # safe to wait in range mode
        if len(sys.argv) < 3:
            sys.exit("ERROR: 'range' requires a start date. Usage: range YYYY-mm-dd [YYYY-mm-dd]")
        try:
            s = datetime.datetime.strptime(sys.argv[2], '%Y-%m-%d').date()
        except Exception:
            sys.exit("ERROR: unrecognized start date for range. Use YYYY-mm-dd")

        if len(sys.argv) >= 4 and sys.argv[3]:
            try:
                end_date = datetime.datetime.strptime(sys.argv[3], '%Y-%m-%d').date()
            except Exception:
                sys.exit("ERROR: unrecognized end date for range. Use YYYY-mm-dd")
            e = end_date + timedelta(days=1)
        else:
            e = date.today() + timedelta(days=1)

if s is None:
    # Prompt for custom date range - safe to wait on rate limits
    RATE_LIMIT_WAIT = True
    print("Select Custom Date Range")
    while True:
        user1 = input(" - Enter start date (YYYY-mm-dd, e.g. 2026-01-01): ")
        user2 = input(" - Enter end date   (YYYY-mm-dd, e.g. 2026-01-31): ")
        try:
            s = datetime.datetime.strptime(user1, '%Y-%m-%d')
            e = datetime.datetime.strptime(user2, '%Y-%m-%d')
            e = e + timedelta(days=1)
            break
        except:
            print("** ERROR unrecognized date - try again.")
            pass

if e == s + timedelta(days=1):
    print("\nSending Solar Data [%s]" % (s.strftime('%Y-%m-%d')))
else:
    print("\nSending Solar Data [%s to %s]" % (s.strftime('%Y-%m-%d'), e.strftime('%Y-%m-%d')))

# Loop through all dates we need to send
x = s
while x < e:
    # Pull data from Influxdb
    y = x + timedelta(days=1)
    startday = x.strftime('%Y-%m-%d')
    endday = y.strftime('%Y-%m-%d')
    day = x.strftime('%Y%m%d')

    print("%s: " % startday, end='')
    [generated,exported,consumed,imported,tm,tx] = get_influx(startday, endday)
    if generated is not None and exported < generated:
        if tm is not None and tx is not None:
            temprange = "- Temp = %0.1f / %0.1f" % (tm,tx)
        else:
            temprange = ""
        print("   Generated = %0.0f - Exported = %0.0f - Consumed = %0.0f - Imported = %0.0f %s" % (generated, exported, consumed, imported, temprange), end='')

        # Push data to PVoutput
        day = x.strftime('%Y%m%d')
        push_daily(day, generated, exported, consumed, imported, tm, tx)
        print(" - Published")
    else:
        print("   No Data")

    x = y

print("Done.")
