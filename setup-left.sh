#!/bin/bash
#
# Interactive Setup Script for Powerwall Dashboard
# by Jason Cox - 21 Jan 2022

# Stop on Errors
set -e

# Set Globals
COMPOSE_ENV_FILE="compose-left.env"
TELEGRAF_LOCAL="telegraf-left.local"
PW_ENV_FILE="pypowerwall-left.env"
GF_ENV_FILE="grafana.env"

if [ ! -f VERSION ]; then
    echo "ERROR: Missing VERSION file. Setup must run from installation directory."
    echo ""
    exit 1
fi
VERSION=`cat VERSION`

echo "Powerwall Dashboard (v${VERSION}) - SETUP"
echo "-----------------------------------------"

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

# Verify user in docker group (not required for Windows Git Bash)
if ! type winpty > /dev/null 2>&1; then
    if ! $(id -Gn 2>/dev/null | grep -qE " docker( |$)"); then
        echo "WARNING: You do not appear to be in the docker group."
        echo ""
        echo "Please ensure your local user is in the docker group and run without sudo."
        echo "   sudo usermod -aG docker \$USER"
        echo "   $0"
        echo ""
        read -r -p "Setup - Proceed? [y/N] " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
        then
            echo ""
        else
            echo "Cancel"
            exit 1
        fi
    fi
fi

# Windows Git Bash docker exec compatibility fix
if type winpty > /dev/null 2>&1; then
    shopt -s expand_aliases
    alias docker="winpty -Xallow-non-tty -Xplain docker"
fi

# Service Running Helper Function
running() {
    local url=${1:-http://localhost:80}
    local code=${2:-200}
    local status=$(curl --head --location --connect-timeout 5 --write-out %{http_code} --silent --output /dev/null ${url})
    [[ $status == ${code} ]]
}

# Compose Profiles Helper Functions
get_profile() {
    if [ ! -f ${COMPOSE_ENV_FILE} ]; then
        return 1
    else
        unset COMPOSE_PROFILES
        . "${COMPOSE_ENV_FILE}"
    fi
    # Check COMPOSE_PROFILES for profile
    IFS=',' read -a PROFILES <<< ${COMPOSE_PROFILES}
    for p in "${PROFILES[@]}"; do
        if [ "${p}" == "${1}" ]; then
            return 0
        fi
    done
    return 1
}

add_profile() {
    # Create default docker compose env file if needed.
    if [ ! -f ${COMPOSE_ENV_FILE} ]; then
        cp "${COMPOSE_ENV_FILE}.sample" "${COMPOSE_ENV_FILE}"
    fi
    if ! get_profile "${1}"; then
        # Add profile to COMPOSE_PROFILES and save to env file
        PROFILES+=("${1}")
        if [ -z "${COMPOSE_PROFILES}" ]; then
            if grep -q "^#COMPOSE_PROFILES=" "${COMPOSE_ENV_FILE}"; then
                sed -i.bak "s@^#COMPOSE_PROFILES=.*@COMPOSE_PROFILES=$(IFS=,; echo "${PROFILES[*]}")@g" "${COMPOSE_ENV_FILE}"
            else
                echo -e "\nCOMPOSE_PROFILES=$(IFS=,; echo "${PROFILES[*]}")" >> "${COMPOSE_ENV_FILE}"
            fi
        else
            sed -i.bak "s@^COMPOSE_PROFILES=.*@COMPOSE_PROFILES=$(IFS=,; echo "${PROFILES[*]}")@g" "${COMPOSE_ENV_FILE}"
        fi
    fi
}

# Docker Dependency Check
if ! docker info > /dev/null 2>&1; then
    echo "ERROR: docker is not available or not running."
    echo "This script requires docker, please install and try again."
    exit 1
fi
if ! docker-compose version > /dev/null 2>&1; then
    if ! docker compose version > /dev/null 2>&1; then
        echo "ERROR: docker-compose is not available or not running."
        echo "This script requires docker-compose or docker compose."
        echo "Please install and try again."
        exit 1
    fi
fi

# Check COMPOSE_PROFILES for existing configuration profile
if get_profile "default"; then
    PROFILE="default"
elif get_profile "solar-only"; then
    PROFILE="solar-only"
else
    # Prompt for configuration profile if not set
    echo "Select configuration profile:"
    echo ""
    echo " 1 - default     (Powerwall w/ Gateway on LAN)"
    echo " 2 - solar-only  (No Gateway - data retrieved from Tesla Cloud)"
    echo ""
    while :
    do
        read -r -p "Select profile: " response
        if [ "${response}" == "1" ]; then
            PROFILE="default"
        elif [ "${response}" == "2" ]; then
            PROFILE="solar-only"
        else
            continue
        fi
        # Add selected profile to COMPOSE_PROFILES
        add_profile "${PROFILE}"
        echo ""
        break
    done
fi

# Check if running as non-default user (not required for Windows Git Bash)
if ! type winpty > /dev/null 2>&1; then
    notset=0
    if [ -z "${PWD_USER}" ]; then
        PWD_USER="1000:1000"
        notset=1
    fi
    if [ "${PWD_USER}" == "1000:1000" ]; then
        desc="normal default"
        name="Default"
    else
        desc="configured user"
        name="  Saved"
    fi
    CURRENT_USER="$(id -u):$(id -g)"
    if [ "${CURRENT_USER}" != "${PWD_USER}" ]; then
        echo "WARNING: Your current user uid/gid does not match the ${desc}."
        echo ""
        echo "Current - ${CURRENT_USER}"
        echo "${name} - ${PWD_USER}"
        echo ""
        echo "Do you wish to configure the dashboard to run as the current user?"
        echo "(this is typically required to avoid permission issues)"
        echo ""
        read -r -p "Run as current user? (${CURRENT_USER}) [Y/n] " response
        if [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
            echo ""
            echo "No problem. If you have permission issues, edit ${COMPOSE_ENV_FILE} or re-run setup."
            echo ""
        else
            # Update PWD_USER and save to docker compose env file
            if [ $notset -eq 1 ]; then
                if grep -q "^#PWD_USER=" "${COMPOSE_ENV_FILE}"; then
                    sed -i.bak "s@^#PWD_USER=.*@PWD_USER=\"${CURRENT_USER}\"@g" "${COMPOSE_ENV_FILE}"
                else
                    echo -e "\nPWD_USER=\"${CURRENT_USER}\"" >> "${COMPOSE_ENV_FILE}"
                fi
            else
                sed -i.bak "s@^PWD_USER=.*@PWD_USER=\"${CURRENT_USER}\"@g" "${COMPOSE_ENV_FILE}"
            fi
            echo ""
        fi
    fi
fi

# Check for RPi Issue with Buster
if [[ -f "/etc/os-release" ]]; then
    OS_VER=`grep PRETTY /etc/os-release | cut -d= -f2 | cut -d\" -f2`
    if [[ "$OS_VER" == "Raspbian GNU/Linux 10 (buster)" ]]
    then
        echo "WARNING: You are running ${OS_VER}"
        echo "    This OS version has a bug in the libseccomp2 library that"
        echo "    causes the pypowerwall container to fail."
        echo "    See details: https://github.com/jasonacox/Powerwall-Dashboard/issues/56"
        echo ""
        read -r -p "Setup - Proceed? [y/N] " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
        then
            echo ""
        else
            echo "Cancel"
            exit 1
        fi
    fi
fi

CURRENT=`cat tz`

echo "Timezone (leave blank for ${CURRENT})"
read -p 'Enter Timezone: ' TZ
echo ""

if [ "${PROFILE}" == "default" ]
then
    # Powerwall Credentials
    if [ -f ${PW_ENV_FILE} ]; then
        echo "Current Powerwall Credentials:"
        echo ""
        cat ${PW_ENV_FILE}
        echo ""
        read -r -p "Update these credentials? [y/N] " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            rm ${PW_ENV_FILE}
        else
            echo "Using existing ${PW_ENV_FILE}."
        fi
    fi

    # Create Powerwall Settings
    if [ ! -f ${PW_ENV_FILE} ]; then
        echo "Enter credentials for Powerwall..."
        read -p 'Password: ' PASSWORD
        read -p 'Email: ' EMAIL
        read -p 'IP Address: ' IP
        echo "PW_EMAIL=${EMAIL}" > ${PW_ENV_FILE}
        echo "PW_PASSWORD=${PASSWORD}" >> ${PW_ENV_FILE}
        echo "PW_HOST=${IP}" >> ${PW_ENV_FILE}
        echo "PW_TIMEZONE=America/Los_Angeles" >> ${PW_ENV_FILE}
        echo "TZ=America/Los_Angeles" >> ${PW_ENV_FILE}
        echo "PW_DEBUG=no" >> ${PW_ENV_FILE}
        echo "PW_STYLE=grafana-dark" >> ${PW_ENV_FILE}
    fi

    # Create default telegraf local file if needed.
    if [ ! -f ${TELEGRAF_LOCAL} ]; then
        cp "${TELEGRAF_LOCAL}.sample" "${TELEGRAF_LOCAL}"
    fi
fi

# Create Grafana Settings if missing (required in 2.4.0)
if [ ! -f ${GF_ENV_FILE} ]; then
    cp "${GF_ENV_FILE}.sample" "${GF_ENV_FILE}"
fi

echo ""
if [ -z "${TZ}" ]; then
    echo "Using ${CURRENT} timezone..."
    ./tz.sh "${CURRENT}"
else
    echo "Setting ${TZ} timezone..."
    ./tz.sh "${TZ}"
fi
echo "-----------------------------------------"
echo ""

# Optional - Setup Weather Data
if [ -f weather.sh ]; then
    ./weather.sh setup
fi

# Build Docker in current environment
./compose-dash-left.sh up -d
echo "-----------------------------------------"

# Set up Influx
echo "Waiting for InfluxDB to start..."
until running http://localhost:8096/ping 204 2>/dev/null; do
    printf '.'
    sleep 5
done
echo " up!"
sleep 2
echo "Setup InfluxDB Data..."
docker exec --tty influxdb-left sh -c "influx -import -path=/var/lib/influxdb-left/influxdb-left.sql"
sleep 2
# Execute Run-Once queries for initial setup.
cd influxdb
for f in run-once-left-2*.sql; do
    if [ ! -f "${f}.done" ]; then
        echo "Executing single run query $f file..."
        docker exec --tty influxdb-left sh -c "influx -import -path=/var/lib/influxdb-left/${f}"
        echo "OK" > "${f}.done"
    fi
done
cd ..

# Restart weather411 to force a sample
if [ -f weather/weather411.conf ] && get_profile "weather411"; then
    echo "Fetching local weather..."
    docker restart weather411
fi

if [ "${PROFILE}" == "solar-only" ]
then
    # Setup tesla-history
    if [ -z "${TZ}" ]; then
        TZ="${CURRENT}"
    fi
    echo "Setup tesla-history..."
    docker exec -it tesla-history python3 tesla-history.py --setup --timezone "${TZ}"

    # Restart tesla-history
    echo "Restarting tesla-history..."
    docker restart tesla-history
fi

# Display Final Instructions
if [ "${PROFILE}" == "solar-only" ]
then
    DASHBOARD="dashboard-solar-only.json"
else
    DASHBOARD="dashboard.json"
fi
cat << EOF
------------------[ Final Setup Instructions ]-----------------

Open Grafana at http://localhost:9000/ ... use admin/admin for login.

Follow these instructions for *Grafana Setup*:

* From 'Configuration\Data Sources' add 'InfluxDB' database with:
  - Name: 'InfluxDB-Left'
  - URL: 'http://influxdb:8086'
  - Database: 'powerwall-left'
  - Min time interval: '5s'
  - Click "Save & test" button

* From 'Configuration\Data Sources' add 'Sun and Moon' database with:
  - Name: 'Sun and Moon'
  - Enter your latitude and longitude (tool here: https://bit.ly/3wYNaI1 )
  - Click "Save & test" button

* From 'Dashboard\Browse', select 'New/Import', and upload '${DASHBOARD}'
  from the ${PWD}/dashboards folder.

EOF
