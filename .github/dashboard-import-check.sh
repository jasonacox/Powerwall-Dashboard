#!/bin/bash
#
# Host-Python checks for tools/dashboard-import/dashboard-import.sh.
# Synthetic files only. Called from .github/workflows/validate.yml.

set -u

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/tools/dashboard-import/dashboard-import.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dashboard-import-test.XXXXXX")
SHIM="$WORK/bin"
LOG="$WORK/docker.log"
fail=0

cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$SHIM" "$WORK/dashboards" "$WORK/no-such-dir"
printf '%s\n' '{"title":"Probe","uid":"probeuid"}' > "$WORK/dashboards/dashboard.json"
cat > "$SHIM/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$DASHBOARD_IMPORT_DOCKER_LOG"
exit 0
EOF
chmod 755 "$SHIM/docker"

export DASHBOARD_IMPORT_SOURCE=1
export DASHBOARD_IMPORT_DOCKER_LOG="$LOG"
# shellcheck disable=SC1090
. "$SCRIPT"
export PATH="$SHIM:$PATH"

choose_python
: > "$LOG"

JOB='{"live":false,"reset":false,"legend":"","refresh":"","time_from":"","time_to":"","do_hide":false,"hide":[],"unhide":[],"dashboard":{"uid":"probeuid","title":"Probe","panels":[]},"response":null,"datasources":[],"existing":null}'
printf '%s' "$JOB" | run_python plan "$WORK/post.json" > "$WORK/plan.txt" 2>"$WORK/plan.err"
if [ ! -s "$WORK/post.json" ]; then
    echo "FAIL plan did not write post.json" >&2
    cat "$WORK/plan.err" >&2
    fail=1
elif ! grep -q probeuid "$WORK/post.json"; then
    echo "FAIL post.json missing uid" >&2
    fail=1
else
    echo "PASS plan wrote post.json"
fi

printf '%s' "$WORK/dashboards" | run_python catalog > "$WORK/catalog.txt" 2>"$WORK/catalog.err"
if ! grep -q 'dashboard.json|Probe' "$WORK/catalog.txt"; then
    echo "FAIL catalog" >&2
    cat "$WORK/catalog.txt" "$WORK/catalog.err" >&2
    fail=1
else
    echo "PASS catalog listed dashboard.json"
fi

if [ -s "$LOG" ]; then
    echo "FAIL docker was called" >&2
    cat "$LOG" >&2
    fail=1
else
    echo "PASS docker shim was not used"
fi

printf '%s' "$JOB" | run_python plan "$WORK/no-such-dir/missing/post.json" >"$WORK/bad.out" 2>"$WORK/bad.err" || true
if grep -q 'could not read the JSON' "$WORK/bad.err"; then
    echo "FAIL error is still generic" >&2
    fail=1
elif ! grep -E -q 'FileNotFoundError|OSError|NotADirectoryError' "$WORK/bad.err"; then
    echo "FAIL error did not name the cause" >&2
    cat "$WORK/bad.err" >&2
    fail=1
else
    echo "PASS error names the cause"
fi

printf '%s\n' '{"refresh":"","time":{"from":"now/d","to":"now/d"}}' > "$WORK/dashboards/empty-refresh.json"
printf '%s' "$WORK/dashboards/empty-refresh.json" | run_python filemeta > "$WORK/meta.txt"
meta=$(cat "$WORK/meta.txt")
if [ "$meta" != "none
Today" ]; then
    echo "FAIL filemeta none/Today" >&2
    printf '%s\n' "$meta" >&2
    fail=1
else
    echo "PASS filemeta none and Today"
fi

printf '%s' "$ROOT/dashboards/dashboard.json" | run_python filemeta > "$WORK/meta.txt"
if ! grep -q '^5m$' "$WORK/meta.txt" || ! grep -q '^Last 24 hours$' "$WORK/meta.txt"; then
    echo "FAIL dashboard.json labels" >&2
    cat "$WORK/meta.txt" >&2
    fail=1
else
    echo "PASS dashboard.json labels"
fi

printf '%s' "$ROOT/dashboards/dashboard-min-mean-max.json" | run_python filemeta > "$WORK/meta.txt"
if ! grep -q '^Last 7 days$' "$WORK/meta.txt"; then
    echo "FAIL min-mean-max time" >&2
    cat "$WORK/meta.txt" >&2
    fail=1
else
    echo "PASS min-mean-max is Last 7 days"
fi

printf '%s\n' "$ROOT/dashboards/dashboard.json" default auto default default | run_python summary > "$WORK/sum.txt"
if ! grep -q 'refresh=keep file setting (5m)' "$WORK/sum.txt" || ! grep -q 'time=keep file setting (Last 24 hours)' "$WORK/sum.txt"; then
    echo "FAIL summary" >&2
    cat "$WORK/sum.txt" >&2
    fail=1
else
    echo "PASS summary uses file names"
fi

JOB_TODAY='{"live":false,"reset":false,"legend":"","refresh":"","time_from":"now/d","time_to":"now/d","do_hide":false,"hide":[],"unhide":[],"dashboard":{"uid":"probeuid","title":"Probe","panels":[],"time":{"from":"now-24h","to":"now"}},"response":null,"datasources":[],"existing":null}'
printf '%s' "$JOB_TODAY" | run_python plan "$WORK/post-today.json" > "$WORK/plan-today.txt"
if ! grep -q 'time -> Today$' "$WORK/plan-today.txt"; then
    echo "FAIL plan time name" >&2
    cat "$WORK/plan-today.txt" >&2
    fail=1
else
    echo "PASS plan says Today"
fi

printf '\n' | prompt_choice "Time range" default \
    "default|keep file setting (Last 24 hours)" \
    "today|Today (today)" "today_so_far|Today so far (today_so_far)" \
    "last_24h|Last 24 hours (last_24h)" "last_7d|Last 7 days (last_7d)" \
    > "$WORK/choice.txt" 2>"$WORK/menu.txt"
if grep -q '\[stock\]' "$WORK/menu.txt"; then
    echo "FAIL menu still says stock" >&2
    fail=1
elif ! grep -q '1) keep file setting (Last 24 hours)' "$WORK/menu.txt" || ! grep -q '2) Today (today)' "$WORK/menu.txt"; then
    echo "FAIL time menu" >&2
    cat "$WORK/menu.txt" >&2
    fail=1
elif [ "$(cat "$WORK/choice.txt")" != "default" ]; then
    echo "FAIL empty choice" >&2
    fail=1
else
    echo "PASS time menu"
fi

RESET=1
DASHBOARD_FILE=dashboard.json
LEGEND=bottom
HIDE_STRINGS=auto
REFRESH=30s
TIME_RANGE=today
print_settings > "$WORK/reset.txt"
if [ "$(cat "$WORK/reset.txt")" != "Settings: file=dashboard.json (reset)" ]; then
    echo "FAIL reset settings line" >&2
    cat "$WORK/reset.txt" >&2
    fail=1
else
    echo "PASS reset settings line"
fi

LIVE_RESET='{"live":true,"reset":true,"legend":"bottom","refresh":"30s","time_from":"now/d","time_to":"now/d","do_hide":false,"hide":[],"unhide":[],"dashboard":null,"datasources":null,"existing":null,"response":{"meta":{},"dashboard":{"uid":"probeuid","title":"Probe","refresh":"30s","time":{"from":"now/d","to":"now/d"},"panels":[{"id":1,"type":"timeseries","title":"String Voltage","targets":[{"refId":"B","alias":"B","hide":true}],"dashboardTune":{"hidden":["B"],"legend":{"kind":"placement","value":"right"}},"options":{"legend":{"placement":"bottom"}}}]}}}'
printf '%s' "$LIVE_RESET" | run_python plan "$WORK/live-reset.json" > "$WORK/live-reset.txt"
python3 - "$WORK/live-reset.json" <<'PY'
import json, sys
dash = json.load(open(sys.argv[1]))["dashboard"]
panel = dash["panels"][0]
ok = (
    dash.get("refresh") == "30s"
    and dash.get("time") == {"from": "now/d", "to": "now/d"}
    and panel["targets"][0].get("hide") is False
    and panel["options"]["legend"].get("placement") == "right"
    and "dashboardTune" not in panel
)
sys.exit(0 if ok else 1)
PY
if [ "$?" -ne 0 ]; then
    echo "FAIL live reset kept refresh and time" >&2
    fail=1
else
    echo "PASS live reset keeps refresh and time"
fi

exit "$fail"
