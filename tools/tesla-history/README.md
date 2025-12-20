# Tesla History Import Tool

This is a command line tool to retrieve Powerwall history data from the Tesla Owner API (Tesla cloud) and import into InfluxDB of Powerwall-Dashboard. This tool was submitted by @mcbirse and can be discussed further in issue [#12](https://github.com/jasonacox/Powerwall-Dashboard/issues/12) if you have any questions or find problems.

## Features

This script, [tesla-history.py](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/tools/tesla-history/tesla-history.py) can be used to import historical data by date/time period from your Tesla cloud account (i.e. Tesla app data) into Powerwall-Dashboard.

This could be useful for instance to import data from before you started using Powerwall-Dashboard. It can also be used to fill in missing data (data gaps) for periods where Powerwall-Dashboard stopped working (e.g. system down, or lost communication with the Local Gateway).

- The available data from Tesla cloud is limited to 5 minute intervals of power usage, and backup events only. It will not be as accurate as data logged by Powerwall-Dashboard, however is still sufficient to provide approximate usage history. The historical data is obtained via the same API as used by the Tesla mobile app, so should be very similar in accuracy to what is displayed in the app.
- Data imported by this tool will not overwrite existing data, and will update the following panels only: Energy Usage, Grid Status, Power Meters, and Monthly Analysis

## Usage

To use the script:
- Install the required python modules: 
  ```bash
  pip install python-dateutil pypowerwall influxdb
  ```
- Follow the steps below

### Setup and logging in to Tesla account

On first use, it is recommended to use the `--login` option. This will create the config file, save an auth token so you will not need to login again, and then display the energy site details associated with your Tesla account.

```bash
# Login to Tesla account
python3 tesla-history.py --login
```

It will run in an interactive mode. The example below shows the config creation:

```
Config file 'tesla-history.conf' not found

Do you want to create the config now? [Y/n] Y

Tesla Account Setup
-------------------
Email address: your@email.address
Save auth token to: [tesla-history.auth]

InfluxDB Setup
--------------
Host: [localhost]
Port: [8086]
User (leave blank if not used): [blank]
Pass (leave blank if not used): [blank]
Database: [powerwall]
Timezone (e.g. America/Los_Angeles): Australia/Sydney

Config saved to 'tesla-history.conf'
```

In most cases, the `[default]` values will be correct and can be accepted by pressing Enter, however these can be changed if you have a custom setup.

Generally, only your Tesla account `email address` and your `timezone` will be required.

After the config is saved, you will be prompted to login to your Tesla account.

This is done by opening the displayed URL in your browser and then logging in:

```
----------------------------------------
Tesla account: your@email.address
----------------------------------------
Open the below address in your browser to login.

<copy URL to browser> e.g.: https://auth.tesla.com/oauth2/v3/authorize?response_type=code...etc.

After login, paste the URL of the 'Page Not Found' webpage below.

Enter URL after login: <paste URL from browser> e.g.: https://auth.tesla.com/void/callback?code=...etc.
```

After you have logged in successfully, the browser will show a 'Page Not Found' webpage. Copy the URL of this page and paste it at the prompt.

Once logged in successfully, you will be shown details of the energy site(s) associated with your account:

```
----------------------------------------
Tesla account: your@email.address
----------------------------------------
      Site ID: 1234567890
    Site name: My Powerwall
     Timezone: Australia/Sydney
    Installed: 2021-04-01 13:09:54+11:00
  System time: 2022-10-13 22:40:59+11:00
----------------------------------------
```

Once these steps are completed, you should not have to login again.

### Basic script usage and examples

To import history data from Tesla cloud for a given start/end period, use the `--start` and `--end` options (date/time range is inclusive and in format `YYYY-MM-DD hh:mm:ss`):

```bash
# Get history data for start/end period
python3 tesla-history.py --start "2022-10-01 00:00:00" --end "2022-10-05 23:59:59"
```

The above example would retrieve history data for the first 5 full days of October. By default, the script will search InfluxDB for data gaps and fill gaps only, so you do not need to identify time periods where you have missing data, as this will be done automatically.

You can run in test mode first which will not import any data, by using the `--test` option:

```bash
# Run in test mode with --test (will not import data)
python3 tesla-history.py --start "2022-10-01 00:00:00" --end "2022-10-05 23:59:59" --test
```

Example output:

```
----------------------------------------
Tesla account: your@email.address
----------------------------------------
      Site ID: 1234567890
    Site name: My Powerwall
     Timezone: Australia/Sydney
    Installed: 2021-04-01 13:09:54+11:00
  System time: 2022-10-13 22:40:59+11:00
----------------------------------------
Running for period: [2022-10-01 00:00:00+10:00] - [2022-10-05 23:59:59+11:00] (4 days, 22:59:59s)

Searching InfluxDB for data gaps (power usage)
* Found data gap: [2022-10-02 11:21:00+11:00] - [2022-10-02 12:41:00+11:00] (1:20:00s)
* Found data gap: [2022-10-04 06:09:00+11:00] - [2022-10-04 06:45:00+11:00] (0:36:00s)
* Found data gap: [2022-10-04 12:29:00+11:00] - [2022-10-04 14:56:00+11:00] (2:27:00s)

Searching InfluxDB for data gaps (grid status)
* Found data gap: [2022-10-02 11:21:00+11:00] - [2022-10-02 12:41:00+11:00] (1:20:00s)
* Found data gap: [2022-10-04 06:09:00+11:00] - [2022-10-04 06:45:00+11:00] (0:36:00s)
* Found data gap: [2022-10-04 12:29:00+11:00] - [2022-10-04 14:56:00+11:00] (2:27:00s)

Retrieving data for gap: [2022-10-02 11:22:00+11:00] - [2022-10-02 12:40:59+11:00] (1:18:59s)
* Loading daily history: [2022-10-02]
Retrieving data for gap: [2022-10-04 06:10:00+11:00] - [2022-10-04 06:44:59+11:00] (0:34:59s)
* Loading daily history: [2022-10-04]
Retrieving data for gap: [2022-10-04 12:30:00+11:00] - [2022-10-04 14:55:59+11:00] (2:25:59s)

Retrieving backup event history
* Creating grid status data: [2022-10-02 11:22:00+11:00] - [2022-10-02 12:40:59+11:00] (1:18:59s)
* Creating grid status data: [2022-10-04 06:10:00+11:00] - [2022-10-04 06:44:59+11:00] (0:34:59s)
* Creating grid status data: [2022-10-04 12:30:00+11:00] - [2022-10-04 14:55:59+11:00] (2:25:59s)

Writing to InfluxDB (*** skipped - test mode enabled ***)
Updating InfluxDB (*** skipped - test mode enabled ***)
Done.
```

If backup events are identified, this will be shown in the output, and the imported grid status data will include the outages:

```
----------------------------------------
Tesla account: your@email.address
----------------------------------------
      Site ID: 1234567890
    Site name: My Powerwall
     Timezone: Australia/Sydney
    Installed: 2021-04-01 13:09:54+11:00
  System time: 2022-10-13 22:40:59+11:00
----------------------------------------
Running for period: [2022-04-03 00:00:00+11:00] - [2022-04-20 00:00:00+10:00] (17 days, 1:00:00s)

Searching InfluxDB for data gaps (power usage)
* Found data gap: [2022-04-03 00:00:00+11:00] - [2022-04-20 00:00:00+10:00] (17 days, 1:00:00s)

Searching InfluxDB for data gaps (grid status)
* Found data gap: [2022-04-03 00:00:00+11:00] - [2022-04-20 00:00:00+10:00] (17 days, 1:00:00s)

Retrieving data for gap: [2022-04-03 00:00:00+11:00] - [2022-04-20 00:00:00+10:00] (17 days, 1:00:00s)
* Loading daily history: [2022-04-03]
* Loading daily history: [2022-04-04]
* Loading daily history: [2022-04-05]
* Loading daily history: [2022-04-06]
* Loading daily history: [2022-04-07]
* Loading daily history: [2022-04-08]
* Loading daily history: [2022-04-09]
* Loading daily history: [2022-04-10]
* Loading daily history: [2022-04-11]
* Loading daily history: [2022-04-12]
* Loading daily history: [2022-04-13]
* Loading daily history: [2022-04-14]
* Loading daily history: [2022-04-15]
* Loading daily history: [2022-04-16]
* Loading daily history: [2022-04-17]
* Loading daily history: [2022-04-18]
* Loading daily history: [2022-04-19]
* Loading daily history: [2022-04-20]

Retrieving backup event history
* Creating grid status data: [2022-04-03 00:00:00+11:00] - [2022-04-20 00:00:00+10:00] (17 days, 1:00:00s)
* Found backup event period: [2022-04-19 20:55:53+10:00] - [2022-04-19 22:00:16+10:00] (1:04:23s)
* Found backup event period: [2022-04-19 20:53:39+10:00] - [2022-04-19 20:54:46+10:00] (0:01:07s)
* Found backup event period: [2022-04-08 19:00:14+10:00] - [2022-04-08 19:02:55+10:00] (0:02:41s)
* Found backup event period: [2022-04-08 18:57:32+10:00] - [2022-04-08 18:58:28+10:00] (0:00:56s)
* Found backup event period: [2022-04-08 18:54:56+10:00] - [2022-04-08 18:56:21+10:00] (0:01:25s)
* Found backup event period: [2022-04-04 21:16:45+10:00] - [2022-04-04 21:19:10+10:00] (0:02:25s)

Writing to InfluxDB
Updating InfluxDB
Done.
```

Since grid status logging was only added to Powerwall-Dashboard in June, you can use the tool to import grid status history from before this time, without affecting your existing power usage data.

The search for missing power usage / grid status data is done independently, so power usage history retrieval will be skipped and the missing grid status data will still be retrieved from Tesla cloud and imported:

```
----------------------------------------
Tesla account: your@email.address
----------------------------------------
      Site ID: 1234567890
    Site name: My Powerwall
     Timezone: Australia/Sydney
    Installed: 2021-04-01 13:09:54+11:00
  System time: 2022-10-13 22:40:59+11:00
----------------------------------------
Running for period: [2022-04-03 00:00:00+11:00] - [2022-04-14 00:00:00+10:00] (11 days, 1:00:00s)

Searching InfluxDB for data gaps (power usage)
* None found

Searching InfluxDB for data gaps (grid status)
* Found data gap: [2022-04-03 00:00:00+11:00] - [2022-04-14 00:00:00+10:00] (11 days, 1:00:00s)

Retrieving backup event history
* Creating grid status data: [2022-04-03 00:00:00+11:00] - [2022-04-14 00:00:00+10:00] (11 days, 1:00:00s)
* Found backup event period: [2022-04-08 19:00:14+10:00] - [2022-04-08 19:02:55+10:00] (0:02:41s)
* Found backup event period: [2022-04-08 18:57:32+10:00] - [2022-04-08 18:58:28+10:00] (0:00:56s)
* Found backup event period: [2022-04-08 18:54:56+10:00] - [2022-04-08 18:56:21+10:00] (0:01:25s)
* Found backup event period: [2022-04-04 21:16:45+10:00] - [2022-04-04 21:19:10+10:00] (0:02:25s)

Writing to InfluxDB
Done.
```

Some convenience date options are also available (e.g. these could be used via cron):

```bash
# Convenience date options (both options can be used in a single command if desired)
python3 tesla-history.py --today
python3 tesla-history.py --yesterday
```

Finally, if something goes wrong, the imported data can be removed from InfluxDB with the `--remove` option. Data logged by Powerwall-Dashboard will not be affected, only imported data will be removed:

```bash
# Remove imported data
python3 tesla-history.py --start "YYYY-MM-DD hh:mm:ss" --end "YYYY-MM-DD hh:mm:ss" --remove
```

For more usage options, run without arguments or with the `--help` option:

```bash
# Show usage options
python3 tesla-history.py --help
```
```
usage: tesla-history.py [-h] [-l] [-t] [-d] [--config CONFIG] [--site SITE] [--ignoretz] [--force] [--remove] [--start START] [--end END] [--today] [--yesterday]

Import Powerwall history data from Tesla Owner API (Tesla cloud) into InfluxDB

options:
  -h, --help       show this help message and exit
  -l, --login      login to Tesla account only and save auth token (do not get history)
  -t, --test       enable test mode (do not import into InfluxDB)
  -d, --debug      enable debug output (print raw responses from Tesla cloud)

advanced options:
  --config CONFIG  specify an alternate config file (default: tesla-history.conf)
  --site SITE      site id (required for Tesla accounts with multiple energy sites)
  --ignoretz       ignore timezone difference between Tesla cloud and InfluxDB
  --force          force import for date/time range (skip search for data gaps)
  --remove         remove imported data from InfluxDB for date/time range

date/time range options:
  --start START    start date and time ("YYYY-MM-DD hh:mm:ss")
  --end END        end date and time ("YYYY-MM-DD hh:mm:ss")
  --today          set start/end range to "today"
  --yesterday      set start/end range to "yesterday"
```

Please refer to issue [#12](https://github.com/jasonacox/Powerwall-Dashboard/issues/12) for further discussion on the other advanced options, or you have questions or find a problem with this script.
