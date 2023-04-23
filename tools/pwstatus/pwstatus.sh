#!/bin/sh
###############################################################################
# Powerwall status monitor and API request dumper
#   Author: Michael Birse (for Powerwall-Dashboard by Jason A. Cox)
#   For more information see https://github.com/jasonacox/Powerwall-Dashboard
#
# Request mode:
#   request Powerwall API URL(s) and return JSON result
#
# Monitor mode:
#   monitor status of grid, battery percentage, and firmware version
#   send e-mail alert when changes detected or low battery reached
#
# Configuration:
#   /etc/pwstatus.conf
###############################################################################

usage()
{
    echo "Powerwall status monitor and API request dumper

- Request Powerwall API URL(s) and return JSON result, or
- Monitor status of grid, battery percentage, and firmware version and
  send e-mail alert when changes detected or low battery reached

Usage: `basename $0` [options] APIURL(s)...
   or: `basename $0` [options] <-m|--monitor|-b|--background>

Mode selection and options include:
 -m, --monitor        Run in monitor mode with output to stdout
 -b, --background     Run in monitor mode with output to logfile
 -c, --config <file>  Read config from file (default /etc/pwstatus.conf)

Examples:

Request single API URL:
    `basename $0` api/status | jq .  (pipe to jq for pretty output)

Request multiple API URLs in a single command:
    `basename $0` api/system_status/grid_status api/system_status/soe | jq -s .
        (pipe to jq with slurp option to place each result into an array)

Run in monitor mode with output to stdout:
    `basename $0` --monitor

Run in monitor mode with output to logfile specified in /etc/pwstatus.conf
    `basename $0` --background
        (useful for running as a system service, i.e. using start-stop-daemon)

Specify alternative configuration file:
    `basename $0` -c /home/powerwall/pwstatus.conf --monitor" >&2

    exit 2
}

CFGFILE="/etc/pwstatus.conf"
monitor=0
background=0

while [ $# -gt 0 ]
do
    arg="$1"

    case "$arg" in
        -m|--monitor )              monitor=1; shift;;
        -b|-bm|-mb|--background )   monitor=1; background=1; shift;;
        -c|--config )               CFGFILE="$2"; shift; shift;;
        -h|--help )                 usage;;
        * )                         break;;
    esac
done

if ( [ $monitor -eq 0 ] && [ $# -eq 0 ] ) || ( [ $monitor -eq 1 ] && [ $# -ne 0 ] )
then
    usage
fi

if [ ! -r "$CFGFILE" ]
then
    echo "Error reading config from '$CFGFILE'" >&2
    exit 1
else
    . "$CFGFILE"

    case "$SHAREFILES" in
        YES|Yes|yes|Y|y )   SHAREFILES="YES"; umask 0000;;
        * )                 SHAREFILES="NO";;
    esac

    case "$USEPROXY" in
        YES|Yes|yes|Y|y )   USEPROXY="YES";;
        * )                 USEPROXY="NO";;
    esac

    case "$FALLBACK" in
        YES|Yes|yes|Y|y )   FALLBACK="YES";;
        * )                 FALLBACK="NO";;
    esac

    if [ -z "$PWPROXY" ] && [ "$USEPROXY" = "YES" ]
    then
        echo "Config error: PWPROXY address not defined" >&2
        exit 1
    elif [ ! -z "$PWPROXY" ]
    then
        PWPROXY="${PWPROXY%*/}"
    fi

    if [ -z "$POWERWALL" ] && ( [ "$USEPROXY" = "NO" ] || [ "$USEPROXY" = "YES" ] && [ "$FALLBACK" = "YES" ] )
    then
        echo "Config error: POWERWALL address not defined" >&2
        exit 1
    fi

    if [ -z "$PASSWORD" ] && ( [ "$USEPROXY" = "NO" ] || [ "$USEPROXY" = "YES" ] && [ "$FALLBACK" = "YES" ] )
    then
        echo "Config error: Powerwall PASSWORD not defined" >&2
        exit 1
    fi

    if [ -z "$USERNAME" ] && ( [ "$USEPROXY" = "NO" ] || [ "$USEPROXY" = "YES" ] && [ "$FALLBACK" = "YES" ] )
    then
        USERNAME="customer"
    fi

    if [ -z "$EMAIL" ] && ( [ "$USEPROXY" = "NO" ] || [ "$USEPROXY" = "YES" ] && [ "$FALLBACK" = "YES" ] )
    then
        EMAIL="email@example.com"
    fi

    if [ -z "$COOKIE" ]
    then
        echo "Config error: COOKIE file not defined" >&2
        exit 1
    elif [ $( touch "$COOKIE" > /dev/null 2>&1; echo $? ) -ne 0 ] || [ ! -w "$COOKIE" ]
    then
        echo "Config error: COOKIE file '$COOKIE' not writable" >&2
        exit 1
    fi

    if [ -z "$GRIDSTATUS" ]
    then
        echo "Config error: GRIDSTATUS file not defined" >&2
        exit 1
    elif [ $( touch "$GRIDSTATUS" > /dev/null 2>&1; echo $? ) -ne 0 ] || [ ! -w "$GRIDSTATUS" ]
    then
        echo "Config error: GRIDSTATUS file '$GRIDSTATUS' not writable" >&2
        exit 1
    fi

    if [ -z "$VERSION" ]
    then
        echo "Config error: VERSION file not defined" >&2
        exit 1
    elif [ $( touch "$VERSION" > /dev/null 2>&1; echo $? ) -ne 0 ] || [ ! -w "$VERSION" ]
    then
        echo "Config error: VERSION file '$VERSION' not writable" >&2
        exit 1
    fi

    case "$SHAREFILES" in
        YES )   chmod 666 "$COOKIE" "$GRIDSTATUS" "$VERSION" > /dev/null 2>&1;;
        NO )    chmod 644 "$COOKIE" "$GRIDSTATUS" "$VERSION" > /dev/null 2>&1;;
    esac

    if [ -z "$FROM" ]
    then
        FROM="Powerwall"
    fi

    if [ -z "$SLEEP" ] || [ $SLEEP -lt 1 ]
    then
        SLEEP=5
    fi

    if [ -z "$RETRY" ] || [ $RETRY -lt 1 ]
    then
        RETRY=10
    fi

    if [ -z "$BATTLOW" ] || [ $BATTLOW -lt 0 ] || [ $BATTLOW -gt 99 ]
    then
        BATTLOW=0
    fi

    if [ -z "$BATTCRIT" ] || [ $BATTCRIT -lt 0 ] || [ $BATTCRIT -gt 99 ] || [ $BATTCRIT -ge $BATTLOW ]
    then
        BATTCRIT=0
    fi

    if [ -z "$CHKVERHR" ] || [ $CHKVERHR -lt 0 ] || [ $CHKVERHR -gt 23 ]
    then
        CHKVERHR=0
    fi
fi

if [ $background -eq 0 ]
then
    LOGFILE=""
elif [ ! -z "$LOGFILE" ] && ( [ $( touch "$LOGFILE" > /dev/null 2>&1; echo $? ) -ne 0 ] || [ ! -w "$LOGFILE" ] )
then
    echo "Config error: LOGFILE file '$LOGFILE' not writable" >&2
    exit 1
else
    chmod 644 "$LOGFILE" > /dev/null 2>&1
fi


###############################################################################
# Function definitions
###############################################################################

log_msg()
{
    if [ $monitor -eq 1 ]
    then
        if [ -z "$LOGFILE" ]
        then
            echo [$( date +"%Y-%m-%d %H:%M:%S" )] "$@"
        else
            ( umask 0022; echo [$( date +"%Y-%m-%d %H:%M:%S" )] "$@" >> "$LOGFILE" )
        fi
    fi
}

log_exit()
{
    trap '' INT QUIT TERM EXIT

    log_msg "Stopping `basename $0` ..."
    exit
}

send_alert()
{
    if [ $monitor -eq 0 ] || [ -z "$1" ]
    then
        return
    fi

    log_msg "Sending alert to $1 - $2: $3"

    body="$( printf "%s\n" \
            "EvnTime: $( date +"%Y-%m-%d %H:%M:%S" )" \
            "Message: $3" \
            "Details: $4" )"

    err="$( echo -e "$body" | mail -s "$2" "$1" -F "$FROM" 2>&1 )"
    rv=$?

    if [ $rv -ne 0 ]
    then
        log_msg "Mail command returned error code $rv: $err"
    fi
}

pw_login()
{
    while [ 1 ]
    do
        log_msg "Logging in and saving cookie to '$COOKIE'"

        now=$( date +"%s" )

        if [ $(( now - lastlogin )) -lt $SLEEP ]
        then
            wait=$(( SLEEP - (now - lastlogin) ))

            log_msg "Waiting $wait seconds before login attempt"

            sleep $wait &
            wait $!
        fi

        lastlogin=$( date +"%s" )

        rm -f "$COOKIE" > /dev/null 2>&1
        result="$( curl -s -S -m 10 --fail-early -k -c "$COOKIE" -X POST -H "Content-Type: application/json" -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\", \"email\":\"$EMAIL\",\"force_sm_off\":false}" "https://$POWERWALL/api/login/Basic" 2>&1 )"

        if [ $? -ne 0 ] || [ $( echo "$result" | jq 'empty' > /dev/null 2>&1; echo $? ) -ne 0 ] || [ ! -z "$( echo "$result" | jq -r '.code // empty' )" ]
        then
            log_msg "Login failed: $result"

            if [ $monitor -eq 0 ]
            then
                return
            fi

            if [ $loginfail -eq 0 ]
            then
                loginfail=1

                send_alert "$ERRORS" \
                    "Login failed" \
                    "Unable to login" \
                    "$result"
            fi

            log_msg "Waiting $RETRY seconds before login retry"

            sleep $RETRY &
            wait $!
            continue
        else
            log_msg "Login successful: $result"

            if [ $loginfail -eq 1 ]
            then
                loginfail=0

                send_alert "$ERRORS" \
                    "Login successful" \
                    "Login has now succeeded" \
                    "$result"
            fi
            return
        fi
    done
}

get_stats()
{
    while [ 1 ]
    do
        stats=""

        for stat in $@
        do
            if [ "${stat:0:1}" = "/" ]
            then
                stat="${stat:1}"
            fi

            if [ $proxyactive -eq 1 ]
            then
                apiurl="$PWPROXY"

                if [ "$stat" = "api/system_status/soe" ]
                then
                    stat="soe"
                elif [ "$stat" = "soe" ]
                then
                    stat="api/system_status/soe"
                fi
            else
                apiurl="https://$POWERWALL"
            fi
            stats="$stats $apiurl/$stat"
        done

        log_msg "Requesting from $apiurl: $@"

        if [ $proxyactive -eq 1 ]
        then
            result="$( curl -s -S -m 10 --fail-early -k $stats 2>&1 )"
        else
            result="$( curl -s -S -m 10 --fail-early -k -b "$COOKIE" $stats 2>&1 )"
        fi

        if [ $? -ne 0 ] || [ $( echo "$result" | jq 'empty' > /dev/null 2>&1; echo $? ) -ne 0 ]
        then
            log_msg "Request from $apiurl failed: $result"

            if [ $monitor -eq 0 ]
            then
                if [ $proxyactive -eq 1 ] && [ "$FALLBACK" = "YES" ]
                then
                    proxyactive=0
                    continue
                else
                    return
                fi
            fi

            if [ $proxyactive -eq 1 ] && [ "$FALLBACK" = "YES" ]
            then
                if [ $proxyfail -eq 0 ]
                then
                    send_alert "$ERRORS" \
                        "Proxy request failed" \
                        "Request via proxy for $( echo $@ ) failed, switching to direct" \
                        "$result"
                fi
                proxyfail=1
                proxyactive=0
                continue
            fi

            if [ $requestfail -eq 0 ]
            then
                requestfail=1
                chkvernow=1

            elif [ $requestfail -eq 1 ]
            then
                requestfail=2

                send_alert "$ERRORS" \
                    "Request failed" \
                    "Request for $( echo $@ ) failed" \
                    "$result"
            fi

            log_msg "Waiting $RETRY seconds before request retry"

            sleep $RETRY &
            wait $!
            continue

        elif [ ! -z "$( echo "$result" | jq -sr '.[].code? // empty' )" ]
        then
            log_msg "Error code from $apiurl returned: $result"

            if [ $proxyactive -eq 1 ] && [ "$FALLBACK" = "YES" ]
            then
                if [ $proxyfail -eq 0 ]
                then
                    send_alert "$ERRORS" \
                        "Proxy error code returned" \
                        "Request via proxy for $( echo $@ ) returned error, switching to direct" \
                        "$result"
                fi
                proxyfail=1
                proxyactive=0
                continue
            fi

            if [ $errcodefail -eq 0 ]
            then
                errcodefail=1

            elif [ $errcodefail -eq 1 ]
            then
                errcodefail=2

                send_alert "$ERRORS" \
                    "Error code returned" \
                    "Request for $( echo $@ ) returned error" \
                    "$result"
            fi

            if [ $proxyactive -eq 0 ]
            then
                pw_login
            else
                if [ $monitor -eq 0 ]
                then
                    return
                fi

                log_msg "Waiting $RETRY seconds before request retry"

                sleep $RETRY &
                wait $!
            fi
            continue
        else
            log_msg "Got response: $result"

            if [ $requestfail -eq 2 ] || [ $errcodefail -eq 2 ]
            then
                send_alert "$ERRORS" \
                    "Request successful" \
                    "Request for $( echo $@ ) has now succeeded" \
                    "$result"
            fi
            requestfail=0
            errcodefail=0

            if [ $proxyfail -eq 1 ] && [ $proxyactive -eq 0 ]
            then
                proxyactive=1

            elif [ $proxyfail -eq 1 ] && [ $proxyactive -eq 1 ]
            then
                proxyfail=0

                send_alert "$ERRORS" \
                    "Proxy request successful" \
                    "Request via proxy for $( echo $@ ) has now succeeded, switching back to proxy" \
                    "$result"
            fi
            return
        fi
    done
}

###############################################################################
# Main program start
###############################################################################

lastlogin=0
loginfail=0
requestfail=0
errcodefail=0
proxyfail=0
proxyactive=0
battlowalert=0
battcritalert=0
lastverchk=0
chkvernow=1

trap log_exit INT QUIT TERM EXIT

log_msg "Starting `basename $0` ..."
log_msg "   CFGFILE    = $CFGFILE"
log_msg "   POWERWALL  = $POWERWALL"
log_msg "   USERNAME   = $USERNAME"
log_msg "   PASSWORD   = $PASSWORD"
log_msg "   EMAIL      = $EMAIL"
log_msg "   PWPROXY    = $PWPROXY"
log_msg "   USEPROXY   = $USEPROXY"
log_msg "   FALLBACK   = $FALLBACK"
log_msg "   COOKIE     = $COOKIE"
log_msg "   GRIDSTATUS = $GRIDSTATUS"
log_msg "   VERSION    = $VERSION"
log_msg "   SHAREFILES = $SHAREFILES"
log_msg "   FROM       = $FROM"
log_msg "   ALERTS     = $ALERTS"
log_msg "   ERRORS     = $ERRORS"
log_msg "   SLEEP      = $SLEEP"
log_msg "   RETRY      = $RETRY"
log_msg "   BATTLOW    = $BATTLOW"
log_msg "   BATTCRIT   = $BATTCRIT"
log_msg "   CHKVERHR   = $CHKVERHR"

if [ "$USEPROXY" = "YES" ]
then
    proxyactive=1
fi

if [ ! -s "$COOKIE" ] && [ "$USEPROXY" = "NO" ]
then
    log_msg "Error reading cookie from '$COOKIE'"
    pw_login
fi

# request stats from command line and exit immediately
#
if [ $monitor -eq 0 ]
then
    get_stats $@
    echo "$result"
    exit
fi

if [ -s "$GRIDSTATUS" ]
then
    grid_status_old="$( cat "$GRIDSTATUS" )"
else
    get_stats "api/system_status/grid_status"
    grid_status_old="$( echo "$result" | jq -sr '.[0].grid_status' )"
    echo "$grid_status_old" > "$GRIDSTATUS"
fi

if [ -s "$VERSION" ]
then
    version_old="$( cat "$VERSION" )"
else
    get_stats "api/status"
    version_old="$( echo "$result" | jq -sr '.[0].version' )"
    echo "$version_old" > "$VERSION"
    chkvernow=0
fi


###############################################################################
# Main program loop
###############################################################################
#
# monitor status of grid, battery percentage, and firmware version
# send e-mail alert when changes detected or low battery reached
#
while [ 1 ]
do
    if [ $chkvernow -eq 1 ] || ( [ $( date +"%H" ) -eq $CHKVERHR ] && [ $( date +"%Y%m%d" ) -ne $lastverchk ] )
    then
        if [ $chkvernow -eq 1 ]
        then
            chkvernow=0
        else
            lastverchk=$( date +"%Y%m%d" )
        fi

        get_stats "api/system_status/grid_status" "api/system_status/soe" "api/status"

        version="$( echo "$result" | jq -sr '.[2].version' )"
        uptime="$( echo "$result" | jq -sr '.[2].up_time_seconds' )"

        if [ "$version" != "$version_old" ]
        then
            log_msg "Firmware version changed from $version_old to $version"

            send_alert "$ALERTS" \
                "Firmware updated" \
                "Firmware version has been updated" \
                "Version changed from $version_old to $version\nUp time: $uptime"

            version_old="$version"
            echo "$version" > "$VERSION"
        fi
    else
        get_stats "api/system_status/grid_status" "api/system_status/soe"
    fi

    grid_status="$( echo "$result" | jq -sr '.[0].grid_status' )"
    percentage="$( echo "$result" | jq -sr '.[1].percentage' )"
    percentscl="$( echo "($percentage / 0.95) - (5 / 0.95)" | bc -l )"
    percentrnd=$( printf "%.0f" "$percentscl" )

    if [ "${percentrnd:0:1}" = "-" ]
    then
        percentrnd=0
    fi

    if [ "$grid_status" != "$grid_status_old" ]
    then
        log_msg "Grid status changed from $grid_status_old to $grid_status"

        case "$grid_status" in

            "SystemTransitionToIsland" )

                send_alert "$ALERTS" \
                    "Going off-grid ($percentrnd% charged)" \
                    "Transitioning to off-grid" \
                    "Status changed from $grid_status_old to $grid_status\nBattery: $percentrnd% charged"
                ;;

            "SystemIslandedReady" )

                send_alert "$ALERTS" \
                    "Ready for off-grid ($percentrnd% charged)" \
                    "Ready to go off-grid" \
                    "Status changed from $grid_status_old to $grid_status\nBattery: $percentrnd% charged"
                ;;

            "SystemIslandedActive" )

                send_alert "$ALERTS" \
                    "Grid outage ($percentrnd% charged)" \
                    "Power outage detected" \
                    "Status changed from $grid_status_old to $grid_status\nBattery: $percentrnd% charged"
                ;;

            "SystemMicroGridFaulted" )

                send_alert "$ALERTS" \
                    "Grid outage (Powerwall disconnected)" \
                    "Powerwall breaker may be off" \
                    "Status changed from $grid_status_old to $grid_status\nBattery: $percentrnd% charged"
                ;;

            "SystemWaitForUser" )

                send_alert "$ALERTS" \
                    "Grid outage (Powerwall inactive)" \
                    "Powerwall inactive due to low charge" \
                    "Status changed from $grid_status_old to $grid_status\nBattery: $percentrnd% charged"
                ;;

            "SystemTransitionToGrid" )

                send_alert "$ALERTS" \
                    "Returning to grid ($percentrnd% charged)" \
                    "Transitioning back to grid" \
                    "Status changed from $grid_status_old to $grid_status\nBattery: $percentrnd% charged"
                ;;

            "SystemGridConnected" )

                send_alert "$ALERTS" \
                    "Grid restored ($percentrnd% charged)" \
                    "Power has been restored" \
                    "Status changed from $grid_status_old to $grid_status\nBattery: $percentrnd% charged"
                ;;

            * )
                send_alert "$ALERTS" \
                    "Grid unknown ($percentrnd% charged)" \
                    "Grid status changed to unknown value" \
                    "Status changed from $grid_status_old to $grid_status\nBattery: $percentrnd% charged"
                ;;
        esac
        grid_status_old="$grid_status"
        echo "$grid_status" > "$GRIDSTATUS"
    fi

    if [ $percentrnd -gt 0 ]
    then
        if [ $percentrnd -le $BATTCRIT ] && [ $battcritalert -eq 0 ]
        then
            battlowalert=1
            battcritalert=1

            send_alert "$ALERTS" \
                "Battery critical ($percentrnd% charged)" \
                "Battery charge level is critical" \
                "Grid status is $grid_status\nBattery: $percentrnd% charged"

        elif [ $percentrnd -le $BATTLOW ] && [ $battlowalert -eq 0 ]
        then
            battlowalert=1

            send_alert "$ALERTS" \
                "Battery low ($percentrnd% charged)" \
                "Battery charge level is low" \
                "Grid status is $grid_status\nBattery: $percentrnd% charged"

        elif [ $percentrnd -gt $BATTLOW ] && [ $battlowalert -eq 1 ]
        then
            battlowalert=0
            battcritalert=0

            send_alert "$ALERTS" \
                "Battery charging ($percentrnd% charged)" \
                "Battery charge level is recovering" \
                "Grid status is $grid_status\nBattery: $percentrnd% charged"
        fi
    fi

    sleep $SLEEP &
    wait $!
done
