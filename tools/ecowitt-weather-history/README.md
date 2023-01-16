# Ecowitt Weather History Import Tool

This is a command line tool to retrieve weather history data from Ecowitt API and import into InfluxDB of Powerwall-Dashboard. This tool was submitted by [@BJReplay](https://github.com/BJReplay), shamelessly based on the tool written by [@mcbirse](https://github.com/mcbirse) - thanks for the inspiration.

## Features

This script, [ecowitt-weather-history.py](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/tools/ecowitt-weather-history/ecowitt-weather-history.py) can be used to import historical weather data by date/time period into Powerwall-Dashboard.

This could be useful for instance to import data from before you started using Powerwall-Dashboard or the contrib/weather/ecowitt container. It can also be used to fill in missing data (data gaps) for periods where Powerwall-Dashboard or ecowitt stopped working (e.g. system down, or lost communication with Ecowitt API).

## Ecowitt API

Historical weather data from Ecowitt is available provided you have set up an API key as described for the contrib/ecowitt weather service and only for the time that your local weather station was uploading data.

## Data Observations and Notes

This is generally available in: 
* 5 minutes resolution data within the past 90days, each data request time span should not be longer than a complete day；
* 30 minutes resolution data within the past 365days, each data request time span should not be longer than a complete week；
* 240 minutes resolution data within the past 730days, each data request time span should not be longer than a complete month；
* 24hours resolution data since 2019.1.1, each data request time span should not be longer than a complete year;
* 24 hours resolution data within the past 7days, each data request time span should not be longer than a complete day.

Gap detection is based on these rules:
* if the time period is within the last 90 days, it looks for gaps of 5 minutes;
* if the time period is between 90 days and 365 days, it looks for gaps of 30 minutes;
* if the time period is between 365 days and 730 days, it looks for gaps of 240 minutes;
* if the time period is between 730 days and 2019-01-01, it looks for gaps of 1,440 minutes;


Finally, the data imported by this tool will not overwrite existing data. It will add data to the same field names as Ecowitt (localweather) which will update the following same panels that refer to the localweather measurement.

## Usage

To use the script:
* Set up your API key as described at: https://github.com/jasonacox/Powerwall-Dashboard/tree/main/weather/contrib/ecowitt#ecowitt-local-weather-server
* Install the required python modules:
  ```bash
  pip install python-dateutil influxdb
  ```
* Follow the steps below

### Setup

On first use, it is recommended to use the `--setup` option. This will create the config file without retrieving history data.

```bash
# Run setup to create or update configuration
python3 ecowitt-weather-history.py --setup
```

Initial configuration defaults will be sourced from the ecowitt config file, when found. If the location of this file is different, it can be specified with the `--ecowitt` option.

Setup will then run in an interactive mode. The example below shows the config creation:

```
---------------------------------------------------
Weather History Import Tool for Powerwall-Dashboard
---------------------------------------------------

Config file 'weather-history.conf' not found

Do you want to create the config now? [Y/n]

Loaded [defaults] from '/home/admin/Powerwall-Dashboard/weather/contrib/ecowitt/ecowitt.conf'...

Ecowitt Setup
--------------------
Historical weather data from Ecowitt can be imported into your
Powerwall Dashboard graphs.

API Key: [xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx]
APP Key: [xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx]
MAC: [XX:XX:XX:XX:XX:XX]
Units - M)etric, I)mperial or S)tandard: [M]

InfluxDB Setup
--------------
Host: [localhost]
Port: [8086]
User (leave blank if not used): [blank]
Pass (leave blank if not used): [blank]
Database: [powerwall]
Field: [localweather]
Timezone (e.g. America/Los_Angeles): Australia/Victoria

Config saved to 'ecowitt-weather-history.conf'
```

In most cases, the `[default]` values will be correct and can be accepted by pressing Enter, however these can be changed if you have a custom setup.

Saved config values can also be changed at any time by running with the `--setup` option again.

Once the configuration is complete, you can then run the script to retrieve historical weather data.

### Basic script usage and examples

To import history data from OpenWeatherMap for a given start/end period, use the `--start` and `--end` options (date/time range is inclusive and in format `YYYY-MM-DD hh:mm:ss`):

```bash
# Get history data for start/end period
python3 ecowitt-weather-history.py --start "2022-08-01" --end "2022-09-01"
```

By default, the script will search InfluxDB for data gaps and fill gaps only, so you do not need to identify time periods where you have missing data, as this will be done automatically.

The "gap" threshold is the same as the history interval and is identical to the detail available from the Ecowitt API - so five minute gaps for the last 90 days, but only daily gaps after two years.

You may want to run in test mode first for a short time period. This could be done by using the `--test` option:

```bash
# Run in test mode with --test (will not import data)
python3 ecowitt-weather-history.py --start "2022-08-01" --end "2022-08-01" --test
```

Example output:

```
---------------------------------------------------
Weather History Import Tool for Powerwall-Dashboard
---------------------------------------------------
Running for period: [2022-08-01 12:00:00+10:00] - [2022-08-01 13:00:00+10:00] (1:00:00s)

Searching InfluxDB for data gaps >= 10 minutes
* Found data gap: [2022-08-01 12:00:00+10:00] - [2022-08-01 13:00:00+10:00] (1:00:00s)

Retrieving data for gap: [2022-08-01 12:00:00+10:00] - [2022-08-01 13:00:00+10:00] (1:00:00s)
* Loading data for time: [2022-08-01 12:00:00+10:00]
* Loading data for time: [2022-08-01 12:30:00+10:00]
* Loading data for time: [2022-08-01 13:00:00+10:00]

Writing to InfluxDB (*** skipped - test mode enabled ***)
Done.
```

If you prefer, you can abort the script by pressing Ctrl-C and you will be given the option to quit and still write the data retrieved to that point to InfluxDB.

```
---------------------------------------------------
Weather History Import Tool for Powerwall-Dashboard
---------------------------------------------------
Running for period: [2022-08-01 00:00:00+10:00] - [2022-09-01 00:00:00+10:00] (31 days, 0:00:00s)

Searching InfluxDB for data gaps >= 30 minutes
* Found data gap: [2022-08-01 02:30:00+10:00] - [2022-08-01 06:00:00+10:00] (3:30:00s)
* Found data gap: [2022-08-01 12:00:00+10:00] - [2022-08-22 22:37:51+10:00] (21 days, 10:37:51s)

Retrieving data for gap: [2022-08-01 03:00:00+10:00] - [2022-08-01 05:59:59+10:00] (2:59:59s)
* Loading data for time: [2022-08-01 03:00:00+10:00]
* Loading data for time: [2022-08-01 03:30:00+10:00]
* Loading data for time: [2022-08-01 04:00:00+10:00]
* Loading data for time: [2022-08-01 04:30:00+10:00]
* Loading data for time: [2022-08-01 05:00:00+10:00]
* Loading data for time: [2022-08-01 05:30:00+10:00]
Retrieving data for gap: [2022-08-01 12:30:00+10:00] - [2022-08-22 22:37:50+10:00] (21 days, 10:07:50s)
* Loading data for time: [2022-08-01 12:30:00+10:00]
* Loading data for time: [2022-08-01 13:00:00+10:00]
* Loading data for time: [2022-08-01 13:30:00+10:00]
* Loading data for time: [2022-08-01 14:00:00+10:00]
* Loading data for time: [2022-08-01 14:30:00+10:00]

Writing to InfluxDB
Done.
```

Some convenience date options are also available (e.g. these could be used via cron):

```bash
# Convenience date options (both options can be used in a single command if desired)
python3 ecowitt-weather-history.py --today
python3 ecowitt-weather-history.py --yesterday
```

For more usage options, run without arguments or with the `--help` option:

```bash
# Show usage options
python3 ecowitt-weather-history.py --help
```

```
usage: ecowitt-weather-history.py [-h] [-s] [-t] [-d] [--config CONFIG] [--ecoconf ECOCONF] [--force] [--start START] [--end END] [--today] [--yesterday]

Import weather history data from Ecowitt API 3.0 into InfluxDB

options:
  -h, --help           show this help message and exit
  -s, --setup          run setup to create or update configuration only (do not get history)
  -t, --test           enable test mode (do not import into InfluxDB)
  -d, --debug          enable debug output (print raw responses from OpenWeatherMap)

advanced options:
  --config CONFIG      specify an alternate config file (default: weather-history.conf)
  --w411conf W411CONF  specify Weather411 config file to set defaults from during setup
  --force              force import for date/time range (skip search for data gaps)

date/time range options:
  --start START        start date and time ("YYYY-MM-DD hh:mm:ss")
  --end END            end date and time ("YYYY-MM-DD hh:mm:ss")
  --today              set start/end range to "today"
  --yesterday          set start/end range to "yesterday"
```

### Advanced option notes

* `--debug` can be used to enable debug output. This will print the raw responses from OpenWeatherMap which might be helpful in some circumstances.
* `--force` option can be used to import data regardless of existing data (i.e. the search for data gaps is skipped). This should not be required normally, but could be useful for testing purposes.

### Discussion Link
Please refer to discussion [#145](https://github.com/jasonacox/Powerwall-Dashboard/discussions/145) if you have any questions or find problems.
