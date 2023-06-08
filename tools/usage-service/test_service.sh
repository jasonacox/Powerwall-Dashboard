#!/bin/bash
#
# Run the docker detached.
docker run \
-d \
-p 9050:9050 \
-e USAGE_JSON='/var/lib/pwdusage/usage.json' \
--name pwdusage \
-v ${PWD}:/var/lib/pwdusage \
jasonacox/pwdusage

echo "Hit enter when you are done testing to stop and delete the test container."
read -r -p "(This does not delete the pwdusage docker image)> " response

docker stop pwdusage
docker rm pwdusage
