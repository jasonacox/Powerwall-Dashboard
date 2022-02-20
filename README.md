# Powerwall-Dashboard

Monitoring Dashboard for the Tesla Powerwall using Grafana, InfluxDB and Telegraf.

![Dashboard](https://user-images.githubusercontent.com/836718/144769680-78b8abf4-4336-4672-9483-896b0476ec44.png)
![Strings](https://user-images.githubusercontent.com/836718/146310511-7863e4bb-7e43-40b9-9790-65c1d6ce24ba.png)

This is based on the great work by [mihailescu2m](https://github.com/mihailescu2m/powerwall_monitor) but has been modified to use pypowerwall as a proxy to the Powerwall and includes solar String graphs for Powerwall+ systems.

## Requirements

The host system will require:

* docker
* docker-compose

## Setup

Clone this repo to your local host that will run the dashboard:

```bash
    git clone https://github.com/jasonacox/Powerwall-Dashboard.git
```

## Option 1 - Quick Start

Run the interactive setup script that will ask you for your Powerwall details and Time Zone data.

```bash
    ./setup.sh
```

Jump to the **Grafana Setup** below to complete the setup.

## Option 2 - Manual Install

If you prefer, you can perform the same steps that `setup.sh` performs.

You will want to set your local timezone by editing `powerwall.yml`, `influxdb.sql` and `dashboard.json` or you can use this handy `tz.sh` update script.  A list of timezones is available [here](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones).

```bash
  # Replace with your timezone
  bash tz.sh "America/Los_Angeles"
```

### Docker Containers

* Edit `powerwall.yml` and look for the section under `pypowerall` and update the following details for your Powerwall:

```yml
            PW_PASSWORD: "password"
            PW_EMAIL: "email@example.com"
            PW_HOST: "192.168.91.1"
            PW_TIMEZONE: "America/Los_Angeles"
            PW_DEBUG: "yes"

```

* Start the docker containers

```bash
    docker-compose -f powerwall.yml up -d
```

### InfluxDB

* Connect to the Influx database to import setup commands: 

```bash
    docker exec -it influxdb influx -import -path=/var/lib/influxdb/influxdb.sql
```

Note: the influxdb.sql file is set to use `America/Los_Angeles` as timezone. Use the `tz.sh` script or manually update the database commands above to replace `America/Los_Angeles` with your own timezone.

## Grafana Setup

* Open up Grafana in a browser at `http://<server ip>:9000` and login with `admin/admin`

* From `Configuration\Data Sources` add `InfluxDB` database with:
  - Name: `InfluxDB`
  - URL: `http://influxdb:8086`
  - Database: `powerwall`
  - Min time interval: `5s`
  - Click "Save & test" button

* From `Configuration\Data Sources` add `Sun and Moon` database with:
  - Name: `Sun and Moon`
  - Enter your latitude and longitude. You can use this [web page](https://jasonacox.github.io/Powerwall-Dashboard/location.html) to find your GPS location if you don't know).
  - Click "Save & test" button

* From `Dashboard\Manage` (or `Dashboard\Browse`), select `Import`, and upload `dashboard.json`

### Notes

* The database queries and dashboard are set to use `America/Los_Angeles` as the timezone. Remember to edit the database commands [influxdb.sql](influxdb/influxdb.sql), [powerwall.yml](powerwall.yml), and [dashboard.json](dashboard.json) to replace `America/Los_Angeles` with your own timezone.

* InfluxDB does not run reliably on older models of Raspberry Pi, resulting in the Docker container terminating with `error 139`.  

### Troubleshooting Tips and Tricks

Check the logs of the services using:

```bash
    docker logs -f pypowerwall
    docker logs -f telegraf
    docker logs -f influxdb
    docker logs -f grafana
```

#### Missing String data?

* String data only shows up for Tesla inverters as part of the Powerwall+ systems.  Unfortunately, non-Tesla inverter data is not available via the Tesla API. If you find a way to pull this data, please submit an Issue or Pull Request to get it added.
* The default dashboard and InfluxDB setup supports up to 3 Tesla Powerwall+ inverters. Support for more can be added by editing the [dashboard.json](dashboard.json) and [influxdb.sql](influxdb.sql) files. Open an Issue and we can help (see [#2](https://github.com/jasonacox/Powerwall-Dashboard/issues/2)).

#### Tips and Tricks

Since [pyPowerwall proxy](https://github.com/jasonacox/pypowerwall/tree/main/proxy) is part of this dashboard stack, you can query it to get raw data (read only) from the Powerwall API.  This includes some aggregate functions you might find useful for other projects.  I use this for [ESP32 driven display](https://github.com/jasonacox/Powerwall-Display) for example. Replace localhost with the address of the system running the dashboard:

* pyPowerwall stats: http://localhost:8675/stats
* Powerwall firmware version and uptime: http://localhost:8675/api/status
* Powerwall temperatures: http://localhost:8675/temps
* Powerwall device vitals: http://localhost:8675/vitals
* Powerwall strings: http://localhost:8675/strings
* Powerwall battery level: http://localhost:8675/soe
* Key power data in CSV format (grid, home, solar, battery, batterylevel): http://localhost:8675/csv

### Credits

* This is based on the great work by mihailescu2m at [https://github.com/mihailescu2m/powerwall_monitor](https://github.com/mihailescu2m/powerwall_monitor).
* Grafana at https://github.com/grafana/grafana 
* Telegraf at https://github.com/influxdata/telegraf
* InfluxDB at https://github.com/influxdata/influxdb
* pyPowerwall at https://github.com/jasonacox/pypowerwall
