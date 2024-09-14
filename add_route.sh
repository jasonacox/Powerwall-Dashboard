#!/bin/bash
#
# add_route.sh
# Script to setup persistant TEDAPI Routing for Powerwall Dashboard
# Version: 1.0.0
# By Scott Hibbard  - 2024-09-14
#

CRONTAB="/var/spool/cron/crontabs/root"
PW_IP=""
SCRIPT_NAME="TDAPI_routing"
DIR="/root/scripts"

echo "Setup script for persistant Powerall Dashboard TEDAPI Interface network routing"
echo "-------------------------------------------------------------------------------"
echo
echo "This script will require root privileges to read & set a startup cron task."
read -r -p "Do you want to run this script? [Y/n] " response
if [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
	echo "Cancel"
	exit 1
fi

OS=$(uname -s)

if $(ip route | grep -qw "192.168.91.0/24"); then
	read -r -p "192.168.91.0/24 routing is already in routing table. Still want to run this? [y/N] " response
	if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
		echo "Cancel"
		exit 1
	fi
fi

# Running Linux?
if [[ "${OS}" == "Linux" ]]; then
	if ! sudo test -d ${DIR}; then
		sudo mkdir ${DIR}
		echo "Created folder ${DIR}."
	fi
	
	if [ -f ${DIR}/${SCRIPT_NAME}.sh ]; then
		echo "Boot script already exists."
	else
	    while [ "$PW_IP" == "" ]; do
   		    read -p 'Enter Powerwall IP Address: ' PW_IP
		done
	    echo ""
		cat > ${SCRIPT_NAME}.tmp << EOF
#!/bin/bash
declare -i i=0
while (( i < 15 )); do
    RETURN="\$(ip route add 192.168.91.0/24 via ${PW_IP} 2>&1)"
    if [ "\$RETURN" != "RTNETLINK answers: File exists" ]; then
        declare -i i=i+1
        sleep 1
    else
        RETURN="Success"
        break
    fi
done

# Uncomment the lines below to log results of executing this script
# NOW="\$(date)"
# echo "\${NOW}: result=\${RETURN}, delay=\${i}" >> ${DIR}/${SCRIPT_NAME}.log

EOF
	chmod 775 ${SCRIPT_NAME}.tmp
	sudo chown 0 ${SCRIPT_NAME}.tmp
	sudo mv ${SCRIPT_NAME}.tmp ${DIR}/${SCRIPT_NAME}.sh
	fi

	if ! $(sudo cat ${CRONTAB} | grep -qw ${DIR}/${SCRIPT_NAME}.sh); then
		sudo crontab -u root -l > ${SCRIPT_NAME}".cron"
		echo "@reboot ${DIR}/${SCRIPT_NAME}.sh" >> ${SCRIPT_NAME}".cron"
		sudo crontab -u root ${SCRIPT_NAME}".cron"
		rm ${SCRIPT_NAME}".cron"
		echo "Cron entry added."
	else
		echo "Cron line already exists."
	echo "Installation complete."
	fi

else
    echo "You are running '$OS', which is not supported in this script."
    echo "Maybe you could add code to support '$OS'!"
    exit 1
fi
