import "date"
option task = { 
  name: "tesla_energy.alerts",
  every: 1m,
}

from(bucket: "raw_tesla_energy")
//for historical generation change start here, otherwise use -2m for previous minute final total
  |> range(start: date.truncate(t: -2m, unit: 1m), stop: date.truncate(t: now(), unit: 1m))
  |> filter(fn: (r) => r["_measurement"] == "alerts")
  |> drop(columns: ["host", "month", "url", "year"])
  |> aggregateWindow(every: 1m, fn: max, createEmpty: false)
  |> drop(columns: ["_start", "_stop"])
  |> to(bucket: "tesla_energy")
