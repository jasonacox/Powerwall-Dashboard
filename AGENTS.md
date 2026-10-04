# AGENTS.md

Guidance for AI coding agents (and humans) working in Powerwall-Dashboard.

## What this repo is

A Docker Compose stack (InfluxDB 1.8, Telegraf, Grafana, the pypowerwall proxy, weather411) for monitoring Tesla Powerwall and solar systems. The bash scripts in the repo root (`setup.sh`, `upgrade.sh`, `tz.sh`, `verify.sh`, `compose-dash.sh`, `watchdog.sh`, ...) are the product. `tools/` holds optional add-ons and `sandbox/` is experimental; neither ships as part of the stack.

## Merging to `main` is releasing

Users install by cloning this repo, and `upgrade.sh` updates them with `git stash` + `git pull --rebase`. It also downloads the latest `upgrade.sh` from `main` and runs that. So **anything merged to `main` is live for every user the next time they upgrade**. Do not push directly to `main`; use a branch and a PR.

Any PR that changes code, dashboards, configs or behavior should also:

1. Bump `VERSION` and the `VERSION="x.y.z"` line in `upgrade.sh` (they must match; CI checks it).
2. Add a `RELEASE.md` entry at the top: what changed, why, and what existing installs need to do (for example, "re-import `dashboards/dashboard.json`").
3. If an image changes, update the pinned tag in `powerwall.yml`. State the scope in the notes; `tools/k3s` pins its own versions.

Docs-only changes (README, RELEASE notes for already-merged work) don't need a bump. If a change must land without a bump, say why in the PR.

## Scripts must run on every platform

Users run these scripts on Linux, macOS, Windows WSL, Synology (BusyBox), Raspberry Pi and rootless Docker. Write for the lowest common denominator:

* **Bash 3.2 is the floor** (macOS). No associative arrays, `mapfile`/`readarray`, `${var,,}`/`${var^^}`, or `&>>`.
* **`sed -i` differs between GNU and BSD.** Always use `sed -i.bak ...` (attached suffix, as the existing scripts do), and avoid GNU-only escapes like `\n`, `\t` and `\+` in replacements and patterns. Don't leave `.bak` files tracked.
* **Avoid GNU-only flags and tools:** `grep -P`, `readlink -f`, `date -d`, `stat -c`, `xargs -r`, `sort -V`, `find -printf`, `echo -e` (use `printf`). Prefer POSIX options and test that a command exists with `command -v` before relying on it.
* Support both `docker compose` (v2) and `docker-compose` (v1); see `compose-dash.sh` for the detection pattern.
* Don't assume `sudo`, `systemd`/`timedatectl`, `/usr/share/zoneinfo`, or a TTY. `setup.sh` already falls back when these are missing.
* Shell files use LF endings (`.gitattributes`); keep them that way.
* Be conservative with user data: never overwrite `*.env`, `telegraf.local` or `.auth/`, and back up before rewriting a user's file.

Before pushing, run the same checks as CI (`.github/workflows/validate.yml`):

```bash
for f in $(git ls-files '*.sh' '*.sh.sample'); do bash -n "$f"; done
shellcheck --shell=bash --severity=error --exclude=SC2068,SC2145 $(git ls-files '*.sh' '*.sh.sample')
git diff --check origin/main...HEAD
```

CI also validates every tracked `*.json` and `*.yml` file.

## Timezone handling

The timezone is substituted by `tz.sh` into `telegraf.conf`, `influxdb/influxdb.sql`, `pypowerwall.env` and `dashboards/*.json` (default `America/Los_Angeles`, current value in `tz`). InfluxDB `tz('...')` only accepts IANA names. If you add a place that uses the timezone, make `tz.sh` update it too.

## Dashboards and configs

* Dashboards in `dashboards/` are exported Grafana JSON. Keep them valid, and apply changes consistently to the variants (`dashboard.json`, `-no-animation`, `-no-sunmoon`, `-simple`, `-alt`, `-min-mean-max`, `-solar-only`) when the change is relevant to them.
* Tracked files like `influxdb.sql` and `telegraf.conf` get rewritten on users' machines by `tz.sh`. Keep the default timezone string in the repo so `tz.sh` can find and replace it.
* Don't commit secrets or local files: `*.env` (only `*.env.sample`), `telegraf.local`, `.auth/`, `.pypowerwall_data/`.

## Documentation

* `README.md` is linked to from other docs by section anchors (`#docker-errors`, `#windows-11-instructions`, `#grafana-setup`, `#option-1---quick-start`, `#setup`, `#powerwall-3`). Check for inbound links (`grep -rn "README.md#"`) before renaming a heading.
* Follow `.editorconfig` (LF, 4-space indent, no final newline in JSON).
* Keep changes surgical and describe the "why" in commit messages and PRs.
