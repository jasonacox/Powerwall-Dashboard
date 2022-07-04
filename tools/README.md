# Additional Tools

This directory contains a list of tips, tricks and tools discovered or developed by the community to make the most of your Powerwall Dashboard data.

## Submit a Tool

If you have a great tool or trick that you think the community would enjoy, please submit an [issue](https://github.com/jasonacox/Powerwall-Dashboard/issues) or [pull request](https://github.com/jasonacox/Powerwall-Dashboard/pulls) to get it added here.

## PVoutput.org

Several in the community publish their solar production data to [PVoutput.org](https://pvoutput.org/), a free service for publicly sharing and comparing PV output data.  Since this Powerwall-Dashboard project stores all energy production data, it is relatively easy to pull this out of the dashboard and publish it to PVoutput on a one-time or regular basis.

This script, [pvoutput.py](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/tools/pvoutput.py) will help pull and publish the relevant energy data to PVoutput.org.

To use the script:
* Sign up at [pvoutput.org](https://pvoutput.org/account.jsp) to get an API KEY - update the settings in the script with your API_SYSTEM_ID and API_KEY.
* Update the INFLUXDB_HOST in the script to the address of your Dashboard host (default = localhost) and INFLUXDB_TZ to your timezone.
* Install the InfluxDB module:  `pip install influxdb`
* Run the script:

```bash
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
You can also add it to a daily cronjob by specifying a optional parameter:  'yesterday' or 'today'. 

```bash
# Pull and publish yesterdays data
python3 pvoutput.py yesterday

# Pull and publish todays data so far
python3 pvoutput.py today
```

I used this script to import of all the data since my system was installed.  Keep in mind that PVoutput has a rate limit of 60 updates per hour so be careful.  If you are only updating once a day, this shouldn't be a problem.  I donated to help their cause which also increase my rate limit.  That was useful while I developed this script.

You can see my published data here:  https://pvoutput.org/aggregate.jsp?p=0&id=104564&sid=91747&t=m&v=1&s=1 

<img width="960" alt="image" src="https://user-images.githubusercontent.com/836718/175867308-416584ba-82e5-4da8-9cdc-4ece163e1ca2.png">


## NodeRed

* [NodeRed.org](https://nodered.org/) - Low-code programming for event-driven applications

