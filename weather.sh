#!/bin/bash
#
# Interactive Weather Setup Script for Powerwall Dashboard
# by Jason Cox - 20 Aug 2022

# Files
CONF_FILE="weather/weather411.conf"
CONF_SRC="weather/weather411.conf.sample"
COMPOSE_ENV_FILE="compose.env"

# Verify not running as root
if [ "$EUID" -eq 0 ]; then
    echo "ERROR: Running this as root will cause permission issues."
    echo ""
    echo "Please ensure your local user is in the docker group and run without sudo."
    echo "   sudo usermod -aG docker \$USER"
    echo "   $0"
    echo ""
    exit 1
fi

# Docker Dependency Check - moved to compose-dash.sh, 14/10/22

# Set latitude and longitude
LAT="0.0"
LONG="0.0"
# Check for LAT and LONG on command line
if [ "${1}" == "setup" ] && [ -n "${2}" ] && [ -n "${3}" ]; then
    LAT="${2}"
    LONG="${3}"
else
    # Try to detect location
    if PYTHON=$(command -v python3 || command -v python); then
        if IP_RESPONSE=$(curl -s -L --fail https://freeipapi.com/api/json); then
            # Try to parse JSON but catch any errors
            read LAT LONG <<< $(printf '%s' "$IP_RESPONSE" | "${PYTHON}" -c '
import sys, json
try:
    data = json.load(sys.stdin)
    print(data["latitude"], data["longitude"])
except Exception:
    print("0.0", "0.0")
')
        fi
    fi
fi

# Setup Weather?
echo "Weather Data Setup"
echo "-----------------------------------------"
# Weather411 Dependency Check
if grep -q "weather411" powerwall.yml; then
    echo "Weather data from OpenWeatherMap can be added to your Powerwall Dashboard"
    echo "graphs.  This requires that you set up a free account with OpenWeatherMap"
    echo "and enter the API Key during this setup process."
    echo ""
else
    echo "WARNING: Your powerwall.yml file is outdated (missing weather411)."
    echo "         Skipping weather setup."
    echo ""
    exit 0
fi
read -r -p "Do you wish to setup Weather Data? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
    echo "Forecast looks great!  Proceeding..."
    echo ""
else
    echo "No problem. If you change your mind, run weather.sh to setup later."
    echo ""
    exit 0
fi

# Check for missing docker compose env file
if [ ! -f ${COMPOSE_ENV_FILE} ]; then
    echo "ERROR: Missing compose.env file."
    echo "Please run setup.sh or copy compose.env.sample to compose.env."
    exit 1
fi

# Configuration File
if [ -f ${CONF_FILE} ]; then
    echo "Existing Configuration Found"
    echo ""
    # Load existing data
    # TODO
    # Display existing data
    cat "${CONF_FILE}"
    echo ""
    read -r -p "Overwrite existing settings? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Removing old file ${CONF_FILE}."
        cp "${CONF_FILE}" "${CONF_FILE}.orig"
        rm "${CONF_FILE}"
    else
        echo "Using existing ${CONF_FILE}."
        echo ""
        if [ "${1}" != "setup" ]; then
            . compose-dash.sh up -d
        fi
        exit 0
    fi
fi

# Get OpenWeatherMap data from user
if [ ! -f ${CONF_FILE} ]; then
    if [ ! -f ${CONF_SRC} ]; then
        echo "ERROR: You are missing the ${CONF_SRC} file - please pull the latest"
        echo "       from https://github.com/jasonacox/Powerwall-Dashboard and try again."
        exit 1
    fi
    echo ""
    echo "Set up a free account at OpenWeatherMap.org to get an API key"
    echo "   1. Go to https://openweathermap.org/"
    echo "   2. Create a new account and check your email to verify your account"
    echo "   3. Click on 'API Keys' tab and copy 'Key' value and paste below."
    echo ""
    read -p 'Enter OpenWeatherMap API Key: ' APIKEY
    if [ -z "${APIKEY}" ]; then
        echo "ERROR: A key is required. Exiting now."
        exit 0
    fi
    echo ""
    echo "Enter your location coordinates to determine weather in your location."
    # check to see if LAT and LONG are not 0.0
    if [ "${LAT}" == "0.0" ] || [ "${LONG}" == "0.0" ]; then
        echo "   Your current location could not be automatically determined."
        echo "   For help go to https://jasonacox.github.io/Powerwall-Dashboard/location.html"
    else
        echo "   Your current location appears to be Latitude: ${LAT}, Longitude: ${LONG}"
    fi
    echo ""
    read -p 'Enter Latitude (default: '${LAT}'): ' USER_LAT
    if [ -n "${USER_LAT}" ]; then
        LAT="${USER_LAT}"
    fi
    read -p 'Enter Longitude (default '${LONG}'): ' USER_LONG
    if [ -n "${USER_LONG}" ]; then
        LONG="${USER_LONG}"
    fi
    while :
    do
        echo ""
        echo "Enter the desired units: M)etric, I)mperial or S)tandard where:"
        echo "    M)etric = temperature in Celsius"
        echo "    I)mperial = temperature in Fahrenheit"
        echo "    S)tandard = temperature in Kelvin"
        echo ""
        read -p 'Enter M, I or S: ' response
        if [[ "$response" =~ ^([sS])$ ]]; then
            UNITS="standard"
        elif [[ "$response" =~ ^([mM])$ ]]; then
            UNITS="metric"
        elif [[ "$response" =~ ^([iI])$ ]]; then
            UNITS="imperial"
        else
            echo " Error: Invalid selection - try again."
            continue
        fi
        echo "Units selected: ${UNITS}"
        echo ""
        echo "NOTE: The OpenWeatherMap key can take up to 2 hours to be valid."
        echo "      You may see errors or no data until it is fully activated."
        break
    done
    cp "${CONF_SRC}" "${CONF_FILE}"
fi

# Replace configuration data with user input
sed -i.bak \
    -e "s@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@${APIKEY}@g" \
    -e "s@xxx.xxxx@${LAT}@g" \
    -e "s@yyy.yyyy@${LONG}@g" \
    -e "s@UNITS = metric@UNITS = ${UNITS}@g" \
    "${CONF_FILE}"

# Pass back to setup or complete weather411 setup
echo ""
if [[ "${1}" == "setup" ]]; then
    echo "Weather Configuration Complete"
    echo ""
else
    # run docker compose in current shell.
    . compose-dash.sh up -d
    echo "Fetching local weather..."
    docker restart weather411
    echo "Weather Setup Complete"
    echo ""
fi
