#!/bin/bash
#
echo "This script cleans up old versions of the pwdusage docker image,"
echo "and builds a new image using the latest version pwdusage from pypi."
echo "Normal end users should enter 'y' when asked to clean up."
echo "Developers should probably avoid this script - it's a bit terminal."
echo "-------------------------------------------------------------------"
echo ""
read -r -p "Clean up old versions of pwusage before building? (Y/n)>" response
if [[ "$response" =~ ^([yY])$ ]]
then
    echo ""
    # stop the container
    docker stop pwdusage
    # remove the container.
    docker rm pwdusage
    # Finally remove the old image.
    docker rmi jasonacox/pwdusage
else
    echo " "
fi

# For now, assume users will only ever want one build: latest
# (Unless we get a tonne of interest, this will be good enough for most of us.)
docker build -t jasonacox/pwdusage:latest .
