#!/bin/bash
#CONTAINER="${PWD##*/}"
CONTAINER="pwdusage"
echo "Build and Push jasonacox/${CONTAINER} to DockerHub"
echo ""

# Determine version
VER=`curl --silent https://raw.githubusercontent.com/BuongiornoTexas/pwdusage/main/pyproject.toml | grep version | cut -d\" -f2 | cut -dv -f2`
echo "Version: ${VER}"

# Build jasonacox/CONTAINER:x.y.z
echo "* BUILD jasonacox/${CONTAINER}:${VER}"
docker buildx build --platform linux/amd64,linux/arm64 --push -t jasonacox/${CONTAINER}:${VER} .
echo ""

# Build jasonacox/CONTAINER:latest
echo "* BUILD jasonacox/${CONTAINER}:latest"
docker buildx build --platform linux/amd64,linux/arm64 --push -t jasonacox/${CONTAINER}:latest .
echo ""

# Verify
echo "* VERIFY jasonacox/${CONTAINER}:latest"
docker buildx imagetools inspect jasonacox/${CONTAINER} | grep Platform
echo ""
