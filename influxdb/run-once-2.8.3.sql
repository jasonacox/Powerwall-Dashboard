# DDL
# Powerwall-Dashboard v2.8.3
# 
# Version 2.8.3 move alert data into the "alerts" retention policy. This script moves the
# existing data (in the "raw" retention policy) into the new "alerts" policy.
#
# Manual:
# docker exec --tty influxdb sh -c "influx -import -path=/var/lib/influxdb/run-once-2.8.3.sql"
#
# USE powerwall
CREATE DATABASE powerwall
# Copy alert data from raw into alerts
SELECT max(*) INTO "powerwall"."alerts"."alerts" FROM "powerwall"."raw"."alerts" GROUP BY time(1m), month, year
