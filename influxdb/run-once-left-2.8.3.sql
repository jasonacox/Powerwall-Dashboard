# DDL
# Powerwall-Dashboard v2.8.3
# 
# Version 2.8.3 move alert data into the "alerts" retention policy. This script moves the
# existing data (in the "raw" retention policy) into the new "alerts" policy.
#
# Manual:
# docker exec --tty influxdb sh -c "influx -import -path=/var/lib/influxdb/run-once-left-2.8.3.sql"
#
# USE powerwallleft
CREATE DATABASE powerwallleft
# Copy alert data from raw into alerts
SELECT max(*) INTO "powerwallleft"."alerts"."alerts" FROM "powerwallleft"."raw"."alerts" GROUP BY time(1m), month, year
