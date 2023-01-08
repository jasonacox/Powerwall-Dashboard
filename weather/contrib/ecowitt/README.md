# localweather Server

![Docker Pulls](https://img.shields.io/docker/pulls/jasonacox/localweather)

This server pulls current weather data from [Ecowitt.net Weather API](https://api.ecowitt.net/api/v3/device/real_time), makes it available via local API calls and stores the data in InfluxDB for graphing.

This service was built to easily add weather data graphs to the [Powerwall-Dashboard](https://github.com/jasonacox/Powerwall-Dashboard) project.

Docker: docker pull [jasonacox/localweather](https://hub.docker.com/r/jasonacox/localweather)

## Quick Start


1. Create a `localweather.conf` file (`cp localweather.conf.sample localweather.conf`) and update with your specific location details:

    * Enter your OpenWeatherMap API Key (APIKEY and APPLICATION KEY). Set your APIKEY and APPLICATION_KEY from your [Ecowitt User Page](https://www.ecowitt.net/user/index). 
    * Enter your Device MAC Address (MAC).

    ```python
    [LocalWeather]
    DEBUG = no

    [API]
    # Port to listen on for requests (default 8686)
    ENABLE = yes
    PORT = 8686 # Different Port to Weather 411 so they can co-exist

    [Ecowitt]
    # Set your APIKEY and APPLICATION_KEY from https://www.ecowitt.net/user/index
    APIKEY = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    APPLICATION_KEY = XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

    # Set the MAC address for the specific station you want to query
    MAC = 01:23:45:67:89:AB

    WAIT = 1
    TIMEOUT = 10

    # standard, metric or imperial 
    UNITS = metric

    [InfluxDB]
    # Record data in InfluxDB server 
    ENABLE = yes
    HOST = influxdb
    PORT = 8086
    DB = powerwall
    FIELD = localweather
    # Leave blank if not used
    USERNAME = 
    PASSWORD =

2. Run the Docker Container to listen on port 8686.

    ```bash
    docker run \
    -d \
    -p 8686:8686 \
    -e WEATHERCONF='/var/lib/weather/localweather.conf' \
    -v ${PWD}:/var/lib/weather \
    --name localweather \
    --restart unless-stopped \
    jasonacox/localweather
    ```

3. Test the API Service

    Website of Current Weather: http://localhost:8686/

    ```bash
    # Get Current Weather Data
    curl -i http://localhost:8686/temp
    curl -i http://localhost:8686/all
    curl -i http://localhost:8686/conditions

    # Get Proxy Stats
    curl -i http://localhost:8686/stats

    # Clear Proxy Stats
    curl -i http://localhost:8686/stats/clear
    ```

## Build Your Own

This folder contains the `server.py` script that runs a multi-threaded python based API webserver.  

The `Dockerfile` here will allow you to containerize the proxy server for clean installation and running.

1. Build the Docker Container

    ```bash
    # Build for local architecture  
    docker build -t localweather:latest .

    # Build for all architectures - requires Docker experimental 
    docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -t localweather:latest . 

    ```

2. Setup the Docker Container to listen on port 8686.

    ```bash
    docker run \
    -d \
    -p 8686:8686 \
    -e WEATHERCONF='/var/lib/weather/localweather.conf' \
    --name localweather \
    -v ${PWD}:/var/lib/weather \
    --restart unless-stopped \
    localweather
    ```

3. Test the API

    ```bash
    curl -i http://localhost:8686/temp
    curl -i http://localhost:8686/stats
    ```

    Browse to http://localhost:8686/ to see current weather conditions.


## Troubleshooting Help

If you see python errors, make sure you entered your credentials correctly in `docker run`.

```bash
# See the logs
docker logs localweather

# Stop the server
docker stop localweather

# Start the server
docker start localweather
```

## Release Notes


### 0.0.2 - First Release 

* Made as similar as possible to Weather411

### 0.0.1 - Initial Build

* Initial Release
