# Weather Service

This folder contains tools to add current local weather data to your Powerwall Dashboard. 
* Weather411 - This script uses OpenWeatherMap to determine your area weather. The details are below.
* Community Contributed - If you have your own local weather station or want to add another weather service, there is a way to add that data as well. See the example [Ecowitt service](https://github.com/jasonacox/Powerwall-Dashboard/tree/main/weather/contrib/ecowitt) by @BJReplay in the [contrib/](https://github.com/jasonacox/Powerwall-Dashboard/tree/main/weather/contrib) folder.

## Weather411 Server

![Docker Pulls](https://img.shields.io/docker/pulls/jasonacox/weather411)

This server pulls current weather data from [OpenWeatherMap.org](https://openweathermap.org/), makes it available via local API calls and stores the data in InfluxDB for graphing.

This service was built to easily add weather data graphs to the [Powerwall-Dashboard](https://github.com/jasonacox/Powerwall-Dashboard) project.

Docker: docker pull [jasonacox/weather411](https://hub.docker.com/r/jasonacox/weather411)

## Quick Start

1. Create a `weather411.conf` file (`cp weather411.conf.sample weather411.conf`) and update with your specific location details:

    * Enter your OpenWeatherMap API Key (APIKEY) You can get a free account and key at [OpenWeatherMap.org](https://openweathermap.org/). 
    * Enter your GPS Latitude (LAT) and Longitude (LON).  To get your location, you can use [this tool](https://jasonacox.github.io/Powerwall-Dashboard/location.html).

    ```python
    [Weather411]
    DEBUG = no

    [API]
    # Port to listen on for requests (default 8676)
    ENABLE = yes
    PORT = 8676

    [OpenWeatherMap]
    # Register and get APIKEY from OpenWeatherMap.org
    APIKEY = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    # Enter your location in latitude and longitude 
    LAT = xxx.xxxx
    LON = yyy.yyyy
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
    # Auth - Leave blank if not used
    USERNAME =
    PASSWORD =
    # Influx 2.x - Leave blank if not used
    TOKEN =
    ORG =
    URL =
    ```

2. Run the Docker Container to listen on port 8676.

    ```bash
    docker run \
    -d \
    -p 8676:8676 \
    -e WEATHERCONF='/var/lib/weather/weather411.conf' \
    -v ${PWD}:/var/lib/weather \
    --name weather411 \
    --restart unless-stopped \
    --net=host \
    jasonacox/weather411
    ```

3. Test the API Service

    Website of Current Weather: http://localhost:8676/

    ```bash
    # Get Current Weather Data
    curl -i http://localhost:8676/temp
    curl -i http://localhost:8676/all
    curl -i http://localhost:8676/conditions

    # Get Proxy Stats
    curl -i http://localhost:8676/stats

    # Clear Proxy Stats
    curl -i http://localhost:8676/stats/clear
    ```

## Build Your Own

This folder contains the `server.py` script that runs a multi-threaded python based API webserver.  

The `Dockerfile` here will allow you to containerize the proxy server for clean installation and running.

1. Build the Docker Container

    ```bash
    # Build for local architecture  
    docker build -t weather411:latest .

    # Build for all architectures - requires Docker experimental 
    docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -t weather411:latest . 

    ```

2. Setup the Docker Container to listen on port 8676.

    ```bash
    docker run \
    -d \
    -p 8676:8676 \
    -e WEATHERCONF='/var/lib/weather/weather411.conf' \
    --name weather411 \
    -v ${PWD}:/var/lib/weather \
    --restart unless-stopped \
    --net=host \
    weather411
    ```

3. Test the API

    ```bash
    curl -i http://localhost:8676/temp
    curl -i http://localhost:8676/stats
    ```

    Browse to http://localhost:8676/ to see current weather conditions.


## Troubleshooting Help

If you see python errors, make sure you entered your credentials correctly in `docker run`.

```bash
# See the logs
docker logs weather411

# Stop the server
docker stop weather411

# Start the server
docker start weather411
```

## Release Notes

### 0.2.1 - Bug Fix for User/Pass

* Fix access to InfluxDB where username and password and configured and required.  Impacts by InfluxDB v1 and v2. Issue reported by @sumnerboy12 in #199.

### 0.2.0 - Upgrade InfluxDB Client

* Upgrade end of life `influxdb` client library to `influxdb-client` (refer discussion #191 and issue #195), providing support for InfluxDB 1.8 and 2.x.

### 0.1.2 - Snow and Rain Data

* Fix rain and snow values not being retrieved (refer issue #42) by @mcbirse (PR #69)

### 0.1.1 - Error Handling

* Added additional error handling for pulling and processing OpenWeatherMap data.

### 0.1.0 - Free Weather API Update

* Moved from OpenWeatherMap /data/2.5/onecall to free /data/2.5/weather URI (see #51)

### 0.0.5 - Dockerized

* Set up to run in docker and incorporated into Powerwall-Dashboard.

### 0.0.1 - Initial Release

* Initial Release
