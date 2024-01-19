# Tesla Solar Only

For Tesla Solar owners who don't have a Powerwall, to get a similar dashboard for their systems, Powerwall Dashboard can be installed in Tesla Cloud mode. This uses the Tesla Cloud API to grab power metrics and store them in InfluxDB for rendering by Grafana.

![Screenshot (2)](https://github.com/jasonacox/Powerwall-Dashboard/assets/20891340/3f954359-e851-462e-ba20-e1ad90db5bd7)

Thanks to [@Jot18](https://github.com/Jot18) for the example dashboard screenshot.

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

Select `option 2` (Tesla Cloud) to install the dashboard in Solar Only mode.

```
Powerwall Dashboard (v4.0.0) - SETUP
-----------------------------------------
Select configuration mode:

1 - Local Access (Powerwall 1, 2, or + using the Tesla Gateway on LAN) - Default
2 - Tesla Cloud  (Solar-only systems or Powerwalls without LAN access)
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
Upgrade Powerwall-Dashboard from 2.10.0 to 4.0.0
---------------------------------------------------------------------
This script will attempt to upgrade you to the latest version without
removing existing data. A backup is still recommended.

NOTE: Your existing 'solar-only' installation will be migrated to:
      /home/powerwall/Powerwall-Dashboard

Upgrade - Proceed? [y/N]
```

Answer 'Y' to proceed with the upgrade and migration process, after which the dashboard should be configured as if running setup with the Tesla Cloud mode selected, but with existing data and configuration files still intact.

The migration process will remove all docker containers, move all relevant data and configuration files from the previous install location under tools/solar-only, and then re-create the docker containers.

The `verify.sh` script can be executed to confirm all services are running and configured correctly after the migration.

```bash
# Run verify to check the config and services
./verify.sh
```

```
Verify Powerwall-Dashboard 4.0.0 on Linux - Timezone: Australia/Sydney
----------------------------------------------------------------------------
This script will attempt to verify all the services needed to run
Powerwall-Dashboard. Use this output when you open an issue for help:
https://github.com/jasonacox/Powerwall-Dashboard/issues/new


Checking pypowerwall
----------------------------------------------------------------------------
 - Config File pypowerwall.env: GOOD
 - Container (pypowerwall): GOOD
 - Service (port 8675): GOOD
 - Version: 0.7.6 Proxy t39
 - Powerwall State: CONNECTED - Firmware Version: 23.36.3
 - Cloud Mode: YES - Site ID: 123456789890 (My home)

Checking telegraf
----------------------------------------------------------------------------
 - Config File telegraf.conf: GOOD
 - Local Config File telegraf.local: GOOD
 - Container (telegraf): GOOD
 - Version: Telegraf 1.28.2 (git: HEAD@8d9cf395)

Checking influxdb
----------------------------------------------------------------------------
 - Config File influxdb.conf: GOOD
 - Environment File influxdb.env: GOOD
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

Checking weather411
----------------------------------------------------------------------------
 - Container (weather411): GOOD
 - Service (port 8676): GOOD
 - Weather: {"temperature": 19.84}
 - Version: 0.2.3

All tests succeeded.
```

If you have any questions or find problems, you are welcome to join the conversation in Issue [#183](https://github.com/jasonacox/Powerwall-Dashboard/issues/183).
