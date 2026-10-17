#!/bin/bash
# Shell script to replace timezone values in telegraf.conf, influxdb.sql, pypowerwall.env and dashboards
if [ $# -eq 0 ]; then
    echo "ERROR: No timezone supplied"
    echo
    echo "USAGE: ${0} {timezone}"
    exit
fi

# Current and New TZ values
DEFAULT="America/Los_Angeles"
CURRENT=`cat tz`
NEW=$1

# Replace TZ Function
updatetz() {
    local from=${1}
    local to=${2}
    sed -i.bak "s@${from}@${to}@g" telegraf.conf
    sed -i.bak "s@${from}@${to}@g" influxdb/influxdb.sql
    if [ -f "pypowerwall.env" ]; then
        sed -i.bak "s@${from}@${to}@g" pypowerwall.env
    fi
    if [ -d "dashboards" ]; then
        for i in dashboards/*.json; do
            sed -i.bak "s@${from}@${to}@g" $i
        done
    fi
}

# Replace TZ values
updatetz "${CURRENT}" "${NEW}"
updatetz "${DEFAULT}" "${NEW}"

# Record new TZ value
echo "${NEW}" > tz
