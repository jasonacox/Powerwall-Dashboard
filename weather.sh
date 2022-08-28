#!/bin/bash
#
# Interactive Weather Setup Script for Powerwall Dashboard
# by Jason Cox - 20 Aug 2022

# Files
CONF_FILE="weather/weather411.conf"
CONF_SRC="weather/weather411.conf.sample"

# Verify not running as root
if [ "$EUID" -eq 0 ]; then 
  echo "ERROR: Running this as root will cause permission issues."
  echo ""
  echo "Please ensure your local user in in the docker group and run without sudo."
  echo "   sudo usermod -aG docker \$USER"
  echo "   $0"
  echo ""
  exit 1
fi

# Docker Dependency Check
if ! docker info > /dev/null 2>&1; then
    echo "ERROR: docker is not available or not runnning."
    echo "This script requires docker, please install and try again."
    exit 1
fi
if ! docker-compose version > /dev/null 2>&1; then
    echo "ERROR: docker-compose is not available or not runnning."
    echo "This script requires docker-compose, please install and try again."
    exit 1
fi

# Setup Weather?
echo "Weather Data Setup"
echo "-----------------------------------------"
# Weather411 Dependency Check
if grep -q "weather411" powerwall.yml; then
    echo "Weather data from OpenWeatherMap can be added to your Powerwall Dashboard"
    echo "graphs.  This requires that you set up a free acccount with OpenWeatherMap"
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

# Configuration File 
if [ -f ${CONF_FILE} ]; then
    echo "Existing Configuration Founded"
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
        exit 0
    fi
fi

# Get OpenWeatherMap data from user
if [ ! -f ${CONF_FILE} ]; then
    if [ -f ${CONF_SRC} ]; then
        cp "${CONF_SRC}" "${CONF_FILE}"
    else
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
    echo "   For help go to https://jasonacox.github.io/Powerwall-Dashboard/location.html"
    echo ""
    read -p 'Enter Latitude: ' LAT
    if [ -z "${LAT}" ]; then 
        echo "ERROR: Valid coordinates are required. Exiting now."
        exit 0
    fi
    read -p 'Enter Longitude: ' LON
    if [ -z "${LON}" ]; then 
        echo "ERROR: Valid coordinates are required. Exiting now."
        exit 0
    fi
    while :
    do
        echo ""
        echo "Enter the desired units: M)etric, I)mperial or S)tandard where:"
        echo "    M)etrics = temperature in Celsius"
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
fi

# Replace configuration data with user input
sed -i.bak \
    -e "s@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@${APIKEY}@g" \
    -e "s@xxx.xxxx@${LAT}@g" \
    -e "s@yyy.yyyy@${LON}@g" \
    -e "s@UNITS = metric@UNITS = ${UNITS}@g" \
    "${CONF_FILE}"

# Pass back to setup or complete weather411 setup
echo ""
if [[ "${1}" == "setup" ]]; then
    echo "Weather Configuration Complete"
    echo ""
else
    echo "Running Docker-Compose..."
    docker-compose -f powerwall.yml up -d
    echo "Weather Setup Complete"
    echo ""
fi
