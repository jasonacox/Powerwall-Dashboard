import "math"
import "date"

option task = {name: "tesla_energy.instant_power", every: 1m, start: -3m}

data =
    from(bucket: "raw_tesla_energy")
        //for historical generation change start here, otherwise use -3m for previous minute final total
        |> range(start: date.truncate(t: -3m, unit: 1m), stop: date.truncate(t: now(), unit: 1m))
        |> filter(fn: (r) => r["_measurement"] == "http")
        |> filter(
            fn: (r) =>
                r._field == "load_instant_power" or r._field == "solar_instant_power" or r._field
                    ==
                    "battery_instant_power" or r._field == "site_instant_power" or r._field
                    ==
                    "percentage" or r._field == "grid_status" or r["_field"]
                    ==
                    "backup_reserve_percent",
        )
        |> map(fn: (r) => ({r with _measurement: "instant_power"}))
        |> drop(columns: ["host", "month", "url", "year"])

home =
    data
        |> filter(fn: (r) => r["_field"] == "load_instant_power")
        |> map(fn: (r) => ({r with _field: "home"}))
        |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)

solar =
    data
        |> filter(fn: (r) => r["_field"] == "solar_instant_power")
        |> map(fn: (r) => ({r with _field: "solar"}))
        |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)

grid =
    data
        |> filter(fn: (r) => r["_field"] == "site_instant_power")
        |> map(fn: (r) => ({r with _field: "grid"}))
        |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)

fromgrid =
    data
        |> filter(fn: (r) => r["_field"] == "site_instant_power")
        |> map(fn: (r) => ({r with _value: if r._value > 0 then math.abs(x: r._value) else 0.0}))
        |> map(fn: (r) => ({r with _field: "from_grid"}))
        |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)

togrid =
    data
        |> filter(fn: (r) => r["_field"] == "site_instant_power")
        |> map(fn: (r) => ({r with _value: if r._value < 0 then math.abs(x: r._value) else 0.0}))
        |> map(fn: (r) => ({r with _field: "to_grid"}))
        |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)

powerwall =
    data
        |> filter(fn: (r) => r["_field"] == "battery_instant_power")
        |> map(fn: (r) => ({r with _field: "powerwall"}))
        |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)

frompowerwall =
    data
        |> filter(fn: (r) => r["_field"] == "battery_instant_power")
        |> map(fn: (r) => ({r with _value: if r._value > 0 then math.abs(x: r._value) else 0.0}))
        |> map(fn: (r) => ({r with _field: "from_powerwall"}))
        |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)

topowerwall =
    data
        |> filter(fn: (r) => r["_field"] == "battery_instant_power")
        |> map(fn: (r) => ({r with _value: if r._value < 0 then math.abs(x: r._value) else 0.0}))
        |> map(fn: (r) => ({r with _field: "to_powerwall"}))
        |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)

percentage =
    data
        |> filter(fn: (r) => r["_field"] =~ /percent/)
        |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)

gridstatus =
    data
        |> filter(fn: (r) => r["_field"] == "grid_status")
        |> aggregateWindow(every: 1m, fn: min, createEmpty: false)

union(
    tables: [
        home,
        solar,
        grid,
        togrid,
        fromgrid,
        powerwall,
        topowerwall,
        frompowerwall,
        percentage,
        gridstatus,
    ],
)
    |> drop(columns: ["_start", "_stop"])
    |> to(bucket: "tesla_energy")
