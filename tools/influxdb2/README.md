# InfluxDB 2.x Support

This includes optionals files and instructions to help setup InfluxDB 2.x (instead of 1.8) as the database for the Dashboard. Thanks to @ThePnuts for developing the many flux queries required to replace the 1.8 version continuous queries as well as the Grafana queries in the dashboard.json.

# Instructions

## Container Setup
* I am using the latest official containers provided by InfluxData, GrafanaLabs and jasonacox
  * [Influxdb 2.x](https://hub.docker.com/_/influxdb/)
  * [Grafana](https://hub.docker.com/r/grafana/grafana/)
  * [Telegraf](https://hub.docker.com/_/telegraf/)
  * [pyPowerwall](https://hub.docker.com/r/jasonacox/pypowerwall/)
  * [weather411](https://hub.docker.com/r/jasonacox/weather411/)
* InfluxDB 2.x container
  * Docker container options (configure ports and path for your local host)
    * Port: 8083 and 8086 (So its accessible)
    * Host Path: /var/lib/influxdb to wherever you want TO store your databases and config (So your databases are not stored in the container)
* Weather411 container
  * Docker container options (configure ports, variables and paths for your local host)
    * Port: 8676 (So its accessible)
    * Variable: WEATHERCONF | /var/lib/weather/weather411.conf (So your container expects it there)
    * Host Path: /var/lib/weather/weather411.conf TO wherever you create the weather.411.conf file (So your config file is outside of your container)
* pyPowerwall container
  * Docker container options (configure ports and variables for your local host)
    * Port: 8675 (So its accessible)
    * Variable: PW_HOST | IP of Powerwall  (IP Address of your Powerwall)
    * Variable: PW_PORT | 8675  (Your Powerwall Port)
    * Variable: PW_EMAIL | something@else.com  (Your Powerwall account email)
    * Variable: PW_PASSWORD | Sup3rSecr3t  (Your Powerwall account password)
    * Variable: PW_TIMEZONE | America/Los_Angeles  (Variable for your powerwall timezone)
    * Variable: TZ | America/Los_Angeles  (Variable for local timezone)
    * Variable: PW_CACHE_EXPIRE | 5 (Variable for Powerwall Cache Expiration)
  * Test it: http://localhost:8675/aggregates
* Telegraf container
  * Docker container options (configure path for your local host)
    * Host Path: /etc/telegraf/telegraf.conf TO wherever you create the telegraf.conf file (So your config file is outside of your container)
* Grafana
  * Docker Container options (configure ports and path for your local host)
    * Port: 3000 (So its accessible)
    * Host Path: /var/lib/grafana TO wherever you want to store your Grafana config and plugins (So its not stored in the container)
    * Variable: GF_SERVER_ROOT_URL | http://xxx.xxx.xxx.xxx  (Your localhost IP)
    * Variable: GF_SECURITY_ADMIN_PASSWORD | Sup3rSecr3t  (admin account password)
    * Variable: GF_PATHS_CONFIG | /etc/grafana/grafana.ini  (location of config file within container)
    * Host Path: /etc/grafana/grafana.ini TO wherever you want to store your Grafana config (So its not stored in the container)
    
## Configure containers
* InfluxDB 2.x
  *Connect to http://localhost:8086/
  * Plan to either use an existing organization or create one. (An organization contains a collection of buckets (databases))
  * Within the organization create the following buckets (databases) within this organization.
    * raw_weather (For raw weather data from weather411)
      * This data is not aggregated, do not set a retention policy if you want to keep historical data
    * raw_tesla_energy (For raw data from PyPowerwall)
      * At this time not all data is aggregated, everything used for current reporting is aggregated to tesla_energy, set a retention policy respective of how much data you want to keep (its stored at 5s intervals from pyPowerwall)
    * tesla_energy (For aggregate date from raw_tesla_energy, also primary source for tesla data on the dashboard)
      * Aggregate data (@1m intervals) from raw_tesla_energy, do not set a retention policy if you want to keep historical data.
  * Generate the following API tokens. Each a sperate tokens unless specified together. API tokens are only displayed at creatiion and need to be recreated if lost.
    * Write
      * raw_weather (for weather 411)
      * raw_tesla_energy (for Telegraf capturing pyPowerwall)
    * Read
      * raw_weather and tesla_energy (for Grafana to access data)
  * Import Tasks
    * Import each of the tasks here: Powerwall-Dashboard/tools/influxdb2/flux-json/
      * These will likely error until data is populated into the database
* Weather411
  * Follow configuration steps in step 1 on the [weather411](https://hub.docker.com/r/jasonacox/weather411/) page.
    * Use the Influx 2.x details with the info you created above (Write API token for weather411, Orginization you created, URL for influx server you used above)
    * Make sure to update DB = powerwall to DB = raw_weather
    * This file is saved in the location you specified
* Telegraf
  * Edit telegraf.conf file with your server information and Write API token for raw_tesla_energy from above. Ensure it is saved where you specfied above.
* Grafana (http://IP:3000/)
  * grafana.ini
    * Get the sample file from: https://github.com/grafana/grafana/blob/main/conf/sample.ini
    * Save this file as grafana.ini in the location you specified
  * Allow html
    * In the grafana.ini file, find and edit:
      * ;disable_sanitize_html = false TO disable_sanitize_html = true
  * Add data sources in configuration
    * Enter the URL of your influxdb: http://IP:8086
    * Enter the Organization you created
    * Default Bucket: tesla_energy
  * Add plugins in configuration
    * Search for and isntall: Sun and Moon (By fetzerch)
  * Dashboard
    * Import grafana dashboard json file

## Discussion Link

Join discussion [#198](https://github.com/jasonacox/Powerwall-Dashboard/discussions/198).
