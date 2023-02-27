#!/usr/bin/env python
# Ecowitt API - Ecowitt API Personal Weather Station Conditions
# -*- coding: utf-8 -*-
"""
 Python module to poll and store weather data from Ecowitt API for Hyper-Local Weather

 Author: BJReplay
 Based On Weather411 module by: Jason A. Cox
 For more information see https://github.com/jasonacox/Powerwall-Dashboard

 Weather Data Tool
    This tool will poll current weather conditions using Ecowitt API
    and then make it available via local API calls or optionally store 
    it in InfluxDB.

    Ecowitt API information: http://doc.ecowitt.net/web/#/apiv3en?page_id=17

    CONFIGURATION FILE - On startup will look for ecowitt.conf
    which includes the following parameters:

        [LocalWeather]
        DEBUG = no

        [API]
        # Port for API requests (default 8676)
        ENABLE = yes
        PORT = 8686

        [Ecowitt]
        # Set your APIKEY and APPLICATION_KEY from https://www.ecowitt.net/user/index
        APIKEY = xxxxxxxxxxxxxxxxxxxxxxxxxxxxx
        APPLICATION_KEY = xxxxxxxxxxxxxxxxxxxxxxxxxxxx
        
        # Set the MAC address for the specific station you want to query
        MAC = xx:xx:xx:xx:xx:xx

        WAIT = 1
        TIMEOUT = 10
        
        # metric or imperial 
        UNITS = metric
        
        [InfluxDB]
        # Record data in InfluxDB server 
        ENABLE = yes
        HOST = influxdb
        PORT = 8086
        DB = powerwall
        FIELD = ecowitt
        # Auth - Leave blank if not used
        USERNAME =
        PASSWORD =
        # Auth - Influx 2.x - Leave blank if not used
        TOKEN =
        ORG =
        URL =

    ENVIRONMENTAL:
        LOCALWEATHERCONF = "Path to localweather.conf file"

    The API service of LocalWeather has the following functions:
        /           - Human friendly display of current weather conditions
        /json       - All current weather data in JSON format
        /temp       - Current temperature in C
        /humidity   - Current humidity in %
        /pressure   - Current pressure in hPa
        /solar      - Current Insolation in W/m²
        /uvi        - Current UV Index (scale 1 to 11)
        /wind       - Current speed (km/h), gust (km/h) and direction (degree)
        /rain       - Precipitation volume in mm (last hour / daily)
        /aqi        - Air Quality measurements
        /indoor     - Indoor temperature and pressure measurements
        /time       - Current time in UTC


"""
# Modules
from __future__ import print_function
import threading
import time
import logging
import json
import requests
import resource
import datetime
import sys
import os
from http.server import BaseHTTPRequestHandler, HTTPServer, ThreadingHTTPServer
from socketserver import ThreadingMixIn 
import configparser
from influxdb_client import InfluxDBClient
from influxdb_client.client.write_api import SYNCHRONOUS

BUILD = "0.1.0"
CLI = False
LOADED = False
CONFIG_LOADED = False
CONFIGFILE = os.getenv("WEATHERCONF", "ecowitt.conf")
URL = "https://api.ecowitt.net/api/v3/device/real_time"

# Load Configuration File
config = configparser.ConfigParser(allow_no_value=True)
if os.path.exists(CONFIGFILE):
    config.read(CONFIGFILE)
    DEBUGMODE = config["LocalWeather"]["DEBUG"].lower() == "yes"

    # LocalWeather API
    API = config["API"]["ENABLE"].lower() == "yes"
    APIPORT = int(config["API"]["PORT"])

    # Ecowitt
    ECOKEY = config["Ecowitt"]["APIKEY"]
    ECOAPP = config["Ecowitt"]["APPLICATION_KEY"]
    ECOWAIT = int(config["Ecowitt"]["WAIT"])
    ECOUNITS = str(config["Ecowitt"]["UNITS"])
    ECOMAC = str(config["Ecowitt"]["MAC"])
    TIMEOUT = str(config["Ecowitt"]["TIMEOUT"])

    # InfluxDB
    INFLUX = config["InfluxDB"]["ENABLE"].lower() == "yes"
    IHOST = config["InfluxDB"]["HOST"]
    IPORT = int(config["InfluxDB"]["PORT"])
    IUSER = config["InfluxDB"]["USERNAME"]
    IPASS = config["InfluxDB"]["PASSWORD"]
    IDB = config["InfluxDB"]["DB"]
    IFIELD = config["InfluxDB"]["FIELD"]
    # Check for InfluxDB 2.x settings
    ITOKEN = config.get('InfluxDB', 'TOKEN', fallback="") 
    IORG = config.get('InfluxDB', 'ORG', fallback="") 
    IURL = config.get('InfluxDB', 'URL', fallback="") 

    if ITOKEN != "" and IURL == "":
    IURL = "http://%s:%s" % (IHOST, IPORT)
else:
    # No config file - Display Error
    sys.stderr.write("LocalWeather Server %s\nERROR: No config file. Fix and restart.\n" % BUILD)
    sys.stderr.flush()
    while(True):
        time.sleep(3600)

# Logging
log = logging.getLogger(__name__)
if DEBUGMODE:
    logging.basicConfig(format='%(levelname)s:%(message)s',level=logging.DEBUG)
    log.setLevel(logging.DEBUG)
    log.debug("LocalWeather [%s]\n" % BUILD)

# Global Stats
serverstats = {}
serverstats['LocalWeather'] = BUILD
serverstats['gets'] = 0
serverstats['errors'] = 0
serverstats['timeout'] = 0
serverstats['uri'] = {}
serverstats['ts'] = int(time.time())         # Timestamp for Now
serverstats['start'] = int(time.time())      # Timestamp for Start 
serverstats['clear'] = int(time.time())      # Timestamp of lLast Stats Clear
serverstats['influxdb'] = 0
serverstats['influxdberrors'] = 0

# Global Variables
running = True
weather = {}
raw = {}

# Helper Functions
def clearweather():
    global weather
    weather = {
        # header
        "dt": 0, 
        # basics
        "temperature": None, "feels_like": None, "app_temp": None, "dew_point": None, "humidity": None, 
        # indoor
        "inside_temp": None, "inside_humidity": None, 
        # solar_and_uvi
        "solar": 0.0, "uvi": 0, 
        # precipitation
        "rain_1h": 0.0, "rain_24h": 0.0,
        # wind
        "wind_speed": None, "wind_deg": None, "wind_gust": None,
        # pressure
        "pressure": None, 
        # AQI
        "co2": None, "pm25": None, "pm25aqi": None, "pm10": None, "pm10aqi": None, 
        }

def lookup(source, index, valtype='string'):
    # check source dict to see if index key exists
    if index in source:
        if valtype == 'float':
            return float(source[index])
        if valtype == 'int':
            return int(source[index])            
        return str(source[index])
    return None

def getvalue(source, index, valtype):
    # check source dict to see if value key exists under index key 
    if index in source:
        if "value" in source[index]:
            return lookup(source[index], "value", valtype)
    return None

# Clear weather data
clearweather()

# Threads
def fetchWeather():
    """
    Thread to poll for current weather conditions
    """
    global running, weather, LOADED, raw, serverstats, URL
    sys.stderr.write(" + fetchWeather thread\n")
    URL = URL + "?application_key=" + ECOAPP + "&api_key=" + ECOKEY + "&mac=" + ECOMAC

    if ECOUNITS == 'metric':
      URL = URL + "&temp_unitid=1&pressure_unitid=3&wind_speed_unitid=7&rainfall_unitid=12&solar_irradiance_unitid=16"
    elif ECOUNITS == 'imperial':
      URL = URL + "&temp_unitid=2&pressure_unitid=4&wind_speed_unitid=9rainfall_unitid=13&solar_irradiance_unitid=16"

    nextupdate = time.time()

    # Time Loop to update current weather data
    while(running):
        currentts = time.time()
        lasttime = weather["dt"]
        # Is it time for an update?
        if currentts >= nextupdate:
            nextupdate = currentts + (60 * ECOWAIT)
            if CLI:
                print("\n")
            try:
                response = requests.get(URL)
                if response.status_code == 200:
                    raw = response.json()
                    clearweather()
                    try:
                        if 'time' not in raw or lasttime == raw['time']:
                            # Data didn't update - skip rest and loop
                            continue
                        weather["dt"] = raw['time']
                        datapayload = raw['data']
                        if "outdoor" in datapayload:
                            data = datapayload["outdoor"]
                            weather["temperature"] = getvalue(data, 'temperature', 'float')
                            weather["feels_like"] = getvalue(data, 'feels_like', 'float')
                            weather["app_temp"] = getvalue(data, 'app_temp', 'float')
                            weather["dew_point"] = getvalue(data, 'dew_point', 'float')
                            weather["humidity"] = getvalue(data, 'humidity', 'float')
                        if "indoor" in datapayload:
                            data = datapayload["indoor"]
                            weather["inside_temp"] = getvalue(data, 'temperature', 'float')
                            weather["inside_humidity"] = getvalue(data, 'humidity', 'float')
                        if "solar_and_uvi" in datapayload:
                            data = datapayload["solar_and_uvi"]
                            weather["solar"] = getvalue(data, 'solar', 'float')
                            weather["uvi"] = getvalue(data, 'uvi', 'int')
                        if "rainfall" in datapayload:
                            data = datapayload["rainfall"]
                            weather["rain_1h"] = getvalue(data, 'hourly', 'float')
                            weather["rain_24h"] = getvalue(data, 'daily', 'float')
                        if "wind" in datapayload:
                            data = datapayload["wind"]
                            weather["wind_speed"] = getvalue(data, 'wind_speed', 'float')
                            weather["wind_deg"] = getvalue(data, 'wind_direction', 'int')
                            weather["wind_gust"] = getvalue(data, 'wind_gust', 'float')
                        if "pressure" in datapayload:
                            data = datapayload["pressure"]
                            weather["pressure"] = getvalue(data, 'absolute', 'float')
                        if "co2_aqi_combo" in datapayload:
                            data = datapayload["co2_aqi_combo"]
                            weather["co2"] = getvalue(data, 'co2', 'int')
                        if "pm25_aqi_combo" in datapayload:
                            data = datapayload["pm25_aqi_combo"]
                            weather["pm25"] = getvalue(data, 'pm25', 'int')
                            weather["pm25aqi"] = getvalue(data, 'real_time_aqi', 'int')
                        if "pm10_aqi_combo" in datapayload:
                            data = datapayload["pm10_aqi_combo"]
                            weather["pm10"] = getvalue(data, 'pm10', 'int')
                            weather["pm10aqi"] = getvalue(data, 'real_time_aqi', 'int')
                    except:
                        log.debug("Data error in payload from Ecowitt")
                        pass

                    log.debug("Weather data loaded")
                    LOADED = True

                    if INFLUX:
                        log.debug("Writing to InfluxDB")
                        try:
                            if ITOKEN == "":
                                # Influx 1.8
                                client = InfluxDBClient(host=IHOST,
                                    port=IPORT,
                                    username=IUSER,
                                    password=IPASS,
                                    database=IDB)
                            else:
                                # Influx 2.x
                                client = InfluxDBClient(
                                    url=IURL,
                                    token=ITOKEN,
                                    org=IORG)
                            output = [{}]
                            output[0]["measurement"] = IFIELD
                            output[0]["time"] = int(currentts)
                            output[0]["fields"] = {}
                            for i in weather:
                                output[0]["fields"][i] = weather[i]
                            log.debug(output)
                            # print(output)
                            write_api = client.write_api(write_options=SYNCHRONOUS)
                            write_api.write(IDB,IORG,output)
                            serverstats['influxdb'] += 1
                            client.close()
                        except:
                            log.debug("Error writing to InfluxDB")
                            sys.stderr.write("! Error writing to InfluxDB\n")
                            serverstats['influxdberrors'] += 1
                            pass
                else:
                    # showing the error message
                    log.debug("Bad response from Ecowitt")
                    sys.stderr.write("! Bad response from Ecowitt\n")
            except:
                log.debug("Error fetching Ecowitt")
                sys.stderr.write("! Error fetching Ecowitt\n")
                pass
        time.sleep(5)
    sys.stderr.write('\r ! fetchWeather Exit\n')

class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    pass

class handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        if DEBUGMODE:
            sys.stderr.write("%s - - [%s] %s\n" %
                         (self.address_string(),
                          self.log_date_time_string(),
                          format%args))
        else:
            pass

    def address_string(self):
        # replace function to avoid lookup delays
        host, hostport = self.client_address[:2]
        return host

    def do_GET(self):
        global weather, LOADED, URL
        self.send_response(200)
        message = "Error"
        contenttype = 'application/json'
        result = {}  # placeholder
        if self.path == '/':
            # Display friendly intro
            contenttype = 'text/html'
            message = '<html>\n<head><meta http-equiv="refresh" content="5" />\n'
            message += '<style>p, td, th { font-family: Helvetica, Arial, sans-serif; font-size: 10px;}</style>\n' 
            message += '<style>h1 { font-family: Helvetica, Arial, sans-serif; font-size: 20px;}</style>\n' 
            message += '</head>\n<body>\n<h1>LocalWeather Server v%s</h1>\n\n' % BUILD
            if not LOADED:
                message = message + "<p>Error: No weather data available</p>"
            else:
                message = message + '<table>\n<tr><th align ="right">Current</th><th align ="right">Value</th></tr>'
                for i in weather:
                    message = message + '<tr><td align ="right">%s</td><td align ="right">%s</td></tr>\n' % (i, weather[i])
                message = message + "</table>\n"
            message = message + '<p>Last data update: %s<br><font size=-2>From URL: %s</font></p>' % (
                str(datetime.fromtimestamp(int(weather['dt']))), URL)
            message = message + '\n<p>Page refresh: %s</p>\n</body>\n</html>' % (
                str(datetime.fromtimestamp(time.time())))
        elif self.path == '/stats':
            # Give Internal Stats
            serverstats['ts'] = int(time.time())
            serverstats['mem'] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
            message = json.dumps(serverstats)
        elif self.path == '/json' or self.path == '/all':
            message = json.dumps(weather)
        elif self.path == '/raw':
            message = json.dumps(raw)
        elif self.path == '/time':
            ts = time.time()
            result["local_time"] = str(datetime.fromtimestamp(ts))
            result["ts"] = ts
            result["utc"] = str(datetime.utcfromtimestamp(ts)) 
            message = json.dumps(result)
        elif self.path == '/temp':
            result["temperature"] = weather["temperature"]
            message = json.dumps(result)            
        elif self.path in ["/temperature","/humidity","/pressure","/feels_like","/app_temp","/dew_point"]:
            i = self.path.split("/")[1]
            result[i] = weather[i]
            message = json.dumps(result)
        elif self.path == '/wind':
            result["wind_speed"] = weather['wind_speed']
            result["wind_deg"] = weather['wind_deg']
            result["wind_gust"] = weather['wind_gust']
            message = json.dumps(result)
        elif self.path == '/solar':
            result["solar"] = weather['solar']
            message = json.dumps(result)
        elif self.path == '/uvi':
            result["uvi"] = weather['uvi']
            message = json.dumps(result)
        elif self.path == '/indoor':
            result["inside_temp"] = weather["inside_temp"]
            result["inside_humidity"] = weather["inside_humidity"]
            message = json.dumps(result)            
        elif self.path == '/aqi':
            result["pm25"] = weather['pm25']
            result["pm25aqi"] = weather['pm25aqi']
            result["pm10"] = weather['pm10']
            result["pm10aqi"] = weather['pm10aqi']            
            result["co2"] = weather['co2']
            message = json.dumps(result)            
        elif self.path in ['/rain', '/precipitation']:
            result["rain_1h"] = weather['rain_1h']
            result["rain_24h"] = weather['rain_24h']
            message = json.dumps(result)
        else:
            # Error
            message = "Error: Unsupported Request"

        # Counts 
        if "Error" in message:
            serverstats['errors'] = serverstats['errors'] + 1
        else:
            if self.path in serverstats["uri"]:
                serverstats["uri"][self.path] += 1
            else:
                serverstats["uri"][self.path] = 1
        serverstats['gets'] = serverstats['gets'] + 1

        # Send headers and payload
        self.send_header('Content-type',contenttype)
        self.send_header('Content-Length', str(len(message)))
        self.end_headers()
        self.wfile.write(bytes(message, "utf8"))

def api(port):
    """
    API Server - Thread to listen for commands on port 
    """
    sys.stderr.write(" + apiServer thread - Listening on http://localhost:%d\n" % port)

    with ThreadingHTTPServer(('', port), handler) as server:
        try:
            # server.serve_forever()
            while running:
                server.handle_request()
        except:
            print(' CANCEL \n')
    sys.stderr.write('\r ! apiServer Exit\n')

# MAIN Thread
if __name__ == "__main__":
    # Create threads
    thread_fetchWeather = threading.Thread(target=fetchWeather)
    thread_api = threading.Thread(target=api, args=(APIPORT,))
    
    # Print header
    sys.stderr.write("LocalWeather Server [%s]\n" % (BUILD))
    sys.stderr.write("* Configuration Loaded [%s]\n" % CONFIGFILE)
    sys.stderr.write(" + LocalWeather - Debug: %s, Activate API: %s, API Port: %s\n" 
        % (DEBUGMODE, API, APIPORT))
    sys.stderr.write(" + Ecowitt - Key: %s, Wait: %s, Units: %s\n + Ecowitt - App: %s, Timeout: %s\n"
        % (ECOKEY, ECOWAIT, ECOUNITS, ECOAPP, TIMEOUT))
    sys.stderr.write(" + InfluxDB - Enable: %s, Host: %s, Port: %s, DB: %s, Field: %s\n"
        % (INFLUX, IHOST, IPORT, IDB, IFIELD))
    
    # Start threads
    sys.stderr.write("* Starting threads\n")
    thread_fetchWeather.start()
    thread_api.start()
    sys.stderr.flush()
    
    if CLI:
        print("   %15s | %4s | %8s | %8s | %5s | %10s" %
            ('timezone','Temp','Humidity','Pressure','Cloud','Visibility') )
    try:
        while(True):
            if CLI:
                # weather report
                print(" %4d | %8d | %8d " %
                    (weather['temperature'], 
                    weather['humidity'], weather['pressure']),
                    end='\r')
            time.sleep(2)
    except (KeyboardInterrupt, SystemExit):
        running = False
        # Close down API thread
        requests.get('http://localhost:%d/stop' % APIPORT)
        print("\r", end="")

    sys.stderr.write("* Stopping\n")
    sys.stderr.flush()
