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
printf '%s\n' '{"title":"Probe","uid":"probeuid","panels":[],"time":{"from":"now-24h","to":"now"}}' > "$WORK/dashboards/dashboard.json"
printf '%s\n' '[]' > "$WORK/datasources.json"
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

JOB=$(printf '%s' '{"live":false,"reset":false,"legend":"","refresh":"","time":"","do_hide":false,"hide":[],"unhide":[],"stock":"'"$WORK/dashboards/dashboard.json"'","existing":"","response":"","datasources":"'"$WORK/datasources.json"'"}')
printf '%s' "$JOB" | run_python plan "$WORK/post.json" > "$WORK/plan.txt" 2>"$WORK/plan.err"
if [ ! -s "$WORK/post.json" ]; then
    echo "FAIL plan did not write post.json" >&2
    cat "$WORK/plan.err" >&2
    fail=1
elif ! grep -q probeuid "$WORK/post.json"; then
    echo "FAIL post.json missing uid" >&2
    fail=1
elif grep -q folderUid "$WORK/post.json"; then
    echo "FAIL empty folderUid was sent" >&2
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

RESET=0
STOCK_FILE="$ROOT/dashboards/dashboard.json"
DASHBOARD_FILE=dashboard.json
HIDE_STRINGS=auto
LEGEND=default
TIME_RANGE=default
REFRESH=default
print_settings > "$WORK/sum.txt"
if [ "$(cat "$WORK/sum.txt")" != "Settings: file=dashboard.json hide=auto legend=keep time=keep refresh=keep" ]; then
    echo "FAIL keep settings line" >&2
    cat "$WORK/sum.txt" >&2
    fail=1
else
    echo "PASS keep settings line"
fi

LEGEND=bottom
TIME_RANGE=today
REFRESH=30s
print_settings > "$WORK/sum.txt"
if [ "$(cat "$WORK/sum.txt")" != "Settings: file=dashboard.json hide=auto legend=bottom time=Today refresh=30s" ]; then
    echo "FAIL settings line" >&2
    cat "$WORK/sum.txt" >&2
    fail=1
else
    echo "PASS settings line order"
fi

JOB_TODAY=$(printf '%s' '{"live":false,"reset":false,"legend":"","refresh":"30s","time":"today","do_hide":false,"hide":[],"unhide":[],"stock":"'"$WORK/dashboards/dashboard.json"'","existing":"","response":"","datasources":"'"$WORK/datasources.json"'"}')
printf '%s' "$JOB_TODAY" | run_python plan "$WORK/post-today.json" > "$WORK/plan-today.txt"
tline=$(grep -n '^time -> Today$' "$WORK/plan-today.txt" | head -n 1 | cut -d: -f1)
rline=$(grep -n '^refresh -> 30s$' "$WORK/plan-today.txt" | head -n 1 | cut -d: -f1)
if [ -z "$tline" ] || [ -z "$rline" ] || [ "$tline" -ge "$rline" ]; then
    echo "FAIL plan time before refresh" >&2
    cat "$WORK/plan-today.txt" >&2
    fail=1
else
    echo "PASS plan puts time before refresh"
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

printf '%s\n' '{"refresh":"5m","time":{"from":"now-5y","to":"now"}}' > "$WORK/dashboards/unknown-range.json"
printf '%s' "$WORK/dashboards/unknown-range.json" | run_python filemeta > "$WORK/meta.txt"
if ! grep -q '^now-5y to now$' "$WORK/meta.txt"; then
    echo "FAIL unknown range" >&2
    cat "$WORK/meta.txt" >&2
    fail=1
else
    echo "PASS unknown range prints from/to"
fi

printf '%s' '{"strings":{"A":{"Connected":1},"B":{"Connected":false},"C":{"Connected":0}}}' | run_python classify > "$WORK/class.txt"
if [ "$(sed -n '1p' "$WORK/class.txt")" != "hide" ] || [ "$(sed -n '3p' "$WORK/class.txt")" != '["B","C"]' ] || [ "$(sed -n '4p' "$WORK/class.txt")" != '["A"]' ]; then
    echo "FAIL Connected 1" >&2
    cat "$WORK/class.txt" >&2
    fail=1
else
    echo "PASS Connected 1 hides the others"
fi

printf '%s' '{"strings":{"A":{"Connected":false}}}' | run_python classify > "$WORK/class.txt"
if [ "$(sed -n '1p' "$WORK/class.txt")" != "unchanged" ] || [ "$(sed -n '2p' "$WORK/class.txt")" != "String queries were left unchanged." ]; then
    echo "FAIL unchanged strings" >&2
    cat "$WORK/class.txt" >&2
    fail=1
else
    echo "PASS none connected leaves queries unchanged"
fi

printf '%s\n' '{"meta":{"folderUid":"fld"},"dashboard":{"uid":"probeuid","title":"Probe","refresh":"30s","time":{"from":"now/d","to":"now/d"},"panels":[{"id":1,"type":"timeseries","title":"String Voltage","targets":[{"refId":"B","alias":"B","hide":true}],"dashboardTune":{"hidden":["B"],"legend":{"kind":"placement","value":"right"}},"options":{"legend":{"placement":"bottom"}}},{"id":2,"type":"graph","title":"String Current","legend":{"rightSide":false},"targets":[{"refId":"A","alias":"A","hide":true}],"dashboardTune":{"hidden":["A"],"legend":{"kind":"rightSide","value":true}}}]}}' > "$WORK/response.json"
LIVE_RESET=$(printf '%s' '{"live":true,"reset":true,"legend":"bottom","refresh":"30s","time":"today","do_hide":false,"hide":[],"unhide":[],"stock":"","existing":"","datasources":"","response":"'"$WORK/response.json"'"}')
printf '%s' "$LIVE_RESET" | run_python plan "$WORK/live-reset.json" > "$WORK/live-reset.txt"
python3 - "$WORK/live-reset.json" <<'PY'
import json, sys
body = json.load(open(sys.argv[1]))
dash = body["dashboard"]
panel = dash["panels"][0]
graph = dash["panels"][1]
ok = (
    body.get("folderUid") == "fld"
    and dash.get("refresh") == "30s"
    and dash.get("time") == {"from": "now/d", "to": "now/d"}
    and panel["targets"][0].get("hide") is False
    and panel["options"]["legend"].get("placement") == "right"
    and "dashboardTune" not in panel
    and graph["legend"].get("rightSide") is True
    and graph["targets"][0].get("hide") is False
    and "dashboardTune" not in graph
)
sys.exit(0 if ok else 1)
PY
if [ "$?" -ne 0 ]; then
    echo "FAIL live reset kept refresh and time" >&2
    fail=1
else
    echo "PASS live reset keeps refresh and time"
fi

rows=$(run_python rows time)
if [ "$(printf '%s\n' "$rows" | sed -n '1p')" != "today|Today (today)" ]; then
    echo "FAIL time menu source" >&2
    printf '%s\n' "$rows" >&2
    fail=1
else
    echo "PASS time choices come from the range list"
fi

setup=$(awk '/^guided_setup\(\)/,/^}/' "$SCRIPT")
hide_at=$(printf '%s\n' "$setup" | grep -n 'Hide strings' | head -n 1 | cut -d: -f1)
legend_at=$(printf '%s\n' "$setup" | grep -n '"Legend"' | head -n 1 | cut -d: -f1)
time_at=$(printf '%s\n' "$setup" | grep -n 'Time range' | head -n 1 | cut -d: -f1)
refresh_at=$(printf '%s\n' "$setup" | grep -n '"Refresh"' | head -n 1 | cut -d: -f1)
if [ -z "$hide_at" ] || [ -z "$legend_at" ] || [ -z "$time_at" ] || [ -z "$refresh_at" ] || [ "$hide_at" -ge "$legend_at" ] || [ "$legend_at" -ge "$time_at" ] || [ "$time_at" -ge "$refresh_at" ]; then
    echo "FAIL setup order" >&2
    fail=1
else
    echo "PASS setup asks hide, legend, time, refresh"
fi

cat > "$WORK/dashboards/mismatch.json" <<'EOF'
{"uid":"probeuid","title":"Probe","panels":[{"id":32,"type":"timeseries","title":"String Voltage","targets":[
  {"refId":"A0","alias":"B","select":[[{"type":"field","params":["A_Voltage"]}]]},
  {"refId":"A","alias":"A","select":[[{"type":"field","params":["A1_Voltage"]}]]},
  {"refId":"B0","alias":"A"},
  {"refId":"C0","alias":"C","select":[[{"type":"field","params":["B_Voltage"]}]]}
]}]}
EOF
JOB_ID=$(printf '%s' '{"live":false,"reset":false,"legend":"","refresh":"","time":"","do_hide":true,"hide":["A"],"unhide":[],"stock":"'"$WORK/dashboards/mismatch.json"'","existing":"","response":"","datasources":"'"$WORK/datasources.json"'"}')
printf '%s' "$JOB_ID" | run_python plan "$WORK/post-id.json" > "$WORK/plan-id.txt" 2>"$WORK/plan-id.err"
python3 - "$WORK/post-id.json" <<'PY'
import json, sys
panel = json.load(open(sys.argv[1]))["dashboard"]["panels"][0]
targets = panel["targets"]
# field A, field A1 (not A), alias A with no field, field B despite alias C
ok = (
    targets[0].get("hide") is True
    and targets[1].get("hide") is not True
    and targets[2].get("hide") is True
    and targets[3].get("hide") is not True
    and panel["dashboardTune"]["hidden"] == ["A0", "B0"]
)
sys.exit(0 if ok else 1)
PY
if [ "$?" -ne 0 ]; then
    echo "FAIL string id ignores refId" >&2
    cat "$WORK/plan-id.err" "$WORK/post-id.json" >&2
    fail=1
else
    echo "PASS string id uses field then alias"
fi

cat > "$WORK/dashboards/manual.json" <<'EOF'
{"uid":"probeuid","title":"Probe","panels":[{"id":62,"type":"timeseries","title":"String Current","targets":[
  {"refId":"M","alias":"B","hide":true,"select":[[{"type":"field","params":["B_Current"]}]]},
  {"refId":"S","alias":"B","select":[[{"type":"field","params":["B_Current"]}]]}
]}]}
EOF
JOB_HIDE=$(printf '%s' '{"live":false,"reset":false,"legend":"","refresh":"","time":"","do_hide":true,"hide":["B"],"unhide":[],"stock":"'"$WORK/dashboards/manual.json"'","existing":"","response":"","datasources":"'"$WORK/datasources.json"'"}')
printf '%s' "$JOB_HIDE" | run_python plan "$WORK/post-hide.json" > "$WORK/plan-hide.txt"
python3 - "$WORK/post-hide.json" "$WORK/response-manual.json" <<'PY'
import json, sys
dash = json.load(open(sys.argv[1]))["dashboard"]
panel = dash["panels"][0]
targets = panel["targets"]
if not (targets[0].get("hide") is True and targets[1].get("hide") is True and panel["dashboardTune"]["hidden"] == ["S"]):
    sys.exit(1)
json.dump({"meta": {}, "dashboard": dash}, open(sys.argv[2], "w"))
PY
if [ "$?" -ne 0 ]; then
    echo "FAIL manual hide was recorded" >&2
    fail=1
else
    JOB_RESET=$(printf '%s' '{"live":true,"reset":true,"legend":"","refresh":"","time":"","do_hide":false,"hide":[],"unhide":[],"stock":"","existing":"","datasources":"","response":"'"$WORK/response-manual.json"'"}')
    printf '%s' "$JOB_RESET" | run_python plan "$WORK/post-manual-reset.json" > "$WORK/plan-manual-reset.txt"
    python3 - "$WORK/post-manual-reset.json" <<'PY'
import json, sys
targets = json.load(open(sys.argv[1]))["dashboard"]["panels"][0]["targets"]
panel = json.load(open(sys.argv[1]))["dashboard"]["panels"][0]
targets = panel["targets"]
ok = targets[0].get("hide") is True and targets[1].get("hide") is False and "dashboardTune" not in panel
sys.exit(0 if ok else 1)
PY
    if [ "$?" -ne 0 ]; then
        echo "FAIL reset cleared a manual hide" >&2
        fail=1
    else
        echo "PASS reset keeps a manually hidden query"
    fi
fi

mkdir -p "$WORK/failbin"
cat > "$WORK/failbin/curl" <<'EOF'
#!/bin/bash
printf '503'
exit 0
EOF
cat > "$WORK/failbin/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$DASHBOARD_IMPORT_DOCKER_LOG"
case "$*" in
    inspect*) printf 'true'; exit 0 ;;
    *--fail*) exit 22 ;;
    *curl*) printf '%s\n' '{"bad":true}'; exit 0 ;;
esac
exit 0
EOF
chmod 755 "$WORK/failbin/curl" "$WORK/failbin/docker"
PATH="$WORK/failbin:$PATH" PW_HOST_PORT=9 fetch_strings "$WORK/strings-fail.json"
fail_status=$?
if [ "$fail_status" -eq 0 ] || ! grep -q -- '--fail' "$LOG"; then
    echo "FAIL container curl accepted an HTTP error" >&2
    fail=1
else
    echo "PASS container curl --fail rejects HTTP errors"
fi

exit "$fail"
