#!/bin/bash

GF_ENV_FILE="grafana.env"

# This script will enable anonymous access to the repository
echo ""
echo "Anonymous Access Setup"
echo "-----------------------------------------"

read -r -p "Do you want to allow access to your dashboards without a login? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "What type of access do you want to allow?"
    echo ""
else
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
        echo "" >> "${GF_ENV_FILE}"
        echo "# Read-Only Anonymous Access" >> "${GF_ENV_FILE}"
        echo "GF_FEATURE_TOGGLES_PUBLICDASHBOARDS=true" >> "${GF_ENV_FILE}"
        echo "GF_AUTH_ANONYMOUS_ENABLED=true" >> "${GF_ENV_FILE}"
        echo "GF_AUTH_ANONYMOUS_ORG_NAME=Main Org." >> "${GF_ENV_FILE}"
        echo "GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer" >> "${GF_ENV_FILE}"
        ;;
    2)
        echo "" >> "${GF_ENV_FILE}"
        echo "# Read-Write Anonymous Access" >> "${GF_ENV_FILE}"
        echo "GF_AUTH_DISABLE_LOGIN_FORM=true" >> "${GF_ENV_FILE}"
        echo "GF_AUTH_ANONYMOUS_ENABLED=true" >> "${GF_ENV_FILE}"
        echo "GF_AUTH_ANONYMOUS_ORG_NAME=Main Org." >> "${GF_ENV_FILE}"
        echo "GF_AUTH_ANONYMOUS_ORG_ROLE=Admin" >> "${GF_ENV_FILE}"
        echo "GF_USERS_ALLOW_SIGN_UP=false" >> "${GF_ENV_FILE}"
        ;;
    3)
        echo "No anonymous access will be enabled."
        exit 0
        ;;
    *)
        echo "" >> "${GF_ENV_FILE}"
        echo "# Read-Only Anonymous Access" >> "${GF_ENV_FILE}"
        echo "GF_FEATURE_TOGGLES_PUBLICDASHBOARDS=true" >> "${GF_ENV_FILE}"
        echo "GF_AUTH_ANONYMOUS_ENABLED=true" >> "${GF_ENV_FILE}"
        echo "GF_AUTH_ANONYMOUS_ORG_NAME=Main Org." >> "${GF_ENV_FILE}"
        echo "GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer" >> "${GF_ENV_FILE}"
        ;;
esac
