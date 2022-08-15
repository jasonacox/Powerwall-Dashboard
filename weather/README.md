# Weather411 Server

![Docker Pulls](https://img.shields.io/docker/pulls/jasonacox/weather411)

This server pulls current weather data from [OpenWeatherMap.org](https://openweathermap.org/), makes it available via local API calls and stores the data in InfluxDB for graphing.

This service was built to easily add weather data graphs to the [Powerwall-Dashboard](https://github.com/jasonacox/Powerwall-Dashboard) project.

Docker: docker pull [jasonacox/weather411](https://hub.docker.com/r/jasonacox/weather411)

## Quick Start

1. Run the Docker Container to listen on port 8676. Update the `-e` values for your Powerwall.

    ```bash
    docker run \
    -d \
    -p 8676:8676 \
    -e WEATHERCONF='/var/lib/weather/weather411.conf' \
    -v ${PWD}:/var/lib/weather \
    --name weather411 \
    --restart unless-stopped \
    jasonacox/weather411
    ```

2. Test the Proxy

    ```bash
    # Get Powerwall Data
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

### 0.0.5 - Dockerized

* Set up to run in docker and incorporated into Powerwall-Dashboard.

### 0.0.1 - Initial Release

* Initial Release
