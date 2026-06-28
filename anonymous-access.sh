#!/bin/bash

GF_ENV_FILE="grafana.env"

# This script configures dashboard access method for Grafana
echo "Dashboard Access Setup"
echo "-----------------------------------------"

# Function to remove existing anonymous access settings from grafana.env
function remove_existing_settings() {
    sed -i.bak \
        -e '/^# Read-Only Anonymous Access/d' \
        -e '/^# Read-Write Anonymous Access/d' \
        -e '/^GF_FEATURE_TOGGLES_PUBLICDASHBOARDS/d' \
        -e '/^GF_AUTH_DISABLE_LOGIN_FORM/d' \
        -e '/^GF_AUTH_ANONYMOUS_ENABLED/d' \
        -e '/^GF_AUTH_ANONYMOUS_ORG_NAME/d' \
        -e '/^GF_AUTH_ANONYMOUS_ORG_ROLE/d' \
        -e '/^GF_USERS_ALLOW_SIGN_UP/d' \
        "${GF_ENV_FILE}"
    rm -f "${GF_ENV_FILE}.bak"

    # Re-comment the built-in sample lines if they were uncommented
    sed -i.bak -E 's/^(GF_AUTH_ANONYMOUS_(ENABLED|ORG_NAME|ORG_ROLE))/#\1/' "${GF_ENV_FILE}"
    rm -f "${GF_ENV_FILE}.bak"
}

# Function to enable read-only anonymous access
function read_only_anonymous() {
    remove_existing_settings
    echo "" >> "${GF_ENV_FILE}"
    echo "# Read-Only Anonymous Access" >> "${GF_ENV_FILE}"
    echo "GF_FEATURE_TOGGLES_PUBLICDASHBOARDS=true" >> "${GF_ENV_FILE}"
    echo "GF_AUTH_ANONYMOUS_ENABLED=true" >> "${GF_ENV_FILE}"
    echo "GF_AUTH_ANONYMOUS_ORG_NAME=Main Org." >> "${GF_ENV_FILE}"
    echo "GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer" >> "${GF_ENV_FILE}"
}

# Function to enable read-write anonymous access
function read_write_anonymous() {
    remove_existing_settings
    echo "" >> "${GF_ENV_FILE}"
    echo "# Read-Write Anonymous Access" >> "${GF_ENV_FILE}"
    echo "GF_AUTH_DISABLE_LOGIN_FORM=true" >> "${GF_ENV_FILE}"
    echo "GF_AUTH_ANONYMOUS_ENABLED=true" >> "${GF_ENV_FILE}"
    echo "GF_AUTH_ANONYMOUS_ORG_NAME=Main Org." >> "${GF_ENV_FILE}"
    echo "GF_AUTH_ANONYMOUS_ORG_ROLE=Admin" >> "${GF_ENV_FILE}"
    echo "GF_USERS_ALLOW_SIGN_UP=false" >> "${GF_ENV_FILE}"
}

# Detect current access mode (1=password, 2=read-only, 3=read-write)
current_mode=1
if grep -q "^GF_AUTH_DISABLE_LOGIN_FORM=true" "${GF_ENV_FILE}" 2>/dev/null; then
    current_mode=3
elif grep -q "^GF_FEATURE_TOGGLES_PUBLICDASHBOARDS=true" "${GF_ENV_FILE}" 2>/dev/null; then
    current_mode=2
fi

# Display options
echo "Select Dashboard Access Method"
echo "  1) Username / Password [Default]"
echo "  2) Anonymous Read-Only"
echo "  3) Anonymous Read/Write"
echo ""
read -r -p "Enter your selection (or select 1 if you don't know) [current = ${current_mode}]: " choice

# Default to current mode on empty input
choice=${choice:-$current_mode}

case $choice in
    1)
        remove_existing_settings
        echo ""
        echo "Username / Password authentication enabled."
        ;;
    2)
        read_only_anonymous
        echo ""
        echo "Anonymous read-only access has been enabled."
        ;;
    3)
        read_write_anonymous
        echo ""
        echo -e "Anonymous read-write access has been enabled. \e[33mWARNING:\e[0m Anyone on your network can edit your dashboards."
        ;;
    *)
        echo ""
        echo "Invalid selection. Defaulting to Username / Password authentication."
        remove_existing_settings
        ;;
esac
