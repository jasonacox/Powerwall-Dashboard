#!/bin/bash
# Shell script to replace timezone values in powerwall.yml, influxdb.sql and dashboard.json
if [ $# -eq 0 ]
  then
    echo "ERROR: No timzezone supplied"
    echo
    echo "USAGE: ${0} {timzeone}"
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
    sed -i.bak "s@${from}@${to}@g" powerwall.yml
    sed -i.bak "s@${from}@${to}@g" influxdb/influxdb.sql
    for i in dashboard*.json; do
        sed -i.bak "s@${from}@${to}@g" $i
    done
    sed -i.bak "s@${from}@${to}@g" pypowerwall.env
}

# Replace TZ values
updatetz "${CURRENT}" "${NEW}"
updatetz "${DEFAULT}" "${NEW}"
    
# Record new TZ value
echo "${NEW}" > tz
