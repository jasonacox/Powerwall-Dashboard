# Powerwall Status Monitor and API Request Dumper

This tool is a shell script designed to run as a system service to monitor status of grid, battery percentage, and firmware version, and send an e-mail alert when changes are detected or low battery reached. It is also useful as a command line API request dumper.

* Author: [@mcbirse](https://github.com/mcbirse)
* Discussion: [#249](https://github.com/jasonacox/Powerwall-Dashboard/discussions/249)
* Script: [pwstatus.sh](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/tools/pwstatus/pwstatus.sh)

## Features

The script uses curl to poll the Powerwall Gateway with API requests to monitor status of grid, battery percentage, and firmware version. When changes are detected or a low battery condition reached, an alert is sent via e-mail (NOTE: this is achieved by using the system "mail" command and therefore requires the host system to be configured to send e-mail, for example by installing and configuring postfix or a similar mail package).

Currently, the script monitors for firmware version changes, grid status changes, and configurable low or critical battery levels. With the script running, you should receive an e-mail within approximately 5-10 seconds for a grid status change, and within a minute after a firmware upgrade has occurred.

Powerwall-Dashboard is not required to use the script, however when installed and the pyPowerwall proxy is running, the script will utilise this to reduce load on the gateway, and can automatically fall back to sending requests direct to the gateway if pyPowerwall stops responding.

The script has been written to be very lightweight with minimal system requirements. It will work with simple Unix shells such as BusyBox Ash, and additional package requirements have been kept to a minimum. Use of curl has been optimised to be efficient when sending multiple API requests, such that these are sent in a single command to use a persistent HTTP/HTTPS session, thereby further minimising load on the gateway.

As well as the monitoring capabilities, the script can be used as a simple and convenient tool to dump results of API requests sent to the Powerwall Gateway directly from the command line.

## Requirements

The requirements and configuration examples below are based on a minimal Alpine Linux install, as this was the platform I used to develop the script. Requirements and configuration will vary based on your chosen platform. Please submit a PR or join discussion [#249](https://github.com/jasonacox/Powerwall-Dashboard/discussions/249) if you would like to add setup instructions or provide guidance for other platforms.

The script requires the following additional packages to be installed:

* curl
* jq
* mail (e.g. postfix & mailx)

Install missing packages with the appropriate package manager for your system, i.e. for Alpine Linux the above packages can be installed by running the apk package manager.

```sh
# Install required packages
apk add curl
apk add jq
apk add postfix
apk add mailx
```

Configure your host system to be able to send e-mail via the "mail" command from the user account the script will be running as. [Here](https://www.howtoforge.com/tutorial/configure-postfix-to-use-gmail-as-a-mail-relay/) is an example guide to configure postfix to use Gmail as a Mail Relay, very similar to the setup I used in Alpine Linux.

## Script configuration

Copy the sample config file [pwstatus.conf.sample](https://github.com/jasonacox/Powerwall-Dashboard/blob/main/tools/pwstatus/pwstatus.conf.sample) and then edit the configuration for your Powerwall Gateway address, login credentials, pyPowerwall proxy address, and set config options as desired.

The default config file is expected to be `/etc/pwstatus.conf`, however an alternative config file can be specified with the `--config <file>` option when running the script.

```sh
# Copy sample config to /etc and edit for your setup
cp pwstatus.conf.sample /etc/pwstatus.conf
vi /etc/pwstatus.conf
```

### Installing as a system service

The script can be installed as a system service, so it will run permanently in the background and also start automatically on system boot.

You can skip this step if not required or if you wish to test the script beforehand.

<details><summary>Example system service installation for Alpine Linux (click to expand)</summary>

<p>

Additional config files may be required to install the script as a system service depending on your platform. Below is an example of how to install the script as a system service based on requirements for Alpine Linux, which uses the OpenRC init system. Please submit a PR or join discussion [#249](https://github.com/jasonacox/Powerwall-Dashboard/discussions/249) if you would like to add instructions or provide guidance for other platforms.

Copy the script to an appropriate location for your system, e.g. `/usr/local/bin`, and ensure it is executable.

```sh
# Copy script to location in path
cp pwstatus.sh /usr/local/bin/pwstatus.sh
chmod 755 /usr/local/bin/pwstatus.sh
```

Create an init script, for example `/etc/init.d/pwstatus`

```sh
#!/sbin/openrc-run
description="Powerwall status monitor"
command="/usr/local/bin/pwstatus.sh"
pidfile="/run/${RC_SVCNAME}.pid"

depend() {
	need net
	use mta
	after firewall
}

start()	{
	if [ -z "${CFGFILE}" ]
	then
		ARGS="--background"
	else
		ARGS="--config ${CFGFILE} --background"
	fi

	if [ -z "${STDERRLOG}" ]
	then
		STDERR=""
	else
		STDERR="--stderr ${STDERRLOG}"
	fi

	ebegin "Starting ${RC_SVCNAME}"
	start-stop-daemon --wait 1000 --background --start --exec "${command}" \
	    --make-pidfile --pidfile "${pidfile}" ${STDERR} \
	    -- ${ARGS}
	eend $?
}

stop() {
	ebegin "Stopping ${RC_SVCNAME}"
	start-stop-daemon --retry 15000 --stop \
		--pidfile "${pidfile}"
   	eend $?
}
```

Create a configuration file for the init script, for example `/etc/conf.d/pwstatus`

```sh
# pwstatus configuration file to use
CFGFILE="/etc/pwstatus.conf"

# redirect stderr to logfile
STDERRLOG="/var/log/pwstatus.log"
```

You may wish to consider using logrotate to rotate and archive the log file so it doesn't grow forever and consume all disk space. Below is an example logrotate config for the script's log file.

Create a logrotate config file, for example `/etc/logrotate.d/pwstatus`

```sh
/var/log/pwstatus.log {
	missingok
	notifempty
}
```

With the system config files in place, the script can be installed as a service so it will run automatically on system boot. On Alpine Linux, this can be done as below.

```sh
# Install pwstatus as a system service and start the service
rc-update add pwstatus
rc-service pwstatus start
```

</p>
</details>

<details><summary>Example system service installation on Debian Bookworm (click to expand)</summary>
<br>

Below is an example of how to install the script as a system service based on requirements for Debian Bookworm.  Debian Bookworm uses the `systemd` init system and system manager.

Copy the script to an appropriate location for your system (e.g. `/usr/local/bin`) and ensure it is executable.

```sh
# Copy script to location in path
cp pwstatus.sh /usr/local/bin/pwstatus.sh 
chmod 755 /usr/local/bin/pwstatus.sh
```

#### Create service
Create an systemd service (e.g., `/etc/systemd/system/pwstatus.service`) and edit this file:
``` 
sudo nano /etc/systemd/system/pwstatus.service 
```

Add this text and save:

```
[Unit]
Description=custom service for Powerwall status monitor (pwstatus)
After=multi-user.target
Requires=network.target
Requires=network-online.target

[Service]
Type=idle

User=root
ExecStart=/usr/bin/bash /usr/local/bin/pwstatus.sh --config /etc/pwstatus.conf --background

Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
```

After saving change the file permissions:
```
sudo chmod 644 /etc/systemd/system/pwstatus.service 
```


#### Log rotate
You may wish to consider using logrotate to rotate and archive the log file so it doesn't grow forever and consume all disk space. Below is an example logrotate config for the script's log file.

Create a logrotate config file, for example `/etc/logrotate.d/pwstatus` and edit the file:


``` 
sudo nano /etc/logrotate.d/pwstatus 
```

Add this text and save:

```sh
/var/log/pwstatus.log
{
	rotate 7
	weekly
	missingok
	notifempty
	compress
	delaycompress
}
```

With the system config files in place, the script can be enabled as a service so it will run automatically on system boot. On Debian Bookworm, this can be done as below:

```sh
# Enable pwstatus as a system service and start the service
sudo systemctl enable pwstatus.service
sudo systemctl start pwstatus.service
sudo systemctl daemon-reload
```

</details>

## Usage

The script can be run in two different modes: monitor mode, or request mode.

In request mode, the script will simply request the specified API URL(s) from the Powerwall Gateway and return the JSON result.

Before running in monitor mode or as a system service, it is recommended to test the script first in request mode to ensure it is configured for your gateway and operating correctly.

For example, to request the current Powerwall battery percentage, run as below.

```sh
# Request Powerwall battery percentage
pwstatus.sh api/system_status/soe | jq .
```

Output can be piped to the command `jq .` to format the JSON result.

```json
{
  "percentage": 40.43307389997688
}
```

Multiple API requests can be sent in a single command.

```sh
# Request multiple API URLs in a single command
pwstatus.sh api/system_status/grid_status api/system_status/soe | jq -s .
```

Output can be piped to the command `jq -s .` (slurp option) to format multiple JSON results into an array.

```json
[
  {
    "grid_status": "SystemGridConnected",
    "grid_services_active": false
  },
  {
    "percentage": 43.39215535177622
  }
]
```

Once confirmed basic API requests are working correctly, the script should function in monitor mode (i.e. continually monitor status and send e-mail alerts on changes). Before starting the script as a system service, the monitor mode option could be used to run with output to stdout.

```sh
# Run in monitor mode with output to stdout
pwstatus.sh --monitor
```

To test the functionality of the script, including e-mail alerts, the example below shows script execution in monitor mode while the pyPowerwall proxy is not running, with config options "USEPROXY" and "FALLBACK" enabled.

Since pyPowerwall is not running, this will cause the script to fall back to sending API requests directly to the gateway, which ensures the login & API request to the gateway is working. An alert e-mail will also be triggered advising the request to the pyPowerwall proxy failed, which will test the e-mail alert functionality.

```log
[2023-04-20 21:38:52] Starting pwstatus.sh ...
[2023-04-20 21:38:52]    CFGFILE    = /etc/pwstatus.conf
[2023-04-20 21:38:52]    POWERWALL  = 192.168.91.1
[2023-04-20 21:38:52]    USERNAME   = customer
[2023-04-20 21:38:52]    PASSWORD   = XXXXX
[2023-04-20 21:38:52]    EMAIL      = yourname@example.com
[2023-04-20 21:38:52]    PWPROXY    = http://localhost:8675
[2023-04-20 21:38:52]    USEPROXY   = YES
[2023-04-20 21:38:52]    FALLBACK   = YES
[2023-04-20 21:38:52]    COOKIE     = /var/tmp/pwcookie
[2023-04-20 21:38:52]    GRIDSTATUS = /var/tmp/pwgridstatus
[2023-04-20 21:38:52]    VERSION    = /var/tmp/pwversion
[2023-04-20 21:38:52]    SHAREFILES = YES
[2023-04-20 21:38:52]    FROM       = Powerwall
[2023-04-20 21:38:52]    ALERTS     = yourname@example.com
[2023-04-20 21:38:52]    ERRORS     = yourname@example.com
[2023-04-20 21:38:52]    SLEEP      = 5
[2023-04-20 21:38:52]    RETRY      = 10
[2023-04-20 21:38:52]    BATTLOW    = 15
[2023-04-20 21:38:52]    BATTCRIT   = 10
[2023-04-20 21:38:52]    CHKVERHR   = 7
[2023-04-20 21:38:52] Requesting from http://localhost:8675: api/system_status/grid_status
[2023-04-20 21:38:52] Request from http://localhost:8675 failed: curl: (7) Failed to connect to localhost port 8675 after 0 ms: Couldn't connect to server
[2023-04-20 21:38:52] Sending alert to yourname@example.com - Proxy request failed: Request via proxy for api/system_status/grid_status failed, switching to direct
[2023-04-20 21:38:52] Requesting from https://192.168.91.1: api/system_status/grid_status
[2023-04-20 21:38:52] Error code from https://192.168.91.1 returned: {"code":403,"error":"Unable to GET to resource","message":"User does not have adequate access rights"}
[2023-04-20 21:38:52] Logging in and saving cookie to '/var/tmp/pwcookie'
[2023-04-20 21:38:53] Login successful: {"email":"yourname@example.com","firstname":"Tesla","lastname":"Energy","roles":["Home_Owner"],"token":"XXXXXXX","provider":"Basic","loginTime":"2023-04-20T21:38:53.615545876+10:00"}
[2023-04-20 21:38:53] Requesting from https://192.168.91.1: api/system_status/grid_status
[2023-04-20 21:38:54] Got response: {"grid_status":"SystemGridConnected","grid_services_active":false}
[2023-04-20 21:38:54] Requesting from http://localhost:8675: api/status
[2023-04-20 21:38:54] Request from http://localhost:8675 failed: curl: (7) Failed to connect to localhost port 8675 after 0 ms: Couldn't connect to server
[2023-04-20 21:38:54] Requesting from https://192.168.91.1: api/status
[2023-04-20 21:38:54] Got response: {"din":"XXXXXXX","start_time":"2023-04-12 13:39:14 +0800","up_time_seconds":"199h59m39.915343858s","is_new":false,"version":"22.36.9 c55384d2","git_hash":"c55384d2ab897aa8cc4fd28ba7943ec8a6a35609","commission_count":0,"device_type":"teg","teg_type":"unknown","sync_type":"v2","leader":"","followers":null,"cellular_disabled":false}
[2023-04-20 21:38:54] Requesting from http://localhost:8675: api/system_status/grid_status api/system_status/soe
[2023-04-20 21:38:54] Request from http://localhost:8675 failed: curl: (7) Failed to connect to localhost port 8675 after 0 ms: Couldn't connect to server
[2023-04-20 21:38:54] Requesting from https://192.168.91.1: api/system_status/grid_status api/system_status/soe
[2023-04-20 21:38:55] Got response: {"grid_status":"SystemGridConnected","grid_services_active":false}{"percentage":55.536705737199256}
```

If working correctly, the script should then be able to be run in background mode with output to the configured logfile. Generally, this would be started as a system service using the command below.

```sh
# Run in monitor mode with output to logfile specified in /etc/pwstatus.conf
pwstatus.sh --background
```

Check the logfile `/var/log/pwstatus.log` to confirm the script is monitoring the gateway correctly.

Once running, the script will continually poll the gateway for changes in grid status, firmware version, or low battery conditions, and send an e-mail alert when detected. Below is an example e-mail alert sent by the script when a firmware update was detected.

```
From: Powerwall <youremail@example.com>
Subject: Firmware updated
```

```
EvnTime: 2023-04-12 13:40:04
Message: Firmware version has been updated
Details: Version changed from 22.36.6 cf1839cb to 22.36.9 c55384d2
Up time: 50.170524281s
```

For full usage options and examples, run without arguments or with the `--help` option.

```sh
# Show usage options
pwstatus.sh --help
```

```
Powerwall status monitor and API request dumper

- Request Powerwall API URL(s) and return JSON result, or
- Monitor status of grid, battery percentage, and firmware version and
  send e-mail alert when changes detected or low battery reached

Usage: pwstatus.sh [options] APIURL(s)...
   or: pwstatus.sh [options] <-m|--monitor|-b|--background>

Mode selection and options include:
 -m, --monitor        Run in monitor mode with output to stdout
 -b, --background     Run in monitor mode with output to logfile
 -c, --config <file>  Read config from file (default /etc/pwstatus.conf)

Examples:

Request single API URL:
    pwstatus.sh api/status | jq .  (pipe to jq for pretty output)

Request multiple API URLs in a single command:
    pwstatus.sh api/system_status/grid_status api/system_status/soe | jq -s .
        (pipe to jq with slurp option to place each result into an array)

Run in monitor mode with output to stdout:
    pwstatus.sh --monitor

Run in monitor mode with output to logfile specified in /etc/pwstatus.conf
    pwstatus.sh --background
        (useful for running as a system service, i.e. using start-stop-daemon)

Specify alternative configuration file:
    pwstatus.sh -c /home/powerwall/pwstatus.conf --monitor
```

### Discussion Link

Join discussion [#249](https://github.com/jasonacox/Powerwall-Dashboard/discussions/249) if you have questions or find a problem with this script, or would like to contribute additional setup instructions or provide guidance for other platforms.
