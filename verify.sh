#!/bin/bash

# Stop on Errors
set -e

# Formatting
default="\033[39m"
white="\033[97m"
green="\033[32m"
red="\033[91m"
yellow="\033[33m"
bold="\033[0m${white}\033[1m"
subbold="\033[0m${green}"
normal="${white}\033[0m"
dim="\033[0m${white}\033[2m"
alert="\033[0m${red}\033[1m"
alertdim="\033[0m${red}\033[2m"

# Check for no-color mode
if [ $# -ne 0 ]; then
    # no color
    bold=""
    subbold=""
    normal=""
    dim=""
    alert=""
    alertdim=""
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

# Service Running Helper Function
running() {
    local url=${1:-http://localhost:80}
    local code=${2:-200}
    if [[ $3 == 1 ]]; then
        head="--head"
    else
        head=""
    fi
    local status=$(curl ${head} --location --connect-timeout 5 --write-out %{http_code} --silent --output /dev/null ${url})
    [[ $status == ${code} ]]
}

echo -e "${bold}Verify Powerwall-Dashboard - Version ${subbold}${CURRENT}${normal} - Timezone: ${subbold}${TZ}${dim}"
echo -e "----------------------------------------------------------------------------"
echo -e "This script will attempt to verify all the services needed to run"
echo -e "Powerwall-Dashboard. Use this output when you open an issue for help:"
echo -e "https://github.com/jasonacox/Powerwall-Dashboard/issues/new"
echo -e ""

# Check compose env file
COMPOSE_ENV_FILE="compose.env"
if [ ! -f ${COMPOSE_ENV_FILE} ]; then
    echo -e " - WARNING: You are missing ${COMPOSE_ENV_FILE}"
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
PORT="8675"
echo -e -n "${dim} - Config File ${ENV_FILE}: "
if [ ! -f ${ENV_FILE} ]; then
    echo -e "${alert}ERROR: Missing$"
    ALLGOOD=0
else
    echo -e $GOOD
fi
echo -e -n "${dim} - Container ($CONTAINER): "
RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null)
if [ "$RUNNING" = "true" ]; then
    echo -e $GOOD
    echo -e -n "${dim} - Service (port $PORT): "
    if running http://localhost:$PORT/stats 200 0 2>/dev/null;  then
        echo -e $GOOD
        VER=`curl --silent http://localhost:8675/stats | awk '{print $2" "$3" "$4}' | cut -d\" -f 2 2>/dev/null`
        # check connection with powerwall
        if running http://localhost:8675/version 200 0 2>/dev/null;  then
            PWSTATE="CONNECTED"
            PWVER=`curl --silent http://localhost:8675/version | awk '{print $2}' | cut -d\" -f 2 2>/dev/null`
        fi
    else
        echo -e "${alert}ERROR: Not Listening${normal}"
        ALLGOOD=0
    fi
else
  echo -e "${alert}ERROR: Stopped${normal}"
  ALLGOOD=0
fi
echo -e "${dim} - Version: ${subbold}$VER"
echo -e "${dim} - Powerwall State: ${subbold}$PWSTATE${dim} - Firmware Version: $PWVER${normal}"
# Check to see that TZ is set in pypowerwall
if ! grep -q "TZ=" pypowerwall.env; then
    echo -e "${dim} - ${alertdim}ERROR: Your pypowerwall settings are missing TZ.${normal}"
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
RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null)
if [ "$RUNNING" = "true" ]; then
  echo -e $GOOD
  VER=`docker exec --tty telegraf telegraf --version`
else
  echo -e "${alert}ERROR: Stopped${normal}"
  ALLGOOD=0
fi
echo -e "${dim} - Version: ${subbold}$VER"
echo -e ""

# influxdb
echo -e "${bold}Checking influxdb${dim}"
echo -e "----------------------------------------------------------------------------"
CONTAINER="influxdb"
VER=$UKN
CONF_FILE="pypowerwall.env"
PORT="8086"
echo -e -n "${dim} - Config File ${CONF_FILE}: "
if [ ! -f ${CONF_FILE} ]; then
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
else
    echo -e $GOOD
fi
echo -e -n "${dim} - Container ($CONTAINER): "
RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null)
if [ "$RUNNING" = "true" ]; then
    echo -e $GOOD
    echo -e -n "${dim} - Service (port $PORT): "
    if running http://localhost:$PORT/ping 204 1 2>/dev/null;  then
        echo -e $GOOD
        VER=`docker exec --tty influxdb sh -c "influx -version" 2>/dev/null`
    else
        echo -e "${alert}ERROR: Not Listening${normal}"
        ALLGOOD=0
    fi
else
  echo -e "ERROR: Stopped"
  ALLGOOD=0
fi
echo -e -n "${dim} - Filesystem (./$CONTAINER): "
rm -f ./influxdb/WRITE
ERR=`docker exec -it influxdb touch /var/lib/influxdb/WRITE`
if [ -e "./influxdb/WRITE" ]; then
    echo -e $GOOD
    rm -f ./influxdb/WRITE
else
    echo -e "${alert}ERROR: Unable to write to filesystem - check permissions${normal}"
fi
echo -e "${dim} - Version: ${subbold}$VER"
echo -e ""

# grafana
echo -e "${bold}Checking grafana${dim}"
echo -e "----------------------------------------------------------------------------"
CONTAINER="grafana"
VER=$UKN
WEATHER=$UKN
PORT="9000"
ENV_FILE="grafana.env"
echo -e -n "${dim} - Config File ${ENV_FILE}: "
if [ ! -f ${ENV_FILE} ]; then
    echo -e "${alert}ERROR: Missing${normal}"
    ALLGOOD=0
else
    echo -e $GOOD
    if ! grep -q "yesoreyeram-boomtable-panel-1.5.0-alpha.3.zip" grafana.env; then
        echo -e "${dim} - ${alertdim}WARNING: Your Grafana settings are outdated."
    fi
fi
echo -e -n "${dim} - Container ($CONTAINER): "
RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null)
if [ "$RUNNING" = "true" ]; then
    echo -e $GOOD
    VER=`docker exec --tty grafana grafana-cli --version 2>/dev/null`
    echo -e -n "${dim} - Service (port $PORT): "
    if running http://localhost:$PORT/login 200 1 2>/dev/null;  then
        echo -e $GOOD
    else
        echo -e "${alert}ERROR: Not Listening - Logs:${alertdim}"
        echo -e "---"
        docker logs grafana 2>&1 | tail -11
        echo -e "---${normal}"
        ALLGOOD=0
    fi
else
  echo -e "${alert}ERROR: Stopped${normal}"
  ALLGOOD=0
fi
echo -e -n "${dim} - Filesystem (./$CONTAINER): "
rm -f ./grafana/WRITE
ERR=`docker exec -it grafana touch /var/lib/grafana/WRITE`
if [ -e "./grafana/WRITE" ]; then
    echo -e $GOOD
    rm -f ./grafana/WRITE
else
    echo -e "${alert}ERROR: Unable to write to filesystem - check permissions${normal}"
fi
echo -e "${dim} - Version: ${subbold}$VER"
echo -e ""

# weather411
echo -e "${bold}Checking weather411${dim}"
echo -e "----------------------------------------------------------------------------"
CONTAINER="weather411"
VER=$UKN
WEATHER=$UKN
ENV_FILE="weather/weather411.conf"
PORT="8676"
echo -e -n "${dim} - Config File ${ENV_FILE}: "
if [ ! -f ${ENV_FILE} ]; then
    echo -e "${alertdim}Missing - weather411 not set up"
    ALLGOOD=0
else
    echo -e $GOOD
fi
echo -e -n "${dim} - Container ($CONTAINER): "
RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null)
if [ "$RUNNING" = "true" ]; then
    echo -e $GOOD
    echo -e -n "${dim} - Service (port $PORT): "
    if running http://localhost:$PORT/stats 200 0 2>/dev/null;  then
        echo -e $GOOD
        VER=`curl --silent http://localhost:$PORT/stats | awk '{print $2" "$3" "$4}' | cut -d\" -f 2 2>/dev/null`
        # check connection with openweather
        if running http://localhost:$PORT/temp 200 0 2>/dev/null;  then
            WEATHER=`curl --silent http://localhost:$PORT/temp 2>/dev/null`
        fi
        echo -e "${dim} - Weather: ${subbold}${WEATHER}"
    else
        echo -e "${alert}ERROR: Not Listening - Logs:${alertdim}"
        echo -e "---"
        docker logs weather411 2>&1 | tail -11
        echo -e "---${normal}"
        ALLGOOD=0
    fi
else
    echo -e "${alert}ERROR: Stopped${normal}"
    ALLGOOD=0
fi
echo -e "${dim} - Version: ${subbold}$VER"
echo -e ""

if [ -f powerwall.extend.yml ]; then
    # ecowitt
    echo -e "${bold}Checking ecowitt${dim} (optional component - OK if missing)"
    echo -e "----------------------------------------------------------------------------"
    CONTAINER="ecowitt"
    VER=$UKN
    ECOWITT=$UKN
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
    RUNNING=$(docker inspect --format="{{.State.Running}}" $CONTAINER 2>/dev/null)
    if [ "$RUNNING" = "true" ]; then
        echo -e $GOOD
        echo -e -n "${dim} - Service (port $PORT): "
        if running http://localhost:$PORT/stats 200 0 2>/dev/null;  then
            echo -e $GOOD
            VER=`curl --silent http://localhost:$PORT/stats | awk '{print $2" "$3" "$4}' | cut -d\" -f 2 2>/dev/null`
            # check connection with ecowitt
            if running http://localhost:$PORT/temp 200 0 2>/dev/null;  then
                WEATHER=`curl --silent http://localhost:$PORT/temp 2>/dev/null`
            fi
            echo -e "${dim} - Weather: ${subbold}${WEATHER}"
        else
            echo -e "${alert}ERROR: Not Listening - Logs:${alertdim}"
            echo -e "---"
            docker logs weather411 2>&1 | tail -11
            echo -e "---${normal}"
            ALLGOOD=0
        fi
    else
        echo -e "${alert}ERROR: Stopped${normal}"
        ALLGOOD=0
    fi
    echo -e "${dim} - Version: ${subbold}$VER"
    echo -e ""
fi

if [ $ALLGOOD -ne 1 ]; then
  echo "All tests did not succeed."
  exit 1
else
  echo "All tests succeeded."
  exit 0
fi
