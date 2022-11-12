# Fix Month Tags Tool

This is a command line tool to search InfluxDB for incorrect month tags for your timezone. This tool was submitted by [@mcbirse](https://github.com/mcbirse) and can be used to correct the data problems discovered in issue [#80](https://github.com/jasonacox/Powerwall-Dashboard/issues/80).

## Background

Prior to Powerwall-Dashboard v2.6.3, "month" tags of InfluxDB data were based on UTC only, resulting in data points with incorrect month tags for the local timezone.

The [fixmonthtags.py](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/tools/fixmonthtags/fixmonthtags.py) script can be used to search InfluxDB for incorrect month tags for your timezone and correct the data. A backup is recommended before use.

### Example of incorrect month tags

Below is an example where the local timezone was Australia/Sydney (+10 offset), however due to month tags being in UTC, the "month" tag value remains set to "Aug" up until 10am of the first day in September.

<img alt="image" style="max-width: 100%;" src="https://user-images.githubusercontent.com/108725631/201059160-b47d4981-dce5-4183-b1f3-8c3f646a5675.png">

Incorrect month tags may cause issues in some circumstances, such as:
* When creating queries where data is GROUPed BY the "month" tag. This will result in values that do not correctly represent the actual month for your timezone.
* If the [Tesla History Import Tool](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/tools/tesla-history/) was used to fill a data gap which fell within a period where the month tag of existing data was incorrect. This will result in duplicate data points in the kwh retention policy, affecting the analysis data values.

The script can be used to correct these data issues. It could also be used to change timezones or correct the timezone, if for instance the system had been set up with a wrong timezone and changed later.

If you are unsure if your data is affected, it can be safely run to simply check for incorrect month tags - no data corrections will be made without confirmation.

If you have upgraded to Powerwall-Dashboard v2.6.3 or later, the script will only need to be run once to correct the data. All month tags since this version are logged correctly based on your configured timezone.

## Usage

To use the script:

```bash
# Install required python modules
pip install python-dateutil influxdb

# Run the script
python3 fixmonthtags.py
```

The script will run interactively and prompt you to:
* configure your InfluxDB database settings and timezone
* search the database for incorrect month tags
* correct the data if incorrect month tags are found

### Example usage and output

```
Fix incorrect month tags of InfluxDB
------------------------------------
This script will search InfluxDB for incorrect month tags for your
configured timezone and correct the data. A backup is recommended.

You will be asked for confirmation before any data corrections are made.
```

If the config file is not found, you will be prompted to enter your InfluxDB settings.

```
Config file 'fixmonthtags.conf' not found

Do you want to create the config now? [Y/n]

InfluxDB Setup
--------------
Host: [localhost]
Port: [8086]
User (leave blank if not used): [blank]
Pass (leave blank if not used): [blank]
Database: [powerwall]
Timezone (e.g. America/Los_Angeles): Australia/Sydney

Config saved to 'fixmonthtags.conf'
```

This step could be skipped if you have used the Tesla History Import Tool, by using it's saved config.

```bash
# Run the script using existing config containing your InfluxDB settings
python3 fixmonthtags.py --config ../tesla-history/tesla-history.conf
```

To search for incorrect month tags, answer "Y" at the prompt.

The InfluxDB data will then be searched for any incorrect month tags for your timezone.

```
Do you want to search now? [Y/n]

Searching InfluxDB for incorrect month tags for timezone Australia/Sydney
* Found incorrect month tags in Jul 2022
* Found incorrect month tags in Aug 2022
* Found incorrect month tags in Sep 2022
```

If any are found and you wish to correct the data, answer "Y" at the prompt.

```
Do you want to correct the month tags? [y/N] y

This may take some time, please be patient...

Writing corrected data
Updating analysis data
Done.
```

The incorrect month tags will then be corrected, and the analysis data rebuilt.

NOTE: Depending on the number of affected months, this may take some time. _Please be patient and do not abort the script_.

After completion, to confirm the data corrections were successful, you could re-run the script.

```
Fix incorrect month tags of InfluxDB
------------------------------------
This script will search InfluxDB for incorrect month tags for your
configured timezone and correct the data. A backup is recommended.

You will be asked for confirmation before any data corrections are made.

Do you want to search now? [Y/n]

Searching InfluxDB for incorrect month tags for timezone Australia/Sydney
* None found
```

There should be no incorrect month tags reported.

## Additional usage options

```bash
# Show all usage options
python3 fixmonthtags.py --help
```

```
usage: fixmonthtags.py [-h] [--config CONFIG] [--rebuild]

Fix incorrect month tags of InfluxDB

options:
  -h, --help       show this help message and exit
  --config CONFIG  specify an alternate config file (default: fixmonthtags.conf)
  --rebuild        force rebuild of analysis data
```

An additional option has been added which may be useful in some circumstances.

* The `--rebuild` option will force a full rebuild of the analysis data

This could be used to rebuild all analysis data retention policies (kwh, daily, and monthly), regardless of whether incorrect month tags exist or not.

It may be useful if for instance invalid analysis data had been identified. This has been seen to occur in rare occasions when the InfluxDB CQ's (continuous queries) that populate the analysis data had failed or taken too long to execute (for example, the host server was overloaded due to high CPU usage). Refer example and comment posts [here](https://github.com/jasonacox/Powerwall-Dashboard/issues/12#issuecomment-1296011292).
