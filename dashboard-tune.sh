#!/bin/bash
#
# Hide disconnected solar strings on an imported Powerwall dashboard.
# Reads pypowerwall /strings and saves Grafana field overrides.
# Does not print passwords, tokens, emails, or gateway data.
#
# Grafana 12.3.1 has no supported way to save a dashboard from inside the
# container without a credential. `grafana cli admin` can reset the admin
# password, migrate secrets, or migrate data, and that is all. Requests with
# no login, including from inside the container, get HTTP 401. Resetting the
# password, turning on anonymous Admin, or writing grafana.db would change
# the install, so this script does not do those.

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

# Windows Git Bash docker exec compatibility (same pattern as verify.sh).
if type winpty > /dev/null 2>&1; then
    shopt -s expand_aliases
    alias docker="winpty -Xallow-non-tty -Xplain docker"
fi

usage() {
    cat <<'EOF'
Usage: ./dashboard-tune.sh [--dry-run] [--yes] [--reset] [--legend-bottom] [--uid UID] [--title TITLE]

Hide solar strings that are not connected on the String Voltage, String
Current and String Power panels. Run it while the sun is up. A Powerwall 3
reports every string as disconnected at night, and the script then leaves
the dashboard alone.

  --dry-run         Print one line per panel that would change, and do not save
  --yes             Save without the confirm prompt
  --reset           Remove hides this script added
  --legend-bottom   Move legends to the bottom
  --uid UID         Only this dashboard
  --title TITLE     Only dashboards with this exact title

Grafana login, in this order:
  1. GRAFANA_TOKEN  service account token (Editor or Admin). Keep it outside
                    this repo. Do not put it in grafana.env.
  2. Anonymous access, if it can already save dashboards.
  3. A password prompt (default user admin). The password is not printed.

Read-only anonymous access cannot save. Run ./anonymous-access.sh and choose
1 (username and password) or 3 (anonymous read/write), or set GRAFANA_TOKEN.
See README, "Tune an imported dashboard".
EOF
}

die() {
    printf '%s\n' "$1" >&2
    exit 1
}

WORKDIR=""
CURL_CFG=""
AUTH_HEADER=""
PY_MODE=""
PY_CODE=""
GF_SCHEME="http"
GF_HOST_PORT="9000"
GF_INNER_PORT="9000"
PW_HOST_PORT="8675"
PW_INNER_PORT="8675"
DRY_RUN=0
ASSUME_YES=0
RESET=0
LEGEND=0
ONLY_UID=""
ONLY_TITLE=""
EXPLICIT=0
HIDE_JSON="[]"
UNHIDE_JSON="[]"
STRING_ACTION=""
STRING_SUMMARY=""
SEEN=0
HTTP_CODE=""
CHANGE_UID=()
CHANGE_POST=()
EDIT_CHANGED=""
EDIT_PROV=""
EDIT_PANELS=""
EDIT_UID=""
EDIT_FOLDER=""
EDIT_TITLE=""
EDIT_REMOVED=""
EDIT_N=0
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
            "/tmp/dashboard-tune-$$.cfg" \
            "/tmp/dashboard-tune-$$.json" \
            "/tmp/dashboard-tune-$$.out" >/dev/null 2>&1 || true
    fi
    return 0
}

# Read one KEY=value from an env file. Do not source the file: grafana.env
# can hold a mail password, and values are not executed.
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

# Docker compose port spec: [[IP:]HOST_PORT:]CONTAINER_PORT[/PROTOCOL]
# Prints "hostport containerport".
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
    local _listen _gp _parsed _cport _explicit _pp
    _listen=$(read_env_key grafana.env GF_SERVER_HTTP_PORT)
    _explicit=$_listen
    if [ -z "$_listen" ]; then
        _listen=9000
    fi
    case "$_listen" in
        *[!0-9]*) die "GF_SERVER_HTTP_PORT in grafana.env is not a port number." ;;
    esac
    GF_HOST_PORT=$_listen
    GF_INNER_PORT=$_listen
    _gp=$(read_env_key compose.env GRAFANA_PORTS)
    if [ -n "$_gp" ]; then
        _parsed=$(parse_ports "$_gp") || die "GRAFANA_PORTS in compose.env is not a host:container port."
        GF_HOST_PORT=${_parsed%% *}
        _cport=${_parsed##* }
        if [ -z "$_explicit" ]; then
            GF_INNER_PORT=$_cport
        fi
    fi
    case "$(read_env_key grafana.env GF_SERVER_PROTOCOL)" in
        https|HTTPS|Https) GF_SCHEME=https ;;
        *) GF_SCHEME=http ;;
    esac
    PW_HOST_PORT=8675
    PW_INNER_PORT=8675
    _pp=$(read_env_key compose.env PYPOWERWALL_PORTS)
    if [ -n "$_pp" ]; then
        _parsed=$(parse_ports "$_pp") || die "PYPOWERWALL_PORTS in compose.env is not a host:container port."
        PW_HOST_PORT=${_parsed%% *}
        PW_INNER_PORT=${_parsed##* }
    fi
}

PY_CODE=$(cat <<'PYCODE'
import json
import re
import sys

NAME_RE = re.compile(r"^[A-F][1-8]?$")
UID_RE = re.compile(r"^[A-Za-z0-9_-]+$")
STRING_TITLES = ("String Voltage", "String Current", "String Power")
HIDE = {"legend": True, "tooltip": True, "viz": True}
LEGEND_TYPES = ("timeseries", "barchart", "piechart", "state-timeline")


def sort_names(names):
    def key(name):
        num = name[1:]
        if num == "":
            num = "0"
        return (name[0], int(num), name)
    return sorted(names, key=key)


def join_names(names):
    if not names:
        return "none"
    return ", ".join(sort_names(names))


def write_classify(action, summary, hide, unhide):
    summary = summary.replace("\n", " ").replace("\r", " ")
    sys.stdout.write(action + "\n")
    sys.stdout.write(summary + "\n")
    sys.stdout.write(json.dumps(sort_names(hide), separators=(",", ":")) + "\n")
    sys.stdout.write(json.dumps(sort_names(unhide), separators=(",", ":")) + "\n")


def connected_state(value):
    if not isinstance(value, dict) or "Connected" not in value:
        return None
    if value.get("Connected") is True:
        return True
    return False


def mode_classify():
    try:
        data = json.load(sys.stdin)
    except Exception:
        write_classify("bad", "/strings did not return JSON.", [], [])
        return
    strings = data.get("strings") if isinstance(data, dict) else None
    if not isinstance(strings, dict) or not strings:
        write_classify("empty", "No Connected fields in /strings. No changes.", [], [])
        return
    hiding = []
    keeping = []
    leaving = []
    saw = False
    any_true = False
    for name in strings:
        state = connected_state(strings.get(name))
        if state is None:
            if isinstance(name, str) and NAME_RE.match(name):
                leaving.append(name)
            continue
        saw = True
        if state is True:
            any_true = True
            if isinstance(name, str) and NAME_RE.match(name):
                keeping.append(name)
        elif isinstance(name, str) and NAME_RE.match(name):
            hiding.append(name)
    if not saw:
        write_classify("empty", "No Connected fields in /strings. No changes.", [], [])
        return
    if not any_true:
        if hiding:
            summary = "Every Connected string is offline (%s). Run ./dashboard-tune.sh again while the sun is up." % join_names(hiding)
        else:
            summary = "Every Connected string is offline. Run ./dashboard-tune.sh again while the sun is up."
        write_classify("night", summary, [], [])
        return
    summary = "Hiding %s. Keeping %s." % (join_names(hiding), join_names(keeping))
    if leaving:
        summary = summary + " Leaving %s unchanged." % join_names(leaving)
    write_classify("hide", summary, hiding, keeping)


def walk(panels, fn):
    if not isinstance(panels, list):
        return
    for panel in panels:
        if not isinstance(panel, dict):
            continue
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


def override_name(ov):
    if not isinstance(ov, dict) or "__systemRef" in ov:
        return None
    matcher = ov.get("matcher")
    if not isinstance(matcher, dict) or matcher.get("id") != "byName":
        return None
    name = matcher.get("options")
    if not isinstance(name, str) or NAME_RE.match(name) is None:
        return None
    return name


def hide_prop():
    return {"id": "custom.hideFrom", "value": {"legend": True, "tooltip": True, "viz": True}}


def overrides_of(panel, create):
    fc = panel.get("fieldConfig")
    if not isinstance(fc, dict):
        if not create:
            return None
        fc = {}
        panel["fieldConfig"] = fc
    overrides = fc.get("overrides")
    if overrides is None:
        if not create:
            return None
        overrides = []
        fc["overrides"] = overrides
    elif not isinstance(overrides, list):
        return None
    return overrides


def strip_hides(panel, only_names, removed):
    stripped = []
    overrides = overrides_of(panel, False)
    if overrides is None:
        return stripped
    kept_overrides = []
    for ov in overrides:
        name = override_name(ov)
        props = ov.get("properties") if isinstance(ov, dict) else None
        if name is None or not isinstance(props, list) or (only_names is not None and name not in only_names):
            kept_overrides.append(ov)
            continue
        kept_props = []
        found = False
        for prop in props:
            if isinstance(prop, dict) and prop.get("id") == "custom.hideFrom":
                found = True
                continue
            kept_props.append(prop)
        if not found:
            kept_overrides.append(ov)
            continue
        if name not in removed:
            removed.append(name)
        if name not in stripped:
            stripped.append(name)
        if kept_props:
            ov["properties"] = kept_props
            kept_overrides.append(ov)
    overrides[:] = kept_overrides
    return stripped


def add_hides(panel, names):
    added = []
    overrides = overrides_of(panel, True)
    if overrides is None:
        return added
    for name in names:
        if not isinstance(name, str) or NAME_RE.match(name) is None:
            continue
        mutated = False
        target = None
        for ov in overrides:
            if override_name(ov) != name:
                continue
            props = ov.get("properties")
            if not isinstance(props, list):
                continue
            for prop in props:
                if isinstance(prop, dict) and prop.get("id") == "custom.hideFrom":
                    target = ov
                    if prop.get("value") != HIDE:
                        prop["value"] = {"legend": True, "tooltip": True, "viz": True}
                        mutated = True
                    break
            if target is not None:
                break
            if target is None:
                target = ov
        if target is None:
            overrides.append({"matcher": {"id": "byName", "options": name}, "properties": [hide_prop()]})
            added.append(name)
            continue
        props = target.get("properties")
        if not isinstance(props, list):
            props = []
            target["properties"] = props
        already = False
        for prop in props:
            if isinstance(prop, dict) and prop.get("id") == "custom.hideFrom":
                already = True
                break
        if not already:
            props.append(hide_prop())
            mutated = True
        if mutated:
            added.append(name)
    return added


def legend_will_change(panel):
    ptype = panel.get("type")
    if ptype in LEGEND_TYPES:
        options = panel.get("options")
        if options is None:
            return True
        if not isinstance(options, dict):
            return False
        legend = options.get("legend")
        if legend is None:
            return True
        if not isinstance(legend, dict):
            return False
        return legend.get("placement") != "bottom"
    if ptype == "graph":
        legend = panel.get("legend")
        if legend is None:
            return True
        if not isinstance(legend, dict):
            return False
        return legend.get("rightSide") is not False
    return False


def panel_label(panel):
    title = panel.get("title") if isinstance(panel.get("title"), str) else "panel"
    title = title.replace("\n", " ").replace("\r", " ")
    pid = panel.get("id")
    if isinstance(pid, bool) or not isinstance(pid, (int, float)):
        return title
    if isinstance(pid, float) and pid != int(pid):
        return title
    return "%s (%d)" % (title, int(pid))


def apply_legend(panel):
    ptype = panel.get("type")
    if ptype in LEGEND_TYPES:
        options = panel.get("options")
        if options is None:
            options = {}
            panel["options"] = options
        if not isinstance(options, dict):
            return
        legend = options.get("legend")
        if legend is None:
            legend = {}
            options["legend"] = legend
        if isinstance(legend, dict):
            legend["placement"] = "bottom"
    elif ptype == "graph":
        legend = panel.get("legend")
        if legend is None:
            legend = {}
            panel["legend"] = legend
        if isinstance(legend, dict):
            legend["rightSide"] = False


def mode_edit():
    data = json.load(sys.stdin)
    if not isinstance(data, dict) or not isinstance(data.get("response"), dict):
        sys.stderr.write("Could not edit the dashboard JSON.\n")
        sys.exit(1)
    response = data["response"]
    dash = response.get("dashboard")
    meta = response.get("meta") if isinstance(response.get("meta"), dict) else {}
    if not isinstance(dash, dict):
        sys.stderr.write("Could not edit the dashboard JSON.\n")
        sys.exit(1)
    provisioned = meta.get("provisioned") is True
    title = dash.get("title") if isinstance(dash.get("title"), str) else "dashboard"
    title = title.replace("\n", " ").replace("\r", " ")
    uid = dash.get("uid") if isinstance(dash.get("uid"), str) else ""
    folder = meta.get("folderUid") if isinstance(meta.get("folderUid"), str) else ""
    folder = folder.replace("\n", "").replace("\r", "")
    hide = data.get("hide") if isinstance(data.get("hide"), list) else []
    unhide = data.get("unhide") if isinstance(data.get("unhide"), list) else []
    reset = data.get("reset") is True
    legend = data.get("legend") is True
    panels = count_string_panels(dash.get("panels"))
    removed = []
    lines = []
    if not provisioned:
        def edit(panel):
            clauses = []
            if is_string_panel(panel):
                if reset:
                    if strip_hides(panel, None, removed):
                        clauses.append("remove hide overrides")
                else:
                    hidden = []
                    shown = []
                    if unhide:
                        shown = strip_hides(panel, unhide, removed)
                    if hide:
                        hidden = add_hides(panel, hide)
                    if hidden:
                        clauses.append("hide " + ", ".join(sort_names(hidden)))
                    if shown:
                        clauses.append("show " + ", ".join(sort_names(shown)))
            if legend and legend_will_change(panel):
                clauses.append("legend -> bottom")
            if legend:
                apply_legend(panel)
            if clauses:
                lines.append(panel_label(panel) + ": " + "; ".join(clauses))
        before = json.dumps(dash, separators=(",", ":"), ensure_ascii=False)
        walk(dash.get("panels"), edit)
        after = json.dumps(dash, separators=(",", ":"), ensure_ascii=False)
        changed = before != after
    else:
        changed = False
    if not changed:
        lines = []
    if changed and not provisioned:
        bits = []
        if reset:
            bits.append("reset string hides")
        elif hide or unhide:
            bits.append("hide disconnected strings")
        if legend:
            bits.append("legend bottom")
        message = "dashboard-tune.sh"
        if bits:
            message = message + ": " + ", ".join(bits)
        post = {"dashboard": dash, "folderUid": folder, "overwrite": True, "message": message}
    else:
        post = None
        changed = False
    removed_line = "-"
    if removed:
        removed_line = ", ".join(sort_names(removed))
    sys.stdout.write(("1" if changed else "0") + "\n")
    sys.stdout.write(("1" if provisioned else "0") + "\n")
    sys.stdout.write(str(panels) + "\n")
    sys.stdout.write(uid + "\n")
    sys.stdout.write(folder + "\n")
    sys.stdout.write(title + "\n")
    sys.stdout.write(removed_line + "\n")
    sys.stdout.write(str(len(lines)) + "\n")
    for line in lines:
        sys.stdout.write(line + "\n")
    sys.stdout.write("---\n")
    if post is not None:
        json.dump(post, sys.stdout, separators=(",", ":"), ensure_ascii=False)
        sys.stdout.write("\n")


def mode_search():
    data = json.load(sys.stdin)
    if not isinstance(data, dict):
        return
    want = data.get("title")
    hits = data.get("hits")
    if not isinstance(hits, list):
        return
    for hit in hits:
        if not isinstance(hit, dict):
            continue
        if hit.get("type") not in (None, "dash-db"):
            continue
        uid = hit.get("uid")
        if not isinstance(uid, str) or UID_RE.match(uid) is None:
            continue
        if want is not None and hit.get("title") != want:
            continue
        sys.stdout.write(uid + "\n")


def mode_encode():
    json.dump(sys.stdin.read(), sys.stdout)


def mode_b64():
    import base64
    raw = sys.stdin.read().encode("utf-8")
    sys.stdout.write(base64.b64encode(raw).decode("ascii"))


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
                break
    sys.stdout.write("yes" if ok else "no")


def mode_message():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    if not isinstance(data, dict):
        return
    msg = data.get("message")
    if isinstance(msg, str):
        msg = msg.replace("\n", " ").replace("\r", " ")
        sys.stdout.write(msg[:200])


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "classify":
        mode_classify()
    elif mode == "edit":
        mode_edit()
    elif mode == "search":
        mode_search()
    elif mode == "encode":
        mode_encode()
    elif mode == "b64":
        mode_b64()
    elif mode == "can_save_actions":
        mode_can_save_actions()
    elif mode == "can_save_orgs":
        mode_can_save_orgs()
    elif mode == "message":
        mode_message()
    else:
        sys.stderr.write("dashboard-tune: internal error\n")
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.stderr.write("dashboard-tune: could not read the JSON.\n")
        sys.exit(1)
PYCODE
)

choose_python() {
    PY_MODE=""
    if command -v docker >/dev/null 2>&1; then
        if docker exec pypowerwall env -i \
            PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
            PYTHONIOENCODING=utf-8 \
            PYTHONUTF8=1 \
            python3 -c 'import sys' </dev/null >/dev/null 2>&1; then
            PY_MODE=docker
            return
        fi
    fi
    if command -v python3 >/dev/null 2>&1; then
        if env -i PATH="$PATH" PYTHONIOENCODING=utf-8 PYTHONUTF8=1 \
            python3 -c 'import sys' </dev/null >/dev/null 2>&1; then
            PY_MODE=python3
            return
        fi
    fi
    if command -v python >/dev/null 2>&1; then
        if env -i PATH="$PATH" PYTHONIOENCODING=utf-8 PYTHONUTF8=1 \
            python -c 'import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)' \
            </dev/null >/dev/null 2>&1; then
            PY_MODE=python
            return
        fi
    fi
    die "python3 is not available in the pypowerwall container or on this host."
}

# JSON goes on stdin. Credentials do not. The process environment is cleared
# so a password or token in this shell is not copied into Python.
run_python() {
    if [ "$PY_MODE" = "docker" ]; then
        docker exec -i pypowerwall env -i \
            PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
            PYTHONIOENCODING=utf-8 \
            PYTHONUTF8=1 \
            python3 -c "$PY_CODE" "$1"
        return
    fi
    if [ "$PY_MODE" = "python3" ]; then
        env -i PATH="$PATH" PYTHONIOENCODING=utf-8 PYTHONUTF8=1 \
            python3 -c "$PY_CODE" "$1"
        return
    fi
    env -i PATH="$PATH" PYTHONIOENCODING=utf-8 PYTHONUTF8=1 \
        python -c "$PY_CODE" "$1"
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
            --output "$_dest" \
            --write-out '%{http_code}' \
            "$_url" 2>/dev/null) || true
    else
        _code=$(curl --config "$CURL_CFG" --insecure \
            --output "$_dest" \
            --write-out '%{http_code}' \
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
    _tmp="/tmp/dashboard-tune-$$"
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
            --output "${_tmp}.out" \
            --write-out '%{http_code}' \
            "$_url" 2>/dev/null) || true
        if ! docker exec -u 0 grafana cat "${_tmp}.out" > "$_dest" 2>/dev/null; then
            : > "$_dest"
        fi
        docker exec -u 0 grafana rm -f "${_tmp}.cfg" "${_tmp}.json" "${_tmp}.out" >/dev/null 2>&1 || true
    else
        _code=$(docker exec -u 0 -i grafana curl --config - --insecure \
            --output "${_tmp}.out" \
            --write-out '%{http_code}' \
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
    # POST is not sent twice. A 412 or 403 from Grafana is the answer.
    # A refused host port (000) is tried again inside the container.
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
    local _dest _url _code _inner _running
    _dest=$1
    _url="http://localhost:${PW_HOST_PORT}/strings"
    _code=$(curl --silent --connect-timeout 5 --max-time 30 \
        --output "$_dest" --write-out '%{http_code}' \
        "$_url" 2>/dev/null) || true
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
This is what anonymous read-only access does (HTTP 403).
Run ./anonymous-access.sh and choose one:
  1) Username / Password
  2) Anonymous Read-Only (cannot save changes)
  3) Anonymous Read/Write
Or export GRAFANA_TOKEN from a service account with the Editor or Admin role.
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
        die "A password is required. Set GRAFANA_TOKEN to skip the prompt."
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
    if [ -n "${GRAFANA_TOKEN:-}" ]; then
        case "$GRAFANA_TOKEN" in
            *[$'\n\r"\\']*) die "GRAFANA_TOKEN contains a character this script will not send." ;;
        esac
        AUTH_HEADER="Bearer ${GRAFANA_TOKEN}"
        write_curl_cfg
        if ! auth_ok; then
            die "GRAFANA_TOKEN was rejected. Create a new service account token and export it again."
        fi
        return
    fi
    AUTH_HEADER=""
    write_curl_cfg
    grafana_request GET "/api/search?type=dash-db&limit=1" "" "$WORKDIR/probe.json"
    case "$HTTP_CODE" in
        2*)
            if auth_can_save; then
                return
            fi
            explain_403
            exit 1
            ;;
        401)
            prompt_basic
            if ! auth_ok; then
                die "Grafana rejected that login."
            fi
            ;;
        *)
            die "Grafana is not reachable at ${GF_SCHEME}://localhost:${GF_HOST_PORT} (HTTP ${HTTP_CODE})."
            ;;
    esac
}

run_edit() {
    local _src _out
    _src=$1
    _out=$2
    {
        printf '%s' '{"hide":'
        printf '%s' "$HIDE_JSON"
        printf '%s' ',"unhide":'
        printf '%s' "$UNHIDE_JSON"
        printf '%s' ',"reset":'
        if [ "$RESET" -eq 1 ]; then
            printf '%s' 'true'
        else
            printf '%s' 'false'
        fi
        printf '%s' ',"legend":'
        if [ "$LEGEND" -eq 1 ]; then
            printf '%s' 'true'
        else
            printf '%s' 'false'
        fi
        printf '%s' ',"response":'
        cat "$_src"
        printf '%s' '}'
    } | run_python edit > "$_out"
}

load_edit_header() {
    local _file
    _file=$1
    EDIT_CHANGED=$(sed -n '1p' "$_file")
    EDIT_PROV=$(sed -n '2p' "$_file")
    EDIT_PANELS=$(sed -n '3p' "$_file")
    EDIT_UID=$(sed -n '4p' "$_file")
    EDIT_FOLDER=$(sed -n '5p' "$_file")
    EDIT_TITLE=$(sed -n '6p' "$_file")
    EDIT_REMOVED=$(sed -n '7p' "$_file")
    EDIT_N=$(sed -n '8p' "$_file")
    case "$EDIT_N" in
        ""|*[!0-9]*) die "Could not edit the dashboard JSON." ;;
    esac
    EDIT_MARK=$(sed -n "$((9 + EDIT_N))p" "$_file")
}

edit_body_to() {
    local _file _dest _start
    _file=$1
    _dest=$2
    _start=$((10 + EDIT_N))
    sed -n "${_start},\$p" "$_file" > "$_dest"
}

print_edit_details() {
    local _file _end
    _file=$1
    if [ "$EDIT_N" -eq 0 ]; then
        return
    fi
    _end=$((8 + EDIT_N))
    sed -n "9,${_end}p" "$_file"
}

process_uid() {
    local _uid _get _edit _post
    _uid=$1
    case "$_uid" in
        ""|*[!A-Za-z0-9_-]*) return ;;
    esac
    _get="$WORKDIR/get-${_uid}.json"
    _edit="$WORKDIR/edit-${_uid}.txt"
    _post="$WORKDIR/post-${_uid}.json"
    grafana_request GET "/api/dashboards/uid/${_uid}" "" "$_get"
    if [ "$HTTP_CODE" != "200" ]; then
        if [ -n "$ONLY_UID" ]; then
            die "No dashboard with uid ${_uid}."
        fi
        return
    fi
    if ! run_edit "$_get" "$_edit"; then
        die "Could not edit the dashboard JSON."
    fi
    load_edit_header "$_edit"
    if [ "$EDIT_MARK" != "---" ]; then
        die "Could not edit the dashboard JSON."
    fi
    case "$EDIT_CHANGED" in
        0|1) ;;
        *) die "Could not edit the dashboard JSON." ;;
    esac
    if [ "$EXPLICIT" -ne 1 ] && [ "$EDIT_PANELS" = "0" ]; then
        return
    fi
    if [ -z "$EDIT_UID" ]; then
        EDIT_UID=$_uid
    fi
    case "$EDIT_UID" in
        *[!A-Za-z0-9_-]*) die "Grafana returned an unexpected dashboard uid." ;;
    esac
    SEEN=$((SEEN + 1))
    if [ "$EDIT_PROV" = "1" ]; then
        printf '%s\n' "Skipping provisioned dashboard: ${EDIT_TITLE} (${EDIT_UID})"
        return
    fi
    if [ -n "$ONLY_TITLE" ] && [ "$EDIT_TITLE" != "$ONLY_TITLE" ]; then
        die "Dashboard ${EDIT_UID} is titled ${EDIT_TITLE}."
    fi
    edit_body_to "$_edit" "$_post"
    if [ "$EDIT_CHANGED" = "1" ]; then
        if [ ! -s "$_post" ]; then
            die "Could not edit the dashboard JSON."
        fi
        printf '%s\n' "Dashboard: ${EDIT_TITLE} (${EDIT_UID})"
        print_edit_details "$_edit"
        CHANGE_UID[${#CHANGE_UID[@]}]=$EDIT_UID
        CHANGE_POST[${#CHANGE_POST[@]}]=$_post
        return
    fi
    if [ "$EDIT_PANELS" = "0" ] && [ "$LEGEND" -ne 1 ] && [ "$RESET" -ne 1 ]; then
        printf '%s\n' "Dashboard: ${EDIT_TITLE} (${EDIT_UID})"
        printf '%s\n' "No String Voltage, String Current, or String Power panels."
        return
    fi
}

post_one() {
    local _uid _post _changed _prov _msg
    _uid=$1
    _post=$2
    grafana_request POST "/api/dashboards/db" "$_post" "$WORKDIR/post-res.json"
    if [ "$HTTP_CODE" = "412" ]; then
        grafana_request GET "/api/dashboards/uid/${_uid}" "" "$WORKDIR/retry-get.json"
        if [ "$HTTP_CODE" != "200" ]; then
            die "Grafana refused the save (HTTP 412) and the dashboard could not be read again."
        fi
        if ! run_edit "$WORKDIR/retry-get.json" "$WORKDIR/retry-edit.txt"; then
            die "Could not edit the dashboard JSON."
        fi
        load_edit_header "$WORKDIR/retry-edit.txt"
        if [ "$EDIT_MARK" != "---" ]; then
            die "Could not edit the dashboard JSON."
        fi
        _changed=$EDIT_CHANGED
        _prov=$EDIT_PROV
        if [ "$_prov" = "1" ]; then
            printf '%s\n' "Skipping provisioned dashboard: ${EDIT_TITLE} (${_uid})"
            return 0
        fi
        if [ "$_changed" != "1" ]; then
            return 0
        fi
        edit_body_to "$WORKDIR/retry-edit.txt" "$WORKDIR/retry-post.json"
        grafana_request POST "/api/dashboards/db" "$WORKDIR/retry-post.json" "$WORKDIR/post-res.json"
    fi
    case "$HTTP_CODE" in
        2*) return 0 ;;
        403)
            explain_403
            exit 1
            ;;
        *)
            _msg=$(run_python message < "$WORKDIR/post-res.json" 2>/dev/null || true)
            if [ -n "$_msg" ]; then
                die "Grafana did not save the dashboard (HTTP ${HTTP_CODE}): ${_msg}"
            fi
            die "Grafana did not save the dashboard (HTTP ${HTTP_CODE})."
            ;;
    esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --yes) ASSUME_YES=1 ;;
        --reset) RESET=1 ;;
        --legend-bottom) LEGEND=1 ;;
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
WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/dashboard-tune.XXXXXX") || die "Could not create a temp directory."
chmod 700 "$WORKDIR"
# EXIT covers a normal exit, die(), and set -e. The signal traps exit so
# Ctrl+C, TERM, and HUP run that same cleanup instead of continuing.
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

load_ports
choose_python
write_curl_cfg

if [ "$RESET" -ne 1 ]; then
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
    if [ "$STRING_ACTION" != "hide" ] && [ "$LEGEND" -ne 1 ]; then
        printf '%s\n' "$STRING_SUMMARY"
        exit 0
    fi
    if [ "$STRING_ACTION" != "hide" ]; then
        HIDE_JSON="[]"
        UNHIDE_JSON="[]"
    fi
fi

if [ -n "$STRING_SUMMARY" ]; then
    printf '%s\n' "$STRING_SUMMARY"
fi
if [ "$RESET" -eq 1 ]; then
    printf '%s\n' "Removing this script's string hides."
fi
if [ "$LEGEND" -eq 1 ]; then
    printf '%s\n' "Legend: bottom."
fi
printf '%s\n' "Grafana: ${GF_SCHEME}://localhost:${GF_HOST_PORT}"

establish_auth

if [ -n "$ONLY_UID" ]; then
    printf '%s\n' "$ONLY_UID" > "$WORKDIR/uids.txt"
else
    grafana_request GET "/api/search?type=dash-db&limit=5000" "" "$WORKDIR/search.json"
    if [ "$HTTP_CODE" != "200" ]; then
        die "Could not list dashboards (HTTP ${HTTP_CODE})."
    fi
    if [ -n "$ONLY_TITLE" ]; then
        _title_json=$(printf '%s' "$ONLY_TITLE" | run_python encode) || die "Could not read the dashboard title."
        {
            printf '%s' "{\"title\":${_title_json},\"hits\":"
            cat "$WORKDIR/search.json"
            printf '%s' '}'
        } | run_python search > "$WORKDIR/uids.txt" || die "Could not read Grafana's dashboard list."
        if [ ! -s "$WORKDIR/uids.txt" ]; then
            die "No dashboard titled ${ONLY_TITLE}."
        fi
    else
        {
            printf '%s' '{"title":null,"hits":'
            cat "$WORKDIR/search.json"
            printf '%s' '}'
        } | run_python search > "$WORKDIR/uids.txt" || die "Could not read Grafana's dashboard list."
    fi
fi

while IFS= read -r _one_uid; do
    process_uid "$_one_uid"
done < "$WORKDIR/uids.txt"

if [ "$SEEN" -eq 0 ]; then
    die "No imported dashboard has String Voltage, String Current, or String Power panels."
fi

if [ "${#CHANGE_POST[@]}" -eq 0 ]; then
    printf '%s\n' "No changes needed."
    exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "Dry run. No changes saved."
    exit 0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
    _response=""
    printf '%s' "Apply these changes? [y/N] " >&2
    read -r _response || true
    if [[ ! "$_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        printf '%s\n' "No changes applied."
        exit 0
    fi
fi

_i=0
while [ "$_i" -lt "${#CHANGE_POST[@]}" ]; do
    post_one "${CHANGE_UID[$_i]}" "${CHANGE_POST[$_i]}"
    _i=$((_i + 1))
done
printf '%s\n' "Saved."
