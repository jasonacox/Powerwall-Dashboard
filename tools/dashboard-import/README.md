# Import a dashboard

The String Voltage, String Current and String Power panels draw every string the stock dashboard knows about. pypowerwall's `/strings` says which strings are connected, but that flag is not stored in InfluxDB, so Grafana still draws the disconnected ones and gives each a color.

`dashboard-import.sh` imports a stock file from `dashboards/` and can hide those strings in the same save. It does not change query text. Inverter Power is left alone. Run it from the Powerwall-Dashboard directory.

`GET /strings` on pypowerwall-server and the legacy proxy returns one object per string id. A string counts as connected when `Connected` is JSON `true` or `1`. The script hides a string only when that value is false and at least one string is connected. If none are connected, or `Connected` is missing, it prints `String queries were left unchanged.` and still applies the legend, refresh, and time range. If `/strings` cannot be read, the script stops.

```bash
./tools/dashboard-import/dashboard-import.sh
```

Python 3 must be installed on this computer (`python3`, or `python` if that is Python 3). The script does not run Python inside a container.

The first run on a terminal writes `dashboard-import.env` after asking for each setting. Later runs print those settings and only ask you to confirm. Copy `dashboard-import.env.sample` if you would rather edit the file yourself. The env file has no passwords in it.

Importing overwrites the dashboard with the same uid. Edits you made in Grafana are lost. `--live` changes the dashboard that is already open and leaves your other edits in place. A plain re-import in the Grafana UI brings the disconnected strings back. Run this script to import instead.

## Settings

Each value can be `default`, which keeps the setting already in the chosen dashboard file (for the file name, `default` means `dashboard.json`). The setup menu shows that file's refresh and time range, for example `keep file setting (5m)` and `keep file setting (Last 24 hours)`.

| Setting | Values |
| --- | --- |
| `DASHBOARD_FILE` | `default`, or a file in `dashboards/` such as `dashboard.json` |
| `LEGEND` | `default` (keep the file's legend), `bottom`, `right` |
| `HIDE_STRINGS` | `auto` (hide disconnected strings), `off` (show every string). `default` means `auto` |
| `REFRESH` | `default` (keep the file's interval), or `5s`, `10s`, `30s`, `1m`, `5m`, `15m`, `30m`, `1h`, `2h`, `1d` |
| `TIME_RANGE` | `default` (keep the file's range), `today` (Today, the whole day), `today_so_far` (Today so far), `last_24h` (Last 24 hours), `last_7d` (Last 7 days) |

A bad value stops the script before it saves.

## Flags

Flags override the env file for that run. They do not change the file.

```text
--setup     Ask again and rewrite dashboard-import.env
--file FILE Stock file, for example dashboards/dashboard-alt.json
--live      Edit the open dashboard instead of importing
--reset     With --live, remove this script's string hides and legend moves.
            Refresh and time stay as they are. Without --live, import
            the stock file with no legend, hide, refresh, or time changes.
--dry-run   Print the plan and do not save
--yes       Save without asking
```

`--dry-run` names the dashboard that would be replaced. If a string panel's queries no longer match the names in the file, the plan includes a warning. Grafana refuses to overwrite a dashboard it provisions from a file, and the script prints that error.

## Login

The script needs a Grafana login that can edit. It does not change `grafana.env` or Grafana's database.

1. Anonymous access, when it can already save. That is the commented "disable login requirement (full access)" block in `grafana.env.sample` (`GF_AUTH_ANONYMOUS_ORG_ROLE=Admin`). `./anonymous-access.sh` choice 3 does the same thing.
2. A password prompt. Press Enter for the user `admin`. The password is not shown. It is held only in a private temp file, which is removed on every exit, including Ctrl+C.

Ports come from `compose.env` (`GRAFANA_PORTS`, `PYPOWERWALL_PORTS`) and `grafana.env` (`GF_SERVER_HTTP_PORT`, default `9000`, and `GF_SERVER_PROTOCOL` when that is `https`). If a port is not published on the host, the script tries again inside the container. Do not run it as root.
