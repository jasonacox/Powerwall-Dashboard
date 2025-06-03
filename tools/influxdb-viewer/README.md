# InfluxDB Viewer Tool

A command-line and interactive shell tool for exploring and querying InfluxDB databases. This tool allows you to browse retention policies, measurements, and fields, and to query the last hour of data for any field in your InfluxDB instance. It is ideal for quick data inspection, troubleshooting, and learning the structure of your InfluxDB data.

## Features
- List retention policies, measurements, and fields in an InfluxDB database
- Query the last hour of data for a specific field in a measurement
- Interactive shell mode for navigating retention policies and measurements like directories and files. Navigate with familiar shell commands "ls", "cd" and "cat <measurement>" to view last hour of data.
- Allows specifying the InfluxDB host, database, username, and password via command-line switches
- Tab completion for commands, retention policies, measurements, and fields in shell mode
- Optionally specify the number of data points to show with 'tail' (default 10)
- If no arguments are provided, launches the interactive shell by default
- No authentication is used by default, but you can provide --user and --password if needed

## Requirements
- Python 3.7+
- [requests](https://pypi.org/project/requests/) library

Install dependencies:
```sh
pip install requests
```

## Usage
Run the script from the command line. If you run it with no arguments, it will launch the interactive shell mode.

### Command-Line Options
- `--host HOST` : InfluxDB host (default: `localhost`)
- `--db DB` : InfluxDB database name (default: `powerwall`)
- `--user USER` : InfluxDB username (optional)
- `--password PASSWORD` : InfluxDB password (optional)

### Main Commands
- `shell` : Launch interactive shell mode
- `list [measurement]` : List fields for a measurement (or all measurements if not specified)
- `measurements` : List all measurements in the database
- `retention` : List all retention policies in the database
- `<field> <measurement>` : Query the last hour of data for a field in a measurement

### Interactive Shell Commands
- `ls` : List retention policies, measurements, or fields (depending on your location in the tree)
- `ls -l` : Long listing. For measurements, shows measurement names and field counts. For fields, shows field name, type, and entry count.
- `cd [name]` : Enter a retention policy or measurement (or `..` to go up, `/` to go to root, or `retention.measurement` to jump directly)
- `cat [field]` : Show the last hour of data for a field (must be inside a measurement)
- `tail [field] [n]` : Show the last n data points for a field (default n=10)
- `exit` or `quit` : Exit shell mode
- `help` or `?` : Show help message

Tab completion is available for commands, retention policies, measurements, and fields in shell mode.

## Examples

### Launch Interactive Shell (default)
```sh
python viewer.py
```

### List all retention policies
```sh
python viewer.py retention
```

### List all measurements
```sh
python viewer.py measurements
```

### List fields in a measurement
```sh
python viewer.py list http
```

### Query the last hour of data for a field
```sh
python viewer.py solar_instant_average_voltage raw.http
```

### Use a different host, database, and authentication
```sh
python viewer.py --host influxdb.local --db mydb --user myuser --password mypass shell
```

### In Shell Mode
```
ls
ls -l
cd raw
ls
cd http
ls -l
cat solar_instant_average_voltage
tail solar_instant_average_voltage 20
```

## Author
Jason Cox - [github.com/jasonacox/Powerwall-Dashboard](https://github.com/jasonacox/Powerwall-Dashboard)

## License
MIT License
