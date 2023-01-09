# Installing Docker for Powerwall-Dashboard

Docker is a requirement for running the Dashboard. This file contains some recommended steps to get Docker set up and running on your host.

## Ubuntu 20.4 and Ubuntu 22.10

### Virtual Machine

If you plan to use a VirtualBox virtual machine to host your Ubuntu server:

* Oracle VM [VirtualBox](https://www.virtualbox.org/wiki/Downloads) - Download [Ubuntu 22.10](https://releases.ubuntu.com/kinetic/) Server ISO - Create VM 
* Changed Network mode to "Bridged Adapter" (allows VM to get its own DHCP IP on the local LAN)
* Standard install and activated SSH so I can remote in (ssh in to VM)

### Docker Install

```bash
# install dependencies
sudo apt update
sudo apt upgrade
sudo apt install apt-transport-https curl gnupg-agent ca-certificates software-properties-common -y

# install docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
sudo apt install docker-ce docker-ce-cli containerd.io -y

# add local user to docker group so you can run docker commands
sudo usermod -aG docker $USER
newgrp docker

# install docker compose
sudo apt install docker-compose

# verify it is running
sudo systemctl status docker
docker ps

# make sure it starts on reboot
sudo systemctl enable docker

# Powerwall Dashboard Setup
git clone https://github.com/jasonacox/Powerwall-Dashboard.git
cd Powerwall-Dashboard/
./setup.sh 
```
