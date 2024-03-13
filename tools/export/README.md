# Powerwall Data Export Tool

This script will pull the raw data from the Powerwall Dashboard database (InfluxDB) for the specified time range and write it to a comma delimited file, `export.csv`. The export includes TimeStamp, Solar (W), Powerwall (W), Home (W), Grid (W), and Powerwall Charge (%).

## Usage

```bash
python3 export.py

Usage: export.py [today|yesterday|all] or [YYYY-mm-dd] [YYYY-mm-dd]
    today - export today's data
    yesterday - export yesterday's data
    all - export all data
    YYYY-mm-dd - export single day
    YYYY-mm-dd YYYY-mm-dd - export date range
```

## Output Example

```csv
TimeStamp,Solar,Powerwall,Home,Grid,Charge
2024-03-13T00:47:00Z,430,2187,2558,-59,100
2024-03-13T00:48:00Z,424,2163,2562,-19,100
2024-03-13T00:49:00Z,490,1057,1550,2,100
2024-03-13T00:50:00Z,652,560,1193,-16,100
2024-03-13T00:51:00Z,606,611,1174,-19,100
2024-03-13T00:52:00Z,556,682,1167,-73,100
2024-03-13T00:53:00Z,655,555,1170,-43,100
2024-03-13T00:54:00Z,496,672,1168,-1,100
2024-03-13T00:55:00Z,494,710,1183,-17,100
2024-03-13T00:56:00Z,480,743,1192,-31,100
2024-03-13T00:57:00Z,460,745,1182,-22,100
2024-03-13T00:58:00Z,471,707,1181,0,100
2024-03-13T00:59:00Z,460,713,1173,0,100
2024-03-13T01:00:00Z,388,790,1177,-5,100
2024-03-13T01:01:00Z,345,831,1178,0,100
2024-03-13T01:02:00Z,350,821,1171,0,100
2024-03-13T01:03:00Z,342,833,1178,2,100
```