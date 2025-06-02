# InfluxDB Viewer Tool

A command-line and interactive shell tool for exploring and querying InfluxDB databases. This tool allows you to browse retention policies, measurements, and fields, and to query the last hour of data for any field in your InfluxDB instance. It is ideal for quick data inspection, troubleshooting, and learning the structure of your InfluxDB data.

## Features
- List retention policies, measurements, and fields in an InfluxDB database
- Query the last hour of data for a specific field in a measurement
- Interactive shell mode for navigating retention policies and measurements like directories and files. Navigate with familiar shell commands "ls", "cd" and "cat <measurement>" to view last hour of data.
- Allows specifying the InfluxDB host and database via command-line switches
- If no arguments are provided, launches the interactive shell by default

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

### Main Commands
- `shell` : Launch interactive shell mode
- `list [measurement]` : List fields for a measurement (or all measurements if not specified)
- `measurements` : List all measurements in the database
- `retention` : List all retention policies in the database
- `<field> <measurement>` : Query the last hour of data for a field in a measurement

### Interactive Shell Commands
- `ls` : List retention policies, measurements, or fields (depending on your location in the tree)
- `cd [name]` : Enter a retention policy or measurement (or `..` to go up, `/` to go to root, or `retention.measurement` to jump directly)
- `cat [field]` or `tail [field]` : Show the last hour of data for a field (must be inside a measurement)
- `exit` or `quit` : Exit shell mode
- `help` : Show help message

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

### Use a different host and database
```sh
python viewer.py --host influxdb.local --db mydb shell
```

### In Shell Mode
```
ls
cd raw
ls
cd http
ls
cat solar_instant_average_voltage
```

## Author
Jason Cox - [github.com/jasonacox/Powerwall-Dashboard](https://github.com/jasonacox/Powerwall-Dashboard)

## License
MIT License
