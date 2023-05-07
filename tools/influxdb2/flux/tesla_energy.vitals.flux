import "date"
import "regexp"
option task = { 
  name: "tesla_energy.vitals",
  every: 1m,
}

data = from(bucket: "raw_tesla_energy")
//for historical generation change start here, otherwise use -2m for previous minute final total
  |> range(start: date.truncate(t: -2m, unit: 1m), stop: date.truncate(t: now(), unit: 1m))
  |> filter(fn: (r) => r["_measurement"] == "http")
  |> drop(columns: ["host", "month", "url", "year"])

pinv = data
  |> filter(fn: (r) => r["_field"] =~ /PW[0-99]_PINV/)
  |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)

island = data
  |> filter(fn: (r) => r["_field"] =~ /ISLAND_/)
  |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)

meter = data
  |> filter(fn: (r) => r["_field"] =~ /METER_/)
  |> filter(fn: (r) => r["_field"] !~ /.*Life/)
  |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)

life = data
  |> filter(fn: (r) => r["_field"] =~ /_Life/)
  |> aggregateWindow(every: 1m, fn: last, createEmpty: false)

union(tables: [pinv, island, meter, life])
  |> drop(columns: ["_start", "_stop"])
  |> map(fn: (r) => ({r with _measurement: "vitals"}))
  |> to(bucket: "tesla_energy")