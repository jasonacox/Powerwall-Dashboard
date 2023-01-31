# DDL
# CQs only downsample new incoming data. This script will downsample existing raw data.
# USE powerwall
CREATE DATABASE powerwall
# cq_vitals7
SELECT mean(ISLAND_VL1N_Main) AS ISLAND_VL1N_Main, mean(ISLAND_VL2N_Main) AS ISLAND_VL2N_Main, mean(ISLAND_VL3N_Main) AS ISLAND_VL3N_Main INTO powerwall.vitals.:MEASUREMENT FROM (SELECT ISLAND_VL1N_Main, ISLAND_VL2N_Main, ISLAND_VL3N_Main FROM powerwall.raw.http) GROUP BY time(15s), month, year fill(linear)
