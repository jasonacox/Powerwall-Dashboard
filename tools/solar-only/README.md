# Tesla Solar Only

For Tesla Solar owners who don't have a Powerwall, to get a similar dashboard for their systems, Powerwall Dashboard can be installed in "solar-only" mode. This uses the Tesla Cloud API to grab power metrics and store them in InfluxDB for rendering by Grafana.

![Screenshot (2)](https://github.com/jasonacox/Powerwall-Dashboard/assets/20891340/3f954359-e851-462e-ba20-e1ad90db5bd7)

Thanks to [@Jot18](https://github.com/Jot18) for the example dashboard screenshot. Thanks and credit to [@mcbirse](https://github.com/mcbirse) for the `tesla-history` script that pulls the data from the Tesla Owner API and stores it into InfluxDB.

## Setup

Clone this repo on the host that will run the dashboard:

```bash
git clone https://github.com/jasonacox/Powerwall-Dashboard.git
```

Run the interactive setup script that will ask you for your setup details.

```bash
cd Powerwall-Dashboard
./setup.sh
```

Select `option 2` (solar-only) to install the dashboard in Solar Only mode.

```
Powerwall Dashboard (v3.0.0) - SETUP
-----------------------------------------
Select configuration profile:

1 - default     (Powerwall w/ Gateway on LAN)
2 - solar-only  (No Gateway - data retrieved from Tesla Cloud)
```

Next, you will then be asked for your Local *timezone*, and your Tesla Cloud login details. To find your timezone, see the second column in this table: [https://en.wikipedia.org/wiki/List_of_tz_database_time_zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List)

  * _If you experience issues with your Tesla Cloud login details, re-run `setup.sh` to try again._
  * _If you get docker errors during the setup, see the [Docker Errors](../../README.md#docker-errors) section._
  * _For Windows 11 users, see the [Windows 11 Instructions](../../README.md#windows-11-instructions)._

Follow the **[Grafana Setup](../../README.md#grafana-setup)** instructions provided to complete the setup.

## Migrating Beta Solar Only Installs

If you installed the Solar Only dashboard during beta testing, you can run the `upgrade.sh` script, instead of setup, to migrate your existing install from the placeholder location without losing data. A backup is still recommended.

Change directory to where the Powerwall Dashboard repo was cloned (*not the tools/solar-only sub-directory*), and run `upgrade.sh`. You do not need to manually pull changes from GitHub beforehand, as this will be handled by the upgrade script.

```bash
cd Powerwall-Dashboard
./upgrade.sh
```

The upgrade script should detect the existing solar-only installation, as indicated by the *NOTE* below. If it does not, you may need to remove the `compose.env` file *in the Powerwall-Dashboard directory* (not tools/solar-only), if it exists. This may exist due to attempting to install the dashboard as a Powerwall user previously by mistake.

```
Upgrade Powerwall-Dashboard from 2.10.0 to 3.0.0
---------------------------------------------------------------------
This script will attempt to upgrade you to the latest version without
removing existing data. A backup is still recommended.

NOTE: Your existing 'solar-only' installation will be migrated to:
      /home/powerwall/Powerwall-Dashboard

Upgrade - Proceed? [y/N]
```

Answer 'Y' to proceed with the upgrade and migration process, after which the dashboard should be configured as if running setup with the solar-only option selected, but with existing data and configuration files still intact.

The migration process will remove all docker containers, move all relevant data and configuration files from the previous install location under tools/solar-only, and then re-create the docker containers.

The `verify.sh` script can be executed to confirm all services are running and configured correctly after the migration.

```bash
# Run verify to check the config and services
./verify.sh
```

```
Verify Powerwall-Dashboard 3.0.0 on Linux - Timezone: Australia/Sydney
----------------------------------------------------------------------------
This script will attempt to verify all the services needed to run
Powerwall-Dashboard. Use this output when you open an issue for help:
https://github.com/jasonacox/Powerwall-Dashboard/issues/new


Checking configuration
----------------------------------------------------------------------------
 - Dashboard configuration: solar-only
 - EnvVar COMPOSE_PROFILES: solar-only,weather411

Checking pypowerwall
----------------------------------------------------------------------------
 - Skipped: Only required in 'default' configuration

Checking telegraf
----------------------------------------------------------------------------
 - Skipped: Only required in 'default' configuration

Checking influxdb
----------------------------------------------------------------------------
 - Config File influxdb.conf: GOOD
 - Container (influxdb): GOOD
 - Service (port 8086): GOOD
 - Filesystem (./influxdb): GOOD
 - Version: InfluxDB shell version: 1.8.10

Checking grafana
----------------------------------------------------------------------------
 - Config File grafana.env: GOOD
 - Container (grafana): GOOD
 - Service (port 9000): GOOD
 - Filesystem (./grafana): GOOD
 - Version: Grafana CLI version 9.1.2

Checking tesla-history
----------------------------------------------------------------------------
 - Config File tools/tesla-history/tesla-history.conf: GOOD
 - Auth File tools/tesla-history/tesla-history.auth: GOOD
 - Container (tesla-history): GOOD
 - Version: 0.1.4

Checking weather411
----------------------------------------------------------------------------
 - Config File weather/weather411.conf: GOOD
 - Container (weather411): GOOD
 - Service (port 8676): GOOD
 - Weather: {"temperature": 23.56}
 - Version: 0.2.2

All tests succeeded.
```

If you have any questions or find problems, you are welcome to join the conversation in Issue [#183](https://github.com/jasonacox/Powerwall-Dashboard/issues/183).
