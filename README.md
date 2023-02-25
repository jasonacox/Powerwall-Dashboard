# Powerwall-Dashboard

Monitoring Dashboard for the Tesla Powerwall using Grafana, InfluxDB, Telegraf and pyPowerwall.

![Animation](https://user-images.githubusercontent.com/13752647/198901193-6f5d3f34-3ef6-4d6d-95ff-892a3763541b.png)
![Monthly](https://user-images.githubusercontent.com/836718/214475577-2a633228-4db0-41b8-8738-51642222f462.png)
![Yearly](https://user-images.githubusercontent.com/836718/214475014-4ba090dd-bca8-475f-bbdc-6d80ad5afbb0.png)
![Powerwall+](https://user-images.githubusercontent.com/836718/214475810-bc5748fd-5a6f-4fd7-869b-88ba3f06346c.png)
![FreqVoltage](https://user-images.githubusercontent.com/836718/214475204-d049c0c8-1b2c-4fb7-b015-0a638a33adde.png)
![Alerts](https://user-images.githubusercontent.com/836718/214474307-9c85de97-3730-4e2c-a4a1-0173be3e0ea1.png)
![Weather](https://user-images.githubusercontent.com/836718/214474825-75686470-03a9-41cc-b827-f54dc323f93e.png)

## Dashboards

The default [dashboard.json](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/dashboard-animation.json) shown above, pulls in the live power flows from the Powerwall web portal and embeds that animation in the Grafana dashboard.

A non-animated version of the dashboard is also available using [dashboard-no-animation.json](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/dashboards/dashboard-no-animation.json)

![Dashboard](https://user-images.githubusercontent.com/13752647/155657200-4309306d-84c1-40b7-8f4c-32ef0e8d2efe.png)

## Requirements

The host system will require:

* docker ([install help](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/tools/DOCKER.md))
* docker-compose (works with docker compose (v2) as well)
* You should not need to run `sudo` to install this tool. See [Docker Errors](https://github.com/jasonacox/Powerwall-Dashboard#docker-errors) below for help.
* TCP ports: 8086 (InfluxDB), 8675 (pyPowerwall), and 9000 (Grafana)

## Setup

Clone this repo on the host that will run the dashboard:

```bash
    git clone https://github.com/jasonacox/Powerwall-Dashboard.git
```

## Option 1 - Quick Start

Run the interactive setup script that will ask you for your Powerwall details and Local Time Zone ([options](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)).

  ```bash
    cd Powerwall-Dashboard
    ./setup.sh
  ```

  * _If you get docker errors during the setup, see the [Docker Errors](https://github.com/jasonacox/Powerwall-Dashboard#docker-errors) section below._
  * _For Windows 11 users, see the [Windows 11 Instructions](https://github.com/jasonacox/Powerwall-Dashboard#windows-11-instructions) below._

Follow the **[Grafana Setup](https://github.com/jasonacox/Powerwall-Dashboard#grafana-setup)** instructions provided (or see below) to complete the setup.
 
 
## Option 2 - Manual Install

If you prefer, you can perform the same steps that `setup.sh` performs.

Note: some manual configuration is required if you are running a non-standard docker installation (e.g. rootless). Also, ensure that the `conf`, `env` and `sql` files are readable by the docker services (e.g. `chmod 644`).

You will want to set your local timezone by editing `pypowerwall.env`, `telegraf.conf`, `influxdb.sql` and `dashboard.json` or you can use this handy `tz.sh` update script.  A list of timezones is available [here](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones).

  ```bash
    # Replace with your timezone
    bash tz.sh "America/Los_Angeles"
  ```

### Docker Containers

* Copy `pypowerwall.env.sample` to `pypowerwall.env` and update the following details for your Powerwall:

  ```bash
      PW_EMAIL=email@example.com
      PW_PASSWORD=password
      PW_HOST=192.168.91.1
      PW_TIMEZONE=America/Los_Angeles
      PW_DEBUG=no
  ```

* Copy `compose.env.sample` to `compose.env` - you do not need to edit these defaults unless you are running a non-standard install such as docker rootless.

* Copy `telegraf.local.sample` to `telegraf.local`. If you want to monitor custom measurements for your site (most users don't need this), add the required telegraf.conf TOML entries to this file. Once created, this file is not overwritten by upgrades or future runs of setup.sh. 

* Copy `grafana.env.sample` to `grafana.env` - you do not need to edit these defaults. However, there are optional settings for alert notifications and HTTPS.

* Optional: If you want to pull in local weather data, copy `weather/weather411.conf.sample` to `weather/weather411.conf` and edit the file to include your location ([Latitude and Longitude](https://jasonacox.github.io/Powerwall-Dashboard/location.html)) and your OpenWeatherMap API Key. To get a Key, you need to set up a free account at [openweathermap.org](https://home.openweathermap.org/users/sign_up). Make sure you check your email to verify account. API keys can take a few hours to activate.

  ```conf
      [OpenWeatherMap]
      # Register and get APIKEY from OpenWeatherMap.org
      APIKEY = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      # Enter your location in latitude and longitude 
      LAT = xxx.xxxx
      LON = yyy.yyyy
  ```

* Start the docker containers with the utility docker-compose script

  ```bash
    ./compose-dash.sh up -d
  ```

### InfluxDB

* Connect to the Influx database to import setup commands: 

  ```bash
    docker exec -it influxdb influx -import -path=/var/lib/influxdb/influxdb.sql
  ```

Note: It can take a while for InfluxDB to start.  Also the influxdb.sql file is set to use `America/Los_Angeles` as timezone. Use the `tz.sh` script or manually update the database commands above to replace `America/Los_Angeles` with your own timezone.

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

* From `Dashboard\Browse` select `New/Import`, and upload one of the dashboard files below (in [dashboards folder](https://github.com/jasonacox/Powerwall-Dashboard/tree/main/dashboards)):

  1. `dashboard.json` - Dashboard with the live trend graph, monthly power graphs, an animated power flow diagram and a Powerwall+ section that includes String data, temperature, voltage and frequency graphs. This also includes a "grid status" graph below the animation to identify and track grid outages.
  2. `dashboard-new.json` - Same as above but updated with new Grafana 9 time series graph with "grid outage" data on main energy usage graph.
  3. `dashboard-no-animation.json` - Same as above but without the animated power flow diagram.  
  4. `dashboard-simple.json` - Similar to above but without the Powerwall+ metrics.
  5. `dashboard-grid.json` - Same as dashboard.json but with a simple grid status instead of the trend data.

### Notes

* The database queries and dashboard are set to use `America/Los_Angeles` as the timezone. Remember to edit the database commands [influxdb.sql](influxdb/influxdb.sql), [powerwall.yml](powerwall.yml), and [dashboard.json](dashboard.json) to replace `America/Los_Angeles` with your own timezone.

### Upgrading

* The included `upgrade.sh` script will attempt to upgrade your installation to the latest Powerwall-Dashboard version without removing existing data. A backup is still recommended.

### Troubleshooting Tips and Tricks

Check the logs of the services using:

```bash
  docker logs -f pypowerwall
  docker logs -f telegraf
  docker logs -f influxdb
  docker logs -f grafana
```

* Docker terminating with `error 139`:  InfluxDB does not run reliably on older models of Raspberry Pi. 
* Grafana Error: Invalid interval string, expecting a number followed by one of "Mwdhmsy" - This indicates that the Grafana setup for InfluxDB is missing the time unit, "s", in the "Min time interval" field:
  - Min time interval: `5s`

#### Missing String data?

* String data only shows up for Tesla inverters as part of Powerwall+ systems.  Unfortunately, non-Tesla inverter data is not available via the Tesla API. If you find a way to pull this data, please submit an Issue or Pull Request to get it added.
* The default dashboard and InfluxDB setup supports up to 6 Tesla Powerwall+ inverters. Support for more can be added by editing the [dashboard.json](dashboard.json) and [influxdb.sql](influxdb/influxdb.sql) files. Open an Issue and we can help (see [#2](https://github.com/jasonacox/Powerwall-Dashboard/issues/2)).

#### Docker Errors

If you are getting permission errors running docker, or an error that it isn't installed:
* Ensure docker is installed for your OS (run `docker version` to test)
* If you see permission denied, add your user to the docker group and reboot your system:
  ```bash
  # Add your user to docker group
  sudo usermod -aG docker $USER
  ```
* If the above step hasn't worked, and you get an error trying to run `docker info` like `permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock`:
  ```bash
  # Grant permissions to the docker daemon socket
  sudo chmod 666 /var/run/docker.sock
  ```
* If you can't access the dashboard after a reboot, that means that docker was not set to start on reboot. On many OS distributions you can set it to start on boot with:
  ```bash
  # Set docker to start on boot
  sudo systemctl enable docker.service
  sudo systemctl enable containerd.service
  ```
* See [Docker install here](https://docs.docker.com/engine/install/linux-postinstall/) for more information.
* If you have docker installed but get "ERROR: docker-compose is not available or not running" make sure it is in your PATH or if needed, install the docker-compose cli tool:
  ```bash
  # install
  sudo pip3 install docker-compose

  # test
  docker-compose --version
  ```

#### Savings Errors

The savings estimates are based on a $0.19/kWh utility cost and net metering credit. You likely have a different value for this and can edit the queries in that panel to reflect your actual costs and credits.  To help, here are the variables used to calculate the savings:

* `s` = kWh from solar (based on time frame selected)
* `fp` = kWh from powerwall
* `tp` = kWh to powerwall
* `tg` = kWh to grid

The equations that are used to compute the estimated savings:

* `powerwall>home` = `fp` * `$/kWh`  [assumes all power to home from PW = savings]
* `solar>home` = (`s` - `tp` - `tg`) * `$/kWh`  [assumes all solar not going to PW or grid is going to the home = savings]
* `solar>grid` = `tg` * `$/kWh`  [assumes all power going to grid = savings]

#### Synology NAS and Rootless Docker

* If you are having trouble getting this to work on a Synology NAS, view the resolution discovered in [Issue #22](https://github.com/jasonacox/Powerwall-Dashboard/issues/22) thanks to @jaydkay.
* If you are running docker as a non-privileged (rootless) user, please some setup help [here](https://github.com/jasonacox/Powerwall-Dashboard/issues/22#issuecomment-1254699603) thanks to @BuongiornoTexas.
* Most of the issues running the Dashboard on Synology NAS are related to user or file permission issues. Ensure that the `conf`, `env` and `sql` files are readable by the docker services (most can be set `chmod 644`).

#### Windows 11 Instructions

Installing Powerwall-Dashboard on a Windows 11 host requires some additional setup. Install and Setup using administrator PowerShell or Windows Command Prompt:

* Install WSL (wsl --install) with an OS (recommend Ubuntu)
* Install *Git for Windows* (https://gitforwindows.org/)
* Install *Docker Desktop* for Windows (https://www.docker.com/)
* From *Git Bash* prompt, Clone repo (`git clone https://github.com/jasonacox/Powerwall-Dashboard.git`)
* Run `cd Powerwall-Dashboard`
* Run `./setup.sh`

#### Tips and Tricks

Since [pyPowerwall proxy](https://github.com/jasonacox/pypowerwall/tree/main/proxy) is part of this dashboard stack, you can query it to get raw data (read only) from the Powerwall API.  This includes some aggregate functions you might find useful for other projects.  I use this for [ESP32 driven display](https://github.com/jasonacox/Powerwall-Display) for example. Replace localhost with the address of the system running the dashboard:

* pyPowerwall stats: http://localhost:8675/stats
* Powerwall firmware version and uptime: http://localhost:8675/api/status
* Powerwall temperatures: http://localhost:8675/temps
* Powerwall device vitals: http://localhost:8675/vitals
* Powerwall strings: http://localhost:8675/strings
* Powerwall battery level: http://localhost:8675/soe
* Key power data in CSV format (grid, home, solar, battery, batterylevel): http://localhost:8675/csv

Since [weather411](https://hub.docker.com/r/jasonacox/weather411) is part of this dashboard stack (if you set it up) you can query it to get current weather data from its built-in API.

* Current stats of weather411 service: http://localhost:8676/stats
* Current conditions: http://localhost:8676/
* Current conditions in JSON: http://localhost:8676/json

**Data Retention and Backups**
InfluxDB is configured to use a infinite retention policy (see [influxdb.sql](../influxdb/influxdb.sql)).  It uses continuous queries to downsample Powerwall data and preserve disk space.  However, this does not safeguard the data from accidental deletion or corruption.  It is recommend that you set up a backup plan to snapshot the data for disaster recovery. See [backups](backups/) for some suggestions.

### Credits

* This project is based on the great work by mihailescu2m at [https://github.com/mihailescu2m/powerwall_monitor](https://github.com/mihailescu2m/powerwall_monitor) and has been modified to use pypowerwall as a proxy to the Powerwall and includes solar String, Inverter and Powerwall Temperature graphs for Powerwall+ systems.
* Grafana at https://github.com/grafana/grafana 
* Telegraf at https://github.com/influxdata/telegraf
* InfluxDB at https://github.com/influxdata/influxdb
* pyPowerwall at https://github.com/jasonacox/pypowerwall
* Special thanks to the entire Powerwall-Dashboard community for the great engagement, contributions and encouragement! See [RELEASE notes](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/RELEASE.md#release-notes) for the ever growing list of improvements, tools and cast members making this project possible.
