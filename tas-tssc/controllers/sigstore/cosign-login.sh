#!/bin/bash

#set -e

echo "Logging into Quay with cosign"
echo "============================="
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

# Login to Quay with cosign
echo "Logging into Quay registry with cosign..."
cosign login -u '$oauthtoken' -p "$QUAY_ADMIN_TOKEN" "$QUAY_HOST" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "cosign successfully logged into Quay registry"
else
    echo "Warning: cosign login failed"
fi
echo ""