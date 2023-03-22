# InfluxDB 2.x Support

This includes optionals files and instructions to help setup InfluxDB 2.x (instead of 1.8) as the database for the Dashboard. Thanks to @ThePnuts for developing the many flux queries required to replace the 1.8 version continuous queries as well as the Grafana queries in the dashboard.json.

## Instructions

* Containers (setup)
  * I am using the latest official containers provided by influxdata, GrafanaLabs and jasonacox
    * [Influxdb 2.x](https://hub.docker.com/_/influxdb/)
    * [Grafana](https://hub.docker.com/r/grafana/grafana/)
    * [Telegraf](https://hub.docker.com/_/telegraf/)
    * [pyPowerwall](https://hub.docker.com/r/jasonacox/pypowerwall/)
    * [weather411](https://hub.docker.com/r/jasonacox/weather411/)
* InfluxDB 2.x setup
  * Docker Container options (configure ports and path for your local host)
    * Port: 8083 and 8086 (So its accessible)
    * Host Path: /var/lib/influxdb (So your databases are not stored in the container)
  * Configure
    * If this is your first time, connect to http://localhost:8086/ and follow walk through to create initial oreganization and admin user
    * Plan to either use an existing organization or create one
    * Within the organization create the following buckets within this organization.
      * raw_weather (For raw weather data from weather411)
      * raw_tesla_energy (For raw data from PyPowerwall)
      * tesla_energy (For aggregate date from raw_tesla_energy, also primary source for tesla data on the dashboard)
    * Generate the following API tokens. Each a sperate tokens unless specified together. API tokens are only displayed at creatiion and need to be recreated if lost.
      * Write
        * raw_weather (for weather 411)
        * raw_tesla_energy (for Telegraf capturing pyPowerwall)
      * Read
        * raw_weather and tesla_energy (for Grafana to access data)
* Weather411 setup for influxDB 2.x
  * Docker Container options (configure ports and path for your local host)
* pyPowerwall setup
  * Docker Container options (configure ports and path for your local host)
* Telegraf setup
  * Docker Container options (configure ports and path for your local host)
* Grafana
  * Docker Container options (configure ports and path for your local host)
* Dashboard

## Discussion Link

Join discussion [#198](https://github.com/jasonacox/Powerwall-Dashboard/discussions/198).
