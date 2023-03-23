import "math"
import "date"

option task = {name: "tesla_energy.kwh", every: 1m}

lasthour =
    from(bucket: "tesla_energy")
        //for historical generation change start here, otherwise use -2h for previous hour final total
        |> range(start: date.truncate(t: -2h, unit: 1h), stop: date.truncate(t: now(), unit: 1h))
        |> filter(fn: (r) => r["_measurement"] == "instant_power")
        |> filter(
            fn: (r) =>
                r._field == "home" or r._field == "solar" or r._field == "grid" or r._field
                    ==
                    "to_grid" or r._field == "from_grid" or r._field == "powerwall" or r._field
                    ==
                    "to_powerwall" or r._field == "from_powerwall",
        )
        |> aggregateWindow(every: 1h, fn: integral, createEmpty: false)
        |> map(fn: (r) => ({r with _time: date.sub(d: 1h, from: r._time)}))
        |> map(fn: (r) => ({r with _measurement: "kwh"}))

livehour =
    from(bucket: "tesla_energy")
        |> range(start: date.truncate(t: now(), unit: 1h))
        |> filter(fn: (r) => r["_measurement"] == "instant_power")
        |> filter(
            fn: (r) =>
                r._field == "home" or r._field == "solar" or r._field == "grid" or r._field
                    ==
                    "to_grid" or r._field == "from_grid" or r._field == "powerwall" or r._field
                    ==
                    "to_powerwall" or r._field == "from_powerwall",
        )
        |> aggregateWindow(every: 1h, fn: integral, createEmpty: false)
        |> map(fn: (r) => ({r with _measurement: "kwh"}))
        |> map(fn: (r) => ({r with _time: date.truncate(t: now(), unit: 1h)}))

union(tables: [lasthour, livehour])
    |> map(fn: (r) => ({r with _value: r._value / 1000.0 / 3600.0}))
    |> to(bucket: "tesla_energy")
