#!/bin/bash
set -euo pipefail

source ./switch-mode.conf

# Check required variables
: "${PYPOWERWALL:?PYPOWERWALL is not set in switch-mode.conf}"
: "${TOKEN:?TOKEN is not set in switch-mode.conf}"
: "${LOGFILE:?LOGFILE is not set in switch-mode.conf}"
: "${NTFY_URL:?NTFY_URL is not set in switch-mode.conf}"
: "${NTFY_SOS_URL:?NTFY_SOS_URL is not set in switch-mode.conf}"
: "${TRIGGER_RESERVE:?TRIGGER_RESERVE is not set in switch-mode.conf}"
: "${EXPORT_RESERVE:?EXPORT_RESERVE is not set in switch-mode.conf}"
: "${BACKUP_RESERVE:?BACKUP_RESERVE is not set in switch-mode.conf}"
: "${OFF_PEAK_CUTOFF:?OFF_PEAK_CUTOFF is not set in switch-mode.conf}"

readonly AUTONOMOUS="autonomous"
readonly SELF_CONSUMPTION="self_consumption"


# Logging function
log() {
  echo "$(date): $*" >> "$LOGFILE"
}

# Generic function to get a value from pyPowerwall API
get_powerwall_value() {
  local endpoint="$1"
  local jq_filter="$2"
  local description="$3"
  local result

  result=$(curl -s "$endpoint" | jq -r "$jq_filter")

  if [[ $result == "null" || -z "$result" || "$result" == "0" ]]; then
    error_message="Failed to get $description from Powerwall"
    log "$error_message"
    curl -s -H "Tags: powerwall" -H "Title: Homelab" -d "$error_message" "$NTFY_SOS_URL" &> /dev/null
    # If the result is empty or zero, we exit with an error code
    exit 1
  fi

  echo $result
}

# Generic function to set a value via pyPowerwall API
set_powerwall_value() {
  local endpoint="$1"
  local value="$2"
  local notify_msg="$3"

  if [[ "${DEBUG:-false}" = 'true' ]]; then
    echo "Setting $endpoint to: $value"
  fi

  local response
  response=$(curl -s -X POST -d "value=$value&token=$TOKEN" "$PYPOWERWALL/control/$endpoint")
  local is_error=$(echo "$response" | jq -r 'if .error then 0 else 1 end')

  if [[ $is_error -eq 0 ]]; then
    # If the response indicates an error, log it and notify
    error_message="Failed to set $endpoint to $value"
    log "$error_message: $response"
    curl -s -H "Tags: powerwall" -H "Title: Homelab" -d "$error_message" "$NTFY_SOS_URL" &> /dev/null
    exit 1
  fi

  log "$response"

  curl -s -H "Tags: powerwall" -H "Title: Powerwall" -d "$notify_msg" "$NTFY_URL" &> /dev/null
}

# Function to set the mode
set_mode() {
  local mode="$1"
  set_powerwall_value "mode" "$mode" "Battery at $APP_BATTERY_LEVEL%. Set mode from $CURRENT_MODE to $mode"

  # This is necessary as the CURRENT_MODE variable is used later in the script to check if the mode has changed, 
  # and we want to avoid resetting it if the set_mode function is called multiple times in a row without changing the 
  # mode value. This way, we ensure that the CURRENT_MODE variable always reflects the latest mode value set by 
  # the set_mode function. 
  if [[ $? -eq 0 ]]; then
    CURRENT_MODE=$mode
  fi
}

# Function to set battery reserve
set_reserve() {
  local reserve="$1"
  set_powerwall_value "reserve" "$reserve" "Battery at $APP_BATTERY_LEVEL%. Set reserve from $CURRENT_RESERVE to $reserve"

  # This is necessary as the CURRENT_RESERVE variable is used later in the script to check if the reserve has changed, 
  # and we want to avoid resetting it if the set_reserve function is called multiple times in a row without changing the 
  # reserve value. This way, we ensure that the CURRENT_RESERVE variable always reflects the latest reserve value set by 
  # the set_reserve function. 
  if [[ $? -eq 0 ]]; then
    CURRENT_RESERVE=$reserve
  fi
}

readonly BATTERY_LEVEL=$(get_powerwall_value "$PYPOWERWALL/json" ".soe" "battery level" | xargs printf "%.0f\n")
readonly APP_BATTERY_LEVEL=$(echo "($BATTERY_LEVEL/0.95)-(5/0.95)" | bc)
readonly CURRENT_RESERVE=$(get_powerwall_value "$PYPOWERWALL/control/reserve" ".reserve" "current reserve" | xargs printf "%.0f\n")
readonly CURRENT_MODE=$(get_powerwall_value "$PYPOWERWALL/control/mode" ".mode" "current mode")

if [[ "${DEBUG:-false}" = 'true' ]]; then
  echo "Current mode: ${CURRENT_MODE}"
  echo "Current reserve: ${CURRENT_RESERVE}"
  echo "Powerwall battery level: ${BATTERY_LEVEL}"
  echo "App battery level: ${APP_BATTERY_LEVEL}"
fi

readonly CURRENT_TIME=$(date +%H%M)

# Export - Switch from self-powered to time-based control if APP_BATTERY_LEVEL >= TRIGGER_RESERVE
if [[ $CURRENT_MODE == $SELF_CONSUMPTION && $(echo "$APP_BATTERY_LEVEL >= $TRIGGER_RESERVE" | bc -l) -eq 1 ]]; then
  if [[ $CURRENT_RESERVE != $EXPORT_RESERVE ]]; then
    set_reserve "$EXPORT_RESERVE"
  fi
  set_mode "$AUTONOMOUS"
fi

# Switch to self-powered if APP_BATTERY_LEVEL < EXPORT_RESERVE or if its peak time
if { [[ $CURRENT_MODE == $AUTONOMOUS && $(echo "$APP_BATTERY_LEVEL <= $EXPORT_RESERVE" | bc -l) -eq 1 ]]; } || \
   { [[ $CURRENT_MODE == $AUTONOMOUS && $CURRENT_TIME -ge $OFF_PEAK_CUTOFF ]]; }; then
  set_mode "$SELF_CONSUMPTION"
  if [[ $CURRENT_RESERVE != $BACKUP_RESERVE ]]; then
    set_reserve "$BACKUP_RESERVE"
  fi
fi

# Update reserve if it was modified between runs
if [[ $CURRENT_MODE == $AUTONOMOUS && $CURRENT_RESERVE != $EXPORT_RESERVE ]]; then
  set_reserve "$EXPORT_RESERVE"
fi
