#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
 Command line tool to publish daily solar stats to PVoutput.org
 Set up as a cronjob or use to mass publish several days.

 Author: Jason A. Cox
 For more information see https://github.com/jasonacox/Powerwall-Dashboard

 Usage:
    * Sign up at pvoutput.org and get an API KEY - update the settings below
      with your API_SYSTEM_ID and API_KEY.
    * Update the INFLUXDB_HOST below to the address of your Dashboard host
      (default = localhost) and INFLUXDB_TZ for your timezone.
    * Install the InfluxDB module:  pip install influxdb
    * Run this script:
        python3 pvoutput.py <option>

              <option> is 'yesterday' or 'today' or empty
    
        If no <option> is provided you will be prompted for a start date and
        and end date to send.
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

# PVoutput API Credentials
API_SYSTEM_ID = "SYSTEM_ID_FROM_PVOUTPUT.ORG"
API_KEY = "API_KEY_FROM_PVOUTPUT.ORG"
API_HOST = "pvoutput.org"

# InfluxDB Settings
INFLUXDB_HOST = "localhost"
INFLUXDB_PORT = "8086"
INFLUXDB_USER = ""
INFLUXDB_PASS = ""
INFLUXDB_DB = "powerwall"
INFLUXDB_TZ = "America/Los_Angeles"

# Weather Settings
WEATHER_UNITS = "metric"  # metric, imperial or standard

# Helper Functions
def make_request(method, path, params=None):
    conn = http.client.HTTPConnection(API_HOST)
    headers = {
            'Content-type': 'application/x-www-form-urlencoded',
            'Accept': 'text/plain',
            'X-Pvoutput-Apikey': API_KEY,
            'X-Pvoutput-SystemId': API_SYSTEM_ID
            }
    conn.request(method, path, params, headers)

    return conn.getresponse()
    
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

    if response.status == 400:
        raise ValueError(response.read())
    if response.status != 200:
       raise Exception(response.read())

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

# Command line arguments for presets
if len(sys.argv) >= 2:
    if sys.argv[1].lower() == 'today':
        s = date.today()
        e = date.today() + timedelta(days=1)
    elif sys.argv[1].lower() == 'yesterday':
        s = date.today() - timedelta(days=1)
        e = date.today()

if s is None:
    # Prompt for custom date range
    print("Select Custom Date Range")
    while True:
        user1 = input(" - Enter start day (YYYY-mm-dd): ")
        user2 = input(" - Enter end date (YYYY-mm-dd): ")
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
