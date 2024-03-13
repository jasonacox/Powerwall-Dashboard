#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
 Command line tool to export home, powerwall, solar and grid data from InfluxDB
 
 Author: Jason A. Cox
 Date: 12 Mar 2024
 https://github.com/jasonacox/Powerwall-Dashboard

"""
import datetime
from datetime import date, timedelta
import urllib.request, urllib.parse, urllib.error
import http.client
import sys
try:
    from influxdb import InfluxDBClient
except:
    sys.exit("ERROR: Missing python influxdb module. Run 'pip install influxdb'.")

# InfluxDB Settings
INFLUXDB_HOST = "localhost"
INFLUXDB_PORT = "8086"
INFLUXDB_USER = ""
INFLUXDB_PASS = ""
INFLUXDB_DB = "powerwall"
INFLUXDB_TZ = "America/Los_Angeles"
OUTPUT_FILE = "export.csv"

# InfluxDB
def get_influx(start=None, end=None, output=None):
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

    # Connect to influxDB and run query
    client = InfluxDBClient(host, port, user, password, dbname)
    timeFilter = "time > '%s' AND time < '%s' tz('%s')" % (start, end, INFLUXDB_TZ)
    query = 'SELECT "home", "solar", "from_pw" - "to_pw" AS "pw", "from_grid" - "to_grid" AS "grid", "percentage" /0.95 - 5/0.95 AS "charge" FROM "autogen"."http" WHERE %s' % (timeFilter)
    home = solar = pw = grid = charge = None
    result = client.query(query)
    for point in result.get_points():
        try:
            ts = point['time']
            home = int(point['home'])
            solar = int(point['solar'])
            pw = int(point['pw'])
            grid = int(point['grid'])
            charge = point['charge']
            # print ts to console
            print(f"\r{ts}", end="", flush=True)
            # print to file output
            if output:
                output.write("%s,%0.0f,%0.0f,%0.0f,%0.0f,%0.0f\n" % (ts, solar, pw, home, grid, charge))
        except:
            # likely a null value
            pass

# MAIN
s = e = None  # start and end

# Command line arguments for presets
if len(sys.argv) == 1:
    print(f"Usage: {sys.argv[0]} [today|yesterday|all] or [YYYY-mm-dd] [YYYY-mm-dd]") 
    print("  today - export today's data")
    print("  yesterday - export yesterday's data")
    print("  all - export all data")
    print("  YYYY-mm-dd - export single day")
    print("  YYYY-mm-dd YYYY-mm-dd - export date range")
    sys.exit()

# Print Header
print(f"Exporting Powerwall Data from InfluxDB to {OUTPUT_FILE}")
print("")

# Open file for output
try:
    output = open(OUTPUT_FILE, "w")
    output.write("TimeStamp,Solar,Powerwall,Home,Grid,Charge\n")
except:
    sys.exit(f"ERROR: Unable to open {OUTPUT_FILE} for writing.")

if len(sys.argv) >= 2:
    if sys.argv[1].lower() == 'today':
        s = date.today()
        e = date.today() + timedelta(days=1)
    elif sys.argv[1].lower() == 'yesterday':
        s = date.today() - timedelta(days=1)
        e = date.today()
    elif sys.argv[1].lower() == 'all':
        print("Exporting All Data")
        s = datetime.datetime.strptime("1970-01-01", '%Y-%m-%d')
        e = date.today() + timedelta(days=1)
    else:
        if len(sys.argv) == 2:
            # Single date
            s = datetime.datetime.strptime(sys.argv[1], '%Y-%m-%d')
            e = s + timedelta(days=1)
        else:
            # Date range
            s = datetime.datetime.strptime(sys.argv[1], '%Y-%m-%d')
            e = datetime.datetime.strptime(sys.argv[2], '%Y-%m-%d')
            e = e + timedelta(days=1)

if e == s + timedelta(days=1):
    print("Exporting Data [%s]" % (s.strftime('%Y-%m-%d')))
else:
    print("Exporting Data [%s to %s]" % (s.strftime('%Y-%m-%d'), e.strftime('%Y-%m-%d')))
startday = s.strftime('%Y-%m-%d')
endday = e.strftime('%Y-%m-%d')
print("")
get_influx(startday, endday, output)
print("")

print("Done.")
