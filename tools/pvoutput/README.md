# PVoutput Export Tool

Several in the community publish their solar production data to [PVoutput.org](https://pvoutput.org/), a free service for publicly sharing and comparing PV output data.  Since this Powerwall-Dashboard project stores all energy production data, it is relatively easy to pull this out of the dashboard and publish it to PVoutput on a one-time or regular basis.

This script, [pvoutput.py](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/tools/pvoutput.py) will help pull and publish the relevant energy data to PVoutput.org.

## Usage

To use the script:
* Sign up at [pvoutput.org](https://pvoutput.org/account.jsp) to get an API KEY - update the settings in the script with your API_SYSTEM_ID and API_KEY.
* Update the INFLUXDB_HOST in the script to the address of your Dashboard host (default = localhost) and INFLUXDB_TZ to your timezone.
* Install the InfluxDB module and run the script:

```bash
# Install required python modules
pip install influxdb

# Run the script
python3 pvoutput.py 
```
It will run an interactive mode:

```
Select Custom Date Range
 - Enter start day (YYYY-mm-dd): 2022-06-20
 - Enter end date (YYYY-mm-dd): 2022-06-26

Sending Solar Data [2022-06-20 to 2022-06-27]
2022-06-20:    Generated = 49256 - Exported = 9067 - Consumed = 43501 - Imported = 2455 - Published
2022-06-21:    Generated = 49543 - Exported = 8386 - Consumed = 47026 - Imported = 7581 - Published
2022-06-22:    Generated = 39698 - Exported = 243 - Consumed = 46923 - Imported = 9212 - Published
2022-06-23:    Generated = 47508 - Exported = 127 - Consumed = 58052 - Imported = 12342 - Published
2022-06-24:    Generated = 48716 - Exported = 4474 - Consumed = 51203 - Imported = 8881 - Published
2022-06-25:    Generated = 49506 - Exported = 5609 - Consumed = 51118 - Imported = 9041 - Published
2022-06-26:    Generated = 48904 - Exported = 1083 - Consumed = 54617 - Imported = 8280 - Published
Done.
```
You can also add it to a daily cronjob by specifying an optional parameter: `yesterday`, `today`, or `range START [END]`.

```bash
# Pull and publish yesterdays data
python3 pvoutput.py yesterday

# Pull and publish todays data so far
python3 pvoutput.py today

# Pull and publish a specific date range (end date defaults to today if omitted)
python3 pvoutput.py range 2026-03-01 2026-03-07

# Show help or version
python3 pvoutput.py --help
python3 pvoutput.py --version
```

## Configuration

All settings can be overridden with environment variables instead of editing the script directly:

| Variable | Description | Default |
|---|---|---|
| `PVOUTPUT_API_SYSTEM_ID` | PVOutput system ID | *(set in script)* |
| `PVOUTPUT_API_KEY` | PVOutput API key | *(set in script)* |
| `PVOUTPUT_API_HOST` | PVOutput hostname | `pvoutput.org` |
| `INFLUXDB_HOST` | InfluxDB hostname | `localhost` |
| `INFLUXDB_PORT` | InfluxDB port | `8086` |
| `INFLUXDB_USER` | InfluxDB username | *(empty)* |
| `INFLUXDB_PASS` | InfluxDB password | *(empty)* |
| `INFLUXDB_DB` | InfluxDB database name | `powerwall` |
| `INFLUXDB_TZ` | Timezone for queries | `America/Los_Angeles` |
| `PVOUTPUT_WEATHER_UNITS` | Units for temperature: `metric`, `imperial`, or `standard` | `metric` |
| `PVOUTPUT_MAX_RETRIES` | Number of HTTP retry attempts on network errors | `3` |
| `PVOUTPUT_BACKOFF_FACTOR` | Exponential backoff multiplier between retries | `1` |
| `PVOUTPUT_RATE_LIMIT_WAIT` | Set to `1` to force waiting on rate limit (403) in any mode | `0` |

Example using environment variables:

```bash
export PVOUTPUT_API_KEY="abc123"
export INFLUXDB_HOST="influx.local"
export PVOUTPUT_MAX_RETRIES=5
python3 pvoutput.py range 2026-03-01 2026-03-07
```

## Retry Logic

The script automatically retries failed HTTP requests due to transient network errors (e.g. `Network is unreachable`) or server-side errors (HTTP 5xx / 429). It uses exponential backoff between attempts. You can tune this with `PVOUTPUT_MAX_RETRIES` and `PVOUTPUT_BACKOFF_FACTOR`.

For PVOutput's **rate limit (403 Exceeded 60 requests/hour)**, behavior depends on the mode:

* `range` and interactive mode — the script waits until the top of the next clock hour and retries automatically. This is safe when running interactively or doing a bulk backfill.
* `today` / `yesterday` (cron) — the script logs the rate limit error and exits immediately so the cron job does not hang.
* Set `PVOUTPUT_RATE_LIMIT_WAIT=1` to force waiting in any mode (e.g. if running `today` manually).

## Example

I used this script to import of all the data since my system was installed.  Keep in mind that PVoutput has a rate limit of 60 updates per hour so be careful.  If you are only updating once a day, this shouldn't be a problem.  I donated to help their cause which also increase my rate limit.  That was useful while I developed this script.

You can see my published data here:  https://pvoutput.org/aggregate.jsp?p=0&id=104564&sid=91747&t=m&v=1&s=1 

<img width="960" alt="image" src="https://user-images.githubusercontent.com/836718/175867308-416584ba-82e5-4da8-9cdc-4ece163e1ca2.png">

