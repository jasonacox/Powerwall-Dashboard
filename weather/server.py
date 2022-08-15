#!/usr/bin/env python
# Weather411 - Current Weather Conditions
# -*- coding: utf-8 -*-
"""
 Python module to poll and store weather data from OpenWeatherMap

 Author: Jason A. Cox
 For more information see https://github.com/jasonacox/Powerwall-Dashboard

 Weather Data Tool
    This tool will poll current weather conditions using OpenWeatherMap
    and then make it available via local API calls or optionally store 
    it in InfluxDB.

    CONFIGURATION - On startup will look for a conf/weather411.conf file
    which includes the following parameters:

        [Weather411]
        DEBUG = no

        [API]
        # Port for API requests (default 8676)
        ENABLE = yes
        PORT = 8676

        [OpenWeatherMap]
        # Register and get APIKEY from OpenWeatherMap.org
        APIKEY = xxxxxxxxxxxxxxxxxxxxxxxxxxxxx
        LAT = xx.xxxx
        LON = xx.xxxx
        WAIT = 10
        TIMEOUT = 10
        # standard, metric or imperial 
        UNITS = metric

        [InfluxDB]
        # Record data in InfluxDB server 
        ENABLE = yes
        HOST = influxdb
        PORT = 8086
        DB = powerwall
        FIELD = weather

    The API service of Weather411 has the following functions:
        /           - Human friendly display of current weather conditions
        /json       - All current weather data in JSON format
        /temp       - Current temperature in C
        /humidity   - Current humidity in %
        /pressure   - Current pressure in hPa
        /visibility - Current visibility in meters (max = 10k)
        /wind       - Current speed (m/s), gust (m/s) and direction (degree)
        /clouds     - Cloudiness in %
        /rain       - Rain volume in mm (last hour / 3 hour) 
        /time       - Current time in UTC
        /conditions - Current weather conditions (e.g. Clear)

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
from influxdb import InfluxDBClient

BUILD = "0.0.5"
CLI = False
LOADED = False
CONFIG_LOADED = False
CONFIGFILE = os.getenv("WEATHERCONF", "weather411.conf")

# Load Configuration File
config = configparser.ConfigParser(allow_no_value=True)
if os.path.exists(CONFIGFILE):
    config.read(CONFIGFILE)
    DEBUGMODE = config["Weather411"]["DEBUG"].lower() == "yes"

    # Weather411 API
    API = config["API"]["ENABLE"].lower() == "yes"
    APIPORT = int(config["API"]["PORT"])

    # OpenWeatherMap
    OWKEY = config["OpenWeatherMap"]["APIKEY"]
    OWWAIT = int(config["OpenWeatherMap"]["WAIT"])
    OWUNITS = config["OpenWeatherMap"]["UNITS"]
    OWLAT = str(config["OpenWeatherMap"]["LAT"])
    OWLON = str(config["OpenWeatherMap"]["LON"])
    TIMEOUT = int(config["OpenWeatherMap"]["TIMEOUT"])

    # InfluxDB
    INFLUX = config["InfluxDB"]["ENABLE"].lower() == "yes"
    IHOST = config["InfluxDB"]["HOST"]
    IPORT = int(config["InfluxDB"]["PORT"])
    IUSER = config["InfluxDB"]["USERNAME"]
    IPASS = config["InfluxDB"]["PASSWORD"]
    IDB = config["InfluxDB"]["DB"]
    IFIELD = config["InfluxDB"]["FIELD"]

else:
    # No config file - Display Error
    sys.stderr.write("Weather411 Server %s\nERROR: No config file. Fix and restart.\n" % BUILD)
    sys.stderr.flush()
    while(True):
        time.sleep(3600)

# Logging
log = logging.getLogger(__name__)
if DEBUGMODE:
    logging.basicConfig(format='%(levelname)s:%(message)s',level=logging.DEBUG)
    log.setLevel(logging.DEBUG)
    log.debug("Weather411 [%s]\n" % BUILD)

# Global Stats
serverstats = {}
serverstats['weather411'] = BUILD
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
    weather = {"dt": 0, "temperature": None, "humidity": None,
        "pressure": None, "clouds": None, "visibility": None,
        "timezone": None, "wind_speed": None, "wind_deg": None,
        "weather_id": None, "weather_main": None,
        "weather_description": None, "weather_icon": None,
        "rain1h": 0, "rain3h": 0, "sunrise": None, "sunset": None,
        "feels_like": None, "dew_point": None}


def lookup(source, index, valtype='string'):
    # check source dict to see if index key exists
    if index in source:
        if valtype == 'float':
            return float(source[index])
        if valtype == 'int':
            return int(source[index])            
        return str(source[index])
    return None

# Clear weather data
clearweather()

# Threads
def fetchWeather():
    """
    Thread to poll for current weather conditions
    """
    global running, weather, LOADED, raw, serverstats
    sys.stderr.write(" + fetchWeather thread\n")
    URL = "https://api.openweathermap.org/data/2.5/onecall"
    URL = URL + "?lat=" + OWLAT + "&lon=" + OWLON + "&units=" + OWUNITS
    URL = URL + "&exclude=minutely,hourly,daily&appid=" + OWKEY
    nextupdate = time.time()

    # Time Loop to update current weather data
    while(running):
        currentts = time.time()
        lastdt = weather["dt"]
        # Is it time for an update?
        if currentts >= nextupdate:
            nextupdate = currentts + (60 * OWWAIT)
            if CLI:
                print("\n")
            response = requests.get(URL)
            if response.status_code == 200:
                raw = response.json()
                clearweather()
                try:
                    if "current" in raw:
                        data = raw['current']
                        if 'dt' not in data or lastdt == data['dt']:
                            # Data didn't update - skip rest and loop
                            continue
                        weather["dt"] = data['dt']
                        weather["temperature"] = lookup(data, 'temp', 'float')
                        weather["humidity"] = lookup(data, 'humidity', 'int')
                        weather["pressure"] = lookup(data, 'pressure', 'int')
                        weather["clouds"] = lookup(data, 'clouds', 'int')
                        weather["visibility"] = lookup(data, 'visibility', 'int')
                        weather["wind_speed"] = lookup(data, 'wind_speed', 'float')
                        weather["wind_deg"] = lookup(data, 'wind_deg', 'int')
                        weather["wind_gust"] = lookup(data, 'wind_gust', 'float')
                        weather["uvi"] = lookup(data, 'uvi', 'float')
                        weather["sunrise"] = lookup(data, 'sunrise', 'int')
                        weather["sunset"] = lookup(data, 'sunset', 'int')
                        weather["feels_like"] = lookup(data, 'feels_like', 'float')
                        weather["dew_point"] = lookup(data, 'dew_point', 'float')
                        if "weather" in data and len(data["weather"]) > 0:
                            weather["weather_id"] = lookup(data["weather"][0], 'id', 'int')
                            weather["weather_main"] = lookup(data["weather"][0], 'main')
                            weather["weather_description"] = lookup(data["weather"][0], 'description')
                            weather["weather_icon"] = lookup(data["weather"][0], 'icon')
                    if "timezone" in raw:
                        weather["timezone"] = lookup(raw, 'timezone')
                    if "rain" in raw:
                        weather["rain1h"] = lookup(raw['rain'], 'rain.1h', 'float')
                        weather["rain3h"] = lookup(raw['rain'], 'rain.3h', 'float')
                    if "alerts" in raw and len(data["alerts"]) > 0:
                        weather["alert"] = lookup(raw['alerts'][0], 'event')
                except:
                    log.debug("Data error in payload from OpenWeatherMap")
                    pass

                log.debug("Weather data loaded")
                LOADED = True

                if INFLUX:
                    log.debug("Writing to InfluxDB")
                    try:
                        client = InfluxDBClient(host=IHOST,
                            port=IPORT,
                            username=IUSER,
                            password=IPASS,
                            database=IDB)
                        output = [{}]
                        output[0]["measurement"] = IFIELD
                        output[0]["time"] = weather["dt"]
                        output[0]["fields"] = {}
                        for i in weather:
                            output[0]["fields"][i] = weather[i]
                        # print(output)
                        if client.write_points(output, time_precision='s'):
                            serverstats['influxdb'] += 1
                        else:
                            serverstats['influxdberrors'] += 1
                        client.close()
                    except:
                        log.debug("Error writing to InfluxDB")
                        sys.stderr.write("! Error writing to InfluxDB\n")
                        serverstats['influxdberrors'] += 1
                        pass
            else:
                # showing the error message
                log.debug("Error reaching OpenWeatherMap")
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
        global weather, LOADED
        self.send_response(200)
        message = "Error"
        contenttype = 'application/json'
        result = {}  # placeholder
        if self.path == '/':
            # Display friendly intro
            contenttype = 'text/html'
            message = '<html>\n<head><meta http-equiv="refresh" content="5" />'
            message = message + '</head>\n<body>\n<h1>Weather411 Server v%s</h1>\n\n' % BUILD
            if not LOADED:
                message = message + "<p>Error: No weather data available</p>"
            else:
                message = message + '<table>\n<tr><th align ="right">Current</th><th align ="right">Value</th></tr>'
                for i in weather:
                    message = message + '<tr><td align ="right">%s</td><td align ="right">%s</td></tr>\n' % (i, weather[i])
                message = message + "</table>\n"
            message = message + '<p>Last update: %s</p>' % (
                str(datetime.datetime.fromtimestamp(weather['dt'])))
            message = message + '\n<p>Page refresh: %s</p>\n</body>\n</html>' % (
                str(datetime.datetime.fromtimestamp(time.time())))
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
            result["local_time"] = str(datetime.datetime.fromtimestamp(ts))
            result["ts"] = ts
            result["utc"] = str(datetime.datetime.utcfromtimestamp(ts)) 
            result["timezone"] = weather["timezone"]
            message = json.dumps(result)
        elif self.path == '/temp':
            result["temperature"] = weather["temperature"]
            message = json.dumps(result)            
        elif self.path in ["/temperature","/humidity","/pressure","/visibility",
                           "/clouds","/uvi","/sunrise","/sunset","/feels_like",
                           "/dew_point","/alerts"]:
            i = self.path.split("/")[1]
            result[i] = weather[i]
            message = json.dumps(result)
        elif self.path == '/wind':
            result["wind_speed"] = weather['wind_speed']
            result["wind_deg"] = weather['wind_deg']
            result["wind_gust"] = weather['wind_gust']
            message = json.dumps(result)
        elif self.path == '/rain':
            result["rain1h"] = weather['rain1h']
            result["rain3h"] = weather['rain3h']
            message = json.dumps(result)
        elif self.path == '/conditions' or self.path == '/weather':
            result["conditions"] = weather['weather_main']
            result["weather_description"] = weather['weather_description']
            result["weather_icon"] = weather['weather_icon']
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
    sys.stderr.write("Weather411 Server [%s]\n" % (BUILD))
    sys.stderr.write("* Configuration Loaded [%s]\n" % CONFIGFILE)
    sys.stderr.write(" + Weather411 - Debug: %s, Activate API: %s, API Port: %s\n" 
        % (DEBUGMODE, API, APIPORT))
    sys.stderr.write(" + OpenWeatherMap - Key: %s, Wait: %s, Units: %s\n   OpenWeatherMap - Lat: %s, Lon: %s, Timeout: %s\n"
        % (OWKEY, OWWAIT, OWUNITS, OWLAT, OWLON, TIMEOUT))
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
            if CLI and 'timezone' in weather and weather['timezone'] is not None:
                # weather report
                print("   %15s | %4d | %8d | %8d | %5d | %10d" %
                    (weather['timezone'], weather['temperature'], 
                    weather['humidity'], weather['pressure'], 
                    weather['cloudiness'], weather['visibility']),
                    end='\r')
            time.sleep(2)
    except (KeyboardInterrupt, SystemExit):
        running = False
        # Close down API thread
        requests.get('http://localhost:%d/stop' % APIPORT)
        print("\r", end="")

    sys.stderr.write("* Stopping\n")
    sys.stderr.flush()
