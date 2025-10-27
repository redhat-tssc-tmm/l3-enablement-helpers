#!/bin/bash

set -e

echo "Copying Image to Local Quay Registry"
echo "====================================="
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
QUAY_ADMIN_TOKEN=$(oc get secret quay-admin-token -n quay-enterprise -o jsonpath='{.data.QUAY_ADMIN_TOKEN}' | base64 -d)
if [ -z "$QUAY_ADMIN_TOKEN" ]; then
    echo "Error: Could not extract QUAY_ADMIN_TOKEN from secret"
    exit 1
fi
echo "Quay Admin Token: [REDACTED]"
echo ""

# Source and destination image details
SOURCE_IMAGE="quay.io/tssc_demos/l3-rhads-demoimage:latest"
DEST_IMAGE="$QUAY_HOST/l3-students/l3-rhads-demoimage:latest"

echo "Source Image: $SOURCE_IMAGE"
echo "Destination Image: $DEST_IMAGE"
echo ""

# Check if skopeo is available
if ! command -v skopeo &> /dev/null; then
    echo "Error: skopeo is not installed. Please install skopeo to copy images."
    echo "You can install it with: sudo dnf install skopeo"
    exit 1
fi

# Copy image using skopeo
echo "Copying image from $SOURCE_IMAGE to $DEST_IMAGE..."
echo "This may take a few moments..."
echo ""

skopeo copy \
    --src-tls-verify=true \
    --dest-tls-verify=false \
    --dest-creds="\$oauthtoken:$QUAY_ADMIN_TOKEN" \
    "docker://$SOURCE_IMAGE" \
    "docker://$DEST_IMAGE"

if [ $? -eq 0 ]; then
    echo ""
    echo "================================"
    echo "Success!"
    echo "================================"
    echo "Image copied successfully"
    echo "Source: $SOURCE_IMAGE"
    echo "Destination: $DEST_IMAGE"
    echo "Image URL: $QUAY_URL/repository/l3-students/l3-rhads-demoimage"
    echo "================================"
else
    echo ""
    echo "Error: Failed to copy image"
    exit 1
fi
