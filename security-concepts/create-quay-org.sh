#!/bin/bash

#set -e

echo "Creating Quay Organization 'l3-students'"
echo "========================================="
echo ""

# Extract Quay admin token from secret
echo "Retrieving Quay admin token from secret..."
QUAY_ADMIN_TOKEN=$(oc get secret quay-admin-token -n quay-enterprise -o jsonpath='{.data.token}' | base64 -d)
if [ -z "$QUAY_ADMIN_TOKEN" ]; then
    echo "Error: Could not extract QUAY_ADMIN_TOKEN from secret"
    exit 1
fi
echo "Quay Admin Token: [REDACTED]"

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

# Create organization via Quay API
echo ""
echo "Creating organization 'l3-students'..."
RESPONSE=$(curl -k -X POST \
    -H "Authorization: Bearer $QUAY_ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name": "l3-students", "email": ""}' \
    "$QUAY_URL/api/v1/organization/" \
    -w "\n%{http_code}" \
    -s)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 200 ]; then
    echo ""
    echo "================================"
    echo "Success!"
    echo "================================"
    echo "Organization 'l3-students' created successfully"
    echo "Quay URL: $QUAY_URL"
    echo "Organization URL: $QUAY_URL/organization/l3-students"
    echo "================================"
elif [ "$HTTP_CODE" -eq 400 ] && echo "$RESPONSE_BODY" | grep -q "already exists"; then
    echo ""
    echo "================================"
    echo "Organization already exists"
    echo "================================"
    echo "Organization 'l3-students' already exists in Quay"
    echo "Organization URL: $QUAY_URL/organization/l3-students"
    echo "================================"
else
    echo ""
    echo "Error: Failed to create organization (HTTP $HTTP_CODE)"
    echo "Response: $RESPONSE_BODY"
    exit 1
fi
