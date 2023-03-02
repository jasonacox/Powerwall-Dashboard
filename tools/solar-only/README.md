# Tesla Solar Only

This is a tool for Tesla Solar owners who don't have a Powerwall to get a similar dashboard for their systems. This uses the Tesla API to grab power metrics and store them in InfluxDB for rendering by Grafana.

Credit to @mcbirse for the `tesla-history` script that pulls the data from the Tesla Owner API and stores it into InfluxDB.

BETA

## Setup

This is currently in beta for testing.

```bash
# Download 
git clone https://github.com/jasonacox/Powerwall-Dashboard.git

# Select Solar Only
cd Powerwall-Dashboard/tools/solar-only

# Run setup
./setup.sh

TBD to get tesla-history working...

## Troubleshooting

TBD