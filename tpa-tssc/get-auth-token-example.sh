#!/bin/bash

# Get the cluster ingress domain
INGRESS_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')

# Construct the ISSUER_URL (we know the realm is "chicken")
ISSUER_URL="https://sso.${INGRESS_DOMAIN}/realms/chicken"

# Set the client ID
CLIENT_ID="cli"

# Get the client secret from the tpa-realm-chicken-clients secret 
CLIENT_SECRET=$(oc get secret tpa-realm-chicken-clients -n tssc-tpa -o jsonpath='{.data.cli}' | base64 -d)

# Get the access token
# /protocol/openid-connect/token is the endpoint to request a token from keycloak
# "grant_type=client_credentials" is needed for "confidential" clients
TOKEN=$(curl -s -X POST "${ISSUER_URL}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${CLIENT_SECRET}" \
  | jq -r '.access_token')

echo "Access Token: "
echo "=================================================================================================="
echo ${TOKEN}
echo "=================================================================================================="
echo ""
