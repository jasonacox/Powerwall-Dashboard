# Energy Calculator

This script polls the InfluxDB to compute energy (kWh) for a specified time period.

## Setup

Install influxdb library:

```bash
pip install influxdb
```

## Usage

```
Usage: python energy.py -s <start_time> -e <end_time> -h <host> -p <port> -u <username> -w <password> -d <database> -j
   -s <start_time>  Start time in the format 'YYYY-MM-DDTHH:MM:SSZ'
   -e <end_time>    End time in the format 'YYYY-MM-DDTHH:MM:SSZ'
   -h <host>        InfluxDB host (default is 'localhost')
   -p <port>        InfluxDB port (default is 8086)
   -u <username>    InfluxDB username
   -w <password>    InfluxDB password
   -d <database>    InfluxDB database (default is 'powerwall')
   -j               Output JSON format
```

## Examples

### Default Time Range

```bash
python3 energy.py -h 192.168.1.100
```

```
Energy Calculator
-----------------
Enter start time [2025-01-01T00:00:00Z]: 
Enter end time [2025-01-31T23:59:59Z]: 

Connecting to InfluxDB at 192.168.1.100:8086 as None using database powerwall...

Querying energy values from 2025-01-01T00:00:00Z to 2025-01-31T23:59:59Z...

Energy values:

Home           Solar          PW In          PW Out         Grid In        Grid Out       
------------------------------------------------------------------------------------------
937.87 kWh     589.30 kWh     415.75 kWh     469.55 kWh     441.60 kWh     39.13 kWh     
```

### Specify Range

```bash
python3 energy.py -h 192.168.1.100 -s "2024-01-01T00:00:00Z" -e "2025-01-31T23:59:59Z"
```

```
Energy Calculator
-----------------
Start time: 2024-01-01T00:00:00Z
End time: 2025-01-31T23:59:59Z

Connecting to InfluxDB at 192.168.1.100:8086 as None using database powerwall...

Querying energy values from 2024-01-01T00:00:00Z to 2025-01-31T23:59:59Z...

Energy values:

Home           Solar          PW In          PW Out         Grid In        Grid Out       
------------------------------------------------------------------------------------------
14.10 MWh      12.42 MWh      6.10 MWh       6.74 MWh       4.38 MWh       2.06 MWh      
```

### JSON Output

```bash
python3 energy.py -h 10.0.1.26 -s "2024-01-01T00:00:00Z" -e "2025-01-01T00:00:00Z" -j
```

```json
{
    "home": 13165.40484380579,
    "solar": 11831.718628749133,
    "from_pw": 5686.209712180349,
    "to_pw": 6273.8019262416665,
    "from_grid": 3939.267602490971,
    "to_grid": 2016.390444631733
}
```