#!/bin/bash
echo "Build and Push jasonacox/weather411 to DockerHub"
echo ""

# Determine version
VER=`grep "BUILD = " server.py | cut -d\" -f2`
echo "Version: ${VER}"

# Build jasonacox/weather411:x.y.z
echo "* BUILD jasonacox/weather411:${VER}"
docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 --push -t jasonacox/weather411:${VER} .
echo ""

# Build jasonacox/weather411:latest
echo "* BUILD jasonacox/weather411:latest"
docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 --push -t jasonacox/weather411:latest .
echo ""

# Verify
echo "* VERIFY jasonacox/weather411:latest"
docker buildx imagetools inspect jasonacox/weather411 | grep Platform
echo ""
