# Tools

This directory contains a list of tools discovered or developed by the community to make the most of your Powerwall Dashboard. If you have a great tool or trick that you think the community would enjoy, please open an [issue](https://github.com/jasonacox/Powerwall-Dashboard/issues) or [pull request](https://github.com/jasonacox/Powerwall-Dashboard/pulls) to get it added here.

## Tesla History Import Tool

This is a command line tool to import Powerwall history data from the Tesla Cloud into Powerwall-Dashboard.

* Author: [@mcbirse](https://github.com/mcbirse) - see issue [#12](https://github.com/jasonacox/Powerwall-Dashboard/issues/12) if you have any questions or find problems.
* [Details and Instructions](tesla-history/)
* Script: [tesla-history.py](tesla-history/tesla-history.py)

## Weather History Import Tool

This is a command line tool to import weather history data from OpenWeatherMap into Powerwall-Dashboard.

* Author: [@mcbirse](https://github.com/mcbirse) - see discussion [#146](https://github.com/jasonacox/Powerwall-Dashboard/discussions/146) if you have any questions or find problems.
* [Details and Instructions](weather-history/)
* Script: [weather-history.py](weather-history/weather-history.py)

## Ecowitt Weather History Import Tool

This is a command line tool to import weather history data from the Ecowitt API into Powerwall-Dashboard.

* Author: [@BJReplay](https://github.com/BJReplay) - see discussion [#145](https://github.com/jasonacox/Powerwall-Dashboard/discussions/145) if you have any questions or find problems.
* [Details and Instructions](ecowitt-weather-history/)
* Script: [ecowitt-weather-history.py](ecowitt-weather-history/ecowitt-weather-history.py)

## PVoutput Export Tool

This is a command line tool to publish your solar production data to [PVoutput.org](https://pvoutput.org/), a free service for publicly sharing and comparing PV output data.

* [Details and Instructions](pvoutput/)
* Script: [pvoutput.py](pvoutput/pvoutput.py)

## Fix Month Tags Tool

Prior to Powerwall-Dashboard v2.6.3, "month" tags of InfluxDB data were based on UTC only, resulting in data points with incorrect month tags for the local timezone.

This command line tool can be used to search InfluxDB for incorrect month tags for your timezone and correct the data. A backup is recommended before use.

* Author: [@mcbirse](https://github.com/mcbirse)
* [Details and Instructions](fixmonthtags/)
* Script: [fixmonthtags.py](fixmonthtags/fixmonthtags.py)

## MySQL Connector

This includes step-by-step set of instructions and scripts for adding MySQL to the Powerwall Dashboard, including the monthly charts and time of use pricing.

* Author: [@youzer-name](https://github.com/youzer-name) and Collaborator: [@BJReplay](https://github.com/BJReplay) - Join discussion [#82](https://github.com/jasonacox/Powerwall-Dashboard/discussions/82) if you have any questions or find problems.
* [Details and Instructions](mysql/)

## NodeRed

Several in the community use NodeRed to help automate usage of their Solar and Powerwall data.

* [NodeRed.org](https://nodered.org/) - Low-code programming for event-driven applications

## Solar Only Systems

For Tesla Solar owners who don't have a Powerwall, to get a similar dashboard for their systems, Powerwall Dashboard can be installed in "solar-only" mode. This setup uses the `tesla-history` script developed by [@mcbirse](https://github.com/mcbirse) to grab power metrics from the Tesla Cloud.

This folder contains an example Solar Only dashboard and setup instructions, and upgrade instructions for users who were involved in the beta testing to migrate their existing install without losing data.

* [Solar Only Setup](solar-only/)

## InfluxDB 2.x Support

This includes optional files and instructions to help setup InfluxDB 2.x (instead of 1.8) as the database for the Dashboard. Thanks to @ThePnuts for developing the many flux queries required to replace the 1.8 version continuous queries as well as the Grafana queries in the dashboard.json.

* [InfluxDB 2.x Support](influxdb2/)

## Powerwall Status Monitor and API Request Dumper

This tool is a shell script designed to run as a system service to monitor status of grid, battery percentage, and firmware version, and send an e-mail alert when changes are detected or low battery reached. It is also useful as a command line API request dumper.

* Author: [@mcbirse](https://github.com/mcbirse)
* [Details and Instructions](pwstatus/)
* Script: [pwstatus.sh](pwstatus/pwstatus.sh)

## Powerwall Dashboard on Kubernetes

Run Powerwall Dashboard on k3s. These config files assume you are using metallb for ingress and rook-ceph for storage. Local storage pvc configs are provided for testing but should not be used in deployment.

* Author: [@cfoos](https://github.com/cfoos)
* [Details and Instructions](k3s/)

## InfluxDB Viewer Tool

A command-line and interactive shell tool for exploring and querying InfluxDB databases. This tool allows you to browse retention policies, measurements, and fields, and to query the last hour of data for any field in your InfluxDB instance. It is ideal for quick data inspection, troubleshooting, and learning the structure of your InfluxDB data.

* Author: [@jasonacox](https://github.com/jasonacox)
* [Details and Instructions](influxdb-viewer/README.md)
* Script: [viewer.py](influxdb-viewer/viewer.py)
