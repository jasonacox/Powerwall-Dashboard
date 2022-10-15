#!/bin/bash
#
# Convenience script for docker-compose
# Enables
#   - docker-compose and docker compose (v1, v2)
#   - moves multiple versions of unweildy compose invocation to one place
#   - very convenient for starting and stopping containers when developing.
# Takes up to two arguments, typicallly "up -d", "start", and "stop"
# Always verifies docker and docker-compose, as it is run infrequently.
# by Jason Cox - 21 Jan 2022

# Stop on Errors
set -e

# Docker Dependency Check
if ! docker info > /dev/null 2>&1; then
    echo "ERROR: docker is not available or not runnning."
    echo "This script requires docker, please install and try again."
    exit 1
fi

echo "Running Docker Compose..."  
if docker-compose version > /dev/null 2>&1; then
    # Build Docker (v1)
    docker-compose --env-file ./compose.env -f powerwall.yml $1 $2
else
    if docker compose version > /dev/null 2>&1; then
        # Build Docker (v2)
        docker compose --env-file ./compose.env -f powerwall.yml $1 $2
    else
        echo "ERROR: docker-compose/docker compose is not available or not runnning."
        echo "This script requires docker-compose or docker compose."
        echo "Please install and try again."
        exit 1
    fi
fi
