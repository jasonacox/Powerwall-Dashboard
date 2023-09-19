#!/bin/bash
# Shell script to create files depending on TZ value from templates

# This is an hidden option to not print warning message
#  used by setup.sh script and by upgrade.sh script when
#  updating from version without templates
if [ "$1" == "-y" ]; then
    PRINT_WARNING=false
    shift 1
fi

if [ $# -eq 0 ]; then
    echo "ERROR: No timezone supplied"
    echo
    echo "USAGE: ${0} {timezone}"
    exit
fi

export TZ=$1

TEMPLATES=(
    $(echo dashboards/*.json.template)
    influxdb/influxdb.sql.template
    telegraf.conf.template
)

if ${PRINT_WARNING:-true}; then
    echo "WARNING: the following files will be recreated from templates"
    echo "         using TZ=$TZ; any local changes will be lost."
    printf -- " - %s\n" "${TEMPLATES[@]%.template}"
    echo
    read -r -p "Continue anyway? [y/N] " response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        exit 1
    fi
fi

for template in "${TEMPLATES[@]}"; do
    envsubst '$TZ' < "${template}" > "${template%.template}"
done

# Record TZ value
echo "${TZ}" > tz
