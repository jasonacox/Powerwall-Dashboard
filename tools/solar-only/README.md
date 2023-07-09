# Tesla Solar Only 

This is a tool for Tesla Solar owners who don't have a Powerwall to get a similar dashboard for their systems. This uses the Tesla API to grab power metrics and store them in InfluxDB for rendering by Grafana.

![Screenshot (2)](https://github.com/jasonacox/Powerwall-Dashboard/assets/20891340/3f954359-e851-462e-ba20-e1ad90db5bd7)

Thanks to @Jot18 for example dashboard screenshot. Thanks and credit to @mcbirse for the `tesla-history` script that pulls the data from the Tesla Owner API and stores it into InfluxDB.

***BETA:*** This is currently under development. You are welcome to join the conversation in Issue [#183](https://github.com/jasonacox/Powerwall-Dashboard/issues/183).

## Setup

This is currently in beta for testing.

```bash
# Download 
git clone https://github.com/jasonacox/Powerwall-Dashboard.git

# Select Solar Only
cd Powerwall-Dashboard/tools/solar-only

# Run setup
./setup.sh

# Import Tesla Data 
# TODO: to get tesla-history working... see https://github.com/jasonacox/Powerwall-Dashboard/issues/183

```

## Troubleshooting

TBD
