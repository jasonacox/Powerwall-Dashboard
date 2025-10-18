# Powerwall-Dashboard

Monitoring Dashboard for Tesla Solar and Powerwall systems using Grafana, InfluxDB, Telegraf and pyPowerwall.

> ⚠️ **NOTICE:** As of Powerwall Firmware version 25.10.0, network routing to the TEDAPI endpoint (`192.168.91.1`) is no longer supported by Tesla. You must connect directly to the Powerwall's WiFi access point to use TEDAPI features. If you previously set up a static route for TEDAPI, you can remove it using `./add_route.sh -disable`.

![Animation](https://user-images.githubusercontent.com/13752647/198901193-6f5d3f34-3ef6-4d6d-95ff-892a3763541b.png)
![Monthly](https://user-images.githubusercontent.com/836718/214475577-2a633228-4db0-41b8-8738-51642222f462.png)
![Yearly](https://user-images.githubusercontent.com/836718/214475014-4ba090dd-bca8-475f-bbdc-6d80ad5afbb0.png)
![Powerwall+](https://user-images.githubusercontent.com/836718/214475810-bc5748fd-5a6f-4fd7-869b-88ba3f06346c.png)
![FreqVoltage](https://user-images.githubusercontent.com/836718/214475204-d049c0c8-1b2c-4fb7-b015-0a638a33adde.png)
![Alerts](https://user-images.githubusercontent.com/836718/214474307-9c85de97-3730-4e2c-a4a1-0173be3e0ea1.png)
![Weather](https://user-images.githubusercontent.com/836718/214474825-75686470-03a9-41cc-b827-f54dc323f93e.png)

## Dashboards

The default [dashboard.json](dashboards/dashboard.json) shown above, pulls in live power data from the local Tesla Energy Gateway or the Tesla Cloud and displays that on the Grafana dashboard. A power flow animation is rendered by the pyPowerwall container using that live data.

A non-animated version of the dashboard is also available using [dashboard-no-animation.json](dashboards/dashboard-no-animation.json)

![Dashboard](https://user-images.githubusercontent.com/13752647/155657200-4309306d-84c1-40b7-8f4c-32ef0e8d2efe.png)

## Requirements

The host system will require:

* docker ([install help](tools/DOCKER.md))
* docker-compose (works with docker compose (v2) as well)
* You should not need to run `sudo` to install this tool. See [Docker Errors](#docker-errors) below for help.
* TCP ports: 8086 (InfluxDB), 8675 (pyPowerwall), and 9000 (Grafana)

## Setup

Clone this repo on the host that will run the dashboard:

```bash
    git clone https://github.com/jasonacox/Powerwall-Dashboard.git
```

## Option 1 - Quick Start

Run the interactive setup script that will ask you for your setup details.

  ```bash
    cd Powerwall-Dashboard
    ./setup.sh
  ```

The dashboard can be installed in four different configurations.

  ```
    Powerwall Dashboard (v4.0.0) - SETUP
    -----------------------------------------
    Select configuration mode:

    1 - Local Access     (Powerwall 1, 2, or + using the Tesla Gateway on LAN) - Default
    2 - Tesla Cloud      (Solar-only systems or Powerwalls without LAN access)
    3 - FleetAPI Cloud   (Powerwall systems using Official Telsa API)
    4 - Extended Metrics (Powerwall 2, +, or 3 using TEDAPI and local WiFi access)
  ```

### Local Mode

For Powerwall 1, 2 or + owners with a Tesla Energy Gateway accessible on their LAN, select `option 1` (Local Access). Powerwall 3 owners will need to select one of the cloud options or `option 4`.

### Extended Metrics Mode

The Powerwall Dashboard can access additional metrics through the TEDAPI interface on the Powerwall/Gateway. To use this feature:

* You need the Powerwall/Gateway Password (typically found on the QR sticker)
* Your computer must have access to IP address 192.168.91.1
* Starting with Powerwall firmware 25.10.1+, your computer must connect directly to the Powerwall's WiFi access point. Important: Set up WiFi connectivity before running `setup.sh` if you want to use TEDAPI mode.

For instructions on setting up a Raspberry Pi with Powerwall WiFi, see: https://github.com/jasonacox/Powerwall-Dashboard/discussions/607. Also, unfortunately, Gateway 1 systems will not work with this method as they require a power toggle for access (see [Issue #536](https://github.com/jasonacox/Powerwall-Dashboard/issues/536)).

Using the pypowerwall python library you can test to see if you have access to TEDAPI:

```bash
# Test access to TEDAPI:

  curl -k --head https://192.168.91.1

# Test your password to TEDAPI:

  # Create a virtual python env
  python -m venv venv
  source venv/bin/activate

  # Install package
  pip install pypowerwall

  # Scan for Powerwall
  python -m pypowerwall scan

  # Connect to TEDAPI - You will be prompted for password
  python -m pypowerwall.tedapi
```

If you get a positive result, you can proceed with setup (`./setup.sh`) and selection option 1 or 4.

#### Powerwall 3 Owners (Requires TEDAPI)

If you have access to the Powerwall 192.168.91.1 endpoint (see local mode Extended Device Vitals Metrics note above), you can select option 4 to activate Extended Metrics mode. All data will be pulled from the local Gateway TEDAPI endpoint (requires connecting to Powerwall's WiFi access point). The password will be located on the QR sticker on the Powerwall 3 itself. If you have problems with your setup for the Powerwall 3, see troubleshooting section below.

_Note: This mode also works for Powerwall 2/+ systems. Unlike TEDAPI hybrid mode which uses some existing local APIs, this full mode provides calculated values for extended metrics missing in the TEDAPI payload._


### Cloud and FleetAPI Mode

For Tesla Solar or Powerwall 3 owners without TEDAPI access, select `option 2` (Tesla Owners unofficial Cloud API) or `option 3` (Tesla official FleetAPI) and the dashboard will be installed to pull data from the Tesla Cloud API. This mode should work for ALL systems but will have slightly less details and fidelity than the "Local Access" mode.

### Timezone

Next, you will then be asked for your Local *timezone*, and your Powerwall details or Tesla Cloud login details. To find your timezone, see the second column in this table: [https://en.wikipedia.org/wiki/List_of_tz_database_time_zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List)

### Troubleshooting

  * _If you experience issues with your Powerwall or Tesla Cloud login details, re-run `setup.sh` to try again._
  * _If you get docker errors during the setup, see the [Docker Errors](#docker-errors) section below._
  * _For Windows 11 users, see the [Windows 11 Instructions](#windows-11-instructions) below._
  * _Powerwall 3 Owners - The password you will use for local TEDAPI setup is the one on the sticker on the PW3 itself, not the one on the Gateway._

### Grafana Setup

Follow the **[Grafana Setup](#grafana-setup)** instructions (see below) to complete the setup.

### Enable Watchdog (Optional)

You can use the watchdog.sh script to monitor the health of the pypowerwall container and restart it if it becomes unhealthy. Running the command below will install it in your crontab to run every 5 minutes.

```bash
# Setup watchdog
./watchdog.sh -enable
```

## Option 2 - Manual Install

If you prefer, you can perform the same steps that `setup.sh` performs.

Note: some manual configuration is required if you are running a non-standard docker installation (e.g. rootless). Also, ensure that the `conf`, `env` and `sql` files are readable by the docker services (e.g. `chmod 644`).

You will want to set your local timezone by editing `pypowerwall.env`, `telegraf.conf`, `influxdb.sql` and `dashboard.json` or you can use this handy `tz.sh` update script.  A list of timezones is available here: [TZ Table](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones).

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

* For Tesla Solar owners or Powerwalls without LAN access, to configure pyPowerwall in Tesla Cloud mode instead of Local Access mode, edit `pypowerwall.env` and leave the `PW_HOST=` setting blank. NOTE: Once the docker containers have started, an additional step is then required to login to your Tesla Account by running the command `docker exec -it pypowerwall python3 -m pypowerwall setup`.

* Copy `compose.env.sample` to `compose.env`. You do not need to edit the other defaults unless you are running a non-standard install such as docker rootless or require custom ports.

* Copy `influxdb.env.sample` to `influxdb.env`. You do not need to edit this file, however if you have a custom setup, environment variables can be added to override the default InfluxDB configuration.

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

### Grafana Setup

* Open up Grafana in a browser at `http://<server ip>:9000` and login with `admin/admin`

#### Create Datasources

* As of v4.5.0, the setup script will auto provision data sources for you. However, you can manually set them up as well by following these two steps:

1. From `Configuration\Data Sources` add `InfluxDB` database with:
  - Name: `InfluxDB`
  - URL: `http://influxdb:8086`
  - Database: `powerwall`
  - Min time interval: `5s`
  - Click "Save & test" button

2. From `Configuration\Data Sources` add `Sun and Moon` database with:
  - Name: `Sun and Moon`
  - Enter your latitude and longitude. You can use this [web page](https://jasonacox.github.io/Powerwall-Dashboard/location.html) to find your GPS location if you don't know).
  - Click "Save & test" button

#### Import Dashboard

* From `Dashboard\Browse` select `New/Import`, and upload one of the dashboard files below (in [dashboards folder](dashboards)):

  1. `dashboard.json` - Dashboard with the live trend graph, monthly power graphs, an animated power flow diagram and a Powerwall+ section that includes String data, temperature, voltage and frequency graphs. This also includes a "grid status" graph below the animation to identify and track grid outages.
  2. `dashboard-no-animation.json` - Similar to above but without the animated power flow diagram.
  3. `dashboard-simple.json` - Similar to above but without the Powerwall+ metrics.
  4. `dashboard-solar-only.json` - For Tesla [Solar Only](tools/solar-only/) users, similar to above but without the animated power flow diagram or the Powerwall+ metrics.

### Notes

* The database queries are set to use `America/Los_Angeles` as the timezone. Remember to edit the database commands [influxdb.sql](influxdb/influxdb.sql) with your own timezone. During import of dashboards into Grafana you'll be prompted to enter your timezone for queries.

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
* PyPowerwall Error: If you are getting `LoginError: Invalid Powerwall Login` errors but have double checked your password and are sure it is correct, try using the last 5 characters of the password written on the Powerwall Gateway.
* Gateway 1 systems will not work with the local TEDAPI method as they require a power toggle for access (see [Issue #536](https://github.com/jasonacox/Powerwall-Dashboard/issues/536)).
* Powerwall 3 system owners: For systems with a PW3 and GW2 wanting to use an ethernet cable rather than WiFi to collect data, be sure to run the cable to the PW3 and not the GW2.
* Synology upgrade failure: Your system may have two git versions installed: /usr/bin/git and /opt/bin/git. Update PATH to use /usr/bin/git first, and then run upgrade script ([discussion](https://github.com/jasonacox/Powerwall-Dashboard/discussions/385#discussioncomment-11923607))
* Metrics stop working after upgrade: If, in Tesla One, the system is showing as "Stopped" TEDAPI queries will fail as well. Possible fix: power cycle the systems.

#### Missing Powerwalls or String data?

* String data only shows up for Tesla inverters as part of Powerwall+ systems.  Unfortunately, non-Tesla inverter data is not available via the Tesla API. If you find a way to pull this data, please submit an Issue or Pull Request to get it added.
* The default dashboard and InfluxDB setup supports up to 12 Tesla Powerwalls. Support for more can be added by editing the [dashboard.json](dashboards/dashboard.json) and [influxdb.sql](influxdb/influxdb.sql) files. Open an Issue and we can help (see [#2](https://github.com/jasonacox/Powerwall-Dashboard/issues/2)).

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
  
* If you have docker installed but get "ERROR: docker-compose is not available or not running" make sure it is in your PATH or if needed, install the [docker compose](https://docs.docker.com/compose/install/linux/#install-using-the-repository) tool:
  ```bash
  # install - for Ubuntu and Debian, run:
  sudo apt-get update
  sudo apt-get install docker-compose-plugin
  
  # install - for RPM-based distros, run:
  sudo yum update
  sudo yum install docker-compose-plugin
  
  # test
  docker compose version
  ```

#### Savings Errors

The savings estimates are based on a $0.19/kWh (by default) utility cost and net metering credit. You likely have a different value for this and during importing dashboards indicate your average cost per kWh to reflect your actual costs and credits. As of now there's one variable to set both cost and credit per kWh. To help, here are the variables used to calculate the savings:

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

Installing Powerwall-Dashboard on a Windows 11 host requires some additional setup. Install and Setup using **administrator** PowerShell or Windows Command Prompt:

If required, see [WINDOWS.md](WINDOWS.md) for notes on how to upgrade your WSL installation from WSL1 to WSL2, or for an installation *without Docker Desktop* - only recommended for very advanced users.

* (optional) install *Windows Terminal* [Windows Terminal](https://aka.ms/terminal)
* Install WSL `wsl --install` with a Linux distro (recommend Ubuntu - this is the default WSL Linux distro if you install with wsl --install)
* Install *Docker Desktop* for Windows [Docker Desktop](https://www.docker.com/products/docker-desktop/) (after install, note sign in is optional, and to ensure the docker engine starts automatically go to Settings and select _Start Docker Desktop when you log in_)
* Start your WSL from the shortcut for Ubuntu (or your chosen distro) that will have been set up when you installed WSL or from Windows Terminal
* Make sure you are in your home directory `cd ~`
* Clone repo (`git clone https://github.com/jasonacox/Powerwall-Dashboard.git`)
* Run `cd Powerwall-Dashboard`
* Run `./setup.sh`

#### Powerwall 3

The new Powerwall 3 does not have the local APIs that were found on the Powerwall 2/+ systems. However, it does provide APIs available via its internal Gateway WiFI access point at 192.168.91.1. If you add your Powerwall 3 to your local network (e.g. ethernet hardwire) or create a WiFi bridge to this access point, you are able to get the extended metrics from the /tedapi API. Additionally, users can use the "Tesla Cloud" mode to generate the basic graph data. It is more limited than the local APIs but does provide the core data  points. See details in the Powerwall 3 Support issue: https://github.com/jasonacox/Powerwall-Dashboard/issues/387

Some have reported issues setting up their Powerwall 3 and the local 192.168.91.1 access point. Make sure that this IP address is reachable from the host running the Dashboard (e.g. `ping` or `curl` commands).

Since the Powerwall 3 does not have previous generation APIs, you will need to use the `full` TEDAPI mode. This requires that the PW_EMAIL and PW_PASSWORD environmental variables are empty and that PW_GW_PWD is set to the Powerwall 3 Gateway WiFi password (usually found on the QR code either located [inside the glass cover](https://github.com/jasonacox/Powerwall-Dashboard/discussions/694#discussioncomment-14589042) or on the outside of the unit, left side).

Example of a working `pypowerwall.env` file for Powerwall 3:

```
PW_EMAIL=
PW_PASSWORD=
PW_HOST=192.168.91.1
PW_TIMEZONE=America/Los_Angeles
TZ=America/Los_Angeles
PW_DEBUG=no
PW_STYLE=grafana-dark
PW_GW_PWD=<YOUR_PW3_PASSWORD> 
```

Note, for Powerwall 3 systems, the PW_GW_PWD will be the password you find on the Powerwall 3 itself, not the gateway password. This password is printed on the label under the Powerwall 3 glass cover, visible during installation. If you have multiple Powerwalls, use the one from the primary Powerwall 3.

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
InfluxDB is configured to use an infinite retention policy (see [influxdb.sql](influxdb/influxdb.sql)).  It uses continuous queries to downsample Powerwall data and preserve disk space.  However, this does not safeguard the data from accidental deletion or corruption.  It is recommended that you set up a backup plan to snapshot the data for disaster recovery. See [backups](backups/) for some suggestions.

### Other Tools and Related Projects

* NetZero app - iOS and Android App for monitoring your System - https://www.netzeroapp.io/

### Support

There are several ways you can support this project.

* Submit ideas, issues, discussions and code! Thanks to our active community, the project continues to grow and improve. Your engagement and help is needed and appreciated.
* Tell others. If you find this useful, please share with others to help build our community.
* Help test the installation and upgrades. We need help testing the project on different platforms and versions of Powerwalls. Report your finding and any suggestions to make it easier to setup and use.
* Some of you have asked how you can contribute to help fund the project. This is work of love and a hobby. I'm not looking for financial help. However, if you are considering purchasing a Tesla Solar and/or Powerwall system, please take advantage of this code for a discount and I'll get a referral credit as well: https://www.tesla.com/referral/jason50054

### Acknowledgements 

* [Tesla Energy](https://www.tesla.com/energy/design?referral=jason50054&redirect=no) - Tesla is not affiliated with this project but we want to thank the brilliant minds at Tesla for creating such a great system for solar home energy generation. Tesla and Powerwall are trademarks of Tesla, Inc.
* This project was based on the great work by mihailescu2m at [https://github.com/mihailescu2m/powerwall_monitor](https://github.com/mihailescu2m/powerwall_monitor) and has been modified to use pypowerwall as a proxy to the Powerwall and includes solar String, Inverter and Powerwall Temperature graphs for Powerwall+ and Powerwall 3 systems.
* Grafana at https://github.com/grafana/grafana
* Telegraf at https://github.com/influxdata/telegraf
* InfluxDB at https://github.com/influxdata/influxdb
* pyPowerwall at https://github.com/jasonacox/pypowerwall
* Special thanks to the entire Powerwall-Dashboard community for the great engagement, contributions and encouragement! See [RELEASE notes](RELEASE.md#release-notes) for the ever growing list of improvements, tools and cast members making this project possible.

## Contributors

<a href="https://github.com/jasonacox/Powerwall-Dashboard/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=jasonacox/Powerwall-Dashboard" />
</a>
