#!/bin/bash
#
# Convenience script for docker-compose
# Enables
#   - docker-compose and docker compose (v1, v2)
#   - moves multiple versions of unweildy compose invocation to one place
#   - very convenient for starting and stopping containers when developing.
# Takes up to two arguments, typicallly "up -d", "start", and "stop"
# Always verifies docker and docker-compose, as it is run infrequently.
# by BuongiornoTexas 16 Oct 2022

# Stop on Errors
set -e

# Check for Arguments
if [ -z "$1" ]
  then
    echo "Powerwall-Dashboard helper script for docker-compose"
    echo ""
    echo "Usage:"
    echo "  ${0} [COMMAND] [ARG]"
    echo ""
    echo "Commands (see docker-compose for full list):"
    echo "  up -d              Create and start containers"
    echo "  start              Start services"
    echo "  stop               Stop services"
    exit 1
fi

# Docker Dependency Check
if ! docker info > /dev/null 2>&1; then
    echo "ERROR: docker is not available or not runnning."
    echo "This script requires docker, please install and try again."
    exit 1
fi

# Load enviroment variables for compose
set -a
. compose.env
set +a

echo "Running Docker Compose..."  
if docker-compose version > /dev/null 2>&1; then
    # Build Docker (v1)
    docker-compose -f powerwall.yml $1 $2
else
    if docker compose version > /dev/null 2>&1; then
        # Build Docker (v2)
    docker compose -f powerwall.yml $1 $2
    else
        echo "ERROR: docker-compose/docker compose is not available or not runnning."
        echo "This script requires docker-compose or docker compose."
        echo "Please install and try again."
        exit 1
    fi
fi
