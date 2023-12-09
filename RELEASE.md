# RELEASE NOTES

## v3.0.3 - Setup Profiles Updates

* Updated `setup.sh` process descriptions to include Tesla Cloud data source in profile options (see below). This is currently the only option for Powerwall 3 owners (see #387) by @mcbirse
* Update `setup.sh` to allow config changes.
* Added weather data to `dashboard-no-animation.json` dashboard.
* [[Tools](https://github.com/jasonacox/Powerwall-Dashboard/tree/main/tools)] - Revise `pwstatus` and `weather-history` retry handling by @mcbirse.

```
1 - Local Access (Powerwall 1, 2, or + using extended data from Tesla Gateway on LAN) - Default
2 - Tesla Cloud (Solar-only, Powerwall 1, 2, +, or 3 using data from Tesla Cloud)
```


## v3.0.2 - Docker-Compose Fixes

* Add future deprecation WARNING for older docker-compose versions.
* Add support for docker-compose >= 1.28.0 to use compose profiles.
* Change logic in `compose-dash.sh` to default to Docker compose V2.

## v3.0.1 - Fix for Docker-Compose V1

* This fixes an issue introduced by v3.0.0 for old Docker-Compose V1 systems in https://github.com/jasonacox/Powerwall-Dashboard/pull/389
* Updates example backup script to use `xz` compression in #337

## v3.0.0 - Integrate Solar Only Support

* Added Solar Only support as a setup option when installing Powerwall Dashboard by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/386 see https://github.com/jasonacox/Powerwall-Dashboard/issues/183 and https://github.com/jasonacox/Powerwall-Dashboard/tree/main/tools/solar-only
* Updated Solar Only dashboard with user adjustable tz and cost variables, and removed Grid Status & Current State panels
* Updated Docker Compose environment to support compose profiles and updated setup, upgrade and verify scripts
* Added checks to setup script for common issues such as user/group problems
* Added migration for beta Solar Only installs to upgrade script

## v2.10.0 - Docker Compose and Container Updates

* Update versions: Telegraf (v1.28.2) and pyPowerwall (v0.6.2t28)
* Updated to pyPowerwall Proxy t28 to support newer Grafana versions. Adds new PW_STYLE setting for `grafana-dark` mode.
* Updated `setup.sh` and `upgrades.sh` to support adding additional PW_STYLE setting.
* Docker Compose Config Improvements by @mcbirse - ref #366
* Update `powerwall.yml` to use variables for "user" and "ports" in containers, per #357 and #360 noted by @hulkster
* Updated `compose.env.sample` with explanation of latest supported options
* Updated `powerwall.yml` to use "unless-stopped" as the default restart policy for containers going forward

## v2.9.12 - Weather411 and pyPowerwall Updates

* Fix weather411 to exit gracefully with SIGTERM by @rcasta74 in https://github.com/jasonacox/Powerwall-Dashboard/pull/354
* Update to pyPowerwall t27 to exit gracefully with SIGTERM.

## v2.9.11 - Updated Default Dashboard

* Updated `dashboard.json` to isolate Powerwall+ string data to make it easier for those without Powerwall+ to close those empty panels as raised in https://github.com/jasonacox/Powerwall-Dashboard/issues/320. Also changed browser default timezone to TZ set by user.
* Dashboard-new formatting fixes and unlink library panels by @s-crypt in https://github.com/jasonacox/Powerwall-Dashboard/pull/316
* Fix dashboard.json in README by @longzheng in https://github.com/jasonacox/Powerwall-Dashboard/pull/319
* Update verify.sh to carry state of all tests back to calling shell by @vikrum in https://github.com/jasonacox/Powerwall-Dashboard/pull/321
* Fix mean in solar energy yr panel #330 by @jasonacox in https://github.com/jasonacox/Powerwall-Dashboard/pull/331
* Shared crosshair by @longzheng in https://github.com/jasonacox/Powerwall-Dashboard/pull/338

## v2.9.10 - Updated Default Dashboard

* Updated default `dashboard.json` to incorporate timeseries migrations by @s-crypt in https://github.com/jasonacox/Powerwall-Dashboard/pull/295 and https://github.com/jasonacox/Powerwall-Dashboard/pull/297 see https://github.com/jasonacox/Powerwall-Dashboard/issues/290
* Updated "Grid Status" to new timeseries graph with red/yellow/green status.

## v2.9.9 - Tools, Solar Only Support and Dashboard Updates

#### Instructions / Cleanup and Misc Tool Updates

* Fix typos and spelling errors by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/281
* Add instructions to make backup script executable by @s-crypt in https://github.com/jasonacox/Powerwall-Dashboard/pull/289
* Add timezone lookup instructions by @jasonacox see https://github.com/jasonacox/Powerwall-Dashboard/discussions/291#discussioncomment-6140863
* Remove option to set e-mail sender name in Powerwall Status Monitor tool for improved compatibility by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/301
* Update Powerwall Status Monitor tool to ignore null responses which can occur during firmware updates by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/305 see https://github.com/jasonacox/Powerwall-Dashboard/discussions/109#discussioncomment-6193560

#### Solar Only Support

* Add daemon option to Tesla History tool and create docker container by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/281
* Revise setup script to utilise docker container environment by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/283
* Add WinOS winpty support to setup script by @jasonacox in https://github.com/jasonacox/Powerwall-Dashboard/pull/283#discussion_r1201492026
* Add support to define InfluxDB PORT by environment variable when running in docker by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/285 see https://github.com/jasonacox/Powerwall-Dashboard/issues/183#issuecomment-1565191526
* Modify script to replace data instead of update by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/293 see https://github.com/jasonacox/Powerwall-Dashboard/issues/286

#### Powerwall-Dashboard Usage Micro Service

* New tool developed by @BuongiornoTexas to generate usage and cost/savings information based on utility usage plans in https://github.com/jasonacox/Powerwall-Dashboard/pull/299 see https://github.com/jasonacox/Powerwall-Dashboard/tree/main/tools/usage-service and https://github.com/jasonacox/Powerwall-Dashboard/issues/276
* Add Docker Hub upload script by @jasonacox in https://github.com/jasonacox/Powerwall-Dashboard/pull/299
* Remove armv7 architecture by @jasonacox see https://github.com/jasonacox/Powerwall-Dashboard/pull/299#issuecomment-1586136593

#### Migrate Dashboard Panels

* Create "dashboard-new" using new Grafana time series type panels by @s-crypt in https://github.com/jasonacox/Powerwall-Dashboard/pull/295 and https://github.com/jasonacox/Powerwall-Dashboard/pull/297 see https://github.com/jasonacox/Powerwall-Dashboard/issues/290

## v2.9.8 - Tool Updates and Bug Fixes

* Update to Powerwall Status Monitor tool to prevent false grid status alerts during Powerwall firmware updates by @mcbirse as raised in https://github.com/jasonacox/Powerwall-Dashboard/discussions/109#discussioncomment-5801031
* Bug fix to Weather History Tool to resolve crash during setup process when weather411.conf is not found by @mcbirse

## v2.9.7 - Backup Script Quickfix

* Quickfix for permissions issues after repo cleanup. This addresses permission issues that interrupt the upgrade script for users of the backup script. Fix by @YesThatAllen in https://github.com/jasonacox/Powerwall-Dashboard/pull/272 as raised in https://github.com/jasonacox/Powerwall-Dashboard/issues/265

## v2.9.6 - Add Git Attributes

* Add `.gitattributes` file to help prevent issues such as .sh files being borked on Windows OS (ref #155) by @YesThatAllen in https://github.com/jasonacox/Powerwall-Dashboard/pull/270
* Fix `verify.sh` to run on Windows OS in https://github.com/jasonacox/Powerwall-Dashboard/commit/25b77e53310d1668b2b3868e59fac55b82286f4f

## v2.9.5 - Repo Cleanup

* Repo cleanup and maintenance by @YesThatAllen in https://github.com/jasonacox/Powerwall-Dashboard/pull/269

## v2.9.4 - pyPowerwall Proxy t26

* Update pyPowerwall Proxy to t26 with updated default `PW_POOL_MAXSIZE` of 15 as raised by @jgleigh
 and @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/discussions/261#discussioncomment-5803595
* Dashboard Update - Update "costs/credit per kWh" for buy vs. sell by @jgleigh in https://github.com/jasonacox/Powerwall-Dashboard/pull/266

## v2.9.3 - Adjustable kWh Cost

* Dashboard Update - Make "costs/credit per kWh" and "timezone" user adjustable variables in Grafana by @emptywee in https://github.com/jasonacox/Powerwall-Dashboard/pull/266

## v2.9.2 - Additional Powerwall Support

* Add support for up to 12 Powerwalls (added PW7 to PW12) for temperature data, frequencies, voltages and capacity as requested in https://github.com/jasonacox/Powerwall-Dashboard/discussions/253 and issue https://github.com/jasonacox/Powerwall-Dashboard/issues/256.

## v2.9.1 - Minimize Grafana Plugins

* Minimize the number of default Grafana plugins as defined in the `grafana.env.sample` file (installed as localized `grafana.env`) for new installations by @jasonacox in https://github.com/jasonacox/Powerwall-Dashboard/issues/234
* Update power flow animation panel code to display Grafana loading image while power flow graphics are loaded by @dkerr64 as discussed in https://github.com/jasonacox/Powerwall-Dashboard/discussions/216#discussioncomment-5573094

## v2.9.0 - Pinned Versions

* Tools - Reinstate setting timezone from history on 1st run by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/236
* Pinned versions in compose file for controlled upgrades and repeatable setups. Fix https://github.com/jasonacox/Powerwall-Dashboard/issues/237 issue by removing image pruning in `upgrade.sh` script by @GrimmiMeloni in https://github.com/jasonacox/Powerwall-Dashboard/pull/240

## v2.8.11 - Animation Auto-Scale

* Add code to power flow animation dashboard panel to auto-scale based on window size by @dkerr64 in https://github.com/jasonacox/Powerwall-Dashboard/discussions/216

## v2.8.10 - Revert Animation Auto-Scale

* Problem with scaling causing scrollbar and clipping reported and reproducible on Windows 11 as raised in https://github.com/jasonacox/Powerwall-Dashboard/discussions/216
* Tools - InfluxDB 2.x fixes and moved to grafana variables use instead of grafana.ini by @ThePnuts in #233

## v2.8.9 - Animation Auto-Scale

* Solar Only Support Development - Fix timezone for solar only sites using an offset by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/226
* Add code to power flow animation dashboard panel to auto-scale based on window size by @dkerr64 in https://github.com/jasonacox/Powerwall-Dashboard/discussions/216 and PR https://github.com/jasonacox/Powerwall-Dashboard/pull/228
* Tools - InfluxDB 2.x updates to instructions and dashboard by @ThePnuts in https://github.com/jasonacox/Powerwall-Dashboard/pull/232

## v2.8.8 - pyPowerwall Cache-Control

* Upgraded to pyPowerwall v0.6.2 Proxy t25 which fixes Cache-Control no-cache header and adds an option to set max-age, See https://github.com/jasonacox/pypowerwall/blob/main/proxy/RELEASE.md#proxy-t25-21-mar-2023
* Solar Only Support Development by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/211 and in https://github.com/jasonacox/Powerwall-Dashboard/pull/218 in https://github.com/jasonacox/Powerwall-Dashboard/tree/main/tools/solar-only
* Grafana Options - Base setup in [grafana.env.sample](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/grafana.env.sample) will allow embedding of graphs into webpages [#219](https://github.com/jasonacox/Powerwall-Dashboard/issues/219) and optional removal of login requirement [#221](https://github.com/jasonacox/Powerwall-Dashboard/issues/221)
* Tools - InfluxDB 2.x optional setup, tasks, and dashboard by @ThePnuts in https://github.com/jasonacox/Powerwall-Dashboard/pull/223 See https://github.com/jasonacox/Powerwall-Dashboard/tree/main/tools/influxdb2

## v2.8.7 - Preserve Peaks in Graphs

* Update Live Monitoring graph queries for Dashboard to use `max()` instead of `mean()` for Solar, Home, Grid and Powerwall to preserve peaks across all time filters as raised in https://github.com/jasonacox/Powerwall-Dashboard/issues/203
* Update pyPowerwall proxy service to v0.6.1 Proxy t24 (see https://github.com/jasonacox/pypowerwall/releases/tag/v0.6.1)

## v2.8.6 - Weather Updates

* Weather411 v0.2.0 - Upgrade InfluxDB Client to support InfluxDB 1.8 and 2.x by @jasonacox in https://github.com/jasonacox/Powerwall-Dashboard/pull/196 closes https://github.com/jasonacox/Powerwall-Dashboard/issues/195 re: https://github.com/jasonacox/Powerwall-Dashboard/discussions/191#discussioncomment-5112333
* README Improvements by @BJReplay in https://github.com/jasonacox/Powerwall-Dashboard/pull/192
* Ecowitt Weather v0.2.2 - Upgrade InfluxDB Client to support InfluxDB 1.8 and 2.x by @BJReplay in https://github.com/jasonacox/Powerwall-Dashboard/pull/200

## v2.8.5 - Verify Tool for Setup

* Added `verify.sh` tool to test setup and operation of the main components for the Dashboard (pypowerwall, telegraf, influxdb, grafana, weather411) by @jasonacox as raised in https://github.com/jasonacox/Powerwall-Dashboard/issues/187

```bash
./verify.sh # optional: -no-color
```

<img width="545" alt="image" src="https://user-images.githubusercontent.com/836718/220232810-5766a38d-05ab-4982-bae9-2dd92d0e4990.png">

## v2.8.4 - Custom Docker Compose Support

* Added support for extending docker-compose setup via `powerwall.extend.yml` by @BJReplay in https://github.com/jasonacox/Powerwall-Dashboard/pull/186
* Renamed `backup.sh` to `backup.sh.sample` to allow local settings changes without impacting upgrade by @BJReplay in https://github.com/jasonacox/Powerwall-Dashboard/pull/186

## v2.8.3 - New Dashboard Meters

* Added "Net Grid Usage" meter by @wreiske and "% Solar Powered" meter by @jasonacox in https://github.com/jasonacox/Powerwall-Dashboard/issues/179 https://github.com/jasonacox/Powerwall-Dashboard/pull/181
* Dashboard archived and versioned in [./dashboards](https://github.com/jasonacox/Powerwall-Dashboard/tree/main/dashboards)
* Moved Alert Data from 3 day retention policy to separate "alerts" infinite (INF) retention policy.

## v2.8.2 - Bug Fix Grid Voltage Data Migration

* Grid Voltage Upgrade - This will fix the run-once script so tags are also copied with historic data by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/177

Note: For anyone that already upgraded to 2.8.0 or later, there is an option to fix the untagged data by running the [Fix Month Tags Tool](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/tools/fixmonthtags/). Thanks to @mcbirse for spotting this issue, submitting the fix and the great `fixmonthtags` tool!

## v2.8.1 - Backup Reserve

* Add Powerwall backup reserve setting (%) to Energy Usage graph thanks to @mp09 in https://github.com/jasonacox/Powerwall-Dashboard/issues/174

## v2.8.0 - Grid Voltage Upgrade

* Now using `ISLAND_VLxN_Main` data for Grid voltage (instead of `METER_x_VLxN`) as this appears to be more common across systems. Upgrade script executes a run-once query to copy historic data over. https://github.com/jasonacox/Powerwall-Dashboard/pull/167
* Added logic to Voltage panel to sum Powerwall L1 and L2 voltages for 230V grid users thanks to @longzheng in https://github.com/jasonacox/Powerwall-Dashboard/pull/165
* Change frequency panel to 3 decimal places by @longzheng in https://github.com/jasonacox/Powerwall-Dashboard/pull/163
* Update README.md - Indent powerwall.yml snippet so that it can be cut and pasted directly into powerwall.yml by @BJReplay in https://github.com/jasonacox/Powerwall-Dashboard/pull/168

## v2.7.1 - Powerwall Alert Data and Panel

* Add Powerwall Alert data to dashboard - Credit to @DerickJohnson in https://github.com/jasonacox/Powerwall-Dashboard/issues/158
* Updated Tools and Contrib READMEs by @BJReplay in https://github.com/jasonacox/Powerwall-Dashboard/pull/160

## v2.7.0 - PyPowerwall t24 and Ecowitt Weather Support

* [[Ecowitt Weather](https://github.com/jasonacox/Powerwall-Dashboard/tree/main/weather/contrib/ecowitt#ecowitt-local-weather-server)] Added Ecowitt local weather station data import service and dashboard by @BJReplay in https://github.com/jasonacox/Powerwall-Dashboard/pull/150 https://github.com/jasonacox/Powerwall-Dashboard/pull/151 https://github.com/jasonacox/Powerwall-Dashboard/pull/153 https://github.com/jasonacox/Powerwall-Dashboard/pull/157
* [[Tesla History Tool](https://github.com/jasonacox/Powerwall-Dashboard/tree/main/tools/tesla-history#tesla-history-import-tool)] Revise error handling of SITE_DATA request by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/156
* [[Ecowitt Weather History Tool](https://github.com/jasonacox/Powerwall-Dashboard/tree/main/tools/ecowitt-weather-history#ecowitt-weather-history-import-tool)] Added Ecowitt Weather History Tool by @BJReplay in https://github.com/jasonacox/Powerwall-Dashboard/pull/159
* [[pyPowerwall Proxy](https://github.com/jasonacox/pypowerwall/tree/main/proxy#pypowerwall-proxy-server)] Upgraded to pyPowerwall Proxy t24 which moves to Python 3.10 and adds /alerts/pw for easier alert history tracking by @DerickJohnson in https://github.com/jasonacox/pypowerwall/pull/26

## v2.6.7 - History Tools and Powerwall Firmware Version

* Add Powerwall Firmware version to Power-Flow animation. #112
* Fix Self-Powered calculations to factor in Grid charging of Powerwall. #135
* Upgrade to pyPowerwall Proxy t22 to better handle Powerwall Firmware updates. This introduces no-cache headers and hopefully eliminates the need for proxy restart. #112
* Fix timezone script (tz.sh) to process file in the dashboards folder. https://github.com/jasonacox/Powerwall-Dashboard/issues/63
* Eliminate horizontal scrollbars on iPhone. by @cwagz in https://github.com/jasonacox/Powerwall-Dashboard/pull/114
* Updated animation and yearly image by @cwagz in https://github.com/jasonacox/Powerwall-Dashboard/pull/117
* Tesla History Tool - Fix bug with error output when dateutil is missing by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/123
* Fix Month Tool - Added tool to fix incorrect month tags of InfluxDB by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/124 and https://github.com/jasonacox/Powerwall-Dashboard/pull/126
* Weather History Tool - Added tool to retrieve weather history data by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/147

## v2.6.6 - History Import Tool & Windows 11 Compatibility

* Added tool to import history data from Tesla cloud by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/99 and https://github.com/jasonacox/Powerwall-Dashboard/pull/108 - see https://github.com/jasonacox/Powerwall-Dashboard/tree/main/tools#tesla-historypy and https://github.com/jasonacox/Powerwall-Dashboard/issues/12
* Adjusted instructions, `setup.sh` and `upgrade.sh` to work with Windows 11 OS. https://github.com/jasonacox/Powerwall-Dashboard/issues/63
* Minor QoL enhancements by @BuongiornoTexas in https://github.com/jasonacox/Powerwall-Dashboard/pull/105 - Closes https://github.com/jasonacox/Powerwall-Dashboard/issues/96

## v2.6.5 - Upgrade pyPowerwall Proxy t18

* Upgrade to pyPowerwall Proxy t18 with enhanced error handling and logging
* Update `backup.sh` to validate directories before starting backup process #85
* Fix panel size for Animation to prevent scroll/clipping of data #98

## v2.6.4 - Upgrade Fix

* Upgrade issue identified in #85 that keeps files from updating (upgrade fails). New method will stash and rebase all but non-tracked files (e.g. `grafana.env` and `pypowerwall.env` local config files).

## v2.6.3 - Dashboard Updates

* Converts the "Energy Usage" graph to a new Grafana 9 time series graph - dashboard.json by @youzer-name in https://github.com/jasonacox/Powerwall-Dashboard/pull/86
* Add timezone to telegraf so tags are localized by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/81

## v2.6.2 - Current State Panel "No Data" Fix (No Archive)

* Fix bug in yesoreyeram-boomtable-panel that causes random "No data" errors in table. This uses the v1.5.0-alpha.3 boomtable by @yesoreyeram. #49

## v2.6.1 - Month and Year Tag Fix (No Archive)

* Add timezone to telegraf so tags are localized by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/81
* Fix dashboard.json bugs and update the rest of dashboard-*.json files for Grafana v9.

## v2.6.0 - Grafana v9.1.2 Upgrade

* Update dashboards and setup to use Grafana v9.1.2 by @techlover1 in https://github.com/jasonacox/Powerwall-Dashboard/pull/73
* Bug fix missing space in `weather.sh` by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/72

## v2.5.2 - Bug Fix

* Fix `upgrade.sh` to prevent sudo/root from running this script. #42

## v2.5.1 - Bug Fix

* Fix bug in `weather.sh` that causes the script to error on location entry. #72

## v2.5.0 - Weather Data

* Adds local weather data from [OpenWeatherMap.org](https://openweathermap.org/) using the [jasonacox/weather411](https://hub.docker.com/r/jasonacox/weather411) container. #42 #51

## v2.4.5 - pyPowerwall v0.6.0

* Upgraded to pyPowerwall [v0.6.0](https://github.com/jasonacox/pypowerwall/releases/tag/v0.6.0) Proxy t17 - Persistent HTTP Connections
* Added setup warning. Raspbian GNU/Linux 10 (buster) has a bug in the libseccomp2 library that causes the pypowerwall container to fail. See details an fix in #56

## v2.4.4 - Dashboard Updates

* Fixed Current State panel so it is not affected by different time range selections, and "No Data" issue by @mcbirse in https://github.com/jasonacox/Powerwall-Dashbsoard/pull/50
* Made the power flow animation dashboard the default (`dashboard.json`). Original dashboard is still available as `dashboard-no-animation.json`.

## v2.4.3 - Upgrade Fixes

* Externalize Grafana environment settings into `grafana.env` to allow for additional customizations.
* Update and fixes to `setup.sh` and `upgrade.sh`.

## v2.3.0 - Bug Fixes

* Fix pypowerwall.env format and timezone bug in setup #23
* Add check in setup.sh to ensure not running as root/sudo.
* Added self-upgrade feature to upgrade.sh with `set -e` to stop on errors #45
* Added VERSION tracking to help with upgrades (`upgrade.sh` and `setup.sh`).

## v2.2.0 - Power Flow Animation

* Added new Grafana dashboard and panel for iFrame for pyPowerwall Proxy passthrough Power Flow Animation - see [dashboard-animation.json](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/dashboard-animation.json).
* Fixed Timezone management for `tz.sh`, `setup.sh` and `upgrade.sh` for easier repeat setup and upgrades. #23

<img width="240" alt="image" src="https://user-images.githubusercontent.com/836718/170847330-bd03c15a-a3af-42d9-8901-1aa887e191c6.png">

## v2.0.0 - Frequency and Voltage Graphs

* Add graph
* pyPowerwall v0.4.0

## v1.0.0 - Initial Release

* Initial Release
* Tested on Ubuntu 18.04.6 LTS, Ubuntu 18.04.6 and 20.04 LTS, Raspberry Pi OS 32-Bit Debian Bullseye (armv7) and MacOS (x86_64, arm64)
* pyPowerwall v0.3.0
