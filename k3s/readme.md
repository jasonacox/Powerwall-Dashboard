These are the config files I used to get this running on k3s. I'm using rook-ceph for storage and metallb to expose the dashboard on an ip. Any pvc will need to be updated to the storage of the cluster this is deployed on, and the grafana service will need to be updated to what is being used to expose services on that cluster as well.

You will need to manually import the influxdb.sql

example:
 kubectl get pods -n powerwall|grep influx
influxdb-5db4797475-b5z44      1/1     Running   0          3h35m

kubectl cp influxdb.sql -n powerwall influxdb-5db4797475-b5z44:/influxdb.sql
kubectl exec --stdin --tty -n powerwall influxdb-5db4797475-b5z44 -- /bin/bash
root@influxdb-5db4797475-b5z44:/# influx -import -path=influxdb.sql




To test this you can use a Raspberry pi 4 4G with a thumb drive. Install Ubuntu server 24.04 onto the thumb drive using the rpi imager and ssh to it.

sudo su - into root and run:
```bash
sed -i '$ s/$/ cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory/' /boot/firmware/cmdline.txt
```
and this but remove the wifi part if you are using wifi as this turns it off
```bash
echo -e "dtoverlay=disable-wifi\ndtoverlay=disable-bt\ngpu_mem=16" >> /boot/firmware/config.txt
```
Then you will want to set your pi to have a static ip either in the config or on your dhcp server and update /etc/hosts to use that ip for the pi's hostname. You will also need to setup the ip routing for accessing the powerwall, I just set this on my router so I do not have to mess with individual machines.

Then you will need to run
```bash
apt install libraspberrypi-bin net-tools ntp snapd lvm2 build-essential golang git kubetail -y
```
followed by an upgrade and reboot
```bash
apt update
apt upgrade -y
reboot
```

Once the pi is back online you can install k3s, I sudo into root to do this.
```bash
curl -sfL http://get.k3s.io | sh -s - server --disable servicelb,traefik --cluster-init
```
and verify it is online by running
kubectl get nodes

Now for metallb so we can give grafana an ip run:
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.5/config/manifests/metallb-native.yaml
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
```
Then edit metallb-config.yml to set an ip range metallb can assign out and apply it and metalLbL2Advertise.yaml
```bash
kubectl apply -f metallb-config.yml
kubectl apply -f metalLbL2Advertise.yaml
```

Make sure all your pods are running with
```bash
kubectl get pods --all-namespaces
```

Now we can start with the powerwall stuff. First make the namespace
```bash
kubectl apply -f namespace.yaml
```
Then edit configmap.yaml to add your powerwall login and ip, grafanadatasources with your lat/lon for sun and moon plugin, grafanaservice.yaml with the ip you want grafana to have, and weather411config.yaml with your api and lat/lon.

Once that is done you can apply the configs and pvcs.
```bash
kubectl apply -f configmap.yaml -f grafanadatasources.yaml -f grafanapvc-local.yaml -f influxdbpvc-local.yaml -f pypowerwallpvc-local.yaml -f telegrafconfig.yaml -f weather411config.yaml
```

Then we can apply the deployments and services.
```bash
kubectl apply -f grafanadeployment.yaml -f g
rafanaservice.yaml -f influxdbdeployment.yaml -f influxdbservice.yaml -f pypowerwalldeployment.yaml -f pypowerwallservice.yaml -f telegrafdeployment.yaml -f weather411deployment.yaml -f weather411service.yaml
```

Check the pods to see when they are all running
```bash
kubectl get pods -n powerwall
```

Once all the pods are in a running state you can check the grafana service to verify your ip to access it.
```bash
root@k3stest:~/Powerwall-Dashboard/k3s# kubectl get services -n powerwall|grep grafana
grafana       LoadBalancer   10.43.179.85   192.168.2.125   3000:30466/TCP   28m
```
get your influxdb pod name
```bash
kubectl get pods -n powerwall|grep influx
influxdb-5db4797475-b548p      1/1     Running   1 (6m50s ago)   31m
```

copy the influxdb.sql into it
```bash
kubectl cp influxdb.sql -n powerwall influxdb-5db4797475-b548p:/influxdb.sql
```

Enter the pod, and import the db
```bash
kubectl exec --stdin --tty -n powerwall influxdb-5db4797475-b548p -- /bin/bash
root@influxdb-5db4797475-b548p:/# influx -import -path=influxdb.sql
```


log in and add the influxdb data source with url of
http://influxdb.powerwall:8086

then add the dashboard k3sdashboard.json
the dashboard still needs some work and the solar flow plugin is not very useful intill the latest version gets on github.
