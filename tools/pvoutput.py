#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
 Command line tool to publish daily solar stats to PVoutput.org
 Set up as a cronjob or use CLI to mass publish several days.

 Author: Jason A. Cox
 For more information see https://github.com/jasonacox/Powerwall-Dashboard

 Usage:
    * Sign up at pvoutput.org and get an API KEY - update the settings below
      with your API_SYSTEM_ID and API_KEY.
    * Update the INFLUXDB_HOST below to the address of your Dashboard host
      (default = localhost)
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
from influxdb import InfluxDBClient

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
"""
Param	Field	           Req  Format      Unit        Example
d	    Date	           Yes  yyyymmdd	date	    20210228
g	    Generated	        No  number	    watt hours	3271
e	    Exported	        No	number	    watt hours	1928
pp	    Peak Power	        No	number	    watts	    2802
pt	    Peak Time	        No	hh:mm	    time	    13:15
cd	    Condition	        No	text	
tm	    Min Temp	        No	decimal	    celsius	    10.2
tx	    Max Temp	        No	decimal	    celsius	    21.2
cm	    Comments	        No	text		Free text
ip	    Import Peak	        No	number	    watt hours	
io	    Import Off Peak	    No	number	    watt hours	
is	    Import Shoulder	    No	number	    watt hours	
ih	    Import High     	No	number	    watt hours	
c	    Consumption	        No	number  	watt hours	
ep	    Export Peak	        No	number	    watt hours	
eo	    Export Off-Peak	    No	number	    watt hours	
es	    Export Shoulder	    No	number	    watt hours	
eh	    Export High     	No	number	    watt hours	
"""
def push_daily(date,  generated=None, exported=None):
    
    path = '/service/r2/addoutput.jsp'
    params = {
            'd': date,
            }
    if generated:
        params['g'] = generated
    if exported:
        params['e'] = exported
    
    params = urllib.parse.urlencode(params)

    response = make_request('POST', path, params)

    if response.status == 400:
        raise ValueError(response.read())
    if response.status != 200:
       raise Exception(response.read())

# PVoutput API Fields - Sample Values - Cumulative - TODO
"""
Param	Field	           Req  Format	    Unit	    Example	Donation
d	    Output Date	       Yes  yyyymmdd	date	    20210228	
t	    Time	           Yes  hh:mm	    time	    14:00	
v1	    Energy Generation	No  number	    watt hours	10000	
v2	    Power Generation	No  number  	watts	    2000	
v3	    Energy Consumption	No  number  	watt hours	10000	
v4  	Power Consumption	No  number  	watts	    2000	
v5	    Temperature	        No  decimal 	celsius 	23.4	
v6	    Voltage	            No  decimal 	volts	    239.2	
c1  	Cumulative Flag	    No  number		            1	
n   	Net Flag	        No  number		            1	
v7      Extended Value v7	No  number	    User 
v8  	Extended Value v8	No  number	    User 
v9  	Extended Value v9	No  number  	User 
v10 	Extended Value v10	No  number	    User 
v11 	Extended Value v11	No  number	    User 
v12	    Extended Value v12	No  number  	User 
m1	    Text Message 1	    No  text	    30 chars 
"""
def push_update(date, time, energy_exp=None, power_exp=None, 
    energy_imp=None, power_imp=None, temp=None, vdc=None, battery_flow=None, 
    load_power=None, soc=None, site_power=None, load_voltage=None, 
    ext_power_exp=None, cumulative=False):
    
    path = '/service/r2/addstatus.jsp'
    params = {
            'd': date,
            't': time
            }
    if energy_exp:
        params['v1'] = energy_exp
    if power_exp:
        params['v2'] = power_exp
    if energy_imp:
        params['v3'] = energy_imp
    if power_imp:
        params['v4'] = power_imp
    if temp:
        params['v5'] = temp
    if vdc:
        params['v6'] = vdc
    if battery_flow:
        params['v7'] = battery_flow
    if load_power:
        params['v8'] = load_power
    if soc:
        params['v9'] = soc
    if site_power:
        params['v10'] = site_power
    if load_voltage:
        params['v11'] = load_voltage
    if ext_power_exp:
        params['v12'] = ext_power_exp
    if cumulative:
        params['c1'] = 1
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

    timeFilter = "time > '%s' AND time < '%s' tz('%s')" % (start, end, INFLUXDB_TZ)
    query = 'SELECT sum("solar") * 1000 AS "generated", sum("to_grid") * 1000 AS "exported" FROM "kwh"."http" WHERE %s' % (timeFilter)
    
    client = InfluxDBClient(host, port, user, password, dbname)

    # print("Querying data: " + query)
    result = client.query(query)
    for point in result.get_points():
        g = point['generated']
        e = point['exported']
    
    return([g,e])

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
            print("Custom")
            break
        except:
            print("** ERROR unrecognized date - try again.")
            pass

if e == s + timedelta(days=1):
    print("Sending Solar Data [%s]" % (s.strftime('%Y-%m-%d')))
else:
    print("Sending Solar Data [%s to %s]" % (s.strftime('%Y-%m-%d'), e.strftime('%Y-%m-%d')))

# Loop through all dates we need to send
x = s
while x < e:
    # Pull data from Influxdb
    y = x + timedelta(days=1)
    startday = x.strftime('%Y-%m-%d')
    endday = y.strftime('%Y-%m-%d')
    day = x.strftime('%Y%m%d')

    print("Pulling Data for %s: " % startday, end='')
    [generated,exported] = get_influx(startday, endday)
    print("   Generated = %0.0f - Exported = %0.0f" % (generated, exported), end='')

    # Push data to PVoutput
    day = x.strftime('%Y%m%d')
    push_daily(day, generated, exported)
    print(" - Published")

    x = y

print("Done.")
