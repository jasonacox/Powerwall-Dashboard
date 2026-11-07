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
    # Only replace the timezone settings themselves: a short zone name such as
    # UTC also appears in code and comments (e.g. Date.UTC() in the Sun and Moon
    # panel), and a bare replace would corrupt them when changing away from it.
    sed -i.bak "s@timezone = \"${from}\"@timezone = \"${to}\"@g" telegraf.conf
    sed -i.bak "s@tz('${from}')@tz('${to}')@g" influxdb/influxdb.sql
    if [ -f "pypowerwall.env" ]; then
        sed -i.bak -e "s@^PW_TIMEZONE=${from}@PW_TIMEZONE=${to}@" -e "s@^TZ=${from}@TZ=${to}@" pypowerwall.env
    fi
    if [ -d "dashboards" ]; then
        for i in dashboards/*.json; do
            sed -i.bak "s@\"value\": \"${from}\"@\"value\": \"${to}\"@g" "$i"
        done
    fi
}

# Replace TZ values
updatetz "${CURRENT}" "${NEW}"
updatetz "${DEFAULT}" "${NEW}"

# Record new TZ value
echo "${NEW}" > tz
