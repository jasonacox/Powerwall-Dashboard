# Windows Installation Detailed Instructions

1. [Upgrading WSL1 to WSL2](#upgrading-wsl1-to-wsl2)
2. [Running without Docker Desktop](#running-without-docker-desktop)

## Upgrading WSL1 to WSL2

If you have previously tried out Windows Subsystem for Linux (WSL) on Windows 10, you may have the original WSL1 version installed.

For many reasons, you probably want to upgrade from WSL1 to WSL2.

To upgrade, you need to be running at least version 1093 of Windows 10 - you can check by running `winver`

If you happen to have installed WSL to play around, and have an old version around, you might want to update the version of that installed distro (but, then again, it might be an old distro, so that might not be the best idea; if it doesn't have anything useful, you might be better of starting with a brand new, up to date Ubuntu distro).

In any case, the best way to get the core WSL2 components installed, and updated is

```
wsl.exe --install
wsl.exe --update
```

To then check if you have any WSL 1 distros installed, you can run the `wsl -l -v` command that will show you the version of any distros

```
  NAME      STATE           VERSION
* Ubuntu    Running         2
```

If any are running version 1, you can upgrade them to version 1 with `wsl --set-version <distro-name> 2`, for example `wsl --set-version Ubuntu 2`


## Running without Docker Desktop

The host system will require:

* The Hyper-V server role must be installed (this can be installed on Windows Workstation - it doesn't need to be Windows Server)
* This works best with an accessible DHCP server like a home router that allows for DHCP reservations so that you can allocate a static lease and host name to your WSL VM
* You need a degree of familiarity with Powershell and Hyper-V
* If you want WSL and Powerwall Dashboard to automatically restart after a server reboot, you'll need a windows account with a password (a passwordless account will not work)
 
You will need to carry out this setup in several phases, and will need to **terminate WSL** in between several steps.

You will want several terminal windows open - [Windows Terminal](https://aka.ms/terminal) is ideal as you can configure it to start **administrative** sessions of command prompts, powershell, and regular sessions of command prompts, powershell, and Ubuntu (WSL) tabs.

### Install prerequisites
* Install Hyper-V Server Role (and tools) - from an **administrative** Powershell `Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart`

### Initial WSL Install / Update
* Install WSL and check that your preferred distro is running WSL 2 as per the instructions above at [Upgrading WSL1 to WSL2](#upgrading-wsl1-to-wsl2)

### Enable systemd
* Enable systemd
    * logged into WSL, `sudo nano /etc/wsl.conf`
    * Add the following section to this file
    
```
[boot]
systemd=true
```
* From a command prompt `wsl --shutdown`

### Enable Bridged Networking and DHCP Allocation
* Create a Virtual Network Bridge to enable your WSL instance to be accessible from the rest of your LAN
* From an **administrative** Powershell prompt
    * List Network Adaptors on your host the first item in each line is the name you'll use for creating the bridge (then status, then description)
    * `foreach ($net in Get-NetAdapter) {Write-Host $net.Name,":",$net.Status,":",$net.InterfaceDescription}`
    * Create a Virtual Switch for the appropriate (e.g. main / LAN) adaptor by name - use *WSLBridge* for example as the suggested name
    * LAN is the name of the network adaptor in the example below - use the name returned by the previous command, you might see something like Ethernet 2, Ethernet, or something else.  Surround with Double Quotes if the name has spaces.
    * `New-VMSwitch -Name WSLBridge -NetAdapterName LAN -AllowManagementOS $true`
    * If you are remoted into your server, you will lose connectivity momentarily, but it will reconnect.
* From an **administrative** Command (not Powershell) prompt
    * Change to the home directory `CD %userprofile%`
    * Edit (or create) .wslconfig `notepad .wslconfig`
    * Set up the .wslconfig as shown in the example below.  Explanation follows.
 
```
# Settings apply across all Linux distros running on WSL 2
[wsl2]
networkingMode = bridged
vmSwitch = WSLBridge
#ipv6 = true
#macAddress = AA:BB:CC:DD:EE:FF

# Enable experimental features
[experimental]
#sparseVhd=true
#autoMemoryReclaim=dropcache
```

* networkingMode = bridged enables bridged networking 
* vmSwitch = WSLBridge specifies the bridge to use, which in turn specifies the host adapter to bridge to
* ipv6 specifies whether or not to enable IPV6 networking.  Uncomment if you want to enable
* macAddress will be uncommented in a subsequent step once you've identified the MAC address assigned by the WSL VM
 
#### Experimental Features
Experimental Features require a preview version of WSL - install by `wsl --update; wsl --update --pre-release`
* sparseVhd enables SparseVHDs, which can save (a lot) of space in the VHDs
* autoMemoryReclaim enables memory reclamation, which can free up memory, particularly after docker builds

Once you have enabled these settings in .wslconfig, shutdown your WSL instance with `wsl --shutdown` from a command prompt, then re-start WSL
Log into WSL, and type `ip a`

You should see something like this - note the link/ether and inet values for eth0
```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether aa:bb:cc:dd:ee:ff brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.125/24 brd 192.168.1.255 scope global eth0
       valid_lft forever preferred_lft forever
```

Grab the mac address listed, and use this to set up a DHPC reservation in your router with a hostname (e.g. wsl2) and update your .wslconfig file with this mac address, and uncomment the line.
`wsl --shutdown` to shutdown WSL, then restart, and WSL should come up on the DHCP allocated IP address, and if you log in, `ip a` should show the new IP address.

Open up the firewall port that Grafana will use, so that it's ready on first run, for later: **administrator** command prompt:
`netsh advfirewall firewall add rule name= "Powerwall-Dashboard" dir=in action=allow protocol=TCP localport=9000`

### Docker Setup

The Docker installation reference [is here](https://docs.docker.com/engine/install/ubuntu/) but at the time of documentation, the following steps are correct:
* Remove any old versions: `for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done`
* Add Docker's official GPG Key
```
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources:
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
```
* Install Docker `sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`
* Check Docker Runs `sudo docker run hello-world`
* Create the Docker Group `sudo groupadd docker`
* Add your user to that group `sudo usermod -aG docker $USER`
* Log out of WSL, then log back in
* Check Docker Runs without SUDO `docker run hello-world`
* Configure Docker to start on WSL Startup
```
sudo systemctl enable docker.service
sudo systemctl enable containerd.service
sudo systemctl start docker.service
sudo systemctl start containerd.service
systemctl status docker.service
systemctl status containerd.service
```

### Create Windows Task Schedule Task to Restart WSL 

* Create a Task (don't choose Basic Task, so you can correctly set all the options) - see example screenshots below
    * Make sure you use the account that has set up WSL and this account has a password
    * Choose Run whether user is logged on or not
    * Configure for Windows 10
    * Name the task Windows 10
* Set up two triggers
    * Startup - Delay task for 1 Minute - to give Windows time to Boot
    * Statup - Delay task for 5 Minutes - this is a back up for the first task, just in case.
* Set up one action
    * Start a program
    * `wsl` for the program
    * Replace USERNAME in the argument with your linux username - usually all lower case `-u root -e sh -c "touch startup.log && service docker start && tmux new-session -d -s keepalive && /home/user/USERNAME/Powerwall-Dashboard/backfill.sh"`
* Modify the Conditions
    * Default Conditions should be OK - see example image below
* Modify the Settings
    * Allow Task to be Run on Demand
* Shutdown WSL
* Test the Task - WSL should Start
 
![image](https://github.com/BJReplay/Powerwall-Dashboard/assets/37993507/c21e35e1-24a2-41c2-b5d6-dd30503207b6)
![image](https://github.com/BJReplay/Powerwall-Dashboard/assets/37993507/e39603d8-dd8b-4676-be89-efd2b64f6d91)
![image](https://github.com/BJReplay/Powerwall-Dashboard/assets/37993507/e67f2caa-cb4b-44c2-85d7-6fd23935f212)
![image](https://github.com/BJReplay/Powerwall-Dashboard/assets/37993507/860d1486-06e2-4dee-9d41-e442a7fc52e6)
![image](https://github.com/BJReplay/Powerwall-Dashboard/assets/37993507/3119ed48-9e8c-44df-859e-fce27dfcbe7d)


### Powerwall-Dashboard Installation
Run the remainder of the Powerwall Dashboard Installation as per the Quick Start [README](README.md#option-1---quick-start) or Manual Installation 

