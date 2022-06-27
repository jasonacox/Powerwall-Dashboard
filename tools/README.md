# Additional Tools

This directory contains a list of tips, tricks and tools discovered or developed by the community to make the most of your Powerwall Dashboard data.

## Submit a Tool

If you have a great tool or trick that you think the community would enjoy, please submit an [issue](https://github.com/jasonacox/Powerwall-Dashboard/issues) or [pull request](https://github.com/jasonacox/Powerwall-Dashboard/pulls) to get it added here.

## Index of Tools

### PVoutput.org

[PVoutput.org](https://pvoutput.org/) - PVOutput is a free service for sharing and comparing PV output data.

* The [pvoutput.py](pvoutput.py) script here will pull the relevant energy production data from InfluxDB and publish this to PVoutput.org.  
* Sign up at [pvoutput.org](https://pvoutput.org/account.jsp) to get an API KEY - update the settings in the script with your API_SYSTEM_ID and API_KEY.
* Update the INFLUXDB_HOST in the script to the address of your Dashboard host (default = localhost) and INFLUXDB_TZ to your timezone.
* Run the script:
    
    ```bash
    python3 pvoutput.py <option>
    ```

The `<option>` is 'yesterday' or 'today'. This is useful for daily cronjobs.
If no `<option>` is provided you will be prompted for a start date and end date to send allowing you to send entire months or years.

### NodeRed

* [NodeRed.org](https://nodered.org/) - Low-code programming for event-driven applications

