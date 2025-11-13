#!/bin/bash

#set -e

echo "Logging cosign into Quay and getting image sha"
echo "=============================================="
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
echo "Quay Admin Token: [REDACTED]"
echo ""

# Login to Quay with cosign
echo "Logging into Quay registry with cosign..."
cosign login -u '$oauthtoken' -p "$QUAY_ADMIN_TOKEN" "$QUAY_HOST" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "Cosign successfully logged into Quay registry"
else
    echo "Warning: cosign login failed, but continuing with skopeo..."
fi
echo ""

# Source and destination image details
DEST_IMAGE="$QUAY_HOST/tssc/tekton-chains-test"

# Login to Quay with skopeo
echo "Logging into Quay with skopeo..."
echo "$QUAY_ADMIN_TOKEN" | skopeo login -u '$oauthtoken' --password-stdin "$QUAY_HOST"
if [ $? -eq 0 ]; then
    echo "Skopeo successfully logged into Quay registry"
else
    echo "Error: skopeo login failed"
    exit 1
fi
echo ""

# Get the latest tag (sorted by creation date), excluding signature/attestation tags
echo "Retrieving latest tag from repository..."
LATEST_TAG=$(skopeo list-tags docker://$DEST_IMAGE | \
    jq -r '.Tags[]' | \
    grep -v '^sha256-' | \
    while read tag; do
        created=$(skopeo inspect docker://$DEST_IMAGE:$tag 2>/dev/null | jq -r '.Created // empty')
        if [ -n "$created" ]; then
            echo "$created $tag"
        fi
    done | \
    sort -r | \
    head -1 | \
    awk '{print $2}')

if [ -z "$LATEST_TAG" ]; then
    echo "Error: Could not retrieve latest tag"
    exit 1
fi
echo "Latest tag: $LATEST_TAG"
echo ""

# Get the SHA of the latest tag
echo "Retrieving image SHA for tag: $LATEST_TAG..."
IMAGE_SHA=$(skopeo inspect docker://$DEST_IMAGE:$LATEST_TAG | jq -r '.Digest')
if [ -z "$IMAGE_SHA" ]; then
    echo "Error: Could not retrieve image SHA"
    exit 1
fi
echo "Image SHA: $IMAGE_SHA"
echo ""

# Create docker-transport-addressable image reference with SHA
CHAINS_IMAGE="$DEST_IMAGE@$IMAGE_SHA"
echo "Docker-transport-addressable image: $CHAINS_IMAGE"
echo ""

