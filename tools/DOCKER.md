# Installing Docker for Powerwall-Dashboard

Docker is a requirement for running the Dashboard. This file contains some suggestions on how to get Docker installed and running on your host. The details can change over time due to OS and Docker updates. Hopefully this document will help you get started.

Request for help: Please open an issue or submit a pull request for add changes or additions that would help others.

## Ubuntu 20.4 and Ubuntu 22.10

If you plan to use a VirtualBox virtual machine to host your Ubuntu server:

* Oracle VM [VirtualBox](https://www.virtualbox.org/wiki/Downloads) - Download [Ubuntu 22.10](https://releases.ubuntu.com/kinetic/) Server ISO - Create VM 
* Changed Network mode to "Bridged Adapter" (allows VM to get its own DHCP IP on the local LAN)
* Standard install and activated SSH so you can remote in (ssh in to VM)

Docker Install

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

## MacOS

* Install Docker Desktop - [Instructions](https://docs.docker.com/desktop/install/mac-install/)

## Windows

Installing Powerwall-Dashboard on a Windows 11 host requires some additional setup. Install and Setup using administrator PowerShell or Windows Command Prompt:

* Install WSL ([Windows Subsystem for Linux](https://learn.microsoft.com/en-us/windows/wsl/install)) (wsl --install) with an OS (recommend Ubuntu)
* Install *Git for Windows* (https://gitforwindows.org/)
* Install *Docker Desktop* for Windows (https://www.docker.com/)
* From *Git Bash* prompt, Clone repo (`git clone https://github.com/jasonacox/Powerwall-Dashboard.git`)
* Run `cd Powerwall-Dashboard`
* Run `./setup.sh`

## Raspberry Pi - Raspbian OS

* Similar to Ubuntu Installation ...

```bash
# install dependencies
sudo apt update
sudo apt upgrade
sudo apt install apt-transport-https curl gnupg-agent ca-certificates software-properties-common -y

# install docker
curl -fsSL https://get.docker.com/ -o get-docker.sh
sudo sh get-docker.sh
sudo apt install -y docker-compose

# Add your user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Set docker to start on boot
sudo systemctl enable docker.service
sudo systemctl enable containerd.service

# install docker-compose
sudo pip3 install docker-compose
```

## Synology NAS and Rootless Docker

Docker is available on the Synology NAS devices.

* If you are having trouble getting this to work on a Synology NAS, view the resolution discovered in [Issue #22](https://github.com/jasonacox/Powerwall-Dashboard/issues/22) thanks to @jaydkay.
* If you are running docker as a non-privileged (rootless) user, please some setup help [here](https://github.com/jasonacox/Powerwall-Dashboard/issues/22#issuecomment-1254699603) thanks to @BuongiornoTexas.

## Others

...
