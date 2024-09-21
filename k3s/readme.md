These are the config files I used to get this running on k3s. I'm using rook-ceph for storage and metallb to expose the dashboard on an ip. Any pvc will need to be updated to the storage of the cluster this is deployed on, and the grafana service will need to be updated to what is being used to expose services on that cluster as well.

You will need to manually import the influxdb.sql

example:
 kubectl get pods -n powerwall|grep influx
influxdb-5db4797475-b5z44      1/1     Running   0          3h35m

kubectl cp influxdb.sql -n powerwall influxdb-5db4797475-b5z44:/influxdb.sql
kubectl exec --stdin --tty -n powerwall influxdb-5db4797475-b5z44 -- /bin/bash
root@influxdb-5db4797475-b5z44:/# influx -import -path=influxdb.sql
