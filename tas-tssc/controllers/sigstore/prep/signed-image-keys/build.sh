#!/bin/bash

#set -e

echo "Building image, signing it and pushing to Quay"
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

# Login to Quay with cosign
echo "Logging into Quay registry with cosign..."
cosign login -u '$oauthtoken' -p "$QUAY_ADMIN_TOKEN" "$QUAY_HOST" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "cosign successfully logged into Quay registry"
else
    echo "Warning: cosign login failed"
fi
echo ""

# Generate timestamp in yyyy-mm-dd_hh-mm format
TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
echo "Timestamp: $TIMESTAMP"

# Build the image
IMAGE="${QUAY_HOST}/l3-students/l3-rhads-signed-key"

echo "Building image: $IMAGE_TAG"
podman build -t "$IMAGE:${TIMESTAMP}" -t "$IMAGE:latest" .

# Push the image
echo "Pushing image to registry..."
podman push "$IMAGE:${TIMESTAMP}"
podman push "$IMAGE:latest"

echo "Successfully built and pushed: $IMAGE"
echo ""

# Make repository public via Quay API
echo "Making repository public..."
REPO_PATH=$(echo "$IMAGE" | sed "s|${QUAY_HOST}/||")
NAMESPACE=$(echo "$REPO_PATH" | cut -d'/' -f1)
REPOSITORY=$(echo "$REPO_PATH" | cut -d'/' -f2)

# Get current repository description (if exists)
CURRENT_DESC=$(curl -k -X GET \
    -H "Authorization: Bearer $QUAY_ADMIN_TOKEN" \
    "$QUAY_URL/api/v1/repository/$NAMESPACE/$REPOSITORY" \
    -s 2>/dev/null | jq -r '.description // "Signed container image (key-based)"')

# Update repository visibility
VISIBILITY_RESPONSE=$(curl -k -X PUT \
    -H "Authorization: Bearer $QUAY_ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"visibility\": \"public\", \"description\": \"$CURRENT_DESC\"}" \
    "$QUAY_URL/api/v1/repository/$NAMESPACE/$REPOSITORY" \
    -w "\n%{http_code}" \
    -s)

VISIBILITY_HTTP_CODE=$(echo "$VISIBILITY_RESPONSE" | tail -n1)

if [ "$VISIBILITY_HTTP_CODE" -eq 200 ] || [ "$VISIBILITY_HTTP_CODE" -eq 201 ]; then
    echo "Repository $NAMESPACE/$REPOSITORY is now public"
else
    echo "Warning: Failed to make repository public (HTTP $VISIBILITY_HTTP_CODE)"
    echo "Response: $(echo "$VISIBILITY_RESPONSE" | sed '$d')"
fi
echo ""

echo "Signing with cosign"

cosign sign --key k8s://openshift-pipelines/signing-secrets "$IMAGE:${TIMESTAMP}"

echo ""
# Save image reference to image.env for later use
echo "IMAGE=$IMAGE:${TIMESTAMP}" > image.env
echo "Image reference saved to image.env"

