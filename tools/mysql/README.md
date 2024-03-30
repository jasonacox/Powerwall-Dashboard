# MySQL Connector

This includes step-by-step set of instructions and scripts for adding MySQL to the Powerwall Dashboard, including the monthly charts and time of use pricing.

* Author: [@youzer-name](https://github.com/youzer-name) and Collaborator: [@BJReplay](https://github.com/BJReplay)
* [Details and Instructions](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/tools/mysql/)

## Instructions

Part 1: Install and configure MySQL

- I used a MariaDB Docker version that is compatible with my 32 bit ARM Raspberry Pi. You can install a MySQL-compatible database anywhere on your network that can be reached by your Grafana instance. I named my container "pimysql"
```
docker run --name pimysql -p 3306:3306 -e MYSQL_ROOT_PASSWORD=secretpassword -d yobasystems/alpine-mariadb:10.6.9-arm32v7
```
- Connect to the docker container and setup the DB. The syntax for docker exec may be different for a different database package
```
docker exec -it pimysql bin/sh
mysql -p
```
- Enter secretpassword that was used in the docker run command and then run these commands:
```
create database powerwall_mysql;
USE powerwall_mysql;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY 'secretpassword';
```

Part 2 - Copy data from InfluxDB to MySQL

- Ensure you have all the necessary packages installed in Python for the data replication script. On my system I had to add sqlalchemy, pymysql, pandas, and influxdb. If you are missing any packages you should get an error listing what you need to install

- Execute the initial python script to copy data from InfluxDB to MySQL. 
  - Below is a modified version of the script from the first post. I removed the 'daily' table from this version and it only copies the kwh data.  In my case the daily data had too many rows with duplicate datetime and month fields after running the historical data import tool. 
  - You can add it back from the script in the first post if your InfluxDB data is cleaner and you want the daily table also. 
  - It would also be easy to recreate the daily table entirely within MySQL rather than copying it.  
  - This script also has the option for the datetime_local field uncommented. I found it was essential to have that field for TOU pricing. 

- Set the port of your InfluxDB database in step 2 if it is not localhost:8086
- Change the time zone in step 4 from America/New_York to your time zone.
- Set the IP and password for your MySQL server in step 5

<details><summary>Click to expand Python script</summary>

<p>

```
## 1. Importing Modules

from sqlalchemy import create_engine
from influxdb import DataFrameClient

## 2. Create a client to Connect to Influx DB

client = DataFrameClient(host='localhost', port=8086)
client.switch_database('powerwall')

## 3. Run the hourly query and store results in a dataframe

results = client.query('select * from kwh.http order by time')
df = results['http']

## 4.. Copy datetime to 'datetime' column - by default it is in the 'index' column

df = df.reset_index()
df['datetime'] = df['index']
## Uncomment the next line to create local TZ timestamp if needed, using your TZ
df['datetime_local'] = df['index'].dt.tz_convert('America/New_York')

## drop the original 'index' column
df = df.drop(columns = ['index'])

## 5. create mySQL Connection

engine = create_engine("mysql+pymysql://{user}:{pw}@192.168.0.xx/{db}".format(user="root", pw="secretpassword", db="powerwall_mysql"))

## 6. Export data to MySQL

df.to_sql('kwh', con=engine, if_exists = 'replace', chunksize =1000, index=False)

##. You must add keys/indexes to MySQL tables after the initial import, before running periodic updates

engine.dispose()

print("Program Completed")
```

Add the primary key to the kwh table. In MySQL command window:

```
ALTER TABLE `powerwall_mysql`.`kwh` 
CHANGE COLUMN `datetime` `datetime` TIMESTAMP NOT NULL ,
ADD PRIMARY KEY (`datetime`);
```

</p>
</details>

If this step fails due to rows with the same datetime field, this will have to be cleaned up and the command re-run before pulling the periodic updates. The periodic update process requires the primary key to be in place to prevent duplicate rows being created.

Set up this Python script on a schedule (using crontab -e on my Pi). I run it every 5 minutes. Set all the same parameters as in the first script.

<details><summary>Click to expand Python script</summary>
<p>

```
## 1. Importing Modules

from sqlalchemy import create_engine
from influxdb import DataFrameClient

## next section is needed when running incremental updates to handle duplicates
from sqlalchemy.dialects.mysql import insert
def insert_on_duplicate(table, conn, keys, data_iter):
    insert_stmt = insert(table.table).values(list(data_iter))
    on_duplicate_key_stmt = insert_stmt.on_duplicate_key_update(insert_stmt.inserted)
    conn.execute(on_duplicate_key_stmt)
    
## 2. Create a client to Connect to Influx DB

client = DataFrameClient(host='localhost', port=8086)
client.switch_database('powerwall')

## 3. Run the query and store results in a dataframe

results = client.query('select * from kwh.http where time > now() -2d order by time')
## (this pulls all data for the last 2 days. Modify as needed based on how often you run the script.

df = results['http']

## 4.. Copy datetime to 'datetime' column - by default it is in the 'index' column

df = df.reset_index()
df['datetime'] = df['index']
## Uncomment the next line to create local TZ timestamp if needed, using your TZ
df['datetime_local'] = df['index'].dt.tz_convert('America/New_York')

## drop the original 'index' column
df = df.drop(columns = ['index'])

## 5. create mySQL Connection

engine = create_engine("mysql+pymysql://{user}:{pw}@192.168.0.xx/{db}".format(user="root", pw="secretpassword", db="powerwall_mysql"))

## 6. Export data to MySQL

## Using 'method=insert_on_duplicate' prevents errors if the script attempts to copy a duplicate record
df.to_sql('kwh', engine, if_exists = 'append', chunksize =1000, index=False, method=insert_on_duplicate)

engine.dispose()

print("Program Completed")
```

</p>
</details>

Part 3 - Set up Time of Use cost calculations

- Add cost fields to kWh table in MySQL. From MySQL command window:
```
ALTER TABLE `kwh` add column `cost_solar` decimal(15,10) DEFAULT NULL;
ALTER TABLE `kwh` add column `cost_grid` decimal(15,10) DEFAULT NULL;
ALTER TABLE `kwh` add column `credit_grid` decimal(15,10) DEFAULT NULL;
```

- In MySQL, create the TOU table:
 - The command below creates price fields with 5 digits after the decimal point. If you need more precision than that, alter the field definitions

<details><summary>Click to expand MySQL query</summary>
<p>

```
CREATE TABLE `TOU` (
  `idTOU` int(11) NOT NULL AUTO_INCREMENT,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `days_of_week` varchar(45) DEFAULT NULL,
  `start_time` time DEFAULT NULL,
  `end_time` time DEFAULT NULL,
  `grid_price` decimal(10,5) DEFAULT NULL,
  `grid_credit` decimal(10,5) DEFAULT NULL,
  `solar_price` decimal(10,5) DEFAULT NULL,
  PRIMARY KEY (`idTOU`)
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4;
```

</p>
</details>

- Create entries in the TOU table
  - It may be useful to install MySQL workbench on a machine so you can use the GUI to interact with the TOU table. I am running MySQL Workbench on a Windows machine on my LAN.
  - The days_of_week field is a of days when the price applies. 1=Sunday, 7=Saturday.
    - I am entering it with the days comma separated, but you can use any non-numeric separator or no separator
  - Make sure you don't create two entries for the same date/time/day of the week. 
  - You can find overlapping dates and times with this query:
```
select * from TOU T1 left join TOU T2 on T1.idTOU <> T2.idTOU
where T1.start_date <= T2.end_date and T1.end_date >= T2.start_date 
and T1.start_time <= T2.end_time and T1.end_time >= T2.start_time
```
  - This query does not check for days of the week. So if this query returns any rows where T1.days_of_week contains any of the same days as T2.days_of_week, you may have an issue. 

Example of TOU data:
![image](https://user-images.githubusercontent.com/57046429/199326253-b397588f-7340-40ee-a37d-6922083b9d50.png)

- Update the price data in kwh from TOU. In MySQL:

<details> <summary>Click to expand MySQL query</summary>
<p>

```
update  kwh as dest,
(select round(solar * solar_price, 10) as solar_total, round(from_grid * grid_price, 10) as grid_total, round(to_grid * grid_credit, 10) as fromgrid_total, datetime_local from kwh 
inner join TOU on TOU.start_date <= kwh.datetime_local and TOU.end_date >= kwh.datetime_local and locate(dayofweek(kwh.datetime_local), TOU.days_of_week) > 0 and time(kwh.datetime_local) >= TOU.start_time and time(kwh.datetime_local) <= TOU.end_time  ) as src
set  dest.cost_solar = src.solar_total, dest.cost_grid = src.grid_total, dest.credit_grid = src.fromgrid_total
where dest.datetime_local = src.datetime_local
```
</p>
</details>

   - This should populate the pricing for all the existing rows in kwh. If there are issues with your TOU table, you may encounter errors here. I accidentally had an overlapping day where the end_date of one row was the same date as the start_date of the next  row, instead of the day before, and it caused this query to throw an error

- Create triggers in the kwh table to update the total cost as the data are inserted and updated. 
  - I did this in the MySQL Workbench GUI, but I think these commands are correct to do this from a command window:
 
<details><summary>Click to expand MySQL queries - edited 2024-03-30</summary>
<p>

```
CREATE TRIGGER `powerwall_mysql`.`kwh_BEFORE_INSERT` BEFORE INSERT ON `kwh` FOR EACH ROW
set new.cost_solar = new.solar * 
(select solar_price from TOU where start_date <= new.datetime_local and end_date >= date(new.datetime_local) and locate(dayofweek(new.datetime_local), days_of_week) > 0 and time(new.datetime_local) >= start_time and time(new.datetime_local) <= end_time ) ;
set new.cost_grid = new.from_grid *
(select grid_price from TOU where start_date <= new.datetime_local and end_date >= date(new.datetime_local) and locate(dayofweek(new.datetime_local), days_of_week) > 0 and time(new.datetime_local) >= start_time and time(new.datetime_local) <= end_time ) ;
set new.credit_grid = new.to_grid *
(select grid_credit from TOU where start_date <= new.datetime_local and end_date >= date(new.datetime_local) and locate(dayofweek(new.datetime_local), days_of_week) > 0 and time(new.datetime_local) >= start_time and time(new.datetime_local) <= end_time  ) ;
```

```
CREATE TRIGGER `powerwall_mysql`.`kwh_BEFORE_UPDATE` BEFORE UPDATE ON `kwh` FOR EACH ROW
set new.cost_solar = new.solar *
(select solar_price from TOU where start_date <= new.datetime_local and end_date >= date(new.datetime_local) and locate(dayofweek(new.datetime_local), days_of_week) > 0 and time(new.datetime_local) >= start_time and time(new.datetime_local) <= end_time  ) ;
set new.cost_grid = new.from_grid *
(select grid_price from TOU where start_date <= new.datetime_local and end_date >= date(new.datetime_local) and locate(dayofweek(new.datetime_local), days_of_week) > 0 and time(new.datetime_local) >= start_time and time(new.datetime_local) <= end_time  ) ;
set new.credit_grid = new.to_grid *
(select grid_credit from TOU where start_date <= new.datetime_local and end_date >= date(new.datetime_local) and locate(dayofweek(new.datetime_local), days_of_week) > 0 and time(new.datetime_local) >= start_time and time(new.datetime_local) <= end_time  ) ;
```

</p>
</details>

Part 4 - Add to Grafana

- If you don't already have the MySQL plugin for Grafana, add it

![image](https://user-images.githubusercontent.com/57046429/199319891-be6f0a56-15f3-42d3-99e7-0b64e7c06a75.png)

- Configure the MySQL data source:

![image](https://user-images.githubusercontent.com/57046429/199320442-fdb481d6-3aa0-4b0a-85c0-e4fbfefeec2c.png)

- Create panels using the TOU data

  - Here is a dashboard with a stat panel and a bar graph panel showing costs:

![image](https://user-images.githubusercontent.com/57046429/199323931-b34d127d-73c2-41fb-a169-84a414c245da.png)


Final thought:
Combining the 'monthly' charts from the first post above and the accurate TOU historical prices, you can get charts like this:

![image](https://user-images.githubusercontent.com/57046429/199331456-df315bcc-d677-4bba-a8c7-9fc4d1f705d5.png)


Here is the JSON for just the two TOU cost panels (stat and bar chart). You should be able to import this into your Grafana and then copy the panels from this to your other dashboards. For a non-PPA you'll want to modify the queries, since the solar would be counted as 'savings' and the total cost is only the 'cost_grid' minus 'credit_grid'. 

<details><summary>Click to expand Grafana JSON</summary>
<p>

```
{
  "__inputs": [
    {
      "name": "DS_POWERWALL_MYSQL",
      "label": "Powerwall_MySQL",
      "description": "",
      "type": "datasource",
      "pluginId": "mysql",
      "pluginName": "MySQL"
    },
    {
      "name": "DS_INFLUXDB",
      "label": "InfluxDB",
      "description": "",
      "type": "datasource",
      "pluginId": "influxdb",
      "pluginName": "InfluxDB"
    }
  ],
  "__elements": {
    "nvEBTYigz": {
      "name": "Total Cost",
      "uid": "nvEBTYigz",
      "kind": 1,
      "model": {
        "datasource": {
          "type": "datasource",
          "uid": "-- Mixed --"
        },
        "description": "",
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "thresholds"
            },
            "decimals": 2,
            "mappings": [],
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {
                  "color": "green",
                  "value": null
                }
              ]
            },
            "unit": "currencyUSD"
          },
          "overrides": [
            {
              "matcher": {
                "id": "byName",
                "options": "http.solar"
              },
              "properties": [
                {
                  "id": "color",
                  "value": {
                    "fixedColor": "yellow",
                    "mode": "fixed"
                  }
                },
                {
                  "id": "displayName",
                  "value": "Solar"
                }
              ]
            },
            {
              "matcher": {
                "id": "byName",
                "options": "http.grid"
              },
              "properties": [
                {
                  "id": "color",
                  "value": {
                    "fixedColor": "purple",
                    "mode": "fixed"
                  }
                },
                {
                  "id": "displayName",
                  "value": "Grid"
                }
              ]
            },
            {
              "matcher": {
                "id": "byName",
                "options": "http.combined"
              },
              "properties": [
                {
                  "id": "color",
                  "value": {
                    "fixedColor": "text",
                    "mode": "fixed"
                  }
                },
                {
                  "id": "displayName",
                  "value": "Combined"
                }
              ]
            }
          ]
        },
        "options": {
          "colorMode": "value",
          "graphMode": "none",
          "justifyMode": "auto",
          "orientation": "auto",
          "reduceOptions": {
            "calcs": [
              "sum"
            ],
            "fields": "",
            "values": false
          },
          "textMode": "auto"
        },
        "pluginVersion": "9.1.2",
        "targets": [
          {
            "datasource": {
              "type": "mysql",
              "uid": "${DS_POWERWALL_MYSQL}"
            },
            "format": "time_series",
            "group": [],
            "hide": false,
            "metricColumn": "none",
            "rawQuery": true,
            "rawSql": "SELECT\n  datetime AS \"time\",\n  cost_solar as \"http.solar\"\nFROM kwh\nWHERE\n  $__timeFilter(datetime)\nORDER BY datetime",
            "refId": "A",
            "select": [
              [
                {
                  "params": [
                    "cost_solar"
                  ],
                  "type": "column"
                }
              ]
            ],
            "table": "kwh",
            "timeColumn": "datetime",
            "timeColumnType": "timestamp",
            "where": [
              {
                "name": "$__timeFilter",
                "params": [],
                "type": "macro"
              }
            ]
          },
          {
            "datasource": {
              "type": "mysql",
              "uid": "${DS_POWERWALL_MYSQL}"
            },
            "format": "time_series",
            "group": [],
            "hide": false,
            "metricColumn": "none",
            "rawQuery": true,
            "rawSql": "SELECT datetime as time,\n  cost_grid - credit_grid AS \"http.grid\"\nFROM kwh \nWHERE\n  $__timeFilter(datetime)\n",
            "refId": "B",
            "select": [
              [
                {
                  "params": [
                    "cost_grid"
                  ],
                  "type": "column"
                },
                {
                  "params": [
                    "cost_grid"
                  ],
                  "type": "alias"
                }
              ]
            ],
            "table": "kwh",
            "timeColumn": "datetime_local",
            "timeColumnType": "timestamp",
            "where": [
              {
                "name": "$__timeFilter",
                "params": [],
                "type": "macro"
              }
            ]
          },
          {
            "datasource": {
              "type": "mysql",
              "uid": "${DS_POWERWALL_MYSQL}"
            },
            "format": "time_series",
            "group": [],
            "hide": false,
            "metricColumn": "none",
            "rawQuery": true,
            "rawSql": "SELECT\n  datetime AS time,\n  cost_solar + cost_grid - credit_grid as \"http.combined\"\nFROM kwh\nWHERE\n  $__timeFilter(datetime)\n",
            "refId": "C",
            "select": [
              [
                {
                  "params": [
                    "cost_solar"
                  ],
                  "type": "column"
                }
              ]
            ],
            "table": "kwh",
            "timeColumn": "datetime",
            "timeColumnType": "timestamp",
            "where": [
              {
                "name": "$__timeFilter",
                "params": [],
                "type": "macro"
              }
            ]
          }
        ],
        "title": "Cost",
        "type": "stat"
      }
    },
    "4QeZTLmgz": {
      "name": "Cost",
      "uid": "4QeZTLmgz",
      "kind": 1,
      "model": {
        "datasource": {
          "type": "datasource",
          "uid": "-- Mixed --"
        },
        "description": "",
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "thresholds"
            },
            "custom": {
              "axisCenteredZero": false,
              "axisColorMode": "text",
              "axisLabel": "",
              "axisPlacement": "hidden",
              "fillOpacity": 80,
              "gradientMode": "none",
              "hideFrom": {
                "legend": false,
                "tooltip": false,
                "viz": false
              },
              "lineWidth": 1,
              "scaleDistribution": {
                "type": "linear"
              }
            },
            "decimals": 2,
            "mappings": [],
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {
                  "color": "green",
                  "value": null
                }
              ]
            },
            "unit": "currencyUSD"
          },
          "overrides": [
            {
              "matcher": {
                "id": "byName",
                "options": "Field"
              },
              "properties": [
                {
                  "id": "mappings",
                  "value": [
                    {
                      "options": {
                        "combined": {
                          "color": "text",
                          "index": 2,
                          "text": "Combined"
                        },
                        "grid": {
                          "color": "purple",
                          "index": 1,
                          "text": "Grid"
                        },
                        "solar": {
                          "color": "yellow",
                          "index": 0,
                          "text": "Solar"
                        }
                      },
                      "type": "value"
                    }
                  ]
                }
              ]
            }
          ]
        },
        "options": {
          "barRadius": 0,
          "barWidth": 0.8,
          "colorByField": "Field",
          "groupWidth": 0.7,
          "legend": {
            "calcs": [
              "sum"
            ],
            "displayMode": "list",
            "placement": "right",
            "showLegend": false
          },
          "orientation": "horizontal",
          "showValue": "never",
          "stacking": "none",
          "tooltip": {
            "mode": "single",
            "sort": "none"
          },
          "xField": "Field",
          "xTickLabelRotation": 0,
          "xTickLabelSpacing": 0
        },
        "pluginVersion": "9.1.2",
        "targets": [
          {
            "datasource": {
              "type": "influxdb",
              "uid": "${DS_INFLUXDB}"
            },
            "groupBy": [
              {
                "params": [
                  "$__interval"
                ],
                "type": "time"
              },
              {
                "params": [
                  "null"
                ],
                "type": "fill"
              }
            ],
            "hide": true,
            "measurement": "http",
            "orderByTime": "ASC",
            "policy": "kwh",
            "query": "SELECT \"solar\" * $solar_price, (from_grid - to_grid) * $grid_price as grid, (solar * $solar_price) + (from_grid  * $grid_price) - (to_grid * $grid_price) as combined FROM \"kwh\".\"http\" WHERE $timeFilter ",
            "rawQuery": true,
            "refId": "B",
            "resultFormat": "table",
            "select": [
              [
                {
                  "params": [
                    "solar"
                  ],
                  "type": "field"
                },
                {
                  "params": [
                    "* $solar_price"
                  ],
                  "type": "math"
                }
              ]
            ],
            "tags": []
          },
          {
            "datasource": {
              "type": "mysql",
              "uid": "${DS_POWERWALL_MYSQL}"
            },
            "format": "time_series",
            "group": [],
            "hide": false,
            "metricColumn": "none",
            "rawQuery": true,
            "rawSql": "SELECT\n  datetime AS \"time\",\n  cost_solar as solar, cost_grid-credit_grid as grid, cost_solar+cost_grid-credit_grid as combined\nFROM kwh\nWHERE\n  $__timeFilter(datetime)\nORDER BY datetime",
            "refId": "A",
            "select": [
              [
                {
                  "params": [
                    "value"
                  ],
                  "type": "column"
                }
              ]
            ],
            "table": "kwh",
            "timeColumn": "datetime",
            "timeColumnType": "timestamp",
            "where": [
              {
                "name": "$__timeFilter",
                "params": [],
                "type": "macro"
              }
            ]
          }
        ],
        "title": "Cost",
        "transformations": [
          {
            "id": "reduce",
            "options": {
              "includeTimeField": false,
              "labelsToFields": false,
              "mode": "seriesToRows",
              "reducers": [
                "sum"
              ]
            }
          }
        ],
        "type": "barchart"
      }
    }
  },
  "__requires": [
    {
      "type": "panel",
      "id": "barchart",
      "name": "Bar chart",
      "version": ""
    },
    {
      "type": "grafana",
      "id": "grafana",
      "name": "Grafana",
      "version": "9.1.2"
    },
    {
      "type": "datasource",
      "id": "influxdb",
      "name": "InfluxDB",
      "version": "1.0.0"
    },
    {
      "type": "datasource",
      "id": "mysql",
      "name": "MySQL",
      "version": "1.0.0"
    },
    {
      "type": "panel",
      "id": "stat",
      "name": "Stat",
      "version": ""
    }
  ],
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": {
          "type": "grafana",
          "uid": "-- Grafana --"
        },
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "target": {
          "limit": 100,
          "matchAny": false,
          "tags": [],
          "type": "dashboard"
        },
        "type": "dashboard"
      }
    ]
  },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "id": null,
  "links": [],
  "liveNow": false,
  "panels": [
    {
      "gridPos": {
        "h": 9,
        "w": 2,
        "x": 0,
        "y": 0
      },
      "id": 2,
      "libraryPanel": {
        "uid": "nvEBTYigz",
        "name": "Total Cost"
      }
    },
    {
      "gridPos": {
        "h": 9,
        "w": 5,
        "x": 2,
        "y": 0
      },
      "id": 4,
      "libraryPanel": {
        "uid": "4QeZTLmgz",
        "name": "Cost"
      }
    }
  ],
  "refresh": false,
  "schemaVersion": 37,
  "style": "dark",
  "tags": [],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-24h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "",
  "title": "Export 2022-11-01",
  "uid": "txTMWCRRz",
  "version": 6,
  "weekStart": ""
}
```

</p>
</details>

### Discussion Link

Join discussion [#82](https://github.com/jasonacox/Powerwall-Dashboard/discussions/82) if you have any questions or find problems.
