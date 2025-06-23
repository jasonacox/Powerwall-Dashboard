#!/bin/bash
# watchdog.sh - Restart pypowerwall container if it becomes unhealthy
# Usage: Run as a background process, via cron, or with the 'setup' option
#
# This script checks the health status of the 'pypowerwall' container every 5 minutes.
# If the container is unhealthy, it will be restarted.

CONTAINER="pypowerwall"
DEBUG=0

if [ "$1" = "-debug" ]; then
    DEBUG=1
    shift
fi

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 [-enable|-disable|-debug|-h|--help]"
    echo "  -enable       Add watchdog.sh to your crontab to run every 5 minutes."
    echo "  -disable      Remove watchdog.sh from your crontab."
    echo "  -debug        Print additional information when running the health check."
    echo "  -h/--help     Show this help message."
    echo ""
    echo "If no argument is given, checks pypowerwall health once and restarts if unhealthy."
    exit 0
fi

if [ "$1" = "-enable" ]; then
    # Check if watchdog.sh is already in the user's crontab (every 5 minutes)
    CRON_LINE="*/5 * * * * /bin/bash $PWD/watchdog.sh > /dev/null 2>&1"
    CRONTAB_EXISTS=$(crontab -l 2>/dev/null | grep -F "$PWD/watchdog.sh" | grep -q '*/5'; echo $?)
    if [ "$CRONTAB_EXISTS" -eq 0 ]; then
        echo "INSTALLED: watchdog.sh is already scheduled in your crontab to run every 5 minutes."
        exit 0
    fi
    echo "Watchdog Script Setup"
    echo "====================="
    echo ""
    echo "This script will monitor the health of the 'pypowerwall' Docker container."
    echo "If the container is found to be unhealthy, it will be automatically restarted."
    echo ""
    echo "Before proceeding, please ensure that you have the following:"
    echo "- Docker installed and running."
    echo "- The 'pypowerwall' container created and running."
    echo ""
    echo "This script will add a cron job to run the health check every 5 minutes."
    echo "You can disable this cron job later if you wish."
    echo ""
    read -p "Would you like to add it to your crontab? [y/N]: " yn
    case $yn in
        [Yy]*)
            (crontab -l 2>/dev/null; echo "*/5 * * * * /bin/bash $PWD/watchdog.sh > /dev/null 2>&1") | crontab -
            echo "DONE. Added watchdog.sh to your crontab."
            ;;
        *)
            echo "No changes made to your crontab."
            ;;
    esac
    exit 0
fi

if [ "$1" = "-disable" ]; then
    # Check if watchdog.sh is in the user's crontab
    CRON_PRESENT=$(crontab -l 2>/dev/null | grep -F "$PWD/watchdog.sh" | grep '*/5')
    if [ -z "$CRON_PRESENT" ]; then
        echo "No watchdog.sh crontab entry found. Nothing to remove."
        exit 0
    else
        echo "Watchdog Removal"
        echo "================"
        echo ""
        echo "INSTALLED:"
        echo "  watchdog.sh is currently scheduled in your crontab to run every 5 minutes."
        echo ""
        read -p "Are you sure you want to remove it from your crontab? [y/N]: " yn
        case $yn in
            [Yy]*)
                TMP_CRON=$(mktemp)
                crontab -l 2>/dev/null | grep -v "$PWD/watchdog.sh" > "$TMP_CRON"
                crontab "$TMP_CRON"
                rm -f "$TMP_CRON"
                echo "Removed watchdog.sh from your crontab."
                ;;
            *)
                echo "No changes made to your crontab."
                ;;
        esac
    fi
    exit 0
fi

if [ -n "$1" ]; then
    "$0" -h
    exit 1
fi

# Remove loop mode: just check once and exit
[ "$DEBUG" -eq 1 ] && echo "[DEBUG] Checking health status of container: $CONTAINER"
STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null)
[ "$DEBUG" -eq 1 ] && echo "[DEBUG] Health status: $STATUS"
if [ "$STATUS" = "unhealthy" ]; then
    echo "[$(date)] Restarting $CONTAINER (status: unhealthy)"
    [ "$DEBUG" -eq 1 ] && echo "[DEBUG] Running: docker restart $CONTAINER"
    docker restart "$CONTAINER"
else
    [ "$DEBUG" -eq 1 ] && echo "[DEBUG] $CONTAINER is healthy. No action taken."
fi
