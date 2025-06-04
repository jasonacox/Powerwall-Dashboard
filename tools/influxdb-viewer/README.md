# InfluxDB Viewer Tool

A command-line and interactive shell tool for exploring and querying InfluxDB databases. This tool allows you to browse retention policies, measurements, and fields, and to query the last hour of data for any field in your InfluxDB instance. It is ideal for quick data inspection, troubleshooting, and learning the structure of your InfluxDB data.

## Features
- List retention policies, measurements, and fields in an InfluxDB database with clear, colorized, and tabular output
- Query the last hour of data for a specific field in a measurement, or specify a custom time window in shell mode (e.g., `cat [field] [minutes]`)
- Interactive shell mode for navigating retention policies and measurements like directories and files, with a shell-like prompt
- Tab completion for commands, retention policies, measurements, and fields in shell mode
- Optionally specify the number of data points to show with 'tail' (default 10)
- If no arguments are provided, launches the interactive shell by default
- Supports authentication via --user and --password
- Option to disable colored output with --nocolor
- Robust error handling and user guidance for incomplete or incorrect commands

## Requirements
- Python 3.7+
- [requests](https://pypi.org/project/requests/) library
- [colorama](https://pypi.org/project/colorama/) library (optional, for color output)

Install dependencies:
```sh
pip install requests colorama
```

## Usage
Run the script from the command line. If you run it with no arguments, it will launch the interactive shell mode.

### Command-Line Options
- `--host HOST` : InfluxDB host (default: `localhost`)
- `--db DB` : InfluxDB database name (default: `powerwall`)
- `--user USER` : InfluxDB username (optional)
- `--password PASSWORD` : InfluxDB password (optional)
- `--nocolor` : Disable colored output

### Main Commands
- `shell` : Launch interactive shell mode
- `list [measurement]` : List fields for a measurement (or all measurements if not specified)
- `measurements` : List all measurements in the database
- `retention` : List all retention policies in the database
- `<field> <measurement>` : Query the last hour of data for a field in a measurement

### Interactive Shell Commands
- `ls` : List retention policies, measurements, or fields (tabular, colorized)
- `ls -l` : Long listing. For measurements, shows measurement names and field counts. For fields, shows field name, type, and entry count.
- `cd [name]` : Enter a retention policy or measurement (or `..` to go up, `/` to go to root, or `retention.measurement` to jump directly)
- `cat [field] [minutes]` : Show the last N minutes of data for a field (default 60, must be inside a measurement)
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

### Query the last 30 minutes of data for a field in shell mode
```
cat solar_instant_average_voltage 30
```

### Use a different host, database, and authentication
```sh
python viewer.py --host influxdb.local --db mydb --user myuser --password mypass shell
```

### Disable color output
```sh
python viewer.py --nocolor shell
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
cat solar_instant_average_voltage 30
tail solar_instant_average_voltage 20
```

### Example Output

![image](https://github.com/user-attachments/assets/368e9d56-1f3f-406e-ae8b-7b65efa7a887)

## Author
Jason Cox - [github.com/jasonacox/Powerwall-Dashboard](https://github.com/jasonacox/Powerwall-Dashboard)

## License
MIT License
