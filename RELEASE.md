# RELEASE NOTES

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
