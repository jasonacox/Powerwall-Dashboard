#!/bin/bash
#
# Import a stock Powerwall dashboard into Grafana and apply local settings.
# Settings live in dashboard-import.env next to this file. See README.md.
# Does not print passwords, tokens, emails, or gateway data.

set +x

if [ "$EUID" -eq 0 ]; then
    echo "ERROR: Running this as root will cause permission issues."
    echo ""
    echo "Please ensure your local user is in the docker group and run without sudo."
    echo "   sudo usermod -aG docker \$USER"
    echo "   $0"
    echo ""
    exit 1
fi

if type winpty > /dev/null 2>&1; then
    shopt -s expand_aliases
    alias docker="winpty -Xallow-non-tty -Xplain docker"
fi
usage() {
    cat <<'EOF'
Usage: ./tools/dashboard-import/dashboard-import.sh [--setup] [--file FILE] [--live] [--reset] [--legend-bottom] [--dry-run] [--yes] [--uid UID] [--title TITLE]

Import a stock dashboard from dashboards/ and apply dashboard-import.env.
Run it from the Powerwall-Dashboard directory, while the sun is up. A
Powerwall 3 reports every string disconnected at night, and the script
then leaves Grafana alone.

  --setup           Ask for each setting and write dashboard-import.env
  --file FILE       Stock file, for example dashboards/dashboard.json
  --live            Edit the open dashboard instead of importing it
  --reset           With --live, undo this script's hides and legend moves.
                    Without --live, import the stock file with no edits.
  --legend-bottom   Same as LEGEND=bottom
  --dry-run         Print the plan and do not save
  --yes             Save without the confirm prompt
  --uid UID         With --live, this dashboard instead of the file's uid
  --title TITLE     With --live, the dashboard with this exact title

The first run on a terminal, with no env file and no flags, asks for the
settings and saves them. Later runs print those settings and only ask to
confirm. Importing overwrites that dashboard, so edits made in Grafana are
lost. Use --live to keep them. A plain Grafana re-import brings the strings
back; run this script to import instead.

Login: anonymous access when it can already save (grafana.env.sample,
"disable login requirement (full access)"), otherwise a password prompt.
The password is not printed. See tools/dashboard-import/README.md.
EOF
}
die() {
    printf '%s\n' "$1" >&2
    exit 1
}

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd) || die "Could not find this script's directory."
REPO_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd) || die "Could not find the dashboard directory."
ENV_FILE="$SCRIPT_DIR/dashboard-import.env"

WORKDIR=""
CURL_CFG=""
AUTH_HEADER=""
PYTHON=""
PY_CODE=""
GF_SCHEME="http"
GF_HOST_PORT="9000"
GF_INNER_PORT="9000"
PW_HOST_PORT="8675"
PW_INNER_PORT="8675"
HTTP_CODE=""
DRY_RUN=0
ASSUME_YES=0
DO_SETUP=0
LIVE=0
RESET=0
EXPLICIT=0
FILE_FLAG=""
LEGEND_FLAG=""
ONLY_UID=""
ONLY_TITLE=""
DASHBOARD_FILE="dashboard.json"
LEGEND="default"
HIDE_STRINGS="auto"
REFRESH="default"
TIME_RANGE="default"
TIME_FROM=""
TIME_TO=""
STOCK_FILE=""
STOCK_UID=""
IMPORT_EXISTS=0
STRING_ACTION=""
STRING_SUMMARY=""
HIDE_JSON="[]"
UNHIDE_JSON="[]"
EDIT_CHANGED=""
EDIT_PROV=""
EDIT_PANELS=""
EDIT_UID=""
EDIT_FOLDER=""
EDIT_TITLE=""
EDIT_N=""
EDIT_MARK=""
cleanup() {
    local _dir
    _dir=$WORKDIR
    WORKDIR=""
    CURL_CFG=""
    if [ -n "$_dir" ] && [ -d "$_dir" ]; then
        rm -rf "$_dir"
    fi
    if command -v docker >/dev/null 2>&1; then
        docker exec -u 0 grafana rm -f \
            "/tmp/dashboard-import-$$.cfg" \
            "/tmp/dashboard-import-$$.json" \
            "/tmp/dashboard-import-$$.out" >/dev/null 2>&1 || true
    fi
    return 0
}
read_env_key() {
    local _rek_file _rek_key _rek_line _rek_val
    _rek_file=$1
    _rek_key=$2
    _rek_line=""
    _rek_val=""
    if [ -f "$_rek_file" ]; then
        _rek_line=$(grep -E "^${_rek_key}=" "$_rek_file" 2>/dev/null | head -n 1 || true)
    fi
    _rek_val=${_rek_line#*=}
    _rek_val=$(printf '%s' "$_rek_val" | tr -d '\r')
    case "$_rek_val" in
        \"*\")
            _rek_val=${_rek_val#\"}
            _rek_val=${_rek_val%\"}
            ;;
        \'*\')
            _rek_val=${_rek_val#\'}
            _rek_val=${_rek_val%\'}
            ;;
    esac
    printf '%s' "$_rek_val"
}
repo_env() {
    if [ -f "$REPO_DIR/$1" ]; then
        printf '%s\n' "$REPO_DIR/$1"
    else
        printf '%s\n' "$1"
    fi
}
parse_ports() {
    local _spec _container _left _hostport
    _spec=$1
    _spec=${_spec%%/*}
    _spec=$(printf '%s' "$_spec" | tr -d '[:space:]')
    case "$_spec" in
        \[*)
            _spec=${_spec#*]}
            _spec=${_spec#:}
            ;;
    esac
    _container=${_spec##*:}
    if [ "$_spec" = "$_container" ]; then
        _hostport=$_container
    else
        _left=${_spec%:*}
        _hostport=${_left##*:}
    fi
    case "$_hostport" in
        ''|*[!0-9]*) return 1 ;;
    esac
    case "$_container" in
        ''|*[!0-9]*) return 1 ;;
    esac
    printf '%s %s\n' "$_hostport" "$_container"
}
load_ports() {
    local _gf _comp _listen _explicit _gp _parsed _cport _pp
    _gf=$(repo_env grafana.env)
    _comp=$(repo_env compose.env)
    _listen=$(read_env_key "$_gf" GF_SERVER_HTTP_PORT)
    _explicit=$_listen
    if [ -z "$_listen" ]; then
        _listen=9000
    fi
    case "$_listen" in
        *[!0-9]*) die "GF_SERVER_HTTP_PORT in grafana.env is not a port number." ;;
    esac
    GF_HOST_PORT=$_listen
    GF_INNER_PORT=$_listen
    _gp=$(read_env_key "$_comp" GRAFANA_PORTS)
    if [ -n "$_gp" ]; then
        _parsed=$(parse_ports "$_gp") || die "GRAFANA_PORTS in compose.env is not a host:container port."
        GF_HOST_PORT=${_parsed%% *}
        _cport=${_parsed##* }
        if [ -z "$_explicit" ]; then
            GF_INNER_PORT=$_cport
        fi
    fi
    case "$(read_env_key "$_gf" GF_SERVER_PROTOCOL)" in
        https|HTTPS|Https) GF_SCHEME=https ;;
        *) GF_SCHEME=http ;;
    esac
    PW_HOST_PORT=8675
    PW_INNER_PORT=8675
    _pp=$(read_env_key "$_comp" PYPOWERWALL_PORTS)
    if [ -n "$_pp" ]; then
        _parsed=$(parse_ports "$_pp") || die "PYPOWERWALL_PORTS in compose.env is not a host:container port."
        PW_HOST_PORT=${_parsed%% *}
        PW_INNER_PORT=${_parsed##* }
    fi
}

PY_CODE=$(cat <<'PYCODE'
import json
import os
import re
import sys

NAME_RE = re.compile(r"^[A-F][1-8]?$")
UID_RE = re.compile(r"^[A-Za-z0-9_-]+$")
STRING_TITLES = ("String Voltage", "String Current", "String Power")
LEGEND_TYPES = ("timeseries", "barchart", "piechart", "state-timeline")
MARKER = "dashboardTune"
# key, from, to, Grafana name. An empty key is only a label for a file's current range.
_LAST = (
    ("5m", "5 minutes"), ("15m", "15 minutes"), ("30m", "30 minutes"),
    ("1h", "1 hour"), ("3h", "3 hours"), ("6h", "6 hours"), ("12h", "12 hours"),
    ("2d", "2 days"), ("30d", "30 days"), ("90d", "90 days"),
    ("6M", "6 months"), ("1y", "1 year"), ("2y", "2 years"), ("5y", "5 years"),
)
RANGES = (
    ("today", "now/d", "now/d", "Today"),
    ("today_so_far", "now/d", "now", "Today so far"),
    ("last_24h", "now-24h", "now", "Last 24 hours"),
    ("last_7d", "now-7d", "now", "Last 7 days"),
) + tuple(("", "now-" + spec, "now", "Last " + name) for spec, name in _LAST) + (
    ("", "now-1d/d", "now-1d/d", "Yesterday"),
    ("", "now/w", "now/w", "This week"), ("", "now/w", "now", "This week so far"),
    ("", "now/M", "now/M", "This month"), ("", "now/M", "now", "This month so far"),
    ("", "now/y", "now/y", "This year"), ("", "now/y", "now", "This year so far"),
)

def sort_names(names):
    def key(name):
        num = name[1:] or "0"
        return (name[0], int(num), name)
    return sorted(names, key=key)

def join_names(names):
    return ", ".join(sort_names(names)) if names else "none"

def clean(value, fallback):
    if not isinstance(value, str) or not value:
        return fallback
    return value.replace("\n", " ").replace("\r", " ")

def walk(panels, fn):
    if not isinstance(panels, list):
        return
    for panel in panels:
        if isinstance(panel, dict):
            fn(panel)
            walk(panel.get("panels"), fn)

def count_string_panels(panels):
    total = 0
    if not isinstance(panels, list):
        return 0
    for panel in panels:
        if not isinstance(panel, dict):
            continue
        if panel.get("title") in STRING_TITLES:
            total = total + 1
        total = total + count_string_panels(panel.get("panels"))
    return total

def is_string_panel(panel):
    return panel.get("title") in STRING_TITLES and panel.get("type") in ("timeseries", "graph")

def field_names(target):
    select = target.get("select")
    if not isinstance(select, list):
        return
    for group in select:
        if not isinstance(group, list):
            continue
        for part in group:
            if not isinstance(part, dict) or part.get("type") != "field":
                continue
            params = part.get("params")
            if isinstance(params, list):
                for param in params:
                    if isinstance(param, str):
                        yield param

def target_string_id(target):
    alias = target.get("alias")
    if isinstance(alias, str) and NAME_RE.match(alias):
        return alias
    ref = target.get("refId")
    if isinstance(ref, str) and NAME_RE.match(ref):
        return ref
    for field in field_names(target):
        prefix = field.split("_", 1)[0]
        if prefix != field and NAME_RE.match(prefix):
            return prefix
    return None

def targets_named(panel, name):
    found = []
    for target in panel.get("targets") or []:
        if isinstance(target, dict) and target_string_id(target) == name:
            found.append(target)
    return found

def marker(panel, create):
    state = panel.get(MARKER)
    if not isinstance(state, dict):
        if not create:
            return None
        state = {}
        panel[MARKER] = state
    return state

def hidden_names(state):
    raw = state.get("hidden") if isinstance(state, dict) else None
    names = []
    if isinstance(raw, list):
        for name in raw:
            if isinstance(name, str) and name not in names:
                names.append(name)
    return names

def set_hidden(panel, names):
    state = marker(panel, True)
    if names:
        state["hidden"] = sort_names(names)
    elif "hidden" in state:
        del state["hidden"]

def drop_empty_marker(panel):
    state = panel.get(MARKER)
    if isinstance(state, dict) and not state.get("hidden") and "legend" not in state:
        del panel[MARKER]

def strip_hides(panel, removed):
    fc = panel.get("fieldConfig")
    if not isinstance(fc, dict) or not isinstance(fc.get("overrides"), list):
        return []
    stripped = []
    kept = []
    for ov in fc["overrides"]:
        if not isinstance(ov, dict) or "__systemRef" in ov:
            kept.append(ov)
            continue
        matcher = ov.get("matcher")
        props = ov.get("properties")
        if not isinstance(matcher, dict) or matcher.get("id") != "byName":
            kept.append(ov)
            continue
        name = matcher.get("options")
        if not isinstance(name, str) or NAME_RE.match(name) is None or not isinstance(props, list):
            kept.append(ov)
            continue
        rest = [p for p in props if not (isinstance(p, dict) and p.get("id") == "custom.hideFrom")]
        if len(rest) == len(props):
            kept.append(ov)
            continue
        if name not in removed:
            removed.append(name)
        if name not in stripped:
            stripped.append(name)
        if rest:
            ov["properties"] = rest
            kept.append(ov)
    fc["overrides"][:] = kept
    return stripped

def hide_targets(panel, names):
    added = []
    state = marker(panel, False)
    hidden = hidden_names(state) if state is not None else []
    for name in names:
        if not isinstance(name, str) or NAME_RE.match(name) is None:
            continue
        did = False
        for target in targets_named(panel, name):
            if target.get("hide") is not True:
                target["hide"] = True
                did = True
        if did:
            if name not in hidden:
                hidden.append(name)
            added.append(name)
    if added:
        set_hidden(panel, hidden)
    return added

def show_targets(panel, only_names):
    state = marker(panel, False)
    if state is None:
        return []
    shown = []
    kept = []
    for name in hidden_names(state):
        if only_names is not None and name not in only_names:
            kept.append(name)
            continue
        for target in targets_named(panel, name):
            if target.get("hide") is True:
                target["hide"] = False
        shown.append(name)
    set_hidden(panel, kept)
    return shown

def legend_snapshot(panel):
    ptype = panel.get("type")
    if ptype in LEGEND_TYPES:
        options = panel.get("options")
        legend = options.get("legend") if isinstance(options, dict) else None
        if isinstance(legend, dict) and "placement" in legend:
            return {"kind": "placement", "value": legend.get("placement")}
        return {"kind": "placement", "value": None}
    if ptype == "graph":
        legend = panel.get("legend")
        if isinstance(legend, dict) and "rightSide" in legend:
            return {"kind": "rightSide", "value": legend.get("rightSide") is True}
        return {"kind": "rightSide", "value": None}
    return None

def legend_side(panel):
    snap = legend_snapshot(panel)
    if snap is None:
        return None
    if snap["kind"] == "rightSide":
        if snap["value"] is False:
            return "bottom"
        if snap["value"] is True:
            return "right"
        return None
    return snap["value"] if snap["value"] in ("bottom", "right") else None

def legend_dict(panel, create):
    ptype = panel.get("type")
    if ptype in LEGEND_TYPES:
        options = panel.get("options")
        if not isinstance(options, dict):
            if not create or options is not None:
                return None
            options = {}
            panel["options"] = options
        legend = options.get("legend")
        if not isinstance(legend, dict):
            if not create or legend is not None:
                return None
            legend = {}
            options["legend"] = legend
        return legend
    if ptype == "graph":
        legend = panel.get("legend")
        if not isinstance(legend, dict):
            if not create or legend is not None:
                return None
            legend = {}
            panel["legend"] = legend
        return legend
    return None

def legend_phrase(snap):
    if not isinstance(snap, dict):
        return "legend restored"
    if snap.get("kind") == "rightSide":
        if snap.get("value") is True:
            return "legend -> right"
        if snap.get("value") is False:
            return "legend -> bottom"
    value = snap.get("value")
    if isinstance(value, str) and value:
        return "legend -> " + value
    return "legend restored"

def apply_saved_legend(panel, snap):
    legend = legend_dict(panel, snap.get("value") is not None)
    if legend is None:
        return
    if snap.get("kind") == "rightSide":
        if snap.get("value") is None and "rightSide" in legend:
            del legend["rightSide"]
        elif snap.get("value") is not None:
            legend["rightSide"] = snap.get("value") is True
        return
    if snap.get("value") is None and "placement" in legend:
        del legend["placement"]
    elif snap.get("value") is not None:
        legend["placement"] = snap.get("value")

def move_legend(panel, where):
    if legend_snapshot(panel) is None or legend_side(panel) == where:
        return None
    state = marker(panel, True)
    if not isinstance(state.get("legend"), dict):
        state["legend"] = legend_snapshot(panel)
    legend = legend_dict(panel, True)
    if legend is None:
        return None
    if panel.get("type") == "graph":
        legend["rightSide"] = where == "right"
    else:
        legend["placement"] = where
    return "legend -> " + where

def restore_legend(panel):
    state = marker(panel, False)
    if not isinstance(state, dict) or not isinstance(state.get("legend"), dict):
        return None
    phrase = legend_phrase(state["legend"])
    apply_saved_legend(panel, state["legend"])
    del state["legend"]
    return phrase

def panel_label(panel):
    title = clean(panel.get("title"), "panel")
    pid = panel.get("id")
    if isinstance(pid, bool) or not isinstance(pid, (int, float)) or isinstance(pid, float) and pid != int(pid):
        return title
    return "%s (%d)" % (title, int(pid))

def time_key(key):
    for item in RANGES:
        if item[0] and item[0] == key:
            return item
    return None
def range_name(frm, to):
    for item in RANGES:
        if item[1] == frm and item[2] == to:
            return item[3]
    if frm and to:
        return frm + " to " + to
    return "none"
def file_labels(path):
    with open(path, "r") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        data = {}
    refresh = data.get("refresh")
    if not isinstance(refresh, str) or not refresh:
        refresh = "none"
    span = data.get("time") if isinstance(data.get("time"), dict) else {}
    frm = span.get("from") if isinstance(span.get("from"), str) else ""
    to = span.get("to") if isinstance(span.get("to"), str) else ""
    return refresh, range_name(frm, to)
def query_warning(panel):
    targets = panel.get("targets") if isinstance(panel.get("targets"), list) else []
    total = 0
    matched = 0
    for target in targets:
        if not isinstance(target, dict):
            continue
        total = total + 1
        if target_string_id(target):
            matched = matched + 1
    if matched < total or total == 0:
        return "matched %d of %d string queries. The query names may have changed." % (matched, total)
    return None

def apply_dashboard(dash, hide, unhide, reset, legend, refresh, time_from, time_to, do_hide):
    lines = []
    removed = []

    def edit(panel):
        clauses = []
        if is_string_panel(panel) and (do_hide or reset):
            warn = query_warning(panel)
            if warn:
                lines.append(panel_label(panel) + ": warning: " + warn)
            dropped = strip_hides(panel, removed)
            if reset:
                shown = show_targets(panel, None)
                hidden = []
            else:
                shown = show_targets(panel, unhide) if unhide else []
                hidden = hide_targets(panel, hide) if hide else []
            if hidden:
                clauses.append("hide " + ", ".join(sort_names(hidden)))
            if shown:
                clauses.append("show " + ", ".join(sort_names(shown)))
            if dropped:
                clauses.append("drop hideFrom " + ", ".join(sort_names(dropped)))
        if reset:
            phrase = restore_legend(panel)
            if phrase:
                clauses.append(phrase)
        elif legend in ("bottom", "right"):
            phrase = move_legend(panel, legend)
            if phrase:
                clauses.append(phrase)
        drop_empty_marker(panel)
        if clauses:
            lines.append(panel_label(panel) + ": " + "; ".join(clauses))

    before = json.dumps(dash, separators=(",", ":"), ensure_ascii=False)
    walk(dash.get("panels"), edit)
    if not reset:
        if refresh and dash.get("refresh") != refresh:
            dash["refresh"] = refresh
            lines.append("refresh -> " + refresh)
        if time_from and time_to:
            current = dash.get("time") if isinstance(dash.get("time"), dict) else {}
            if current.get("from") != time_from or current.get("to") != time_to:
                dash["time"] = {"from": time_from, "to": time_to}
                lines.append("time -> " + range_name(time_from, time_to))
    after = json.dumps(dash, separators=(",", ":"), ensure_ascii=False)
    return before != after, lines

def pick_datasource(plugin_id, label, datasources):
    same = []
    for ds in datasources:
        if isinstance(ds, dict) and ds.get("type") == plugin_id and isinstance(ds.get("uid"), str) and ds.get("uid"):
            same.append(ds)
    for ds in same:
        if label and ds.get("name") == label:
            return ds, None
    if len(same) == 1:
        return same[0], None
    return None, ("many" if same else "none")

def build_inputs(dash, datasources):
    inputs = []
    defined = dash.get("__inputs")
    if not isinstance(defined, list):
        return inputs
    for item in defined:
        if not isinstance(item, dict) or not isinstance(item.get("name"), str):
            continue
        name = item["name"]
        if item.get("type") == "datasource":
            plugin = item.get("pluginId") if isinstance(item.get("pluginId"), str) else ""
            label = item.get("label") if isinstance(item.get("label"), str) else ""
            chosen, why = pick_datasource(plugin, label, datasources)
            if chosen is None:
                if why == "many":
                    names = [ds.get("name") for ds in datasources if isinstance(ds, dict) and ds.get("type") == plugin and isinstance(ds.get("name"), str)]
                    sys.stderr.write("Grafana has more than one %s datasource (%s). Leave one, or name it \"%s\".\n" % (plugin or "matching", ", ".join(names), label or name))
                else:
                    sys.stderr.write("Grafana has no %s datasource for \"%s\".\n" % (plugin or "matching", label or name))
                sys.exit(1)
            inputs.append({"name": name, "type": "datasource", "pluginId": plugin, "value": chosen["uid"]})
        elif item.get("type") == "constant":
            value = item.get("value")
            if not isinstance(value, str):
                value = "" if value is None else str(value)
            inputs.append({"name": name, "type": "constant", "value": value})
    return inputs

def emit(changed, provisioned, panels, uid, folder, title, lines, post, path):
    sys.stdout.write(("1" if changed else "0") + "\n")
    sys.stdout.write(("1" if provisioned else "0") + "\n")
    sys.stdout.write(str(panels) + "\n")
    sys.stdout.write(uid + "\n")
    sys.stdout.write(folder + "\n")
    sys.stdout.write(title + "\n")
    sys.stdout.write(str(len(lines)) + "\n")
    for line in lines:
        sys.stdout.write(line + "\n")
    sys.stdout.write("---\n")
    if post is not None:
        handle = open(path, "w")
        try:
            json.dump(post, handle, separators=(",", ":"), ensure_ascii=False)
            handle.write("\n")
        finally:
            handle.close()

def mode_classify():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.stdout.write("bad\n/strings did not return JSON.\n[]\n[]\n")
        return
    strings = data.get("strings") if isinstance(data, dict) else None
    if not isinstance(strings, dict) or not strings:
        sys.stdout.write("empty\nNo Connected fields in /strings. No changes.\n[]\n[]\n")
        return
    hiding, keeping, leaving = [], [], []
    saw = False
    any_true = False
    for name in strings:
        item = strings.get(name)
        if not isinstance(item, dict) or "Connected" not in item:
            if isinstance(name, str) and NAME_RE.match(name):
                leaving.append(name)
            continue
        saw = True
        if item.get("Connected") is True:
            any_true = True
            if isinstance(name, str) and NAME_RE.match(name):
                keeping.append(name)
        elif isinstance(name, str) and NAME_RE.match(name):
            hiding.append(name)
    if not saw:
        sys.stdout.write("empty\nNo Connected fields in /strings. No changes.\n[]\n[]\n")
        return
    if not any_true:
        if hiding:
            summary = "Every Connected string is offline (%s). Run ./tools/dashboard-import/dashboard-import.sh again while the sun is up." % join_names(hiding)
        else:
            summary = "Every Connected string is offline. Run ./tools/dashboard-import/dashboard-import.sh again while the sun is up."
        sys.stdout.write("night\n" + summary + "\n[]\n[]\n")
        return
    summary = "Hiding %s. Keeping %s." % (join_names(hiding), join_names(keeping))
    if leaving:
        summary = summary + " Leaving %s unchanged." % join_names(leaving)
    sys.stdout.write("hide\n" + summary + "\n")
    sys.stdout.write(json.dumps(sort_names(hiding), separators=(",", ":")) + "\n")
    sys.stdout.write(json.dumps(sort_names(keeping), separators=(",", ":")) + "\n")

def mode_plan(path):
    data = json.load(sys.stdin)
    if not isinstance(data, dict):
        sys.stderr.write("Could not prepare the dashboard.\n")
        sys.exit(1)
    live = data.get("live") is True
    reset = data.get("reset") is True
    legend = data.get("legend") if data.get("legend") in ("bottom", "right") else ""
    refresh = data.get("refresh") if isinstance(data.get("refresh"), str) else ""
    time_from = data.get("time_from") if isinstance(data.get("time_from"), str) else ""
    time_to = data.get("time_to") if isinstance(data.get("time_to"), str) else ""
    do_hide = data.get("do_hide") is True
    hide = data.get("hide") if isinstance(data.get("hide"), list) else []
    unhide = data.get("unhide") if isinstance(data.get("unhide"), list) else []
    if live:
        response = data.get("response")
        if not isinstance(response, dict) or not isinstance(response.get("dashboard"), dict):
            sys.stderr.write("Could not edit the dashboard JSON.\n")
            sys.exit(1)
        dash = response["dashboard"]
        meta = response.get("meta") if isinstance(response.get("meta"), dict) else {}
    else:
        dash = data.get("dashboard")
        if not isinstance(dash, dict):
            sys.stderr.write("The dashboard file is not JSON.\n")
            sys.exit(1)
        existing = data.get("existing")
        meta = existing.get("meta") if isinstance(existing, dict) and isinstance(existing.get("meta"), dict) else {}
    uid = dash.get("uid") if isinstance(dash.get("uid"), str) else ""
    if UID_RE.match(uid) is None:
        sys.stderr.write("This dashboard file has no uid.\n")
        sys.exit(1)
    title = clean(dash.get("title"), "dashboard")
    folder = meta.get("folderUid") if isinstance(meta.get("folderUid"), str) else ""
    folder = folder.replace("\n", "").replace("\r", "")
    panels = count_string_panels(dash.get("panels"))
    if meta.get("provisioned") is True:
        emit(False, True, panels, uid, folder, title, [], None, path)
        return
    if not live:
        if not isinstance(data.get("datasources"), list):
            sys.stderr.write("Could not read Grafana datasources.\n")
            sys.exit(1)
        inputs = build_inputs(dash, data["datasources"])
        if "id" in dash:
            del dash["id"]
    changed, lines = apply_dashboard(dash, hide, unhide, reset, legend, refresh, time_from, time_to, do_hide)
    if live:
        post = None
        if changed:
            post = {"dashboard": dash, "folderUid": folder, "overwrite": True, "message": "dashboard-import.sh"}
        emit(changed, False, panels, uid, folder, title, lines, post, path)
        return
    post = {"dashboard": dash, "overwrite": True, "inputs": inputs, "folderUid": folder}
    emit(changed, False, panels, uid, folder, title, lines, post, path)

def mode_file_uid():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.stderr.write("The dashboard file is not JSON.\n")
        sys.exit(1)
    uid = data.get("uid") if isinstance(data, dict) else None
    if not isinstance(uid, str) or UID_RE.match(uid) is None:
        sys.stderr.write("This dashboard file has no uid.\n")
        sys.exit(1)
    sys.stdout.write(uid + "\n")

def mode_encode():
    json.dump(sys.stdin.read(), sys.stdout)

def mode_catalog():
    root = sys.stdin.read().strip()
    if not os.path.isdir(root):
        sys.stderr.write("No dashboards folder.\n")
        sys.exit(1)
    names = [name for name in os.listdir(root) if name.startswith("dashboard") and name.endswith(".json") and os.path.isfile(os.path.join(root, name))]
    for name in sorted(names, key=lambda item: (item != "dashboard.json", item)):
        title = ""
        try:
            with open(os.path.join(root, name), "r") as handle:
                data = json.load(handle)
            if isinstance(data, dict) and isinstance(data.get("title"), str):
                title = data["title"].replace("\n", " ").replace("|", " ")
        except Exception:
            title = ""
        sys.stdout.write(name + "|" + title + "\n")

def mode_search():
    data = json.load(sys.stdin)
    want = data.get("title") if isinstance(data, dict) else None
    hits = data.get("hits") if isinstance(data, dict) else None
    if not isinstance(hits, list):
        return
    for hit in hits:
        if not isinstance(hit, dict) or hit.get("type") not in (None, "dash-db"):
            continue
        uid = hit.get("uid")
        if isinstance(uid, str) and UID_RE.match(uid) and (want is None or hit.get("title") == want):
            sys.stdout.write(uid + "\n")

def mode_b64():
    import base64
    sys.stdout.write(base64.b64encode(sys.stdin.read().encode("utf-8")).decode("ascii"))

def mode_can_save_actions():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.stdout.write("no")
        return
    if isinstance(data, dict) and (data.get("dashboards:write") is True or data.get("dashboards:create") is True):
        sys.stdout.write("yes")
    else:
        sys.stdout.write("no")

def mode_can_save_orgs():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.stdout.write("no")
        return
    ok = False
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict) and item.get("role") in ("Admin", "Editor"):
                ok = True
    sys.stdout.write("yes" if ok else "no")

def mode_bounds():
    found = time_key(sys.stdin.read().strip())
    if found is not None:
        sys.stdout.write(found[1] + "\n" + found[2] + "\n")
def mode_filemeta():
    try:
        refresh, tname = file_labels(sys.stdin.read().strip())
    except Exception:
        sys.stderr.write("Could not read the dashboard file.\n")
        sys.exit(1)
    sys.stdout.write(refresh + "\n" + tname + "\n")
def mode_summary():
    parts = sys.stdin.read().splitlines() + [""] * 5
    path, legend, hide, refresh, key = parts[:5]
    try:
        file_refresh, file_time = file_labels(path)
    except Exception:
        file_refresh, file_time = "none", "none"
    if legend == "default":
        legend = "keep file setting"
    if refresh == "default":
        refresh = "keep file setting (" + file_refresh + ")"
    found = time_key(key)
    if key == "default":
        shown = "keep file setting (" + file_time + ")"
    elif found is not None:
        shown = found[3]
    else:
        shown = key
    sys.stdout.write("Settings: file=%s legend=%s hide=%s refresh=%s time=%s\n" % (
        os.path.basename(path), legend, hide, refresh, shown))
def mode_message():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    if isinstance(data, dict) and isinstance(data.get("message"), str):
        sys.stdout.write(data["message"].replace("\n", " ").replace("\r", " ")[:200])

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "classify":
        mode_classify()
    elif mode == "plan":
        if len(sys.argv) < 3:
            sys.stderr.write("dashboard-import: internal error\n")
            sys.exit(1)
        mode_plan(sys.argv[2])
    elif mode == "file_uid":
        mode_file_uid()
    elif mode == "encode":
        mode_encode()
    elif mode == "catalog":
        mode_catalog()
    elif mode == "search":
        mode_search()
    elif mode == "b64":
        mode_b64()
    elif mode == "can_save_actions":
        mode_can_save_actions()
    elif mode == "can_save_orgs":
        mode_can_save_orgs()
    elif mode == "bounds":
        mode_bounds()
    elif mode == "filemeta":
        mode_filemeta()
    elif mode == "summary":
        mode_summary()
    elif mode == "message":
        mode_message()
    else:
        sys.stderr.write("dashboard-import: internal error\n")
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        text = str(exc).replace("\n", " ").replace("\r", " ")
        if len(text) > 160:
            text = text[:160]
        if text:
            sys.stderr.write("dashboard-import: %s: %s\n" % (type(exc).__name__, text))
        else:
            sys.stderr.write("dashboard-import: %s\n" % type(exc).__name__)
        sys.exit(1)
PYCODE
)
choose_python() {
    PYTHON=$(command -v python3 || command -v python || true)
    if [ -z "$PYTHON" ]; then
        die "python3 was not found. Install Python 3 and run this again."
    fi
    if ! "$PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1; then
        die "python3 was not found. Install Python 3 and run this again."
    fi
}
run_python() {
    env -i PATH="$PATH" PYTHONIOENCODING=utf-8 PYTHONUTF8=1 \
        "$PYTHON" -c "$PY_CODE" "$@"
}
write_curl_cfg() {
    local _new _old
    _old=$CURL_CFG
    umask 077
    _new=$(mktemp "${WORKDIR}/curl.XXXXXX") || die "Could not create a temp file."
    chmod 600 "$_new"
    {
        printf '%s\n' "silent"
        printf '%s\n' "connect-timeout = 5"
        printf '%s\n' "max-time = 60"
    } > "$_new"
    if [ -n "$AUTH_HEADER" ]; then
        printf 'header = "Authorization: %s"\n' "$AUTH_HEADER" >> "$_new"
    fi
    CURL_CFG=$_new
    if [ -n "$_old" ] && [ -f "$_old" ]; then
        rm -f "$_old"
    fi
}
grafana_curl_host() {
    local _method _url _body _dest _code
    _method=$1
    _url=$2
    _body=$3
    _dest=$4
    if [ "$_method" = "POST" ]; then
        _code=$(curl --config "$CURL_CFG" --insecure --request POST \
            --header "Content-Type: application/json" \
            --data-binary @"$_body" \
            --output "$_dest" --write-out '%{http_code}' \
            "$_url" 2>/dev/null) || true
    else
        _code=$(curl --config "$CURL_CFG" --insecure \
            --output "$_dest" --write-out '%{http_code}' \
            "$_url" 2>/dev/null) || true
    fi
    if [ -z "$_code" ]; then
        _code=000
    fi
    printf '%s' "$_code"
}
grafana_curl_exec() {
    local _method _url _body _dest _tmp _code
    _method=$1
    _url=$2
    _body=$3
    _dest=$4
    _tmp="/tmp/dashboard-import-$$"
    _code=000
    if ! command -v docker >/dev/null 2>&1; then
        printf '%s' "000"
        return
    fi
    if [ "$(docker inspect --format '{{.State.Running}}' grafana 2>/dev/null || true)" != "true" ]; then
        printf '%s' "000"
        return
    fi
    if ! docker exec -u 0 grafana sh -c 'command -v curl' >/dev/null 2>&1; then
        printf '%s' "000"
        return
    fi
    if [ "$_method" = "POST" ]; then
        docker cp "$CURL_CFG" "grafana:${_tmp}.cfg" >/dev/null 2>&1 || { printf '%s' "000"; return; }
        docker cp "$_body" "grafana:${_tmp}.json" >/dev/null 2>&1 || {
            docker exec -u 0 grafana rm -f "${_tmp}.cfg" >/dev/null 2>&1 || true
            printf '%s' "000"
            return
        }
        _code=$(docker exec -u 0 grafana curl --config "${_tmp}.cfg" --insecure --request POST \
            --header "Content-Type: application/json" \
            --data-binary @"${_tmp}.json" \
            --output "${_tmp}.out" --write-out '%{http_code}' \
            "$_url" 2>/dev/null) || true
        if ! docker exec -u 0 grafana cat "${_tmp}.out" > "$_dest" 2>/dev/null; then
            : > "$_dest"
        fi
        docker exec -u 0 grafana rm -f "${_tmp}.cfg" "${_tmp}.json" "${_tmp}.out" >/dev/null 2>&1 || true
    else
        _code=$(docker exec -u 0 -i grafana curl --config - --insecure \
            --output "${_tmp}.out" --write-out '%{http_code}' \
            "$_url" < "$CURL_CFG" 2>/dev/null) || true
        if ! docker exec -u 0 grafana cat "${_tmp}.out" > "$_dest" 2>/dev/null; then
            : > "$_dest"
        fi
        docker exec -u 0 grafana rm -f "${_tmp}.out" >/dev/null 2>&1 || true
    fi
    if [ -z "$_code" ]; then
        _code=000
    fi
    printf '%s' "$_code"
}
grafana_request() {
    local _method _path _body _dest _host _inner _inner_code
    _method=$1
    _path=$2
    _body=$3
    _dest=$4
    _host="${GF_SCHEME}://localhost:${GF_HOST_PORT}${_path}"
    _inner="${GF_SCHEME}://127.0.0.1:${GF_INNER_PORT}${_path}"
    HTTP_CODE=$(grafana_curl_host "$_method" "$_host" "$_body" "$_dest")
    case "$HTTP_CODE" in
        2*) return 0 ;;
    esac
    if [ "$_method" = "POST" ] && [ "$HTTP_CODE" != "000" ]; then
        return 0
    fi
    _inner_code=$(grafana_curl_exec "$_method" "$_inner" "$_body" "$_dest.inner")
    case "$_inner_code" in
        2*)
            HTTP_CODE=$_inner_code
            cat "$_dest.inner" > "$_dest"
            ;;
        *)
            if [ "$HTTP_CODE" = "000" ] && [ -n "$_inner_code" ]; then
                HTTP_CODE=$_inner_code
                cat "$_dest.inner" > "$_dest" 2>/dev/null || true
            fi
            ;;
    esac
    rm -f "$_dest.inner"
}
fetch_strings() {
    local _dest _code _inner _running
    _dest=$1
    _code=$(curl --silent --connect-timeout 5 --max-time 30 \
        --output "$_dest" --write-out '%{http_code}' \
        "http://localhost:${PW_HOST_PORT}/strings" 2>/dev/null) || true
    case "$_code" in
        2*) return 0 ;;
    esac
    if ! command -v docker >/dev/null 2>&1; then
        return 1
    fi
    _running=$(docker inspect --format '{{.State.Running}}' pypowerwall 2>/dev/null || true)
    if [ "$_running" != "true" ]; then
        return 1
    fi
    _inner="http://127.0.0.1:${PW_INNER_PORT}/strings"
    if docker exec pypowerwall sh -c 'command -v curl' >/dev/null 2>&1; then
        docker exec pypowerwall curl --silent --connect-timeout 5 --max-time 30 \
            "$_inner" > "$_dest" 2>/dev/null || return 1
    elif docker exec pypowerwall sh -c 'command -v wget' >/dev/null 2>&1; then
        docker exec pypowerwall wget -q -O - -T 5 "$_inner" > "$_dest" 2>/dev/null || return 1
    else
        return 1
    fi
    if [ ! -s "$_dest" ]; then
        return 1
    fi
    return 0
}
explain_403() {
    cat <<'EOF'
Grafana can view dashboards but cannot save them.
Read-only anonymous access does this (HTTP 403).
To save without a password, uncomment "disable login requirement (full access)"
in grafana.env.sample (GF_AUTH_ANONYMOUS_ORG_ROLE=Admin), or from the dashboard
directory run ./anonymous-access.sh and choose 3) Anonymous Read/Write.
You can also sign in with a Grafana user that can edit.
No changes saved.
EOF
}
auth_can_save() {
    local _answer
    grafana_request GET "/api/access-control/user/actions" "" "$WORKDIR/actions.json"
    if [ "$HTTP_CODE" = "200" ]; then
        _answer=$(run_python can_save_actions < "$WORKDIR/actions.json" 2>/dev/null || true)
        if [ "$_answer" = "yes" ]; then
            return 0
        fi
        return 1
    fi
    grafana_request GET "/api/user/orgs" "" "$WORKDIR/orgs.json"
    if [ "$HTTP_CODE" = "200" ]; then
        _answer=$(run_python can_save_orgs < "$WORKDIR/orgs.json" 2>/dev/null || true)
        if [ "$_answer" = "yes" ]; then
            return 0
        fi
        return 1
    fi
    return 0
}
auth_ok() {
    grafana_request GET "/api/search?type=dash-db&limit=1" "" "$WORKDIR/probe.json"
    case "$HTTP_CODE" in
        2*) ;;
        401) return 1 ;;
        403)
            explain_403
            exit 1
            ;;
        *)
            die "Grafana is not reachable at ${GF_SCHEME}://localhost:${GF_HOST_PORT} (HTTP ${HTTP_CODE})."
            ;;
    esac
    if auth_can_save; then
        return 0
    fi
    explain_403
    exit 1
}
prompt_basic() {
    local _user _pass _b64
    _user=""
    _pass=""
    _b64=""
    printf '%s' "Grafana user [admin]: " >&2
    read -r _user || true
    if [ -z "$_user" ]; then
        _user="admin"
    fi
    case "$_user" in
        *[$'\n\r':]*) die "That user name cannot be used." ;;
    esac
    printf '%s' "Grafana password: " >&2
    read -r -s _pass || true
    printf '\n' >&2
    case "$_pass" in
        *[$'\n\r']*) die "The password cannot contain a newline." ;;
    esac
    if [ -z "$_pass" ]; then
        die "A password is required."
    fi
    _b64=$(printf '%s' "${_user}:${_pass}" | run_python b64) || die "Could not encode the login."
    _pass=""
    AUTH_HEADER="Basic ${_b64}"
    _b64=""
    write_curl_cfg
}
establish_auth() {
    grafana_request GET "/api/health" "" "$WORKDIR/health.json"
    case "$HTTP_CODE" in
        2*) ;;
        *) die "Grafana is not reachable at ${GF_SCHEME}://localhost:${GF_HOST_PORT}." ;;
    esac
    AUTH_HEADER=""
    write_curl_cfg
    grafana_request GET "/api/search?type=dash-db&limit=1" "" "$WORKDIR/probe.json"
    case "$HTTP_CODE" in
        2*)
            if auth_can_save; then
                return
            fi
            ;;
        401) ;;
        *)
            die "Grafana is not reachable at ${GF_SCHEME}://localhost:${GF_HOST_PORT} (HTTP ${HTTP_CODE})."
            ;;
    esac
    prompt_basic
    if ! auth_ok; then
        die "Grafana rejected that login."
    fi
}
blank_to() {
    if [ -n "$2" ]; then
        printf '%s' "$2"
    else
        printf '%s' "$1"
    fi
}
load_saved_settings() {
    DASHBOARD_FILE=$(blank_to "default" "$(read_env_key "$ENV_FILE" DASHBOARD_FILE)")
    LEGEND=$(blank_to "default" "$(read_env_key "$ENV_FILE" LEGEND)")
    HIDE_STRINGS=$(blank_to "auto" "$(read_env_key "$ENV_FILE" HIDE_STRINGS)")
    REFRESH=$(blank_to "default" "$(read_env_key "$ENV_FILE" REFRESH)")
    TIME_RANGE=$(blank_to "default" "$(read_env_key "$ENV_FILE" TIME_RANGE)")
}
valid_refresh() {
    case "$1" in
        default|5s|10s|30s|1m|5m|15m|30m|1h|2h|1d) return 0 ;;
    esac
    return 1
}
apply_time_bounds() {
    TIME_FROM=""
    TIME_TO=""
    if [ "$TIME_RANGE" = "default" ]; then
        return
    fi
    printf '%s' "$TIME_RANGE" | run_python bounds > "$WORKDIR/bounds.txt" 2>"$WORKDIR/bounds.err" || true
    TIME_FROM=$(sed -n '1p' "$WORKDIR/bounds.txt")
    TIME_TO=$(sed -n '2p' "$WORKDIR/bounds.txt")
    if [ -z "$TIME_FROM" ] || [ -z "$TIME_TO" ]; then
        die "TIME_RANGE must be default, today, today_so_far, last_24h, or last_7d."
    fi
}
validate_settings() {
    case "$DASHBOARD_FILE" in
        default) DASHBOARD_FILE="dashboard.json" ;;
    esac
    case "$DASHBOARD_FILE" in
        dashboard*.json) ;;
        *) die "DASHBOARD_FILE must be default or a file in dashboards/, for example dashboard.json." ;;
    esac
    case "$DASHBOARD_FILE" in
        *[!A-Za-z0-9._-]*) die "DASHBOARD_FILE must be a file in dashboards/, for example dashboard.json." ;;
    esac
    case "$LEGEND" in
        default|bottom|right) ;;
        *) die "LEGEND must be default, bottom, or right." ;;
    esac
    case "$HIDE_STRINGS" in
        default) HIDE_STRINGS="auto" ;;
        auto|off) ;;
        *) die "HIDE_STRINGS must be auto, off, or default." ;;
    esac
    if ! valid_refresh "$REFRESH"; then
        die "REFRESH must be default, 5s, 10s, 30s, 1m, 5m, 15m, 30m, 1h, 2h, or 1d."
    fi
    apply_time_bounds
    STOCK_FILE="$REPO_DIR/dashboards/$DASHBOARD_FILE"
    if [ ! -f "$STOCK_FILE" ]; then
        die "No stock dashboard named ${DASHBOARD_FILE}."
    fi
}
apply_flag_overrides() {
    local _base
    if [ -n "$FILE_FLAG" ]; then
        case "$FILE_FLAG" in
            *..*) die "Use a file in dashboards/, for example dashboards/dashboard.json." ;;
        esac
        _base=$(basename -- "$FILE_FLAG")
        case "$FILE_FLAG" in
            "$_base"|"dashboards/$_base"|"./dashboards/$_base"|"$REPO_DIR/dashboards/$_base")
                DASHBOARD_FILE=$_base
                ;;
            *) die "Use a file in dashboards/, for example dashboards/dashboard.json." ;;
        esac
    fi
    if [ -n "$LEGEND_FLAG" ]; then
        LEGEND=$LEGEND_FLAG
    fi
}
prompt_choice() {
    local _title _def _ans _i _n _pick _val _lab _deflab
    _title=$1
    _def=$2
    shift 2
    _deflab=$_def
    printf '%s\n' "$_title" >&2
    _i=1
    for _pick in "$@"; do
        _val=${_pick%%|*}
        _lab=${_pick#*|}
        if [ "$_val" = "$_def" ]; then
            _deflab=$_lab
        fi
        printf '  %s) %s\n' "$_i" "$_lab" >&2
        _i=$((_i + 1))
    done
    printf '%s' "${_title} [${_deflab}]: " >&2
    _ans=""
    read -r _ans || true
    if [ -z "$_ans" ]; then
        printf '%s\n' "$_def"
        return
    fi
    case "$_ans" in
        *[!0-9]*)
            for _pick in "$@"; do
                _val=${_pick%%|*}
                _lab=${_pick#*|}
                if [ "$_ans" = "$_val" ] || [ "$_ans" = "$_lab" ]; then
                    printf '%s\n' "$_val"
                    return
                fi
            done
            die "There is no choice ${_ans}."
            ;;
        *)
            _n=1
            for _pick in "$@"; do
                if [ "$_n" -eq "$_ans" ]; then
                    printf '%s\n' "${_pick%%|*}"
                    return
                fi
                _n=$((_n + 1))
            done
            die "There is no choice ${_ans}."
            ;;
    esac
}
choose_dashboard_file() {
    local _line _name _title _i _ans
    printf '%s' "$REPO_DIR/dashboards" | run_python catalog > "$WORKDIR/catalog.txt" || die "Could not list dashboards."
    CATALOG_NAME=()
    printf '%s\n' "Dashboard file:" >&2
    while IFS= read -r _line || [ -n "$_line" ]; do
        if [ -z "$_line" ]; then
            continue
        fi
        _name=${_line%%|*}
        _title=${_line#*|}
        CATALOG_NAME[${#CATALOG_NAME[@]}]=$_name
        _i=${#CATALOG_NAME[@]}
        printf '  %s) %s (%s)\n' "$_i" "$_name" "$_title" >&2
    done < "$WORKDIR/catalog.txt"
    if [ "${#CATALOG_NAME[@]}" -eq 0 ]; then
        die "No dashboards found in dashboards/."
    fi
    printf '%s' "Dashboard file [dashboard.json]: " >&2
    _ans=""
    read -r _ans || true
    if [ -z "$_ans" ] || [ "$_ans" = "default" ] || [ "$_ans" = "dashboard.json" ] || [ "$_ans" = "1" ]; then
        DASHBOARD_FILE="dashboard.json"
        return
    fi
    case "$_ans" in
        *[!0-9]*) DASHBOARD_FILE=$_ans ;;
        *)
            if [ "$_ans" -ge 1 ] && [ "$_ans" -le "${#CATALOG_NAME[@]}" ]; then
                DASHBOARD_FILE=${CATALOG_NAME[$((_ans - 1))]}
            else
                die "There is no dashboard number ${_ans}."
            fi
            ;;
    esac
}
write_settings() {
    local _tmp
    umask 077
    _tmp=$(mktemp "$SCRIPT_DIR/dashboard-import.env.XXXXXX") || die "Could not write dashboard-import.env."
    chmod 600 "$_tmp"
    {
        printf '%s\n' "# Local settings for dashboard-import.sh. This file is not committed."
        printf '%s\n' "# default keeps the value shipped in the stock dashboard."
        printf '%s\n' "DASHBOARD_FILE=${DASHBOARD_FILE}"
        printf '%s\n' "LEGEND=${LEGEND}"
        printf '%s\n' "HIDE_STRINGS=${HIDE_STRINGS}"
        printf '%s\n' "REFRESH=${REFRESH}"
        printf '%s\n' "TIME_RANGE=${TIME_RANGE}"
    } > "$_tmp"
    mv "$_tmp" "$ENV_FILE" || die "Could not write dashboard-import.env."
    chmod 600 "$ENV_FILE"
    printf '%s\n' "Wrote tools/dashboard-import/dashboard-import.env"
}
guided_setup() {
    if [ ! -t 0 ]; then
        die "Setup needs a terminal. Copy dashboard-import.env.sample to dashboard-import.env, or pass flags."
    fi
    choose_dashboard_file
    printf '%s' "$REPO_DIR/dashboards/$DASHBOARD_FILE" | run_python filemeta > "$WORKDIR/filemeta.txt" || die "Could not read ${DASHBOARD_FILE}."
    FILE_REFRESH=$(sed -n '1p' "$WORKDIR/filemeta.txt")
    FILE_TIME=$(sed -n '2p' "$WORKDIR/filemeta.txt")
    prompt_choice "Legend" "default" "default|keep file setting" bottom right > "$WORKDIR/choice.txt"
    LEGEND=$(cat "$WORKDIR/choice.txt")
    prompt_choice "Hide strings" "auto" "auto|auto (hide disconnected strings)" "off|off (show all strings)" > "$WORKDIR/choice.txt"
    HIDE_STRINGS=$(cat "$WORKDIR/choice.txt")
    prompt_choice "Refresh" "default" "default|keep file setting (${FILE_REFRESH})" 5s 10s 30s 1m 5m 15m 30m 1h 2h 1d > "$WORKDIR/choice.txt"
    REFRESH=$(cat "$WORKDIR/choice.txt")
    prompt_choice "Time range" "default" "default|keep file setting (${FILE_TIME})" \
        "today|Today (today)" "today_so_far|Today so far (today_so_far)" \
        "last_24h|Last 24 hours (last_24h)" "last_7d|Last 7 days (last_7d)" > "$WORKDIR/choice.txt"
    TIME_RANGE=$(cat "$WORKDIR/choice.txt")
    validate_settings
    write_settings
}
load_plan() {
    local _file
    _file=$1
    EDIT_CHANGED=$(sed -n '1p' "$_file")
    EDIT_PROV=$(sed -n '2p' "$_file")
    EDIT_PANELS=$(sed -n '3p' "$_file")
    EDIT_UID=$(sed -n '4p' "$_file")
    EDIT_FOLDER=$(sed -n '5p' "$_file")
    EDIT_TITLE=$(sed -n '6p' "$_file")
    EDIT_N=$(sed -n '7p' "$_file")
    case "$EDIT_N" in
        ""|*[!0-9]*) die "Could not prepare the dashboard." ;;
    esac
    EDIT_MARK=$(sed -n "$((8 + EDIT_N))p" "$_file")
    if [ "$EDIT_MARK" != "---" ]; then
        die "Could not prepare the dashboard."
    fi
}
print_plan_lines() {
    local _end
    if [ "$EDIT_N" -gt 0 ]; then
        _end=$((7 + EDIT_N))
        sed -n "8,${_end}p" "$WORKDIR/plan.txt"
    elif [ "$EDIT_PANELS" = "0" ]; then
        printf '%s\n' "No String Voltage, String Current, or String Power panels."
    elif [ "$RESET" -eq 1 ]; then
        printf '%s\n' "No string hides or legend moves."
    fi
}
build_job() {
    local _err
    rm -f "$WORKDIR/post.json"
    {
        printf '%s' '{"live":'
        if [ "$LIVE" -eq 1 ]; then
            printf '%s' 'true'
        else
            printf '%s' 'false'
        fi
        printf '%s' ',"reset":'
        if [ "$RESET" -eq 1 ]; then
            printf '%s' 'true'
        else
            printf '%s' 'false'
        fi
        printf '%s' ',"legend":'
        if [ "$RESET" -eq 1 ] || [ "$LEGEND" = "default" ]; then
            printf '%s' '""'
        else
            printf '%s' "\"${LEGEND}\""
        fi
        printf '%s' ',"refresh":'
        if [ "$RESET" -eq 1 ] || [ "$REFRESH" = "default" ]; then
            printf '%s' '""'
        else
            printf '%s' "\"${REFRESH}\""
        fi
        printf '%s' ',"time_from":'
        if [ "$RESET" -eq 1 ]; then
            printf '%s' '""'
        else
            printf '%s' "\"${TIME_FROM}\""
        fi
        printf '%s' ',"time_to":'
        if [ "$RESET" -eq 1 ]; then
            printf '%s' '""'
        else
            printf '%s' "\"${TIME_TO}\""
        fi
        printf '%s' ',"do_hide":'
        if [ "$RESET" -ne 1 ] && [ "$HIDE_STRINGS" = "auto" ]; then
            printf '%s' 'true'
        else
            printf '%s' 'false'
        fi
        printf '%s' ',"hide":'
        printf '%s' "$HIDE_JSON"
        printf '%s' ',"unhide":'
        printf '%s' "$UNHIDE_JSON"
        printf '%s' ',"dashboard":'
        if [ "$LIVE" -eq 1 ]; then
            printf '%s' 'null'
        else
            cat "$STOCK_FILE"
        fi
        printf '%s' ',"response":'
        if [ "$LIVE" -eq 1 ]; then
            cat "$WORKDIR/existing.json"
        else
            printf '%s' 'null'
        fi
        printf '%s' ',"datasources":'
        if [ "$LIVE" -eq 1 ]; then
            printf '%s' 'null'
        else
            cat "$WORKDIR/datasources.json"
        fi
        printf '%s' ',"existing":'
        if [ "$LIVE" -eq 1 ] || [ "$IMPORT_EXISTS" -ne 1 ]; then
            printf '%s' 'null'
        else
            cat "$WORKDIR/existing.json"
        fi
        printf '%s' '}'
    } | run_python plan "$WORKDIR/post.json" > "$WORKDIR/plan.txt" 2>"$WORKDIR/plan.err"
    if [ "$?" -ne 0 ]; then
        _err=$(sed -n '1p' "$WORKDIR/plan.err")
        die "${_err:-Could not prepare the dashboard.}"
    fi
    load_plan "$WORKDIR/plan.txt"
    if [ "$EDIT_PROV" = "1" ]; then
        die "Grafana will not overwrite a provisioned dashboard: ${EDIT_TITLE} (${EDIT_UID})."
    fi
}
confirm_or_stop() {
    local _response
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '%s\n' "Dry run. No changes saved."
        exit 0
    fi
    if [ "$ASSUME_YES" -eq 1 ]; then
        return 0
    fi
    _response=""
    printf '%s' "Apply these changes? [y/N] " >&2
    read -r _response || true
    if [[ ! "$_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        printf '%s\n' "No changes applied."
        exit 0
    fi
}
grafana_error() {
    local _msg
    _msg=$(run_python message < "$WORKDIR/post-res.json" 2>/dev/null || true)
    if [ -n "$_msg" ]; then
        die "$1: ${_msg}"
    fi
    die "$1."
}
post_save() {
    local _url
    if [ "$LIVE" -eq 1 ]; then
        _url="/api/dashboards/db"
    else
        _url="/api/dashboards/import"
    fi
    if [ ! -s "$WORKDIR/post.json" ]; then
        die "Could not prepare the dashboard."
    fi
    grafana_request POST "$_url" "$WORKDIR/post.json" "$WORKDIR/post-res.json"
    if [ "$LIVE" -eq 1 ] && [ "$HTTP_CODE" = "412" ]; then
        grafana_request GET "/api/dashboards/uid/${EDIT_UID}" "" "$WORKDIR/existing.json"
        if [ "$HTTP_CODE" != "200" ]; then
            die "Grafana refused the save (HTTP 412) and the dashboard could not be read again."
        fi
        build_job
        if [ "$EDIT_CHANGED" != "1" ]; then
            return 0
        fi
        grafana_request POST "$_url" "$WORKDIR/post.json" "$WORKDIR/post-res.json"
    fi
    case "$HTTP_CODE" in
        2*) return 0 ;;
        403)
            explain_403
            exit 1
            ;;
        412)
            grafana_error "Grafana refused the save (HTTP 412)"
            ;;
        *)
            grafana_error "Grafana did not save the dashboard (HTTP ${HTTP_CODE})"
            ;;
    esac
}

# Tests source this file and call run_python. A normal run does not set this.
if [ "${DASHBOARD_IMPORT_SOURCE:-0}" = 1 ]; then
    return 0 2>/dev/null || exit 0
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --yes) ASSUME_YES=1 ;;
        --setup) DO_SETUP=1 ;;
        --reset) RESET=1 ;;
        --live) LIVE=1 ;;
        --legend-bottom) LEGEND_FLAG="bottom" ;;
        --file)
            shift
            if [ $# -lt 1 ] || [ -z "$1" ]; then
                die "Missing file after --file."
            fi
            FILE_FLAG=$1
            ;;
        --file=*)
            FILE_FLAG=${1#--file=}
            if [ -z "$FILE_FLAG" ]; then
                die "Missing file after --file."
            fi
            ;;
        --uid)
            shift
            if [ $# -lt 1 ] || [ -z "$1" ]; then
                die "Missing UID after --uid."
            fi
            ONLY_UID=$1
            ;;
        --uid=*)
            ONLY_UID=${1#--uid=}
            if [ -z "$ONLY_UID" ]; then
                die "Missing UID after --uid."
            fi
            ;;
        --title)
            shift
            if [ $# -lt 1 ] || [ -z "$1" ]; then
                die "Missing title after --title."
            fi
            ONLY_TITLE=$1
            ;;
        --title=*)
            ONLY_TITLE=${1#--title=}
            if [ -z "$ONLY_TITLE" ]; then
                die "Missing title after --title."
            fi
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf '%s\n' "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

if [ "$LIVE" -ne 1 ]; then
    if [ -n "$ONLY_UID" ] || [ -n "$ONLY_TITLE" ]; then
        die "--uid and --title apply to --live. Use --file to choose a stock dashboard."
    fi
fi
if [ -n "$ONLY_UID" ]; then
    case "$ONLY_UID" in
        *[!A-Za-z0-9_-]*) die "The dashboard uid may only contain letters, numbers, _ and -." ;;
    esac
    EXPLICIT=1
fi
if [ -n "$ONLY_TITLE" ]; then
    EXPLICIT=1
fi

umask 077
WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/dashboard-import.XXXXXX") || die "Could not create a temp directory."
chmod 700 "$WORKDIR"
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

load_ports
choose_python
write_curl_cfg

if [ "$DO_SETUP" -eq 1 ] || { [ ! -f "$ENV_FILE" ] && [ -t 0 ] && [ "$EXPLICIT" -eq 0 ] && [ -z "$FILE_FLAG" ] && [ -z "$LEGEND_FLAG" ] && [ "$LIVE" -eq 0 ] && [ "$RESET" -eq 0 ] && [ "$DRY_RUN" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; }; then
    guided_setup
elif [ -f "$ENV_FILE" ]; then
    load_saved_settings
fi
apply_flag_overrides
validate_settings

if [ "$RESET" -ne 1 ] && [ "$HIDE_STRINGS" = "auto" ]; then
    if ! fetch_strings "$WORKDIR/strings.json"; then
        die "pypowerwall /strings is not reachable at http://localhost:${PW_HOST_PORT}/strings."
    fi
    {
        printf '%s' '{"strings":'
        cat "$WORKDIR/strings.json"
        printf '%s' '}'
    } | run_python classify > "$WORKDIR/classify.txt" || die "Could not read /strings."
    STRING_ACTION=$(sed -n '1p' "$WORKDIR/classify.txt")
    STRING_SUMMARY=$(sed -n '2p' "$WORKDIR/classify.txt")
    HIDE_JSON=$(sed -n '3p' "$WORKDIR/classify.txt")
    UNHIDE_JSON=$(sed -n '4p' "$WORKDIR/classify.txt")
    if [ "$STRING_ACTION" = "bad" ] || [ -z "$STRING_ACTION" ]; then
        die "${STRING_SUMMARY:-/strings did not return JSON.}"
    fi
    case "$HIDE_JSON" in
        \[*\]) ;;
        *) die "Could not read /strings." ;;
    esac
    if [ "$STRING_ACTION" != "hide" ]; then
        if [ "$LIVE" -ne 1 ]; then
            printf '%s\n' "$STRING_SUMMARY"
            printf '%s\n' "Not importing. The dashboard was left as it is."
            exit 0
        fi
        if [ "$LEGEND" = "default" ] && [ "$REFRESH" = "default" ] && [ "$TIME_RANGE" = "default" ]; then
            printf '%s\n' "$STRING_SUMMARY"
            exit 0
        fi
        HIDE_JSON="[]"
        UNHIDE_JSON="[]"
    fi
fi

printf '%s\n' "$STOCK_FILE" "$LEGEND" "$HIDE_STRINGS" "$REFRESH" "$TIME_RANGE" | run_python summary || die "Could not read ${DASHBOARD_FILE}."
if [ -n "$STRING_SUMMARY" ]; then
    printf '%s\n' "$STRING_SUMMARY"
fi
if [ "$RESET" -eq 1 ]; then
    if [ "$LIVE" -eq 1 ]; then
        printf '%s\n' "Removing this script's string hides and legend moves."
    else
        printf '%s\n' "Importing the stock file with no legend, hide, refresh, or time changes."
    fi
fi
printf '%s\n' "Grafana: ${GF_SCHEME}://localhost:${GF_HOST_PORT}"

establish_auth

if [ -n "$ONLY_TITLE" ] && [ -z "$ONLY_UID" ]; then
    grafana_request GET "/api/search?type=dash-db&limit=5000" "" "$WORKDIR/search.json"
    if [ "$HTTP_CODE" != "200" ]; then
        die "Could not list dashboards (HTTP ${HTTP_CODE})."
    fi
    _title_json=$(printf '%s' "$ONLY_TITLE" | run_python encode) || die "Could not read the dashboard title."
    {
        printf '%s' "{\"title\":${_title_json},\"hits\":"
        cat "$WORKDIR/search.json"
        printf '%s' '}'
    } | run_python search > "$WORKDIR/uids.txt" || die "Could not read Grafana's dashboard list."
    ONLY_UID=$(sed -n '1p' "$WORKDIR/uids.txt")
    if [ -z "$ONLY_UID" ]; then
        die "No dashboard titled ${ONLY_TITLE}."
    fi
    if [ "$(wc -l < "$WORKDIR/uids.txt" | tr -d ' ')" -gt 1 ]; then
        die "More than one dashboard is titled ${ONLY_TITLE}."
    fi
fi

if [ -z "$ONLY_UID" ]; then
    ONLY_UID=$(run_python file_uid < "$STOCK_FILE" 2>"$WORKDIR/uid.err") || {
        _err=$(sed -n '1p' "$WORKDIR/uid.err")
        die "${_err:-This dashboard file has no uid.}"
    }
fi

grafana_request GET "/api/dashboards/uid/${ONLY_UID}" "" "$WORKDIR/existing.json"
IMPORT_EXISTS=0
case "$HTTP_CODE" in
    200) IMPORT_EXISTS=1 ;;
    404)
        if [ "$LIVE" -eq 1 ]; then
            die "No dashboard with uid ${ONLY_UID}."
        fi
        ;;
    *) die "Could not read dashboard ${ONLY_UID} (HTTP ${HTTP_CODE})." ;;
esac

if [ "$LIVE" -ne 1 ]; then
    grafana_request GET "/api/datasources" "" "$WORKDIR/datasources.json"
    if [ "$HTTP_CODE" != "200" ]; then
        die "Could not list Grafana datasources (HTTP ${HTTP_CODE})."
    fi
fi

build_job
printf '%s\n' "Dashboard: ${EDIT_TITLE} (${EDIT_UID})"
printf '%s\n' "File: dashboards/${DASHBOARD_FILE}"
print_plan_lines
if [ "$LIVE" -eq 1 ]; then
    if [ "$EDIT_CHANGED" != "1" ]; then
        printf '%s\n' "No changes needed."
        exit 0
    fi
elif [ "$IMPORT_EXISTS" -eq 1 ]; then
    printf '%s\n' "This will overwrite \"${EDIT_TITLE}\" (${EDIT_UID})."
    printf '%s\n' "Manual edits in Grafana will be lost. Use --live to edit the dashboard that is already there."
else
    printf '%s\n' "This will add \"${EDIT_TITLE}\" (${EDIT_UID}) to Grafana."
fi
confirm_or_stop
post_save
printf '%s\n' "Saved."
