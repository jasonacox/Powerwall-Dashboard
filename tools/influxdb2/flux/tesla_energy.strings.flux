import "date"
import "regexp"

option task = {name: "tesla_energy.strings", every: 1m}

data =
    from(bucket: "raw_tesla_energy")
        //for historical generation change start here, otherwise use -2m for previous minute final total
        |> range(start: date.truncate(t: -2m, unit: 1m), stop: date.truncate(t: now(), unit: 1m))
        |> filter(fn: (r) => r["_measurement"] == "http")

withoutnum =
    data
        |> filter(fn: (r) => r["_field"] =~ /\A[A-D]_.*/)
        |> map(fn: (r) => ({r with _field: regexp.replaceAllString(v: r._field, r: /_/, t: "0_")}))

withnum =
    data
        |> filter(fn: (r) => r["_field"] =~ /\A[A-D][1-99]_.*/)

union(tables: [withoutnum, withnum])
    |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)
    |> drop(columns: ["host", "month", "url", "year"])
    |> map(fn: (r) => ({r with _measurement: "strings"}))
    |> drop(columns: ["_start", "_stop"])
    |> to(bucket: "tesla_energy")
