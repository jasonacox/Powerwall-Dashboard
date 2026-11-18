# Import a dashboard

The String Voltage, String Current and String Power panels draw every string the stock dashboard knows about. pypowerwall's `/strings` says which strings are connected, but that flag is not stored in InfluxDB, so Grafana still draws the disconnected ones and gives each a color.

`dashboard-import.sh` imports a stock file from `dashboards/` and can hide those strings in the same save. It does not change query text. Inverter Power is left alone. Run it from the Powerwall-Dashboard directory, while the sun is up. A Powerwall 3 reports every string disconnected at night, and the script then leaves Grafana alone.

```bash
./tools/dashboard-import/dashboard-import.sh
```

The first run on a terminal writes `dashboard-import.env` after asking for each setting. Later runs print those settings and only ask you to confirm. Copy `dashboard-import.env.sample` if you would rather edit the file yourself. The env file has no passwords in it.

Importing overwrites the dashboard with the same uid. Edits you made in Grafana are lost. `--live` changes the dashboard that is already open and leaves your other edits in place. A plain re-import in the Grafana UI brings the disconnected strings back. Run this script to import instead.

## Settings

Each value can be `default`, which leaves the stock dashboard alone (for the dashboard file, `default` means `dashboard.json`).

| Setting | Values |
| --- | --- |
| `DASHBOARD_FILE` | `default`, or a file in `dashboards/` such as `dashboard.json` |
| `LEGEND` | `default`, `bottom`, `right` |
| `HIDE_STRINGS` | `auto` (hide strings `/strings` reports as disconnected), `off`. `default` means `auto` |
| `REFRESH` | `default`, or `5s`, `10s`, `30s`, `1m`, `5m`, `15m`, `30m`, `1h`, `2h`, `1d` |
| `TIME_RANGE` | `default`, `today` (the whole day, `now/d` to `now/d`), `today_so_far` (`now/d` to `now`), `last_24h`, `last_7d` |

A bad value stops the script before it saves.

## Flags

Flags override the env file for that run. They do not change the file.

```text
--setup           Ask again and rewrite dashboard-import.env
--file FILE       Stock file, for example dashboards/dashboard-alt.json
--live            Edit the open dashboard instead of importing
--reset           With --live, undo this script's hides and legend moves.
                  Without --live, import the stock file with none of those edits
--legend-bottom   Same as LEGEND=bottom
--dry-run         Print the plan and do not save
--yes             Save without asking
--uid UID         With --live, this dashboard instead of the file's uid
--title TITLE     With --live, the dashboard with this exact title
```

`--dry-run` names the dashboard that would be replaced. If a string panel's queries no longer match the names in the file, the plan includes a warning. A dashboard Grafana provisions from a file is not overwritten.

## Login

The script needs a Grafana login that can edit. It does not change `grafana.env` or Grafana's database.

1. Anonymous access, when it can already save. That is the commented "disable login requirement (full access)" block in `grafana.env.sample` (`GF_AUTH_ANONYMOUS_ORG_ROLE=Admin`). `./anonymous-access.sh` choice 3 does the same thing.
2. A password prompt. Press Enter for the user `admin`. The password is not shown. It is held only in a private temp file, which is removed on every exit, including Ctrl+C.

Ports come from `compose.env` (`GRAFANA_PORTS`, `PYPOWERWALL_PORTS`) and `grafana.env` (`GF_SERVER_HTTP_PORT`, default `9000`, and `GF_SERVER_PROTOCOL` when that is `https`). If a port is not published on the host, the script tries again inside the container. Do not run it as root.
