#!/bin/bash
#
# Interactive Setup Script for Powerwall Dashboard
# by Jason Cox - 21 Jan 2022

# Stop on Errors
set -e

# Set Globals
COMPOSE_ENV_FILE="compose.env"
INFLUXDB_ENV_FILE="influxdb.env"
TELEGRAF_LOCAL="telegraf.local"
PW_ENV_FILE="pypowerwall.env"
GF_ENV_FILE="grafana.env"
PW_STYLE="grafana-dark"

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

# Verify user has write permission to this directory
if [ ! -w . ]; then
    echo "ERROR: Your user ($USER) does not have write permission to this directory."
    echo ""
    ls -ld "$(pwd)"
    echo ""
    echo "Please fix file permissions and try again."
    echo ""
    exit 1
fi

# Verify user in docker group (not required for Windows Git Bash)
if ! type winpty > /dev/null 2>&1; then
    if ! $(id -Gn 2>/dev/null | grep -qw "docker"); then
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

# Docker Dependency Check
if ! docker info > /dev/null 2>&1; then
    echo "ERROR: docker is not available or not running."
    echo "This script requires docker, please install and try again."
    exit 1
fi

# Verify Docker Compose Version
if ! docker compose version > /dev/null 2>&1; then
    if docker-compose version > /dev/null 2>&1; then
        # Check for version information to see if it is not V1
        COMPOSE_VERSION=`docker-compose version --short`
        if [[ "${COMPOSE_VERSION}" == "1"* ]]; then
            # Build Docker (v1)
            echo "ERROR: Docker Compose V1 Found: Upgrade Required"
            echo "See Migration Instructions at https://docs.docker.com/compose/migrate/"
            exit 1
        fi
    else
        echo "ERROR: Docker Compose is not available."
        echo "This script requires Docker Compose."
        echo "Please install and try again."
        exit 1
    fi
fi

# Command Line Options
while getopts ":hf" opt; do
    case ${opt} in
        h )
            echo "Usage: setup.sh [-h]"
            echo "  -h   Display this help message."
            echo "  -f   Setup FleetAPI Cloud Mode"
            exit 0
            ;;
        f )
            echo "Setup FleetAPI Cloud Mode"
            echo ""
            if [ ! -f ${PW_ENV_FILE} ]; then
                echo "ERROR: Missing ${PW_ENV_FILE}. Run setup.sh first."
                echo ""
                exit 1
            fi
            echo "This will configure FleetAPI Cloud mode for Powerwall systems."
            echo ""
            read -r -p "Setup FleetAPI Cloud Mode? [Y/n] " response
            if [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
                echo "Cancel"
                exit 1
            fi
            echo ""
            echo "Running FleetAPI Cloud Mode Setup..."
            echo ""
            docker exec -it pypowerwall python3 -m pypowerwall fleetapi
            echo ""
            echo "Restarting..."
            docker restart pypowerwall
            echo "-----------------------------------------"
            exit 0
            ;;
        \? )
            echo "Invalid Option: -$OPTARG" 1>&2
            exit 1
            ;;
    esac
done

# Check PW_ENV_FILE for existing configuration
if [ ! -f ${PW_ENV_FILE} ]; then
    choice=""
    config="None"
elif grep -qE "^PW_HOST=.+" "${PW_ENV_FILE}"; then
    choice="[1] "
    config="Local Access"
else
    choice="[2] "
    config="Tesla Cloud"
fi

# Prompt for configuration
echo "Select configuration mode:"
echo ""
echo "Current: ${config}"
echo ""
echo " 1 - Local Access     (Powerwall 1, 2, or + using the Tesla Gateway on LAN) - Default"
echo " 2 - Tesla Cloud      (Solar-only systems or Powerwalls without LAN access)"
echo " 3 - FleetAPI Cloud   (Powerwall systems using Official Telsa API)"
echo " 4 - Extended Metrics (Powerwall 2, +, or 3 using TEDAPI and local WiFi access)"
echo ""
pw3=0
while :; do
    read -r -p "Select mode: ${choice}" response
    if [ "${response}" == "1" ]; then
        selected="Local Access"
    elif [ "${response}" == "2" ]; then
        selected="Tesla Cloud"
    elif [ "${response}" == "3" ]; then
        selected="FleetAPI Cloud"
    elif [ "${response}" == "4" ]; then
        selected="Local Access"
        pw3=1
    elif [ -z "${response}" ] && [ ! -z "${choice}" ]; then
        selected="${config}"
    else
        continue
    fi
    if [ ! -z "${choice}" ] && [ "${selected}" != "${config}" ]; then
        echo ""
        read -r -p "You are already using the ${config} configuration, are you sure you wish to change? [y/N] " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
        then
            config="${selected}"
            rm ${PW_ENV_FILE}
            echo ""
            break
        else
            echo "Cancel"
            exit 1
        fi
    else
        config="${selected}"
        echo ""
        break
    fi
done

# Create default docker compose env file if needed.
if [ ! -f ${COMPOSE_ENV_FILE} ]; then
    cp "${COMPOSE_ENV_FILE}.sample" "${COMPOSE_ENV_FILE}"
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

# Function to display a (filtered) paginated list of timezones
show_timezones() {
    local FILTER="$1"
    local LIST_CMD=""
    if command -v timedatectl >/dev/null 2>&1; then
        LIST_CMD="timedatectl list-timezones"
    elif [ -f /usr/share/zoneinfo/zone.tab ]; then
        # Escape $3 so shell doesn't expand it before awk runs
        LIST_CMD="awk '!/^#/ {print \\$3}' /usr/share/zoneinfo/zone.tab"
    else
        LIST_CMD="find /usr/share/zoneinfo -type f -maxdepth 4 2>/dev/null | sed 's#^/usr/share/zoneinfo/##'"
    fi

    # Build list (apply optional filter) - allow zero matches without aborting
    if [ -n "$FILTER" ]; then
        TZ_LIST=$( { eval "$LIST_CMD" | grep -F "$FILTER" || true; } | sort )
    else
        TZ_LIST=$(eval "$LIST_CMD" | sort)
    fi

    if [ -z "$TZ_LIST" ]; then
        echo "No timezones match filter '$FILTER'."
        return 0
    fi

    # If less is available and stdout is a TTY, use it for paging
    if command -v less >/dev/null 2>&1 && [ -t 1 ]; then
        echo "$TZ_LIST" | less
        return 0
    fi

    # Manual pagination fallback
    local PAGE_SIZE=30
    local count=0
    while IFS= read -r line; do
        printf '%s\n' "$line"
        count=$((count+1))
        if (( count % PAGE_SIZE == 0 )); then
            read -p "--More-- (Enter=continue, q=quit) " ans
            [[ "$ans" == "q" || "$ans" == "Q" ]] && break
        fi
    done <<< "$TZ_LIST"
}


# Timezone input validation
echo "Timezone (leave blank for ${CURRENT} or ? to browse)"
while true; do
    read -p 'Enter Timezone: ' TZ
    if [ "$TZ" = "?" ]; then
        read -p 'Optional filter (e.g., America/ or Europe/Paris): ' TZFILT
        show_timezones "$TZFILT"
        continue
    fi
    if [ -z "$TZ" ]; then
        TZ="$CURRENT"
        break
    fi

    # 1) timedatectl (most accurate, includes multi-level names)
    if command -v timedatectl >/dev/null 2>&1; then
        if timedatectl list-timezones 2>/dev/null | grep -Fx "$TZ" >/dev/null; then
            break
        fi
    fi

    # 2) Direct zoneinfo file path (supports multi-level e.g. America/Argentina/Buenos_Aires)
    if [ -f "/usr/share/zoneinfo/$TZ" ]; then
        break
    fi

    # 3) Check zone.tab third column (if present) – some systems lack timedatectl
    if [ -f /usr/share/zoneinfo/zone.tab ]; then
        if awk '{print $3}' /usr/share/zoneinfo/zone.tab | grep -Fx "$TZ" >/dev/null; then
            break
        fi
    fi

    # 4) POSIX / RFC style TZ strings (e.g. GMT, UTC, GMT+5, EST5EDT, etc.)
    # Only accept if it contains at least one alphabetic character to avoid numeric garbage like '1'.
    if [[ "$TZ" =~ [A-Za-z] ]]; then
        if TZ="$TZ" date +%Z >/dev/null 2>&1; then
            echo "Note: '$TZ' accepted as POSIX TZ string (not an Olson zone identifier)."
            break
        fi
    fi

    echo ""
    echo "WARNING: '$TZ' is not a recognized timezone."
    echo -n "Do you wish to use this timezone anyway? [y/N] "
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        break
    fi
    echo ""
done
echo ""

# Powerwall Credentials
if [ -f ${PW_ENV_FILE} ]; then
    echo "Current Credentials:"
    echo ""
    cat ${PW_ENV_FILE}
    echo ""
    read -r -p "Update these credentials? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        rm ${PW_ENV_FILE}
        echo ""
    else
        echo "Using existing ${PW_ENV_FILE}."
    fi
fi

# Function to test a GW IP to see if it responds
function test_ip() {
    local IP=$1
    if [ -z "${IP}" ]; then
        return 1
    fi
    if curl -k --head --connect-timeout 2 --silent https://${IP} > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Create Powerwall Settings
if [ ! -f ${PW_ENV_FILE} ]; then
    if [ "${config}" == "Local Access" ]; then
        if [ $pw3 -eq 1 ]; then
            echo "Setting credentials for Powerwall 3..."
            PASSWORD=""
            EMAIL=""
        else
            echo "Enter credentials for Powerwall..."
            while [ -z "${PASSWORD}" ]; do
                read -p 'Password: ' PASSWORD
            done
            while [ -z "${EMAIL}" ]; do
                read -p 'Email: ' EMAIL
            done
        fi
        IP=""
        # Can we reach 192.168.91.1
        if test_ip "192.168.91.1"; then
            IP="192.168.91.1"
            echo "Found Powerwall Gateway at ${IP}"
            read -p 'Use this IP? [Y/n] ' response
            if [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
                IP=""
            else
                echo ""
                echo "Congratulations!"
                echo "Extended Device Metrics (vitals) are available on this endpoint via TEDAPI."
                echo "However, for this to work, you must connect directly to the WiFi access point of the"
                echo "Powerwall or gateway access point, and you will need the WiFi password."
                echo "This password is often found on a QR code on the Powerwall."
                echo ""
                read -p 'Enter Gateway Password or leave blank to disable: ' PW
                if [ -z "${PW}" ]; then
                    PW_GW_PWD=""
                else
                    PW_GW_PWD="${PW}"
                fi
                echo ""
                # Double check the user doesn't have a Powerwall 3
                if [ $pw3 -ne 1 ]; then
                    read -p 'Do you have a Powerwall 3? [y/N] ' response
                    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                        pw3=1
                        PASSWORD=""
                        EMAIL=""
                    fi
                    echo ""
                fi
            fi
        else
            echo "The Powerwall Gateway (192.168.91.1) is not found on your LAN."
            if [ $pw3 -eq 1 ]; then
                echo ""
                echo "Powerwall 3 requires access to the Gateway for pull local data."
                echo "Ensure the Gateway can be reached by your host and rerun setup."
                echo "Alternatively you can select a Tesla Cloud mode."
                echo ""
                echo "Test: curl -k --head https://192.168.91.1"
                echo ""
                exit 1
            fi
            echo "Standard dashboard metrics will work but Extended data (vitals) via TEDAPI"
            echo "will not be available. Consult the project for information on how to enable."
            echo "Proceeding with standard metrics..."
            echo ""
        fi
        if [ -z "${IP}" ]; then
            read -p 'Powerwall IP Address (leave blank to scan network): ' IP
        fi
    else
        echo "Enter email address for Tesla Account..."
        while [ -z "${EMAIL}" ]; do
            read -p 'Email: ' EMAIL
        done
        echo "If you have a Solar-only system, you can customize the dashboard for Solar and"
        echo "hide the Powerwall metrics."
        echo ""
        # ask if user has a solar only system
        read -p 'Set dashboard to Solar-only system? [y/N] ' response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            PW_STYLE="solar"
        fi
    fi
    echo "PW_EMAIL=${EMAIL}" > ${PW_ENV_FILE}
    echo "PW_PASSWORD=${PASSWORD}" >> ${PW_ENV_FILE}
    echo "PW_HOST=${IP}" >> ${PW_ENV_FILE}
    echo "PW_TIMEZONE=America/Los_Angeles" >> ${PW_ENV_FILE}
    echo "TZ=America/Los_Angeles" >> ${PW_ENV_FILE}
    echo "PW_DEBUG=no" >> ${PW_ENV_FILE}
    echo "PW_STYLE=${PW_STYLE}" >> ${PW_ENV_FILE}
    if [ ! -z "${PW_GW_PWD}" ]; then
        echo "PW_GW_PWD=${PW_GW_PWD}" >> ${PW_ENV_FILE}
    fi
fi

# Create default telegraf local file if needed.
if [ ! -f ${TELEGRAF_LOCAL} ]; then
    cp "${TELEGRAF_LOCAL}.sample" "${TELEGRAF_LOCAL}"
fi

# Create InfluxDB env file if missing (required in 3.0.7)
if [ ! -f ${INFLUXDB_ENV_FILE} ]; then
    cp "${INFLUXDB_ENV_FILE}.sample" "${INFLUXDB_ENV_FILE}"
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

# Get latitude and longitude 
LAT="0.0"
LONG="0.0"
# Check for existing LAT and LONG in grafana/provisions/datasources/sunandmoon.yml
if [ -f grafana/provisions/datasources/sunandmoon.yml ]; then
    LAT=$(grep latitude grafana/provisions/datasources/sunandmoon.yml | cut -d: -f2 | tr -d '[:space:]')
    LONG=$(grep longitude grafana/provisions/datasources/sunandmoon.yml | cut -d: -f2 | tr -d '[:space:]')
fi
# If LAT and LONG are zzLAT and zzLONG, then use the IP address to determine location
if [ "${LAT}" == "zzLAT" ] || [ "${LONG}" == "zzLONG" ] || [ "${LAT}" == "0.0" ] || [ "${LONG}" == "0.0" ]; then
    echo "Attempting to determine your location..."
    LAT="0.0"
    LONG="0.0"
    # Use IP address to determine location
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
else
    echo "Found existing location coordinates for sun cycle."
fi
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
echo ""

# Optional - Setup Weather Data
if [ -f weather.sh ]; then
    ./weather.sh setup "${LAT}" "${LONG}"
fi

if [ -f grafana/sunandmoon-template.yml ]; then
    cp grafana/sunandmoon-template.yml grafana/provisions/datasources/sunandmoon.yml
    sed -i.bak "s@zzLAT@${LAT}@g" grafana/provisions/datasources/sunandmoon.yml
    sed -i.bak "s@zzLONG@${LONG}@g" grafana/provisions/datasources/sunandmoon.yml
    # Remove backup file
    rm grafana/provisions/datasources/sunandmoon.yml.bak
fi

# Build Docker in current environment
./compose-dash.sh up -d
echo "-----------------------------------------"

# Run Local Access mode network scan
if [ "${config}" == "Local Access" ] && ! grep -qE "^PW_HOST=.+" "${PW_ENV_FILE}"; then
    echo "Running network scan... (press Ctrl-C to interrupt)"
    # Get local IP based on the operating system
    OS=$(uname -s)
    case $OS in
        Linux*) IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7}') ;;
        Darwin*) IP=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}') ;;
        CYGWIN*|MINGW*|MSYS*) IP=$(netstat -rn 2>/dev/null | grep "0.0.0.0" | awk '{print $4}' | head -1) ;;
        *) IP=""
    esac
    docker exec -it pypowerwall python3 -m pypowerwall scan -ip=${IP}
    echo "-----------------------------------------"
    echo "Enter address for Powerwall... (or leave blank to switch to Tesla Cloud mode)"
    read -p 'IP Address: ' IP
    echo ""
    if [ -z "${IP}" ]; then
        config="Tesla Cloud"
    fi
    sed -i.bak "s@^PW_HOST=.*@PW_HOST=${IP}@g" "${PW_ENV_FILE}"
    ./compose-dash.sh up -d
    echo "-----------------------------------------"
fi

# Run Tesla Cloud mode setup
if [ "${config}" == "Tesla Cloud" ]; then
    docker exec -it pypowerwall python3 -m pypowerwall setup -email=$(grep -E "^PW_EMAIL=.+" "${PW_ENV_FILE}" | cut -d= -f2)
    echo "Restarting..."
    docker restart pypowerwall
    echo "-----------------------------------------"
fi

# Run FleetAPI mode setup
if [ "${config}" == "FleetAPI Cloud" ]; then
    docker exec -it pypowerwall python3 -m pypowerwall fleetapi
    echo "Restarting..."
    docker restart pypowerwall
    echo "-----------------------------------------"
fi

# Set up Influx
echo "Waiting for InfluxDB to start..."
until running http://localhost:8086/ping 204 2>/dev/null; do
    printf '.'
    sleep 5
done
echo " up!"
sleep 2
echo "Setup InfluxDB Data... ('already exist' errors harmless)"
docker exec --tty influxdb sh -c "influx -import -path=/var/lib/influxdb/influxdb.sql"
sleep 2
# Execute Run-Once queries for initial setup.
cd influxdb
for f in run-once*.sql; do
    if [ ! -f "${f}.done" ]; then
        echo "Executing single run query $f file..."
        docker exec --tty influxdb sh -c "influx -import -path=/var/lib/influxdb/${f}"
        echo "OK" > "${f}.done"
    fi
done
cd ..

# Restart weather411 to force a sample
if [ -f weather/weather411.conf ]; then
    echo "Fetching local weather..."
    docker restart weather411
fi

# Display Final Instructions
if ! grep -qE "^PW_HOST=.+" "${PW_ENV_FILE}"
then
    DASHBOARD="'dashboard.json' or 'dashboard-solar-only.json'"
else
    DASHBOARD="'dashboard.json'"
fi
cat << EOF
------------------[ Final Setup Instructions ]-----------------

Open Grafana at http://localhost:9000/ ... use admin/admin for login.

To complete *Grafana Setup*:

* From 'Dashboard/New', select 'Import dashboard', click "Upload dashboard JSON file", 
  browse to ${PWD}/dashboards and upload ${DASHBOARD}.
* For InfluxDB select "InfluxDB (Auto provisioned)" dropdown.
* For Sun and Moon select "Sun and Moon (Auto provisioned)" dropdown.
* Click "Import" button.

NOTE: The datasources for InfluxDB and SunAndMoon are already configured.
If you need to modify them via Configuration\Data Sources:

* InfluxDB
  - URL: 'http://influxdb:8086'
  - Database: 'powerwall'
  - Min time interval: '5s'
  - Click "Save & test" button

* Sun and Moon
  - Enter your latitude and longitude (tool here: https://bit.ly/3wYNaI1 )
  - Click "Save & test" button

EOF
