#!/bin/bash
#
# Regression: plan and catalog run through the script's host Python,
# even if a docker command is on PATH. Synthetic files only.

set -u

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
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

exit "$fail"
