#!/bin/bash

set -e

# Get Quay route URL
echo "Retrieving Quay route URL..."
QUAY_HOST=$(oc get route quay-quay -n quay-enterprise -o jsonpath='{.spec.host}')
if [ -z "$QUAY_HOST" ]; then
    echo "Error: Could not extract Quay route URL"
    exit 1
fi
echo "Quay host: $QUAY_HOST"

# Generate timestamp in yyyy-mm-dd_hh-mm format
TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
echo "Timestamp: $TIMESTAMP"

# Build the image
IMAGE_TAG="${QUAY_HOST}/demo-imagepolicies/unsigned-image:${TIMESTAMP}"
echo "Building image: $IMAGE_TAG"
podman build -t "$IMAGE_TAG" .

# Push the image
echo "Pushing image to registry..."
podman push "$IMAGE_TAG"

echo "Successfully built and pushed: $IMAGE_TAG"
