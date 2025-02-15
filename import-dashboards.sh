#!/bin/bash

GF_ENV_FILE="grafana.env"

# Function to import the dashboards from dashboards/*.json, but we have to do a little variable replacing
# to make sure the provisioned data sources and variables are correct.
import_dashboards() {
    while true; do
        echo ""
        echo "Enter your average price per kWh. You can change this later in the dashboard variables."
        read -r -p "Cost per kWh [0.19] " avg_price_per_kwh
        if [[ -z "$avg_price_per_kwh" || "$avg_price_per_kwh" =~ ^[0-9]*\.[0-9]+$ ]]; then
            avg_price_per_kwh=${avg_price_per_kwh:-0.19}
            break
        else
            echo "Invalid input. Please enter a decimal number or press Enter to use the default."
        fi
    done

    mkdir -p ./grafana/dashboards || true
    cp dashboards/*.json ./grafana/dashboards/

    # Replace variables in dashboards
    for file in ./grafana/dashboards/*.json; do
        # Replace data source objects with just the name of the source
        perl -0777 -pi -e 's|"datasource":\s*\{[^}]*DS_INFLUXDB[^\n]*\s+\}|"datasource": "InfluxDB (auto provisioned)"|gs' "$file"
        perl -0777 -pi -e 's|"datasource":\s*\{[^}]*DS_SUN_AND[^\n]*\s+\}|"datasource": "DS_SUN_AND MOON"|gs' "$file"

        # Disable the built-in annotation, see https://github.com/grafana/grafana/issues/54574#issuecomment-1431696899
        sed -i '' "s|\"enable\": true|\"enable\": false|g" "$file"

        # Timezone variable
        sed -i '' "s|\${VAR_TZ}|\${tz}|g" "$file"
        CURRENT=`cat tz`
        perl -0777 -pi -e "s|\"query\": \"\\\${tz}\"|\"query\": \"$CURRENT\"|gs" "$file"

        # Cost variables
        sed -i '' "s|\${VAR_AVG_BUY_PER_KWH}|\${avg_buy_per_kwh}|g" "$file"
        perl -0777 -pi -e 's|"query": "\$\{avg_buy_per_kwh\}"|"query": "0.19"|gs' "$file"

        sed -i '' "s|\${VAR_AVG_SELL_PER_KWH}|\${avg_sell_per_kwh}|g" "$file"
        perl -0777 -pi -e 's|"query": "\$\{avg_sell_per_kwh\}"|"query": "0.19"|gs' "$file"

        sed -i '' "s|\${VAR_AVG_PER_KWH}|\${avg_per_kwh}|g" "$file"
        perl -0777 -pi -e 's|"query": "\$\{avg_per_kwh\}"|"query": "0.19"|gs' "$file"

        sed -i '' "s|0.19|${avg_price_per_kwh}|g" "$file"
    done

    echo "Import completed."
    echo ""
}

echo "Dashboard Setup"
echo "-----------------------------------------"

read -r -p "Would you like to import the default dashboards? [Y/n] " response
if [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
    echo "No dashboards will be imported."
    exit 0
else
    import_dashboards
fi

read -r -p "Would you like to configure a default dashboard? [Y/n] " response
if [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
    echo "No default dashboard will be set."
else
    # Prompt for default dashboard
    echo ""
    echo "Choose a default dashboard:"
    echo " 1 - Default Dashboard (Power Flow)"
    echo " 2 - Min-Mean-Max"
    echo " 3 - No Animation"
    echo " 4 - Solar Only"
    echo " (Press Enter to skip)"
    echo ""
    read -r -p "Select default dashboard [1] " dashboard_choice

    case $dashboard_choice in
        1)
            DASHBOARD_PATH="dashboard.json"
            ;;
        2)
            DASHBOARD_PATH="dashboard-min-mean-max.json"
            ;;
        3)
            DASHBOARD_PATH="dashboard-no-animation.json"
            ;;
        4)
            DASHBOARD_PATH="dashboard-solar-only.json"
            ;;
        "")
            echo "Using Default Dashboard"
            DASHBOARD_PATH="dashboard.json"
            ;;
        *)
            echo "Invalid choice. No default dashboard will be set."
            DASHBOARD_PATH=""
            ;;
    esac

    if [ -n "$DASHBOARD_PATH" ]; then
        echo "GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/var/lib/grafana/dashboards/${DASHBOARD_PATH}" >> "${GF_ENV_FILE}"
        echo ""
    fi
fi
