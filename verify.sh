#!/bin/bash
#
# Setup Verification Tool for Powerwall Dashboard

# Stop on Errors
set -e

# Function to detect if terminal has light background
detect_light_background() {
    # Skip OSC 11 query on macOS as it can cause input buffer issues
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Skip Method 1 on macOS and go straight to fallback methods
        :
    else
        # Method 1: Try to query terminal background color (non-macOS only)
        if [[ -t 1 ]]; then
            # Save current terminal settings
            local oldstty=$(stty -g 2>/dev/null) || return 1
            
            # Set up a trap to ensure terminal settings are restored
            trap 'stty "$oldstty" 2>/dev/null' RETURN
            
            # Query background color (OSC 11) with timeout
            printf '\033]11;?\033\\' 2>/dev/null || return 1
            
            # Set terminal to raw mode to read response
            if ! stty raw -echo min 0 time 2 2>/dev/null; then
                return 1
            fi
            
            # Read response with timeout (0.2 seconds)
            local response=""
            local char
            local count=0
            while IFS= read -r -n1 -t 0.2 char 2>/dev/null; do
                response+="$char"
                # Break on bell character or ESC sequence end
                [[ "$char" == $'\007' ]] && break
                [[ "$char" == $'\033' && ${#response} -gt 1 ]] && break
                # Safety limit to prevent hanging
                ((count++))
                [[ $count -gt 100 ]] && break
            done
            
            # Restore terminal settings
            stty "$oldstty" 2>/dev/null
            
            # Flush any remaining input to prevent artifacts in command line
            read -t 0.1 -n 1000 2>/dev/null || true
            
            # Parse RGB values from response (format: rgb:RRRR/GGGG/BBBB)
            if [[ "$response" =~ rgb:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+) ]]; then
                local r=$((0x${BASH_REMATCH[1]:0:2}))
                local g=$((0x${BASH_REMATCH[2]:0:2}))
                local b=$((0x${BASH_REMATCH[3]:0:2}))
                
                # Calculate perceived brightness (ITU-R BT.709)
                local brightness=$((r * 299 + g * 587 + b * 114))
                
                # If brightness > 127500 (roughly 50% of max 255000), consider it light
                [[ $brightness -gt 127500 ]]
                return $?
            fi
        fi
    fi
    
    # Method 2: Check environment variables for light themes
    if [[ "$COLORFGBG" =~ \;15$ ]] || [[ "$COLORFGBG" =~ \;7$ ]]; then
        return 0  # Light background
    fi
    
    # Method 3: Check terminal theme environment variables
    case "${TERM_THEME:-}" in
        *light*|*Light*|*LIGHT*) return 0 ;;
        *dark*|*Dark*|*DARK*) return 1 ;;
    esac
    
    # Method 4: Check some common terminal apps and their defaults
    case "${TERM_PROGRAM:-}" in
        "Apple_Terminal")
            # Check if Terminal.app is using a light theme
            # This is a heuristic based on common settings
            if [[ "${TERM:-}" =~ xterm.*256color ]]; then
                return 1  # Assume dark for xterm-256color
            fi
            return 1  # Default to dark for Terminal.app
            ;;
        "iTerm.app")
            return 1  # iTerm2 typically defaults to dark
            ;;
        "vscode")
            # VS Code integrated terminal usually follows editor theme
            return 1  # Most developers use dark themes
            ;;
    esac
    
    return 1  # Default to dark background assumption
}

# Check for command line options first
DEBUG_COLORS=false
FORCE_BACKGROUND=""
NO_COLOR=false

if [ $# -ne 0 ]; then
    if [[ "$1" == "-no-color" || "$1" == "--no-color" ]]; then
        NO_COLOR=true
    elif [[ "$1" == "-debug-colors" || "$1" == "--debug-colors" ]]; then
        DEBUG_COLORS=true
    elif [[ "$1" == "--light" ]]; then
        FORCE_BACKGROUND="light"
    elif [[ "$1" == "--dark" ]]; then
        FORCE_BACKGROUND="dark"
    elif [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --no-color        Disable colored output"
        echo "  --debug-colors    Show color detection info"
        echo "  --light           Force light background colors"
        echo "  --dark            Force dark background colors"
        echo "  -h, --help        Show this help message"
        echo ""
        echo "This script verifies the Powerwall Dashboard installation and services."
        exit 0
    fi
fi

# Detect background and set appropriate colors
LIGHT_BG=false
if [[ "$FORCE_BACKGROUND" == "light" ]]; then
    LIGHT_BG=true
elif [[ "$FORCE_BACKGROUND" == "dark" ]]; then
    LIGHT_BG=false
elif [[ "$NO_COLOR" == "false" ]]; then
    # Only run detection if not forced and colors are enabled
    if detect_light_background 2>/dev/null; then
        LIGHT_BG=true
    fi
fi

# Formatting - Colors adapted for background
default="\033[39m"
if [[ "$LIGHT_BG" == "true" ]]; then
    # Light background colors
    primary="\033[30m"      # black
    secondary="\033[90m"    # dark gray
    accent="\033[32m"       # green
    highlight="\033[34m"    # blue
else
    # Dark background colors
    primary="\033[97m"      # bright white
    secondary="\033[37m"    # white
    accent="\033[92m"       # bright green
    highlight="\033[96m"    # bright cyan
fi

# Apply color settings based on background and options
if [[ "$NO_COLOR" == "true" ]]; then
    # no color mode
    bold=""
    subbold=""
    normal=""
    dim=""
    alert=""
    alertdim=""
else
    red="\033[91m"
    yellow="\033[33m"
    bold="\033[0m${primary}\033[1m"
    subbold="\033[0m${accent}\033[1m"
    normal="\033[0m${primary}"
    dim="\033[0m${secondary}\033[2m"
    alert="\033[0m${red}\033[1m"
    alertdim="\033[0m${red}\033[2m"
fi

# Set Globals
UKN="${alertdim}Unknown${normal}"
GOOD="${subbold}GOOD${normal}"
CURRENT=$UKN
ALLGOOD=1
if [ -f VERSION ]; then
    CURRENT=`cat VERSION`
fi
TZ=`cat tz`

# Windows Git Bash docker exec compatibility fix
if type winpty > /dev/null 2>&1; then
    shopt -s expand_aliases
    alias docker="winpty -Xallow-non-tty -Xplain docker"
fi

# Service Running Helper Function
running() {
    local url=${1:-http://localhost:80}
    local code=${2:-200}
    if [[ $3 == 1 ]]; then
        head="--head"
    else
        head=""
    fi
    local status=$(curl ${head} -k --location --connect-timeout 5 --write-out %{http_code} --silent --output /dev/null ${url})
    [[ $status == ${code} ]]
}

# Operating system details
case "$OSTYPE" in
    linux*)     OS="Linux" ;;
    darwin*)    OS="MacOS" ;;
    cygwin*)    OS="Windows" ;;
    msys*)      OS="Windows" ;;
    *)          OS="$OSTYPE" ;;
esac

# Clear any terminal artifacts from background detection
printf '\033[2K\r' 2>/dev/null

echo -e "${bold}Verify Powerwall-Dashboard ${subbold}${CURRENT}${normal} on ${OS} - Timezone: ${subbold}${TZ}${dim}"
echo -e "----------------------------------------------------------------------------"
echo -e "This script will attempt to verify all the services needed to run"
echo -e "Powerwall-Dashboard. Use this output when you open an issue for help:"
echo -e "https://github.com/jasonacox/Powerwall-Dashboard/issues/new"
echo -e ""
if [[ "$DEBUG_COLORS" == "true" ]]; then
    echo -e "${dim}Color Detection Debug Info:"
    if [[ -n "$FORCE_BACKGROUND" ]]; then
        echo -e "  Background forced to: ${subbold}${FORCE_BACKGROUND^^}${dim}"
    else
        echo -e "  Background detected as: ${subbold}$(if [[ "$LIGHT_BG" == "true" ]]; then echo "LIGHT"; else echo "DARK"; fi)${dim}"
    fi
    echo -e "  TERM: ${subbold}${TERM:-unset}${dim}"
    echo -e "  TERM_PROGRAM: ${subbold}${TERM_PROGRAM:-unset}${dim}"
    echo -e "  COLORFGBG: ${subbold}${COLORFGBG:-unset}${dim}"
    echo -e "  TERM_THEME: ${subbold}${TERM_THEME:-unset}${dim}"
    echo -e ""
fi
echo -e "${dim}Tip: If colors are hard to read, try: ./verify.sh --no-color, --light, or --dark${normal}"
echo -e ""

# Check compose env file
COMPOSE_ENV_FILE="compose.env"
if [ ! -f ${COMPOSE_ENV_FILE} ]; then
    echo -e " - ${alert}ERROR: You are missing ${COMPOSE_ENV_FILE}${normal}"
    ALLGOOD=0
fi
echo -e ""

# pypowerwall
echo -e "${bold}Checking pypowerwall${dim}"
echo -e "----------------------------------------------------------------------------"
CONTAINER="pypowerwall"
VER=$UKN
PWVER=$UKN
PWSTATE="${alert}ERROR: Not Connected${dim}"
ENV_FILE="pypowerwall.env"
AUTH_FILE=".auth/.pypowerwall.auth"
PORT="8675"
echo -e -n "${dim} - Config File ${ENV_FILE}: "
if [ ! -f ${ENV_FILE} ]; then
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
else
    echo -e $GOOD
fi
echo -e -n "${dim} - Container ($CONTAINER): "
RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null) || true
if [ "$RUNNING" = "true" ]; then
    echo -e $GOOD
    echo -e -n "${dim} - Service (port $PORT): "
    if running http://localhost:$PORT/stats 200 0 2>/dev/null; then
        echo -e $GOOD
        VER=`curl --silent http://localhost:$PORT/stats | awk '{print $2" "$3" "$4}' | cut -d\" -f 2 2>/dev/null`
        SITENAME=`curl --silent http://localhost:$PORT/stats | sed 's/.*"site_name": "\(.*\)", "cloudmode".*/\1/' 2>/dev/null`
        CLOUDMODE=`curl --silent http://localhost:$PORT/stats | sed 's/.*"cloudmode": \(.*\), "fleetapi".*/\1/' 2>/dev/null`
        SITEID=`curl --silent http://localhost:$PORT/stats | sed 's/.*"siteid": \(.*\), "counter".*/\1/' 2>/dev/null`
        TEDAPI=`curl --silent http://localhost:$PORT/stats | sed 's/.*"tedapi": \(.*\), "pw3".*/\1/' 2>/dev/null`
        TEDAPIMODE=`curl --silent http://localhost:$PORT/stats | sed 's/.*"tedapi_mode": "\(.*\)", "siteid".*/\1/' 2>/dev/null`
        # check connection with powerwall
        if running http://localhost:$PORT/version 200 0 2>/dev/null; then
            PWSTATE="CONNECTED"
            PWVER=`curl --silent http://localhost:$PORT/version | awk '{print $2}' | cut -d\" -f 2 2>/dev/null`
        fi
    else
        echo -e "${alert}ERROR: Not Listening${normal}"
        LISTENING="false"
        ALLGOOD=0
    fi
elif [ "$RUNNING" = "false" ]; then
    echo -e "${alert}ERROR: Stopped${normal}"
    ALLGOOD=0
else
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
fi
echo -e "${dim} - Version: ${subbold}$VER"
echo -e "${dim} - Powerwall State: ${subbold}$PWSTATE${dim} - Firmware: ${subbold}$PWVER${dim}"
if [ -n "$SITENAME" ]; then
    echo -e "${dim} - Site Name: ${subbold}$SITENAME${normal}"
    SITEID="$SITEID ($SITENAME)"
fi
if running https://192.168.91.1/tedapi/din 403 0 2>/dev/null; then
    # if TEDAPI = "true" show connected
    if [ "$TEDAPI" = "true" ]; then
        VAL="${subbold}Connected ${dim}- Mode: ${subbold}${TEDAPIMODE}"
    else
        VAL="${alert}Not Connected"
    fi
    echo -e "${dim} - Gateway TEDAPI: ${subbold}Available ${dim}(192.168.91.1)"
    echo -e "${dim} - TEDAPI Vitals: ${VAL} ${dim}"
else
    echo -e "${dim} - Powerwall Gateway TEDAPI: ${normal}Not Available ${dim}(192.168.91.1)"
fi
if [ "$CLOUDMODE" = "true" ]; then
    echo -e "${dim} - Cloud Mode: ${subbold}YES ${dim}- Site ID: ${subbold}$SITEID"
elif [ "$LISTENING" = "false" ] && [ -f ${ENV_FILE} ] && ! grep -qE "^PW_HOST=.+" "${ENV_FILE}"; then
    echo -e "${dim} - Cloud Mode: ${subbold}YES ${dim}- ${alert}ERROR: Not Connected to Tesla Cloud${normal}"
    if [ ! -f "${AUTH_FILE}" ]; then
        echo -e "${dim} - Auth File ${AUTH_FILE}: ${alert}ERROR: Missing${normal}"
    fi
    ALLGOOD=0
else
    echo -e "${dim} - Cloud Mode: ${normal}NO"
fi
# Check to see that TZ is set in pypowerwall
if [ -f ${ENV_FILE} ] && ! grep -q "TZ=" ${ENV_FILE}; then
    echo -e "${dim} - ${alertdim}ERROR: Your pypowerwall settings are missing TZ.${normal}"
    ALLGOOD=0
fi
echo -e ""

# telegraf
echo -e "${bold}Checking telegraf${dim}"
echo -e "----------------------------------------------------------------------------"
CONTAINER="telegraf"
VER=$UKN
PORT=""
CONF_FILE="telegraf.conf"
echo -e -n "${dim} - Config File ${CONF_FILE}: "
if [ ! -f ${CONF_FILE} ]; then
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
else
    echo -e $GOOD
fi
CONF_FILE="telegraf.local"
echo -e -n "${dim} - Local Config File ${CONF_FILE}: "
if [ ! -f ${CONF_FILE} ]; then
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
else
    echo -e $GOOD
fi
echo -e -n "${dim} - Container ($CONTAINER): "
RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null) || true
if [ "$RUNNING" = "true" ]; then
    echo -e $GOOD
    VER=`v=$(docker exec --tty $CONTAINER sh -c "telegraf --version") && echo "$v" || echo "$UKN"`
elif [ "$RUNNING" = "false" ]; then
    echo -e "${alert}ERROR: Stopped${normal}"
    ALLGOOD=0
else
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
fi
echo -e "${dim} - Version: ${subbold}$VER"
echo -e ""

# influxdb
echo -e "${bold}Checking influxdb${dim}"
echo -e "----------------------------------------------------------------------------"
CONTAINER="influxdb"
VER=$UKN
CONF_FILE="influxdb.conf"
ENV_FILE="influxdb.env"
PORT="8086"
echo -e -n "${dim} - Config File ${CONF_FILE}: "
if [ ! -f ${CONF_FILE} ]; then
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
else
    echo -e $GOOD
fi
echo -e -n "${dim} - Environment File ${ENV_FILE}: "
if [ ! -f ${ENV_FILE} ]; then
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
else
    echo -e $GOOD
fi
echo -e -n "${dim} - Container ($CONTAINER): "
RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null) || true
if [ "$RUNNING" = "true" ]; then
    echo -e $GOOD
    echo -e -n "${dim} - Service (port $PORT): "
    if running http://localhost:$PORT/ping 204 1 2>/dev/null; then
        echo -e $GOOD
        VER=`v=$(docker exec --tty $CONTAINER sh -c "influx -version") && echo "$v" || echo "$UKN"`
    else
        echo -e "${alert}ERROR: Not Listening${normal}"
        ALLGOOD=0
    fi
    echo -e -n "${dim} - Filesystem (./$CONTAINER): "
    rm -f ./influxdb/WRITE
    ERR=`docker exec -it $CONTAINER sh -c "touch /var/lib/influxdb/WRITE 2>/dev/null"` || true
    if [ -e "./influxdb/WRITE" ]; then
        echo -e $GOOD
        rm -f ./influxdb/WRITE
    else
        echo -e "${alert}ERROR: Unable to write to filesystem - check permissions${normal}"
        ALLGOOD=0
    fi
elif [ "$RUNNING" = "false" ]; then
    echo -e "${alert}ERROR: Stopped${normal}"
    ALLGOOD=0
else
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
fi
echo -e "${dim} - Version: ${subbold}$VER"
echo -e ""

# grafana
echo -e "${bold}Checking grafana${dim}"
echo -e "----------------------------------------------------------------------------"
CONTAINER="grafana"
VER=$UKN
PORT="9000"
ENV_FILE="grafana.env"
echo -e -n "${dim} - Config File ${ENV_FILE}: "
if [ ! -f ${ENV_FILE} ]; then
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
else
    echo -e $GOOD
    if ! grep -q "yesoreyeram-boomtable-panel-1.5.0-alpha.3.zip" $ENV_FILE; then
        echo -e "${dim} - ${alertdim}WARNING: Your Grafana settings are outdated."
    fi
fi
echo -e -n "${dim} - Container ($CONTAINER): "
RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null) || true
if [ "$RUNNING" = "true" ]; then
    echo -e $GOOD
    VER=`v=$(docker exec --tty $CONTAINER sh -c "grafana-cli --version") && echo "$v" || echo "$UKN"`
    echo -e -n "${dim} - Service (port $PORT): "
    if running http://localhost:$PORT/login 200 1 2>/dev/null; then
        echo -e $GOOD
    else
        echo -e "${alert}ERROR: Not Listening - Logs:${alertdim}"
        echo -e "---"
        docker logs $CONTAINER 2>&1 | tail -11
        echo -e "---${normal}"
        ALLGOOD=0
    fi
    echo -e -n "${dim} - Filesystem (./$CONTAINER): "
    rm -f ./grafana/WRITE
    ERR=`docker exec -it $CONTAINER sh -c "touch /var/lib/grafana/WRITE 2>/dev/null"` || true
    if [ -e "./grafana/WRITE" ]; then
        echo -e $GOOD
        rm -f ./grafana/WRITE
    else
        echo -e "${alert}ERROR: Unable to write to filesystem - check permissions${normal}"
        ALLGOOD=0
    fi
elif [ "$RUNNING" = "false" ]; then
    echo -e "${alert}ERROR: Stopped${normal}"
    ALLGOOD=0
else
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
fi
echo -e "${dim} - Version: ${subbold}$VER"
echo -e ""

if grep -q "tesla-history" powerwall.extend.yml 2>/dev/null; then
    # tesla-history
    echo -e "${bold}Checking tesla-history${dim}"
    echo -e "----------------------------------------------------------------------------"
    CONTAINER="tesla-history"
    VER=$UKN
    CONF_FILE="tools/tesla-history/tesla-history.conf"
    AUTH_FILE="tools/tesla-history/tesla-history.auth"
    echo -e -n "${dim} - Config File ${CONF_FILE}: "
    if [ ! -f ${CONF_FILE} ]; then
        echo -e "${alert}ERROR: Missing${normal}"
        ALLGOOD=0
    else
        echo -e $GOOD
    fi
    echo -e -n "${dim} - Auth File ${AUTH_FILE}: "
    if [ ! -f ${AUTH_FILE} ]; then
        echo -e "${alert}ERROR: Missing${normal}"
        ALLGOOD=0
    else
        echo -e $GOOD
    fi
    echo -e -n "${dim} - Container ($CONTAINER): "
    RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null) || true
    if [ "$RUNNING" = "true" ]; then
        echo -e $GOOD
        VER=`v=$(docker exec -it $CONTAINER sh -c "python3 tesla-history.py --version") && echo "$v" || echo "$UKN"`
    elif [ "$RUNNING" = "false" ]; then
        echo -e "${alert}ERROR: Stopped${normal}"
        ALLGOOD=0
    else
        echo -e "${alert}ERROR: Missing${normal}"
        ALLGOOD=0
    fi
    echo -e "${dim} - Version: ${subbold}$VER"
    echo -e ""
fi

# weather411
echo -e "${bold}Checking weather411${dim}"
echo -e "----------------------------------------------------------------------------"
CONTAINER="weather411"
VER=$UKN
WEATHER=$UKN
ENV_FILE="weather/weather411.conf"
PORT="8676"
if [ ! -f ${ENV_FILE} ]; then
    echo -e "${dim} - Skipped: weather411 not set up (missing ${ENV_FILE})"
else
    echo -e -n "${dim} - Container ($CONTAINER): "
    RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null) || true
    if [ "$RUNNING" = "true" ]; then
        echo -e $GOOD
        echo -e -n "${dim} - Service (port $PORT): "
        if running http://localhost:$PORT/stats 200 0 2>/dev/null; then
            echo -e $GOOD
            VER=`curl --silent http://localhost:$PORT/stats | awk '{print $2" "$3" "$4}' | cut -d\" -f 2 2>/dev/null`
            # check connection with openweather
            if running http://localhost:$PORT/temp 200 0 2>/dev/null; then
                WEATHER=`curl --silent http://localhost:$PORT/temp 2>/dev/null`
            fi
            echo -e "${dim} - Weather: ${subbold}${WEATHER}"
        else
            echo -e "${alert}ERROR: Not Listening - Logs:${alertdim}"
            echo -e "---"
            docker logs $CONTAINER 2>&1 | tail -11
            echo -e "---${normal}"
            ALLGOOD=0
        fi
    elif [ "$RUNNING" = "false" ]; then
        echo -e "${alert}ERROR: Stopped${normal}"
        ALLGOOD=0
    else
        echo -e "${alert}ERROR: Missing${normal}"
        ALLGOOD=0
    fi
    echo -e "${dim} - Version: ${subbold}$VER"
fi
echo -e ""

if grep -q "ecowitt" powerwall.extend.yml 2>/dev/null; then
    # ecowitt
    echo -e "${bold}Checking ecowitt${dim} (optional component - OK if missing)"
    echo -e "----------------------------------------------------------------------------"
    CONTAINER="ecowitt"
    VER=$UKN
    WEATHER=$UKN
    ENV_FILE="weather/contrib/ecowitt/ecowitt.conf"
    PORT="8686"
    echo -e -n "${dim} - Config File ${ENV_FILE}: "
    if [ ! -f ${ENV_FILE} ]; then
        echo -e "${alertdim}Missing - ecowitt not set up"
        ALLGOOD=0
    else
        echo -e $GOOD
    fi
    echo -e -n "${dim} - Container ($CONTAINER): "
    RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null) || true
    if [ "$RUNNING" = "true" ]; then
        echo -e $GOOD
        echo -e -n "${dim} - Service (port $PORT): "
        if running http://localhost:$PORT/stats 200 0 2>/dev/null; then
            echo -e $GOOD
            VER=`curl --silent http://localhost:$PORT/stats | awk '{print $2" "$3" "$4}' | cut -d\" -f 2 2>/dev/null`
            # check connection with ecowitt
            if running http://localhost:$PORT/temp 200 0 2>/dev/null; then
                WEATHER=`curl --silent http://localhost:$PORT/temp 2>/dev/null`
            fi
            echo -e "${dim} - Weather: ${subbold}${WEATHER}"
        else
            echo -e "${alert}ERROR: Not Listening - Logs:${alertdim}"
            echo -e "---"
            docker logs $CONTAINER 2>&1 | tail -11
            echo -e "---${normal}"
            ALLGOOD=0
        fi
    elif [ "$RUNNING" = "false" ]; then
        echo -e "${alert}ERROR: Stopped${normal}"
        ALLGOOD=0
    else
        echo -e "${alert}ERROR: Missing${normal}"
        ALLGOOD=0
    fi
    echo -e "${dim} - Version: ${subbold}$VER"
    echo -e ""
fi

if [ $ALLGOOD -ne 1 ]; then
    echo -e "${alert}One or more tests failed.${normal}"
    # Final cleanup of any remaining terminal input
    read -t 0.1 -n 1000 2>/dev/null || true
    exit 1
else
    echo -e "${subbold}All tests succeeded.${normal}"
    # Final cleanup of any remaining terminal input
    read -t 0.1 -n 1000 2>/dev/null || true
    exit 0
fi
