import "date"
option task = { 
  name: "tesla_energy.pwtemps",
  every: 1m,
}

from(bucket: "raw_tesla_energy")
//for historical generation change start here, otherwise use -2m for previous minute final total
  |> range(start: date.truncate(t: -2m, unit: 1m), stop: date.truncate(t: now(), unit: 1m))
  |> filter(fn: (r) => r["_measurement"] == "http")
  |> filter(fn: (r) => r["_field"] =~ /PW[0-99]_temp/)
  |> drop(columns: ["host", "month", "url", "year"])
  |> aggregateWindow(every: 1m, fn: mean, createEmpty: false)
  |> map(fn: (r) => ({r with _time: date.sub(d: 1m, from: r._time)}))
  |> drop(columns: ["_start", "_stop"])
  |> map(fn: (r) => ({r with _measurement: "pwtemps"}))
  |> to(bucket: "tesla_energy")
