# Installing Docker for Powerwall-Dashboard

Docker is a requirement for running the Dashboard. This file contains some suggestions on how to get Docker installed and running on your host. The details can change over time due to OS and Docker updates. Hopefully this document will help you get started.

Request for help: Please open an issue or submit a pull request for add changes or additions that would help others.

## Ubuntu

**Note:** For the most up-to-date Docker installation instructions, refer to the official Docker documentation at https://docs.docker.com/engine/install/ubuntu/

If you plan to use a VirtualBox virtual machine to host your Ubuntu server:

* Oracle VM [VirtualBox](https://www.virtualbox.org/wiki/Downloads) - Download [Ubuntu 22.10](https://releases.ubuntu.com/kinetic/) Server ISO - Create VM 
* Changed Network mode to "Bridged Adapter" (allows VM to get its own DHCP IP on the local LAN)
* Standard install and activated SSH so you can remote in (ssh in to VM)

Docker Install

```bash
# install dependencies
sudo apt update
sudo apt upgrade
sudo apt install ca-certificates curl

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update

# Install Docker
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# add local user to docker group so you can run docker commands
sudo usermod -aG docker $USER
newgrp docker

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
```

## Synology NAS and Rootless Docker

Docker is available on the Synology NAS devices.

* If you are having trouble getting this to work on a Synology NAS, view the resolution discovered in [Issue #22](https://github.com/jasonacox/Powerwall-Dashboard/issues/22) thanks to @jaydkay.
* If you are running docker as a non-privileged (rootless) user, please some setup help [here](https://github.com/jasonacox/Powerwall-Dashboard/issues/22#issuecomment-1254699603) thanks to @BuongiornoTexas.

## Others

...
