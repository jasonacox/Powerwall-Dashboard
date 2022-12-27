# Weather History Import Tool

This is a command line tool to retrieve weather history data from OpenWeatherMap One Call API 3.0 and import into InfluxDB of Powerwall-Dashboard. This tool was submitted by [@mcbirse](https://github.com/mcbirse) and can be discussed further [here](https://github.com/jasonacox/Powerwall-Dashboard/discussions/146) if you have any questions or find problems.

## Features

This script, [weather-history.py](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/tools/weather-history/weather-history.py) can be used to import historical weather data by date/time period into Powerwall-Dashboard.

This could be useful for instance to import data from before you started using Powerwall-Dashboard or the Weather411 container. It can also be used to fill in missing data (data gaps) for periods where Powerwall-Dashboard or Weather411 stopped working (e.g. system down, or lost communication with OpenWeatherMap).

## OpenWeatherMap Subscription

Historical weather data from OpenWeatherMap is available by subscribing to the "One Call by Call" plan. This is a paid subscription plan, however allows for ***up to 1,000 API calls per day for free***.

To use this tool, you must subscribe to the "One Call by Call" plan, which can be done here: https://openweathermap.org/api

If you wish to use the service for free, or control your spend amount, ***make sure to edit your "calls per day" limit before use***: https://home.openweathermap.org/subscriptions (set to 1,000 for free use)

Once subscribed to "One Call by Call", the same API key as used by Weather411 can be used with this tool (note, plan activation may take some time).

## Data Observations and Notes

OpenWeatherMap provides historical weather data for 40+ years back.

This is generally available in 1-hour steps, however testing has shown requests for recent historical data (e.g. last few weeks/months) may be available in 10-30 minute intervals. Also, more recent historical data may return field values that are otherwise not available in the older historical data (e.g. wind gusts, visibility).

You can set the frequency with which to retrieve historical data during the script configuration. This value is also used as the "gap" threshold when searching InfluxDB for data gaps (NOTE: shorter intervals will increase the number of API calls, and reduce the range of historical data you can retrieve per day, and may be chargeable depending on your "calls per day" limit setting).

If your "calls per day" limit is reached, you may receive a "service usage alert" e-mail from OpenWeatherMap advising you have _exceeded_ your account limit. The tool will continue to retrieve data for some time after this e-mail before the OpenWeatherMap API service catches up and responds with the account limit reached status code (this will be detected, at which point the retrieved data will be written to InfluxDB and the script will exit).

Although the number of API calls will have exceeded your "calls per day" limit - DON'T PANIC - OpenWeatherMap appears to cap the number of _recorded_ API calls to your limit setting regardless, so you will never be charged for more than the limit you have set.

Finally, the data imported by this tool will not overwrite existing data. It will add data to the same field names as Weather411 which will update the following panels: "Energy Usage", "Temperature, Humidity and Clouds" and "Wind, Pressure and Precipitation".

## Usage

To use the script:
* Subscribe to the OpenWeatherMap "One Call by Call" plan: https://openweathermap.org/api
* Set the "calls per day" limit (can be set to 1,000 for free use): https://home.openweathermap.org/subscriptions
* Install the required python modules:
  ```bash
  pip install python-dateutil influxdb
  ```
* Follow the steps below

### Setup

On first use, it is recommended to use the `--setup` option. This will create the config file without retrieving history data.

```bash
# Run setup to create or update configuration
python3 weather-history.py --setup
```

Initial configuration defaults will be sourced from the Weather411 config file, when found. If the location of this file is different, it can be specified with the `--w411conf` option.

Setup will then run in an interactive mode. The example below shows the config creation:

```
---------------------------------------------------
Weather History Import Tool for Powerwall-Dashboard
---------------------------------------------------

Config file 'weather-history.conf' not found

Do you want to create the config now? [Y/n]

Loaded [defaults] from '/home/admin/Powerwall-Dashboard/weather/weather411.conf'...

OpenWeatherMap Setup
--------------------
Historical weather data from OpenWeatherMap can be imported into your
Powerwall Dashboard graphs by subscribing to the "One Call by Call" plan.

This is a paid subscription plan with OpenWeatherMap, however allows for
up to 1,000 API calls per day for free.

Subscribe to "One Call by Call" here: https://openweathermap.org/api

If you wish to use the service for free, or control your spend amount, edit
your "calls per day" limit at the link below (set to 1,000 for free use):
https://home.openweathermap.org/subscriptions

Once subscribed to "One Call by Call", the same API key as used by
Weather411 can be used here (note, plan activation may take some time).

API Key: [xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx]
Latitude: [-33.868]
Longitude: [151.207]
Units - M)etric, I)mperial or S)tandard: [M]
Retrieve weather history every (minutes): [30]

InfluxDB Setup
--------------
Host: [localhost]
Port: [8086]
User (leave blank if not used): [blank]
Pass (leave blank if not used): [blank]
Database: [powerwall]
Field: [weather]
Timezone (e.g. America/Los_Angeles): Australia/Sydney

Config saved to 'weather-history.conf'
```

In most cases, the `[default]` values will be correct and can be accepted by pressing Enter, however these can be changed if you have a custom setup.

Saved config values can also be changed at any time by running with the `--setup` option again.

Once the configuration is complete, you can then run the script to retrieve historical weather data.

### Basic script usage and examples

To import history data from OpenWeatherMap for a given start/end period, use the `--start` and `--end` options (date/time range is inclusive and in format `YYYY-MM-DD hh:mm:ss`):

```bash
# Get history data for start/end period
python3 weather-history.py --start "2022-08-01 00:00:00" --end "2022-09-01 00:00:00"
```

By default, the script will search InfluxDB for data gaps and fill gaps only, so you do not need to identify time periods where you have missing data, as this will be done automatically. The "gap" threshold is configurable and is the same as the history interval chosen during the setup process.

You may want to run in test mode first for a short time period to ensure your OpenWeatherMap "One Call by Call" subscription is active. This could be done by using the `--test` option:

```bash
# Run in test mode with --test (will not import data)
python3 weather-history.py --start "2022-08-01 12:00:00" --end "2022-08-01 13:00:00" --test
```

Example output:

```
---------------------------------------------------
Weather History Import Tool for Powerwall-Dashboard
---------------------------------------------------
Running for period: [2022-08-01 12:00:00+10:00] - [2022-08-01 13:00:00+10:00] (1:00:00s)

Searching InfluxDB for data gaps >= 30 minutes
* Found data gap: [2022-08-01 12:00:00+10:00] - [2022-08-01 13:00:00+10:00] (1:00:00s)

Retrieving data for gap: [2022-08-01 12:00:00+10:00] - [2022-08-01 13:00:00+10:00] (1:00:00s)
* Loading data for time: [2022-08-01 12:00:00+10:00]
* Loading data for time: [2022-08-01 12:30:00+10:00]
* Loading data for time: [2022-08-01 13:00:00+10:00]

Writing to InfluxDB (*** skipped - test mode enabled ***)
Done.
```

If your "calls per day" limit is reached during execution, you may receive a "service usage alert" e-mail from OpenWeatherMap advising you have _exceeded_ your account limit - DON'T PANIC - you will not charged for API calls in excess of your "calls per day" limit setting.

The tool will continue to retrieve data for some time after the usage alert e-mail before the OpenWeatherMap API service catches up and responds with the account limit reached status code, at which point the retrieved data will be written to InfluxDB and the script will exit, as per the example below.

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

Calls per day limit reached - continue tomorrow or edit your limits at: https://home.openweathermap.org/subscriptions

Writing to InfluxDB
Done.
```

Some convenience date options are also available (e.g. these could be used via cron):

```bash
# Convenience date options (both options can be used in a single command if desired)
python3 weather-history.py --today
python3 weather-history.py --yesterday
```

Finally, if something goes wrong, the imported data can be removed from InfluxDB with the `--remove` option. Data logged to Powerwall-Dashboard by Weather411 will not be affected - only imported data will be removed:

```bash
# Remove imported data
python3 weather-history.py --start "YYYY-MM-DD hh:mm:ss" --end "YYYY-MM-DD hh:mm:ss" --remove
```

For more usage options, run without arguments or with the `--help` option:

```bash
# Show usage options
python3 weather-history.py --help
```

```
usage: weather-history.py [-h] [-s] [-t] [-d] [--config CONFIG] [--w411conf W411CONF] [--force] [--remove] [--start START] [--end END] [--today] [--yesterday]

Import weather history data from OpenWeatherMap One Call API 3.0 into InfluxDB

options:
  -h, --help           show this help message and exit
  -s, --setup          run setup to create or update configuration only (do not get history)
  -t, --test           enable test mode (do not import into InfluxDB)
  -d, --debug          enable debug output (print raw responses from OpenWeatherMap)

advanced options:
  --config CONFIG      specify an alternate config file (default: weather-history.conf)
  --w411conf W411CONF  specify Weather411 config file to set defaults from during setup
  --force              force import for date/time range (skip search for data gaps)
  --remove             remove imported data from InfluxDB for date/time range

date/time range options:
  --start START        start date and time ("YYYY-MM-DD hh:mm:ss")
  --end END            end date and time ("YYYY-MM-DD hh:mm:ss")
  --today              set start/end range to "today"
  --yesterday          set start/end range to "yesterday"
```

### Advanced option notes

* `--debug` can be used to enable debug output. This will print the raw responses from OpenWeatherMap which might be helpful in some circumstances.
* `--force` option can be used to import data regardless of existing data (i.e. the search for data gaps is skipped). This should not be required normally, but could be useful for testing purposes.
* `--remove` will remove any previously imported data from InfluxDB for the date/time range, without affecting data logged to Powerwall-Dashboard by Weather411.

Please refer to discussion [#146](https://github.com/jasonacox/Powerwall-Dashboard/discussions/146) if you have any questions or find problems.
