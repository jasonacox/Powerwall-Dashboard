#!/bin/bash

# Determine version
VER=`grep "BUILD = " server.py | cut -d\" -f2`
echo "Build and Push jasonacox/weather411:${VER} to DockerHub"
echo ""

# Build jasonacox/weather411:x.y.z
echo "* BUILD jasonacox/weather411:${VER}"
docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 --push -t jasonacox/weather411:${VER} .
echo ""

echo "* VERIFY jasonacox/weather411:${VER}"
docker buildx imagetools inspect jasonacox/weather411:${VER} | grep Platform
echo ""
