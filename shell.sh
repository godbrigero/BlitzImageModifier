#!/bin/bash
# Helper script to attach to the running container and get a shell

CONTAINER_NAME="blitzimagemodifier-blitz-arm-full-1"

# Try to find the container
CONTAINER_ID=$(docker ps -q -f name=blitz-arm-full)

if [ -z "$CONTAINER_ID" ]; then
    echo "Container not running. Starting it now..."
    docker compose -f compose.arm.full.yml up -d
    sleep 3
    CONTAINER_ID=$(docker ps -q -f name=blitz-arm-full)
fi

if [ -z "$CONTAINER_ID" ]; then
    echo "Failed to start container. Please check docker compose logs."
    exit 1
fi

echo "Attaching to container..."
docker exec -it "$CONTAINER_ID" /bin/bash -l

