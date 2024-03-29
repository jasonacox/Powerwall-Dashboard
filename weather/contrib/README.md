# User Contributed Weather Services

This folder contains user contributed weather service tools to help import local weather information into the Powerwall Dashboard.

## Ecowitt

This server pulls current weather data from [Ecowitt.net Weather API](https://api.ecowitt.net/api/v3/device/real_time), makes it available via local API calls and stores the data in InfluxDB for graphing.

* [Instructions](https://github.com/jasonacox/Powerwall-Dashboard/tree/main/weather/contrib/ecowitt#ecowitt-local-weather-server) 
* Author: [@BJReplay](https://github.com/BJReplay)
* Docker: docker pull [jasonacox/ecowitt](https://hub.docker.com/r/jasonacox/ecowitt)

### Discussion Link
Please refer to discussion [#145](https://github.com/jasonacox/Powerwall-Dashboard/discussions/145) if you have any questions or find problems.

## Submit Your Own

We welcome new contributions!
Follow the example in Ecowitt.
