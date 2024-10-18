# Powerwall Dashboard on Kubernetes

These config files can be used to get Powerwall Dashboard running on k3s. These files assume you are using metallb for ingress and rook-ceph for storage. You will need to update grafanaservice.yaml if you are using something other than metallb, and the pvc configs if you are using storage other than rook-ceph. Local storage pvc configs are provided for testing but should not be used in deployment.

Author: @cfoos

<img width="1012" alt="Screenshot 2024-09-27 130807" src="https://github.com/user-attachments/assets/386f6990-ef56-4148-b4cf-4a1a84e2db47">

## Configuration

Update the values in the following files

configmap.yaml update the following section with your powerwall details
```bash
  email: "user@domain.tld"
  password: "supersecurepass"
  host: "xx.xx.xx.xx"
  pwtz: "America/Chicago"
  timezone: "America/Chicago"
```

grafanadatasources.yaml update these with your lat/lon
```bash
                  "latitude": "xx.xxxx",
                  "longitude":"xx.xxxx"
```

weather411config.yaml add your api key, update lat/lon and set the units to your desired format
```bash
    APIKEY = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    LAT = xxx.xxxx
    LON = yyy.yyyy
    UNITS = metric
```

grafanaservice.yaml set the ip address you want grafana to have
```bash
  loadBalancerIP: xx.xx.xx.xx
```

## Deployment

You will first need to setup the namespace
```bash
kubectl apply -f namespace.yaml
```

Next is the configs and pvc's
```bash
kubectl apply -f configmap.yaml -f grafanadatasources.yaml -f grafanapvc.yaml -f influxdbpvc.yaml -f pypowerwallpvc.yaml -f telegrafconfig.yaml -f weather411config.yaml
```

Finally we can set up the deployments and the services so we can access them
```bash
kubectl apply -f grafanadeployment.yaml -f g
rafanaservice.yaml -f influxdbdeployment.yaml -f influxdbservice.yaml -f pypowerwalldeployment.yaml -f pypowerwallservice.yaml -f telegrafdeployment.yaml -f weather411deployment.yaml -f weather411service.yaml
```

Check the pods to see when they are all running, garafana can take a few minutes but everything should be up in under 5 minutes in most cases
```bash
kubectl get pods -n powerwall
```

Once all the pods are in a running state you can check the grafana service to verify your ip to access it.
```bash
root@k3stest:~/Powerwall-Dashboard/k3s# kubectl get services -n powerwall|grep grafana
grafana       LoadBalancer   10.43.179.85   192.168.2.125   3000:30466/TCP   28m
```

The second ip is the metallb load balancer ip and the first port is the exposed one so at this point assuming the grafana pod started without issues this install would be accessable at:
http://192.168.2.125:3000

Before we can do anything in grafana you need to get your influxdb pod name
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

Now you can log into grafana and add the influxdb data source
http://influxdb.powerwall:8086

1. From `Configuration\Data Sources` add `InfluxDB` database with:
  - Name: `InfluxDB`
  - URL: `http://influxdb.powerwall:8086`
  - Database: `powerwall`
  - Min time interval: `5s`
  - Click "Save & test" button

Once that is done you can add the dashboard
k3sdashboard.json



## Test Environment

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

From this point you can do the same install as above, but use the -local version of the pvc files.
