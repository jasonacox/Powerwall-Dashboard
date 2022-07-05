# Powerwall-Dashboard

Monitoring Dashboard for the Tesla Powerwall using Grafana, InfluxDB, Telegraf and pyPowerwall.

![Dashboard](https://user-images.githubusercontent.com/13752647/155657200-4309306d-84c1-40b7-8f4c-32ef0e8d2efe.png)
![Monthly](https://user-images.githubusercontent.com/836718/155044558-c693743e-8684-4ad9-a5c2-dd2006ad87a6.png)
![Yearly](https://user-images.githubusercontent.com/836718/161393841-1349a93c-8876-4829-abc4-546bfe492d61.png)
![Powerwall+](https://user-images.githubusercontent.com/13752647/155657106-9dbfc9e8-206f-4fa0-8b47-5dd15e726bf0.png)
![FreqVoltage](https://user-images.githubusercontent.com/836718/161393960-87d6c8f1-2f00-4a5b-b201-3ced1fbb44bc.png)
![Powerwall Capacity](https://user-images.githubusercontent.com/836718/174494485-f901cb79-09ae-4674-88a5-7af00e89fb89.png)

## Power Flow Animation

An alternative [dashboard-animation.json](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/dashboard-animation.json) is also available. This pulls in the live power flows from the Powerwall web portal and embeds that animation in the Grafana dashboard.

![Animation](https://user-images.githubusercontent.com/836718/173971313-11ede1ea-8ed6-4750-8404-b57947723355.png)

## Requirements

The host system will require:

* docker
* docker-compose
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
    ./setup.sh
  ```

  _If you get docker errors during the setup, see the [Docker Errors](https://github.com/jasonacox/Powerwall-Dashboard#docker-errors) section below._

Follow the **[Grafana Setup](https://github.com/jasonacox/Powerwall-Dashboard#grafana-setup)** instructions provided (or see below) to complete the setup.
 
 
## Option 2 - Manual Install

If you prefer, you can perform the same steps that `setup.sh` performs.

You will want to set your local timezone by editing `pypowerwall.env`, `influxdb.sql` and `dashboard.json` or you can use this handy `tz.sh` update script.  A list of timezones is available [here](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones).

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

* Copy `grafana.env.sample` to `grafana.env` - you do not need to edit these defaults. However, there are optional settings for alert notifications and HTTPS.

* Start the docker containers

  ```bash
    docker-compose -f powerwall.yml up -d
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

* From `Dashboard\Manage` (or `Dashboard\Browse`), select `Import`, and upload one of the dashboard files below:

  1. `dashboard.json` - Basic dashboard with the live trend graph, monthly power graphs and a Powerwall+ section that includes String data, temperature, voltage and frequency graphs.
  2. `dashboard-animation.json` - Same as above but includes an animated power flow diagram between solar, grid, house and Powerwall.  It also includes a "grid status" graph below the animation to identify and track grid outages.
  3. `dashboard-simple.json` - Similar to dashboard.json but without the Powerwall+ metrics.
  4. `dashboard-grid.json` - Same as dashboard-animation.json but with a simple grid status instead of the trend data.

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
* The default dashboard and InfluxDB setup supports up to 4 Tesla Powerwall+ inverters. Support for more can be added by editing the [dashboard.json](dashboard.json) and [influxdb.sql](influxdb/influxdb.sql) files. Open an Issue and we can help (see [#2](https://github.com/jasonacox/Powerwall-Dashboard/issues/2)).

#### Docker Errors

If you are getting permission errors running docker, or an error that it isn't installed:
* Ensure docker is installed for your OS (run `docker version` to test)
* If you see permission denied, add your user to the docker group and reboot your system:
  ```bash
  # Add your user to docker group
  sudo usermod -aG docker $USER
  ```
* If you can't access the dashboard after a reboot, that means that docker was not set to start on reboot. On many OS distributions you can set it to start on boot with:
  ```bash
  # Set docker to start on boot
  sudo systemctl enable docker.service
  sudo systemctl enable containerd.service
  ```
* See [Docker install here](https://docs.docker.com/engine/install/linux-postinstall/) for more information.

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

#### Synology NAS

* If you are having trouble getting this to work on a Synology NAS, view the resolution discovered in [Issue #22](https://github.com/jasonacox/Powerwall-Dashboard/issues/22).

#### Tips and Tricks

Since [pyPowerwall proxy](https://github.com/jasonacox/pypowerwall/tree/main/proxy) is part of this dashboard stack, you can query it to get raw data (read only) from the Powerwall API.  This includes some aggregate functions you might find useful for other projects.  I use this for [ESP32 driven display](https://github.com/jasonacox/Powerwall-Display) for example. Replace localhost with the address of the system running the dashboard:

* pyPowerwall stats: http://localhost:8675/stats
* Powerwall firmware version and uptime: http://localhost:8675/api/status
* Powerwall temperatures: http://localhost:8675/temps
* Powerwall device vitals: http://localhost:8675/vitals
* Powerwall strings: http://localhost:8675/strings
* Powerwall battery level: http://localhost:8675/soe
* Key power data in CSV format (grid, home, solar, battery, batterylevel): http://localhost:8675/csv

**Data Retention and Backups**
InfluxDB is configured to use a infinite retention policy (see [influxdb.sql](../influxdb/influxdb.sql)).  It uses continuous queries to downsample Powerwall data and preserve disk space.  However, this does not safeguard the data from accidental deletion or corruption.  It is recommend that you set up a backup plan to snapshot the data for disaster recovery. See [backups](backups/) for some suggestions.

### Credits

* This project is based on the great work by mihailescu2m at [https://github.com/mihailescu2m/powerwall_monitor](https://github.com/mihailescu2m/powerwall_monitor) and has been modified to use pypowerwall as a proxy to the Powerwall and includes solar String, Inverter and Powerwall Temperature graphs for Powerwall+ systems.
* Grafana at https://github.com/grafana/grafana 
* Telegraf at https://github.com/influxdata/telegraf
* InfluxDB at https://github.com/influxdata/influxdb
* pyPowerwall at https://github.com/jasonacox/pypowerwall
