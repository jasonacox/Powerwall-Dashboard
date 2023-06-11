#!/bin/bash
#

echo " "
echo "Warning for developers: this script will delete any existing pwdusage container."
echo "However, is does not delete the pwdusage docker image." 
echo "For general end users, this is what you want to happen for trouble shooting." 
echo " "
read -r -p "Enter y/Y to run test> " response

if [[ "$response" =~ ^([yY])$ ]]
then
    # clean up any existing container.
    docker stop pwdusage
    docker rm pwdusage

    # Run the docker detached.
    docker run \
    -d \
    -p 9050:9050 \
    -e USAGE_JSON='/var/lib/pwdusage/usage.json' \
    --name pwdusage \
    -v ${PWD}:/var/lib/pwdusage \
    jasonacox/pwdusage

    echo " "
    read -r -p "Waiting. Please hit enter to clean up test container.> " response

    docker stop pwdusage
    docker rm pwdusage
else
    echo " "
    echo "Cancelled."
    echo " "
fi
