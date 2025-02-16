#!/bin/bash

GF_ENV_FILE="grafana.env"

# This script will enable anonymous access to the repository
echo "Anonymous Access Setup"
echo "-----------------------------------------"

function read_write_anonymous() {
    echo "" >> "${GF_ENV_FILE}"
    echo "# Read-Write Anonymous Access" >> "${GF_ENV_FILE}"
    echo "GF_AUTH_DISABLE_LOGIN_FORM=true" >> "${GF_ENV_FILE}"
    echo "GF_AUTH_ANONYMOUS_ENABLED=true" >> "${GF_ENV_FILE}"
    echo "GF_AUTH_ANONYMOUS_ORG_NAME=Main Org." >> "${GF_ENV_FILE}"
    echo "GF_AUTH_ANONYMOUS_ORG_ROLE=Admin" >> "${GF_ENV_FILE}"
    echo "GF_USERS_ALLOW_SIGN_UP=false" >> "${GF_ENV_FILE}"
}

function read_only_anonymous() {
    echo "" >> "${GF_ENV_FILE}"
    echo "# Read-Only Anonymous Access" >> "${GF_ENV_FILE}"
    echo "GF_FEATURE_TOGGLES_PUBLICDASHBOARDS=true" >> "${GF_ENV_FILE}"
    echo "GF_AUTH_ANONYMOUS_ENABLED=true" >> "${GF_ENV_FILE}"
    echo "GF_AUTH_ANONYMOUS_ORG_NAME=Main Org." >> "${GF_ENV_FILE}"
    echo "GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer" >> "${GF_ENV_FILE}"
}

# Function to remove existing settings
function remove_existing_settings() {
    if grep -q "^GF_FEATURE_TOGGLES_PUBLICDASHBOARDS" "${GF_ENV_FILE}"; then
        sed -i.bak '/^# Read-Only Anonymous Access/d' "${GF_ENV_FILE}"
        sed -i.bak '/^GF_FEATURE_TOGGLES_PUBLICDASHBOARDS/d' "${GF_ENV_FILE}"
        sed -i.bak '/^GF_AUTH_ANONYMOUS_ENABLED/d' "${GF_ENV_FILE}"
        sed -i.bak '/^GF_AUTH_ANONYMOUS_ORG_NAME/d' "${GF_ENV_FILE}"
        sed -i.bak '/^GF_AUTH_ANONYMOUS_ORG_ROLE/d' "${GF_ENV_FILE}"
        rm -f "${GF_ENV_FILE}.bak"
    fi
    if grep -q "^GF_AUTH_DISABLE_LOGIN_FORM" "${GF_ENV_FILE}"; then
        sed -i.bak '/^# Read-Write Anonymous Access/d' "${GF_ENV_FILE}"
        sed -i.bak '/^GF_AUTH_DISABLE_LOGIN_FORM/d' "${GF_ENV_FILE}"
        sed -i.bak '/^GF_AUTH_ANONYMOUS_ENABLED/d' "${GF_ENV_FILE}"
        sed -i.bak '/^GF_AUTH_ANONYMOUS_ORG_NAME/d' "${GF_ENV_FILE}"
        sed -i.bak '/^GF_AUTH_ANONYMOUS_ORG_ROLE/d' "${GF_ENV_FILE}"
        sed -i.bak '/^GF_USERS_ALLOW_SIGN_UP/d' "${GF_ENV_FILE}"
        rm -f "${GF_ENV_FILE}.bak"
    fi
}


read -r -p "Do you want to allow access to your dashboards without a login? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "What type of access do you want to allow?"
    echo ""
else
    remove_existing_settings
    echo ""
    exit 0
fi
echo " 1 - Read-Only (default)"
echo $' 2 - Read-Write Admin (\e[33m**WARNING:**\e[0m This may allow anyone on your network to edit your dashboards)'
echo " 3 - Nevermind, I don't want to enable anonymous access"
echo ""
read -r -p "Select mode: " access_choice

case $access_choice in
    1)
        remove_existing_settings
        read_only_anonymous

        # Feedback
        echo ""
        echo "Anonymous read-only access has been enabled."
        ;;
    2)
        remove_existing_settings
        read_write_anonymous

        # Feedback
        echo ""
        echo "Anonymous read-write access has been enabled."
        ;;
    3)
        echo "No anonymous access will be enabled."
        exit 0
        ;;
    *)
        remove_existing_settings
        read_only_anonymous
        ;;
esac
