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
CURRENT=`cat tz`
NEW=$1

# Replace TZ values
sed -i.bak "s@${CURRENT}@${NEW}@g" powerwall.yml
sed -i.bak "s@${CURRENT}@${NEW}@g" influxdb/influxdb.sql
#sed -i.bak "s@${CURRENT}@${NEW}@g" dashboard.json
for i in dashboard*.json; do
    sed -i.bak "s@${CURRENT}@${NEW}@g" $i
done
sed -i.bak "s@${CURRENT}@${NEW}@g" pypowerwall.env

# Record new TZ value
echo "${NEW}" > tz
