#!/bin/bash

#set -e

echo "Building unsigned image and pushing to Quay"
echo "==========================================="
echo ""

# Get Quay route URL
echo "Retrieving Quay route URL..."
QUAY_HOST=$(oc get route quay-quay -n quay-enterprise -o jsonpath='{.spec.host}')
if [ -z "$QUAY_HOST" ]; then
    echo "Error: Could not extract Quay route URL"
    exit 1
fi
echo "Quay Host: $QUAY_HOST"
QUAY_URL="https://$QUAY_HOST"
echo "Quay URL: $QUAY_URL"

# Extract Quay admin token from secret
echo "Retrieving Quay admin token from secret..."
QUAY_ADMIN_TOKEN=$(oc get secret quay-admin-token -n quay-enterprise -o jsonpath='{.data.token}' | base64 -d)
if [ -z "$QUAY_ADMIN_TOKEN" ]; then
    echo "Error: Could not extract QUAY_ADMIN_TOKEN from secret"
    exit 1
fi
echo ""

# Login to Quay with podman
echo "Logging into Quay registry with podman..."
podman login -u '$oauthtoken' -p "$QUAY_ADMIN_TOKEN" "$QUAY_HOST" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "podman successfully logged into Quay registry"
else
    echo "Warning: podman login failed"
fi
echo ""

# Generate timestamp in yyyy-mm-dd_hh-mm format
TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
echo "Timestamp: $TIMESTAMP"

# Build the image
IMAGE="${QUAY_HOST}/l3-students/l3-rhads-unsigned"

echo "Building image: $IMAGE_TAG"
podman build -t "$IMAGE:${TIMESTAMP}" "$IMAGE:latest" .

# Push the image
echo "Pushing image to registry..."
podman push "$IMAGE:${TIMESTAMP}"
podman push "$IMAGE:latest"

echo "Successfully built and pushed: $IMAGE"
