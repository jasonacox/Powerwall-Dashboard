# AGENTS.md

Guidance for AI coding agents (and humans) working in Powerwall-Dashboard.

## What this repo is

A Docker Compose stack (InfluxDB 1.8, Telegraf, Grafana, the pypowerwall proxy, weather411) for monitoring Tesla Powerwall and solar systems. The bash scripts in the repo root (`setup.sh`, `upgrade.sh`, `tz.sh`, `verify.sh`, `compose-dash.sh`, `watchdog.sh`, ...) are the product. `tools/` holds optional add-ons and `sandbox/` is experimental; neither ships as part of the stack.

## Design principles

* **Keep it simple.** Complex changes are hard to maintain and can break the install base. Prefer the smallest change that solves the problem, and remove code rather than add layers.
* **Stay backward compatible.** Community members run many different versions and setups. Upgrades must work from older versions, and existing configs must keep working. No breaking changes without a serious discussion with the maintainers first (open an issue).
* **Preserve local configuration.** Users upgrade with `git pull`, so tracked files get overwritten. Never ask users to edit tracked core files. Put user-specific or mutable settings in untracked local files created from a `.sample` file (`pypowerwall.env`, `compose.env`, `grafana.env`, `influxdb.env`, `telegraf.local`, `powerwall.extend.yml`, `weather/weather411.conf`), and make new options optional with safe defaults. The timezone substitution done by `tz.sh` in tracked files is a legacy exception; don't add more like it.
* **Keep the UX consistent.** For dashboards, match the existing fonts, colors, fill modes, labels and infographic style; for the CLI (`setup.sh`, `upgrade.sh`, `verify.sh`, ...), match the existing prompts, wording and output layout. The goal is simple, intuitive, clean and consistent. Design changes need maintainer review, so discuss them in an issue before opening a PR.
* **Document clearly and concisely.** The community ranges from novices to expert enthusiasts. Write for the novice without burying the expert: plain steps, copy-pasteable commands, and no unexplained jargon.

## Merging to `main` is releasing

Users install by cloning this repo, and `upgrade.sh` updates them with `git stash` + `git pull --rebase`. It also downloads the latest `upgrade.sh` from `main` and runs that. So **anything merged to `main` is live for every user the next time they upgrade**. Do not push directly to `main`; use a branch and a PR.

Any PR that changes code, dashboards, configs or behavior should also:

1. Bump `VERSION` and the `VERSION="x.y.z"` line in `upgrade.sh` (they must match; CI checks it).
2. Add a `RELEASE.md` entry at the top (format below).
3. If an image changes, update the pinned tag in `powerwall.yml`. State the scope in the notes; `tools/k3s` pins its own versions.

Docs-only changes (README, AGENTS.md, notes for already-merged work) don't need a bump. If a change must land without a bump, say why in the PR.

**Choosing the bump:**

* **Patch** (`5.3.0` to `5.3.1`): bug fixes, image/proxy upgrades, small improvements.
* **Minor** (`5.2.x` to `5.3.0`): notable new features, scripts or dashboard panels.
* **Major**: avoid. `upgrade.sh` treats upgrades from below `5.0.0` as a major upgrade and shows extra warnings. Only the maintainers decide on a major bump.

**`RELEASE.md` entry format** (newest first, see existing entries):

```markdown
## v5.3.1 - Short title

### New Features
* **Name of the change** - what it does and why it helps users. ([PR #123](https://github.com/jasonacox/Powerwall-Dashboard/pull/123) by **@author**, closes [#122](https://github.com/jasonacox/Powerwall-Dashboard/issues/122))

### Updates
### Bug Fixes

**Existing installs:** what users need to do (for example, run `./upgrade.sh`, then re-import `dashboards/dashboard.json`).

### Contributors
Thanks to ...
```

Use only the sections that apply. Always say what existing installs must do, and credit the author and the reporter. Tags and GitHub releases are created by the maintainers.

## Scripts must run on every platform

Users run these scripts on Linux, macOS, Windows WSL, Synology (BusyBox), Raspberry Pi and rootless Docker. Write for the lowest common denominator:

* **Bash 3.2 is the floor** (macOS). No associative arrays, `mapfile`/`readarray`, `${var,,}`/`${var^^}`, or `&>>`.
* **`sed -i` differs between GNU and BSD.** Always use `sed -i.bak ...` (attached suffix, as the existing scripts do), and avoid GNU-only escapes like `\n`, `\t` and `\+` in replacements and patterns. Don't leave `.bak` files tracked.
* **Avoid GNU-only flags and tools:** `grep -P`, `readlink -f`, `date -d`, `stat -c`, `xargs -r`, `sort -V`, `find -printf`, `echo -e` (use `printf`). Prefer POSIX options and test that a command exists with `command -v` before relying on it.
* Support both `docker compose` (v2) and `docker-compose` (v1); see `compose-dash.sh` for the detection pattern.
* Don't assume `sudo`, `systemd`/`timedatectl`, `/usr/share/zoneinfo`, or a TTY. `setup.sh` already falls back when these are missing.
* Shell files use LF endings (`.gitattributes`); keep them that way.
* Be conservative with user data: never overwrite `*.env`, `telegraf.local` or `.auth/`, and back up before rewriting a user's file.

## Testing

There is no automated test suite, so verify changes yourself and say how in the PR.

* Run the CI checks (`.github/workflows/validate.yml`) locally:

  ```bash
  for f in $(git ls-files '*.sh' '*.sh.sample'); do bash -n "$f"; done
  shellcheck --shell=bash --severity=error --exclude=SC2068,SC2145 $(git ls-files '*.sh' '*.sh.sample')
  git diff --check origin/main...HEAD
  ```

  CI also validates every tracked `*.json` and `*.yml` file.
* Check syntax on the oldest Bash: `docker run --rm -v "$PWD":/w -w /w bash:3.2 bash -n setup.sh`.
* For prompts and validation loops, drive the code with scripted input (`printf 'a\nb\n' | bash script.sh`) and try bad input as well as good.
* For changes to `upgrade.sh` or tracked config, test an upgrade from an older release tag, not only from the latest.
* Never test against a real user's Powerwall credentials or commit test output that contains them.

## Timezone handling

The timezone is substituted by `tz.sh` into `telegraf.conf`, `influxdb/influxdb.sql`, `pypowerwall.env` and `dashboards/*.json` (default `America/Los_Angeles`, current value in `tz`). InfluxDB `tz('...')` only accepts IANA names. If you add a place that uses the timezone, make `tz.sh` update it too.

## Dashboards and configs

* Dashboards in `dashboards/` are exported Grafana JSON. Keep them valid, and apply changes consistently to the variants (`dashboard.json`, `-no-animation`, `-no-sunmoon`, `-simple`, `-alt`, `-min-mean-max`, `-solar-only`) when the change is relevant to them.
* Tracked files like `influxdb.sql` and `telegraf.conf` get rewritten on users' machines by `tz.sh`. Keep the default timezone string in the repo so `tz.sh` can find and replace it.
* New dashboard panels must follow the existing look (fonts, colors, fill, labels) and work for the supported system types, or be left out of the variants where they don't apply.
* Don't commit secrets or local files: `*.env` (only `*.env.sample`), `telegraf.local`, `.auth/`, `.pypowerwall_data/`.

## Secrets and privacy

Never print, log or commit passwords, tokens, RSA keys, emails or `PW_HOST` values. Users paste script output into public issues, so diagnostics must mask sensitive values.

## Upstream projects

The pypowerwall proxy lives in [jasonacox/pypowerwall](https://github.com/jasonacox/pypowerwall) and weather411 is a separate image. Fix their behavior there. This repo only pins their image tags (never `latest`) and adapts dashboards and scripts to them. Ignore `sandbox/` and `tools/` for stack changes unless the task is specifically about them.

## Working as an agent

* Work on a branch and open a PR; never push to `main`, and don't create tags or releases.
* Don't post comments or reviews as a maintainer unless asked.
* Ask before anything that could break existing installs, change dashboard or CLI design, or alter what `upgrade.sh` does. Suggest an issue first.
* If a request conflicts with these principles, say so rather than working around them.

## Documentation

* `README.md` is linked to from other docs by section anchors (`#docker-errors`, `#windows-11-instructions`, `#grafana-setup`, `#option-1---quick-start`, `#setup`, `#powerwall-3`). Check for inbound links (`grep -rn "README.md#"`) before renaming a heading.
* Organize `README.md` by task: setup and install steps stay separate from troubleshooting, so add content under the heading where a reader would look for it.
* Use plain language and copy-pasteable commands; explain jargon the first time. Keep it short enough for a novice and complete enough for an expert.
* Follow `.editorconfig` (LF, 4-space indent, no final newline in JSON).
* Keep changes surgical and describe the "why" in commit messages and PRs.
