#!/bin/sh
# Convenience wrapper to idle InfluxDB/telegraf if you're only interested in
# the TimescaleDB datastore. This does NOT remove InfluxDB or its data, and
# it is NOT sticky: docker compose still declares these services unconditionally
# (see ../../timescaledb/README.md), so the next `./setup.sh` or `./upgrade.sh`
# run will start them back up. Re-run this script afterward if you want them
# to stay stopped.
docker compose -f powerwall.yml stop influxdb telegraf
echo ""
echo "Stopped influxdb/telegraf."
echo "Note: these restart automatically next time you run setup.sh or upgrade.sh"
echo "-- re-run this script afterward if you want them to stay stopped."
