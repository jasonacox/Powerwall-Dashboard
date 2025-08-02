# Switch Mode Tool

This script automates the management of both the Powerwall’s operating mode and reserve settings to optimize energy usage and grid export. It is designed for scenarios where you want to:

- **Automatically switch from self-consumption (Self-Powered) to autonomous (Time-Based Control) mode** when the battery is sufficiently charged (above `TRIGGER_RESERVE`). This enables exporting excess energy to the grid during peak times.
- **Set the reserve level to `EXPORT_RESERVE`** before switching to export mode, ensuring enough battery is available for export.
- **Return to self-consumption mode** when the battery drops below `EXPORT_RESERVE` or when peak export time ends (as defined by `OFF_PEAK_CUTOFF`).
- **Set the reserve level to `BACKUP_RESERVE`** when returning to self-consumption, preserving battery for backup use.
- **Continuously monitor and correct the reserve setting** if it is changed externally or between script runs, ensuring the reserve matches the intended mode.

## Setup

1. Setup Control APIs - released in v4.3.1 [RELEASE.md v4.3.1 - Control APIs](../../RELEASE.md#v431---control-apis)

```bash
# Setup cloud mode for pypowerwall container
docker exec -it pypowerwall python3 -m pypowerwall setup -email=example@example.com

MODE=self_consumption
RESERVE=20
PW_CONTROL_SECRET=mySecretKey

# Set Mode
curl -X POST -d "value=$MODE&token=$PW_CONTROL_SECRET" http://localhost:8675/control/mode

# Set Reserve
curl -X POST -d "value=$RESERVE&token=$PW_CONTROL_SECRET" http://localhost:8675/control/reserve

# Read Settings
curl http://localhost:8675/control/mode
curl http://localhost:8675/control/reserve
```

2. Ensure dependencies are installed:
   - `curl`
   - `jq`
   - `bc`

3. Configure `switch-mode.conf` with your API endpoints, tokens, and thresholds.


## Configuration

Edit `switch-mode.conf` to set:
- `PYPOWERWALL`: pyPowerwall API endpoint
- `TOKEN`: Secret token required to call the endpoint
- `LOGFILE`: Log file path
- `NTFY_URL`: Notification URL
- `NTFY_SOS_URL`: SOS notification URL
- `TRIGGER_RESERVE`, `EXPORT_RESERVE`, `BACKUP_RESERVE`: Reserve thresholds
- `OFF_PEAK_CUTOFF`: Off-peak cutoff time
- `DEBUG`: Set to `true` for verbose output

## Usage

Run the script:
```sh
zsh switch-mode.zsh
```

## Automation (Crontab)

To run the script every day between 5pm and 7pm (17:00-19:00), add this to your crontab:
```cron
* 17-19 * * * <user>    /<path to script>/switch-mode.sh >> /tmp/powerwall-mode-cron.log 2>&1
```

## What It Does
- Checks battery level and reserve via pypowerwall API
- Switches between autonomous and self-consumption modes based on thresholds
- Updates reserve settings as needed
- Sends notifications on mode/reserve changes and errors
- Logs all API responses

## Example Output
```
Current mode: self_consumption
Current reserve: 20
Powerwall battery level: 100
App battery level: 100
Setting reserve to: 55
Setting mode to: autonomous
```

## Error Handling
- Exits if required configuration is missing or Powerwall is unreachable
- Logs failures and sends SOS notifications if battery level cannot be read
