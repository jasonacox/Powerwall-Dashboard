# RELEASE NOTES

## v4.8.6 - InfluxDB File Limits and Configuration Updates

* Add ulimits configuration to InfluxDB service to resolve "too many open files" errors by setting soft and hard limits to 65536 by @cwagz in https://github.com/jasonacox/Powerwall-Dashboard/issues/705
* Add enhanced timezone validation with interactive browse feature (`?` at prompt) supporting filters and multi-level IANA zones (e.g., `America/Argentina/Buenos_Aires`) and POSIX TZ strings (e.g., `GMT+5`).
* Add `timezone-test.sh` standalone test script for timezone validation with interactive and non-interactive modes.
* Minor configuration file changes by @BuongiornoTexas in https://github.com/jasonacox/Powerwall-Dashboard/pull/706
* Quote GF_INSTALL_PLUGINS value in grafana.env.sample by @rlerdorf in https://github.com/jasonacox/Powerwall-Dashboard/pull/703

## v4.8.5 - Setup and Verify

* Add enhanced log display options to `verify.sh`: supports `--logs` and `--no-logs` flags to control log output, and interactive prompt for log viewing. Log output is now cleaner and only shown when requested.
* Add input validation for timezone entry in `setup.sh` to prevent invalid/corrupt values in configuration files. Timezone is now checked against system zoneinfo and format before acceptance. 
* Update pypowerwall to v0.14.1 - See updates: https://github.com/jasonacox/pypowerwall/releases/tag/v0.14.1 for error handling updates.

## v4.8.4 - pyPowerwall update

* Update pypowerwall to v0.14.0 - See updates: https://github.com/jasonacox/pypowerwall/releases/tag/v0.14.0 with Cloud updates to accommodate Tesla API changes (embedded TeslaPy patch) and fix a bug in FleetAPI for multi-site installations.

## v4.8.3 - Docker Compose Updates

* Update pypowerwall to v0.13.2 - See updates: https://github.com/jasonacox/pypowerwall/releases/tag/v0.13.2 with improved connection health monitoring and graceful degradation. Including:

### v0.13.2 - TEDAPI Lock Optimization

* Fix TEDAPI lock contention issues causing "Timeout for locked object" errors under concurrent load by optimizing cache-before-lock pattern in core functions
* Optimize `get_config()`, `get_status()`, `get_device_controller()`, `get_firmware_version()`, `get_components()`, and `get_battery_block()` to check cache before acquiring expensive locks
* Remove redundant API call in `pypowerwall_tedapi.py` `get_api_system_status()` method
* Fix proxy server KeyError when status response missing version or git_hash keys by using defensive key access
* Fix proxy server KeyError when auth dictionary missing AuthCookie or UserRecord keys in cookie mode
* Improve performance and reduce lock timeout errors in multi-threaded environments like the pypowerwall proxy server
* Enhance `compute_LL_voltage()` function with voltage threshold detection (100V) to better handle single-phase systems with residual voltages on inactive legs, as well as split- and three-phase systems.
* These optimizations benefit all methods that depend on the core TEDAPI functions, including `vitals()`, `get_blocks()`, and `get_battery_blocks()`

### Proxy t77 (11 Jul 2025)

* **TEDAPI Lock Optimization and Error Handling**: Enhanced proxy stability and performance with comprehensive fixes for TEDAPI-related issues.
  - **Fixed KeyError exceptions** in proxy server when status response missing `version` or `git_hash` keys by implementing defensive key access with `.get()` method
  - **Fixed KeyError exceptions** when auth dictionary missing `AuthCookie` or `UserRecord` keys in cookie mode, now uses safe fallbacks
  - **TEDAPI Performance Improvements**: Optimized core TEDAPI functions (`get_config`, `get_status`, `get_device_controller`, `get_firmware_version`, `get_components`, `get_battery_block`) with cache-before-lock pattern to reduce lock contention
  - **Removed redundant API calls** in TEDAPI wrapper functions to improve response times
  - **Enhanced multi-threading support** for concurrent proxy requests with reduced lock timeout errors
  - **Improved error resilience** for different connection modes (local vs TEDAPI) that return varying data structures

* **Enhanced Health Monitoring**: Added comprehensive endpoint statistics tracking for better observability and debugging.
  - **Endpoint Call Statistics**: Added tracking of successful and failed API calls per endpoint with success rate calculations
  - **Enhanced `/health` endpoint**: Now includes detailed statistics showing:
    - Total calls, successful calls, and failed calls per endpoint
    - Success rate percentage for each endpoint
    - Time since last success and last failure for each endpoint
    - Overall proxy response counters (total_gets, total_posts, total_errors, total_timeouts)
  - **Improved `/health/reset` endpoint**: Now also clears endpoint statistics along with health counters and cache
  - **Automatic tracking**: All endpoints using `safe_endpoint_call()` automatically tracked (includes `/aggregates`, `/soe`, `/vitals`, `/strings`, etc.)

### Proxy t78 (14 Jul 2025)

* Power flow animation update: Show an image of a Powerwall 3 instead of a Powerwall 2 if it is a PW3 by @JEMcats in https://github.com/jasonacox/pypowerwall/pull/193

## v4.8.2 - pypowerwall Updates

* Update pypowerwall version for connection health monitoring and graceful degradation.
* Minor improvements to Docker Compose healthcheck configurations.
* Documentation updates for route management and TEDAPI access changes.

## v4.8.1 - Hotfix for Setup

* Fix breaking error with `setup.sh` script that caused it to fail during geo-location lookup. Improve location parsing to handle JSON errors gracefully.
* Added a prominent notice to the top of the README warning users that, as of Powerwall Firmware 25.10.0+, network routing to the TEDAPI endpoint (192.168.91.1) is no longer supported. Users are instructed to connect directly to the Powerwall's WiFi and can remove old routes using `./add_route.sh -disable`.
* Improved `add_route.sh`:
    * The `-disable` option now reliably removes the static route on Linux systems, even if the Powerwall IP is not set, preventing command errors.
    * The script checks for `-disable` before any prompts or warnings, for a smoother user experience.
    * Documentation and user prompts updated for clarity.

## v4.8.0 - Healthchecks & Watchdog

* Enhanced Docker Compose healthchecks for all services (`influxdb`, `pypowerwall`, `telegraf`, `grafana`, `weather411`), addresses https://github.com/jasonacox/Powerwall-Dashboard/issues/642
* Added optional `watchdog.sh` script to monitor `pypowerwall` container and restarts if unhealthy.
    * `-enable` option adds watchdog to crontab (every 5 min)
    * `-disable` option removes watchdog from crontab
    * `-debug` for verbose output; `-h/--help` for usage.
* Refactor and feature additions to InfluxDB Viewer (`viewer.py`):
    * Interactive shell-like interface with colorized and tabular output.
    * Tab completion for commands and queries.
    * `--nocolor` option for plain output.
    * Added help and error handling.

## v4.7.2 - TEDAPI Updates

* Added InfluxDB interactive tool for troubleshooting - https://github.com/jasonacox/Powerwall-Dashboard/tree/main/tools/influxdb-viewer
* Updated dashboard.json to add total Powerwall capacity graph in addition to separate PW stats. This is helpful for systems with PW3 + DC Expansion packs. See https://github.com/jasonacox/Powerwall-Dashboard/issues/632
* Update pypowerwall to v0.13.1 (t75)
* See updates: https://github.com/jasonacox/pypowerwall/releases/tag/v0.13.0
    * Use Neurio for TEDAPI data when Tesla Remote Meter is not present by @Nexarian 
    * Add connection pool to TEDAPI by @Nexarian
    * Add METER_Z (Backup Switch) data to vitals and aggregates data 
    * Fix logic for aggregates API for consolidated voltage and current data by @jasonacox
* See updates: https://github.com/jasonacox/pypowerwall/releases/tag/v0.13.1
    * Fix missing battery_blocks data on PW3 with Multiple Powerwalls in Local Mode in [#131](https://github.com/jasonacox/pypowerwall/issues/131)
    * Fix errant API base URL check. by @Nexarian in [#185](https://github.com/jasonacox/pypowerwall/pull/185)
    * Update TEDAPI to pull battery blocks from vitals for PW3 Systems by @jasonacox in [#184](https://github.com/jasonacox/pypowerwall/pull/184)

## v4.7.1 - Multiple PW3 Strings

* Update pypowerwall to v0.12.12 - See updates: https://github.com/jasonacox/pypowerwall/releases/tag/v0.12.12
    * Bug Fix - Logic added in https://github.com/jasonacox/pypowerwall/pull/169 does not iterate through all PW3 strings. This adds logic to handle multiple PW3 string sets. Reported in https://github.com/jasonacox/pypowerwall/issues/172 by @heynorm
    * Proxy t73 (10 May 2025) - Add `/json` route to return basic metrics:

```json
{
  "grid": -3,
  "home": 917.5,
  "solar": 5930,
  "battery": -5030,
  "soe": 61.391932759907306,
  "grid_status": 1,
  "reserve": 20,
  "time_remaining_hours": 17.03651226158038
}
```

## v4.7.0 - Firmware 25.10.x

* Starting with Powerwall Firmware 24.10.0 and later, Powerwalls no longer allows routed access to the TEDAPI interface (needed for Powerwall 3 and extended metrics data)
* Updated documentation and setup script to instruct users that direct WiFi access is required for TEDAPI access.

## v4.6.7 - Dashboard Fixes

* Fixed mismatched Powerwall references in pwtemps queries of "Powerwall Temps and Fans" and removed a duplicate query by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/618
* Fixed issue where Powerwall Dashboard version shows "No data" if time filter set to >3d ago by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/618
* Revised dashboard JSON definitions to remove irrelevant queries when rawQuery is false by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/618
* README: Fix path for restore tar by @jasonacox in https://github.com/jasonacox/Powerwall-Dashboard/commit/3c55ed5834ee4302752b0f50a1542e1644027557
* Update pypowerwall to v0.12.11 - See updates: https://github.com/jasonacox/pypowerwall/releases/tag/v0.12.11

## v4.6.6 - Fan Speeds

* Update pypowerwall to v0.12.9, adds vitals metrics for fan speed, fixes bug with FullPackEnergy calcs, improve thread locking for TEDAPI and adds CSV headers. See release notes: https://github.com/jasonacox/pypowerwall/releases
* Update dashboard to show fan speeds on temperature graph.

<img width="888" alt="image" src="https://github.com/user-attachments/assets/3eb14b9e-fd6a-422b-880d-02545d5e4b05" />

## v4.6.5 - Coordinates

* Update `setup.sh` to check for existing LAT and LONG coordinate setting in SunAndMoon auto-provision datasource as reported in https://github.com/jasonacox/Powerwall-Dashboard/issues/589#issuecomment-2704639794.
* Provide disclaimer that 'already exist' errors are harmless as reported in https://github.com/jasonacox/Powerwall-Dashboard/issues/597

## v4.6.4 - InfluxDB Auto

* Fix URI too long issue by adding `POST` method for InfluxDB Auto-provision datasource in Grafana reported in https://github.com/jasonacox/Powerwall-Dashboard/issues/591 by @devachnid.
* Update InfluxDB auto-provisioning to allow user editing.

## v4.6.3 - SunAndMoon Edit

* Update SunAndMoon datasource auto-provisioning to allow user to edit location.
* Add location LAT and LONG confirmation as part of setup.sh script.

## v4.6.2 - Normalize Alerts

Updates to pyPowerwall v0.12.7 which includes:
* Improvements to grid status connected by @Nexarian in https://github.com/jasonacox/pypowerwall/pull/139
* Fix an issue in TEDAPI where the grid status is not accurately reported in certain edge cases. Now, only the "SystemConnectedToGrid" alert will appear if it is present in alerts API. This update also eliminates the risk of duplicate and redundant (e.g. "SystemGridConnected") alerts.
* Updated aggregates call to include site current (METER_X) and external PV inverter data in solar (METER_Y) by @jasonacox in https://github.com/jasonacox/pypowerwall/pull/142. Reported in Issue #140 by @felberch.
* Alerts in extract_grid_status can be None. This fix addresses this edge case. Fix by @Nexarian in https://github.com/jasonacox/pypowerwall/pull/145
Dashboard updates:
* 580 Use F_Voltage field for string voltage by @davemckelvie in https://github.com/jasonacox/Powerwall-Dashboard/pull/581

## v4.6.1 - pyPowerwall Updates

Updates to using pypowerwall v0.12.4 t68 which includes:
* v0.12.4: Address bug iin TEDAPI logic on some systems where Neurio CTS data was not getting processed. Discovery by @anderep in https://github.com/jasonacox/Powerwall-Dashboard/discussions/578#discussioncomment-12033087 - Issue https://github.com/jasonacox/pypowerwall/issues/136 and PR https://github.com/jasonacox/pypowerwall/pull/137. Also adds /csv/v2 API support by @jasonacox in https://github.com/jasonacox/pypowerwall/pull/134
* v0.12.3: Proxy vFix TEDAPI URL from constant GW_IP to constructor selectable host gw_ip by @Nexarian in https://github.com/jasonacox/pypowerwall/pull/129 - The hard-coded 192.168.91.1 for the TEDAPI internal endpoint doesn't work if you're using NAT. This change enables support for this use-case. See https://gist.github.com/jasonacox/91479957d0605248d7eadb919585616c?permalink_comment_id=5373785#gistcomment-5373785 for NAP implementation example.
* v0.12.2: Fix bug in cache expiration timeout code that was not honoring pwcacheexpire setting. Raised by @erikgieseler in https://github.com/jasonacox/pypowerwall/issues/122 - PW_CACHE_EXPIRE=0 not possible? (Proxy) - Fix by @jasonacox in https://github.com/jasonacox/pypowerwall/pull/123. Adds WARNING log in proxy for settings below 5s. Changes TEDAPI config default timeout from 300s to 5s and links to pwcacheexpire setting.
* v0.12.1: Large-scale refactor of Powerwall scan function by @Nexarian in https://github.com/jasonacox/pypowerwall/pull/117

## v4.6.0 - Powerwall Temps

* Updates to pypowerwall proxy v0.12.0 t66 (https://github.com/jasonacox/pypowerwall/pull/114) which supports a new TEDAPI call to gather vitals that includes Powerwall Temps.
* Updates `telegraf.conf` to read Dashboard VERSION using `ver.sh`.
* Updates `dashboard.json` to include Powerwall Temps and current Dashboard Version.
* Add support for pypowerwall environmental variable `PW_NEG_SOLAR` to allow users to zero out negative values (see `pypowerwall.env.xample`)

<img width="1137" alt="image" src="https://github.com/user-attachments/assets/70f2e40a-ca63-413e-9889-b048a98fab6e">

## v4.5.5 - Hotfix

* Fix bug introduced in jasonacox/Powerwall-Dashboard/issues/535 as reported in https://github.com/jasonacox/Powerwall-Dashboard/issues/537 by @wagisdev

## v4.5.4 - Misc Bug Fixes

* Fix two spelling mistakes in upgrade script by @wreiske in https://github.com/jasonacox/Powerwall-Dashboard/pull/521
* Fix PW3 Strings E+F metrics by @jplewis2 in https://github.com/jasonacox/Powerwall-Dashboard/pull/528
* k3s/kubernettes install by @cfoos in https://github.com/jasonacox/Powerwall-Dashboard/pull/525
* Fix bug in setup.sh for MacOS hosts #534 by @jasonacox in https://github.com/jasonacox/Powerwall-Dashboard/pull/535

## v4.5.3 - TEDAPI Route Tool

* New `add_route.sh` tool to add persistent TEDAPI network routing by @SCHibbard in https://github.com/jasonacox/Powerwall-Dashboard/pull/520 
* User can run `add_route.sh` to create a persistent route to the Powerwall TEDAPI endpoint. This can be run before `setup.sh` to allow [extended data local mode](https://github.com/jasonacox/Powerwall-Dashboard?tab=readme-ov-file#local-mode) for PW3 and PW2/+ systems. Existing user can also run this to set the route and re-run `setup.sh` to select the extended local mode.

## v4.5.2 - PW3 and FleetAPI Fixes

* Updates [pyPowerwall to v0.11.1](https://github.com/jasonacox/pypowerwall/pull/112) to fix a PW3 bug in TEDAPI and a site ID bug in FleetAPI.
* Fix bug in `verify.sh` reporting TEDAPI vitals capabilities incorrectly as identified by @SCHibbard in https://github.com/jasonacox/Powerwall-Dashboard/issues/515.
* Update gitattributes to force .env files to have LF line ending by @longzheng in https://github.com/jasonacox/Powerwall-Dashboard/pull/511.

## v4.5.1 - Powerwall 3 Metrics

* Updates [pyPowerwall to v0.11.0](https://github.com/jasonacox/pypowerwall/pull/110) to include PW3 Vitals: string data, capacity, voltages, frequencies, and alerts.
* Updates InfluxDB CQs to include Strings E-F and expands support for up to 6 Inverters (sets of Strings)

## v4.5.0 - Auto Provision Datasources

* Setup: Automatically set up the InfluxDB and Sun-and-Moon data sources in Grafana by @longzheng in https://github.com/jasonacox/Powerwall-Dashboard/pull/512 
* This adds an "(auto provisioned)" suffix to the data source name to prevent breaking exiting installations and to allow custom configurations.
* Setup now attempts to automatically detect latitude and longitude for Sun-and-Moon and Weather setup.

## v4.4.6 - Current and Voltage

* Add data points for system current and voltages (solar, home, grid and powerwall). Includes continuous queries and dashboard.json update. Currently only viable for local mode, non-PW3, systems.
* Upgrade pypowerwall proxy to v0.10.9 to include TEDAPI mode patch that adds computed voltage and current to aggregates (https://github.com/jasonacox/pypowerwall/pull/107).

## v4.4.5 - PW3 Updates

* Powerwall 3 Setup Help - If local setup is selected, it will work with the Powerwall 3 but will produce errors in pypowerwall and not have the complete data. This updates `setup.sh` so ensure Powerwall 3 setups use `full` TEDAPI mode for local access. Raised by @pavandave in https://github.com/jasonacox/Powerwall-Dashboard/issues/492.
* Add check in `setup.sh` script to ensure user has permission to write to the current directory. Raised in https://github.com/jasonacox/Powerwall-Dashboard/discussions/494. 
* Update to latest pypowerwall, updates TEDAPI to provide correct Powerwall firmware version. Discovered by @geptto in https://github.com/jasonacox/pypowerwall/issues/97. This function has been integrated into pypowerwall existing APIs and proxy features.

## v4.4.4 - Bug Fixes

* Fix setup.sh gateway detection logic to better work on Synology and other host without user `ping` commands as raised by @zcpnate in #488
* Update to pypowerwall 0.10.6: pyLint code optimization, fix timeout logic for TEDAPI and FleetAPI modes, fix battery backup reserve level scaling for TEDPAI mode, fix grid status bug in FleetAPI mode and fix control mode error in proxy.

## v4.4.3 - Minor Fixes

* Update to pypowerwall 0.10.5:

    * Fix for TEDAPI "full" (e.g. Powerwall 3) mode, including `grid_status` bug resulting in false reports of grid status, `level()` bug where data gap resulted in 0% state of charge and `alerts()` where data gap from tedapi resulted in a `null` alert.
    * Add TEDAPI API call locking to limit load caused by concurrent polling.
    * Proxy - Add battery full_pack and remaining energy data to `/pod` API call for all cases.

## v4.4.2 - Powerwall 3 Local Support

* Update to pypowerwall v0.10.4 to add support for Powerwall 3 using local Gateway only. 
* Setup script adjusted to allow for Powerwall 3 local mode option.

## v4.4.1 - FleetAPI Hotfix

* Update to pypowerwall v0.10.2 to fix FleetAPI setup but as raised in https://github.com/jasonacox/pypowerwall/issues/98.
* Update `setup.sh` to add optional command line switch `-f` for standalone FleetAPI mode setup.

## v4.4.0 - FleetAPI and TEDAPI

* Add TEDAPI Support for Extended Device Metrics (the return of most of `/vitals`) - This requires connecting to Powerwall WiFi directly or setting up a network route on the Dashboard host to allow it to reach the GW address (192.168.91.1).
* Add support for Tesla's official API, [FleetAPI](https://developer.tesla.com/docs/fleet-api). This requires additional registration and configuration. Instructions are part of setup process or on the project page.
* Run `upgrade.sh` and then run `setup.sh` to choose these new options.
* Upgrade to [pyPowerwall v0.10.0](https://github.com/jasonacox/pypowerwall/releases/tag/v0.10.0) proxy t58 - Release addresses some issues, including fixing Solar Only grid_status issues as reported by @lsgc123 in https://github.com/jasonacox/Powerwall-Dashboard/issues/478
* Fix setup.sh for docker group permission bug identified by @hulkster in #476

* Addresses several open issues and discussions: 
    * https://github.com/jasonacox/Powerwall-Dashboard/discussions/392
    * https://github.com/jasonacox/Powerwall-Dashboard/discussions/402
    * https://github.com/jasonacox/Powerwall-Dashboard/issues/436
    * https://github.com/jasonacox/Powerwall-Dashboard/issues/472

## v4.3.2 - Solar Only Fix

* Upgrade to pyPowerwall v0.8.5 proxy t56
* Fix bug with setup for certain Solar Only systems where clod mode process fails due to missing `site_name`. Identified by @hulkster in https://github.com/jasonacox/Powerwall-Dashboard/discussions/475

## v4.3.1 - Control APIs

* Upgrade to pyPowerwall v0.8.4 proxy t55
* Fix /pod API to add time_remaining_hours and backup_reserve_percent for cloud mode.
* Dashboard: Removed Powerwall temperature panel in default dashboard (data is no longer available with latest Firmware)
* Added GET `/control/mode` and `/control/reserve` APIs to retrieve operating mode and back reserve settings
* Added POST `/control/mode` and `/control/reserve` APIs to set operating mode and back reserve settings. Requires running setup and setting PW_CONTROL_SECRET for pypowerwall in `pypowerwall.env`. Use with caution.

```bash
# Setup cloud mode for pypowerwall container
docker exec -it pypowerwall python3 -m pypowerwall setup -email=example@example.com

MODE=self_consumption
RESERVE=20
PW_CONTROL_SECRET=mySecretKey

# Set Mode
curl -X POST -d "value=$MODE&token=$PW_CONTROL_SECRET" http://localhost:8675/control/mode

# Set Reserve
curl -X POST -d "value=$RESERVE&token=$PW_CONTROL_SECRET" http://localhost:8675/control/reserve

# Read Settings
curl http://localhost:8675/control/mode
curl http://localhost:8675/control/reserve
```

## v4.3.0 - pyPowerwall 0.8.2

* Upgrade to pyPowerwall proxy v0.8.2 - Major refactoring of code in https://github.com/jasonacox/pypowerwall/pull/77 and https://github.com/jasonacox/pypowerwall/pull/78 and addition of new Alerts.
* Disable `GF_PATHS_PROVISIONING` from `grafana.env` base to speed up Grafana startup by @BuongiornoTexas in #461

## v4.2.1 - Docker V2 Fix

* Fixed `upgrade.sh` to support `docker-compose` (V2) command as discussed in #459.
* Updated `setup.sh` to check for Docker Compose V2.

## v4.2.0 - Remove Docker V1

* Remove support for Docker V1 since it is obsolete. Upgrade progress will alert V1 users to upgrade to V2 before proceeding. Updates by @BJReplay in https://github.com/jasonacox/Powerwall-Dashboard/pull/454.

## v4.1.3 - Alerts & Strings

* Updated to using pyPowerwall to v0.7.12 which brings some Alerts and String data back for systems with Firmware 23.44.0+. New library uses `/api/solar_powerwall` instead of now depreciated `/api/devices/vitals` by @DerickJohnson in https://github.com/jasonacox/pypowerwall/pull/75 and by @jasonacox in https://github.com/jasonacox/pypowerwall/pull/76.

## v4.1.2 - Cache 404 Responses

* Updated pyPowerWall to v0.7.11 to add cache and extended TTL for 404 responses from Powerwall as identified in issue jasonacox/Powerwall-Dashboard#449 by @jgleigh. This will help reduce load on Powerwall gateway that may be causing rate limiting for some users (Firmware 23.44.0+).
* Updated logic to disable vitals API calls for Firmware 23.44.0+
* Added rate limit detection (429) and cooldown mode to allow Powerwall gateway time to recover.

## v4.1.1 - Revert Change

* Problems identified with older `docker-compose` versions. Revering upgrade.sh changes but pushing new plugin list in `grafana.env.sample` for new installations.

## v4.1.0 - Grafana Plugin Updates

* Update plugin list for Grafana, removing unneeded plugins (e.g. `flux datasource`) and adding logic to upgrade script to prune old `grafana.env` settings by @BuongiornoTexas in #442 #433

## v4.0.5 - Dashboard Updates

* Updated timezone variable in `dashboard.json` to tz:text to ensure the Time Zone string is output as-is. This will make upgrading Grafana easier later on and future-proof the variables by @s-crypt in #439.
* Removed $tz from any queries that do not have a GROUP BY statement by @s-crypt in #439.
* Updated pyPowerWall Proxy t42 - Adds Power Flow Animation style (set PW_STYLE="solar") for Solar-Only display. Removes the Powerwall image and related text to display a Grid + Solar + Home power flow animation.

## v4.0.4 - Cloud Grid Status

* Update to pyPowerWall v0.7.9 - Bug fix to render correct grid status for Solar-Only systems on cloud mode (see #437)

## v4.0.3 - Cloud Mode Fixes

* Fix enumeration of energy sites during `cloud mode` setup to handle incomplete sites with Unknown names or types by @dcgibbons in https://github.com/jasonacox/pypowerwall/pull/72 
* pyPowerwall Proxy t41 Updates - Bug fixes for Solar-Only systems using `cloud mode` (see https://github.com/jasonacox/Powerwall-Dashboard/issues/437).

## v4.0.2 - Dashboard Update

* Update default `dashboard.json` to not connect null values over 1hr threshhold (corrctly representing data gaps) by @youzer-name in #430.
* Stack powerwall current energy values in Powerwall Capacity panel by @youzer-name in #430.
* Add "Off Grid" indicators to the bottom of the Frequency and Voltages panels by @youzer-name in #430.

## v4.0.1 - Powerwall Voltages

* Added CQs and updated `dashboard.json` to include voltages from battery block vitals by @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/426. This addresses users no longer seeing Powerwall voltages in the dashboard with firmware 23.44.0 or later - See related https://github.com/jasonacox/Powerwall-Dashboard/discussions/109#discussioncomment-8263020

## v4.0.0 - Cloud Mode Support

* Using pyPowerwall for both Local Access and Tesla Cloud mode by @jasonacox and @mcbirse in https://github.com/jasonacox/Powerwall-Dashboard/pull/414 (replaces Tesla-history service, but the Tesla-history tool will continue to be used to fill in historic data or gaps) - See related https://github.com/jasonacox/pypowerwall/pull/59
* Removal of Docker Compose profiles (helps with some older systems that don't fully support this) and the v1 related legacy support.
* Updated `setup.sh` and `upgrade.sh` to support transition to pyPowerwall for Tesla Cloud mode.
* Updated `verify.sh` to support Tesla Cloud mode.
* Updated dashboard for solar-only users to include Powerflow Animation panel.

## v3.0.8 - Critical Bug Fix

* Fixes bug in pypowerwall proxy container version before `jasonacox/pypowerwall:0.7.6t39` related to API calls and 404 HTTP status codes handling. Powerwall Firmware version 23.44.0 has eliminated /api/devices/vitals resulting in a 404 response from the Powerwall Gateway (TEG) when this is requested. There was a bug in the pypowerwall code that will treat this 404 like an authentication failure which will result in attempts to log in over and over, eventually hitting the rate limit. This is especially impactful for those using the proxy for things like Powerwall-Dashboard as the rate limit will prohibit other data gathering.

## v3.0.7 - InfluxDB Environment Variables

* Add support to define InfluxDB configuration options by environment variable by @mcbirse. This allows the default configuration settings to be overridden and addresses https://github.com/jasonacox/Powerwall-Dashboard/discussions/408 raised by @youzer-name
* Change InfluxDB statistics recording to false by default to reduce CPU load by @youzer-name in https://github.com/jasonacox/Powerwall-Dashboard/pull/410
* Update example backup script to use tar.xz (-J option) by @s-crypt in https://github.com/jasonacox/Powerwall-Dashboard/pull/404 and https://github.com/jasonacox/Powerwall-Dashboard/pull/405 see https://github.com/jasonacox/Powerwall-Dashboard/issues/337
* [[Tools](https://github.com/jasonacox/Powerwall-Dashboard/tree/main/tools)] - default to bash in `pwstatus` script for better compatibility by @mcbirse see https://github.com/jasonacox/Powerwall-Dashboard/discussions/249#discussioncomment-7935882

## v3.0.6 - Powerflow Animation Update

* Update to latest pypowerwall proxy t29:
* Default page loaded by proxy (http://localhost:8675/) will render Powerflow Animation. Animation assets (html, css, js, images, fonts, svg) will render from local filesystem instead of pulling from Powerwall TEG portal resulting in faster render time.

## v3.0.5 - Bug Fix for MacOS

* README: fix "Powerall" typo in Powerwall 3 section by @kenyon in #399
* v3.0.4 - Fix `upgrade.sh` to address issue where get_profile() function incorrectly reads compose.env causing upgrade failure by @jasonacox in #401 Closes issue #400.
* v3.0.5 - Fix `setup.sh`, `compose-dash.sh`, `verify.sh` and `weather.sh` by @mcbrise in https://github.com/jasonacox/Powerwall-Dashboard/commit/45428ab56aa18ef2a04dce0f56e527b0a48c606d

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
* Fix `verify.sh` to run on Windows OS in https://github.com/jasonacox/Powerwall-Dashboard/commit/25b77e53310d1668b2b3868e59fac55b82286f

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
