#!/usr/bin/env python3
"""
Runs every InfluxDB -> TimescaleDB historical migration script in sequence,
resolving connection details (prompting if needed) exactly once and sharing
that config across all of them -- see migrate_common.get_config().

Order matters: pw_kwh_1h has no migration script of its own -- its history is
derived from pw_autogen_1m (via timescaledb/aggregate/kwh_backfill.sql), so
autogen must be migrated first. This script runs that backfill automatically
immediately after migrate_autogen finishes.
"""

import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import migrate_common as mc
import migrate_autogen
import migrate_grid
import migrate_vitals
import migrate_pod
import migrate_pwtemps
import migrate_alerts
import migrate_weather
import migrate_strings
import migrate_fans

AGGREGATE_DIR = Path(__file__).resolve().parent.parent / "aggregate"


def backfill_kwh(config, earliest_year, earliest_month):
    print("[fetch] backfilling pw_kwh_1h from pw_autogen_1m ...")
    tz = os.environ.get("TZ", "UTC")
    start = f"{earliest_year:04d}-{earliest_month:02d}-01 00:00:00+00"
    end = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S+00")
    subprocess.run(
        [
            "psql", config["pg_dsn"],
            "-v", f"tz={tz}",
            "-v", f"start_date={start}",
            "-v", f"end_date={end}",
            "-v", "ON_ERROR_STOP=1",
            "-f", str(AGGREGATE_DIR / "kwh_backfill.sql"),
        ],
        check=True,
    )
    print("[done]  pw_kwh_1h backfill")


def main():
    config = mc.get_config()

    print("=== autogen.http -> pw_autogen_1m ===")
    earliest_year, earliest_month = mc.find_earliest_month(config, migrate_autogen.SOURCE_MEASUREMENT)
    migrate_autogen.main(config)

    print("=== pw_kwh_1h backfill (derived from pw_autogen_1m) ===")
    try:
        backfill_kwh(config, earliest_year, earliest_month)
    except subprocess.CalledProcessError as e:
        print(f"[FAIL] kwh backfill: {e}", file=sys.stderr)

    print("=== grid.http -> pw_grid_1m ===")
    migrate_grid.main(config)

    print("=== vitals.http -> pw_vitals_log ===")
    migrate_vitals.main(config)

    print("=== pod.http -> pw_pod_log ===")
    migrate_pod.main(config)

    print("=== pwtemps.http -> pw_pwtemps_log ===")
    migrate_pwtemps.main(config)

    print("=== alerts.alerts -> pw_alerts_log ===")
    migrate_alerts.main(config)

    print("=== autogen.weather -> pw_weather_log ===")
    migrate_weather.main(config)

    print("=== strings.http -> pw_strings_log (best-effort, no PW+ hardware to test against) ===")
    migrate_strings.main(config)

    print("=== fans.http -> pw_fans_log (best-effort, no Backup Switch hardware to test against) ===")
    migrate_fans.main(config)

    print("=== Migration complete ===")


if __name__ == "__main__":
    main()
