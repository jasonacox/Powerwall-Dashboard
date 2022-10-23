# RELEASE NOTES

## v2.6.6 - Add Windows 11 Compatibility

* Adjusted `setup.sh` and `upgrade.sh` to work with Windows 11 OS. #63
* Added Windows 11 Instructions. #63
* Added tool to retrieve history data from Tesla cloud by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/99 and  https://github.com/jasonacox/Powerwall-Dashboard/pull/108 - see https://github.com/jasonacox/Powerwall-Dashboard/tree/main/tools#tesla-historypy 
* Minor QoL enhancements by @BuongiornoTexas in https://github.com/jasonacox/Powerwall-Dashboard/pull/105 - Closes #96

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
