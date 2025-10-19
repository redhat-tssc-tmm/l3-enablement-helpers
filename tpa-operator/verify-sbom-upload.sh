#!/bin/bash

# Get the cluster ingress domain
INGRESS_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')

# Construct the ISSUER_URL
ISSUER_URL="https://sso.${INGRESS_DOMAIN}/realms/trusted-artifact-signer"

# Set the client ID
CLIENT_ID="tpa-cli"

# Get the client secret from the oidc-cli secret in the current namespace
CLIENT_SECRET=$(oc get secret oidc-cli -o jsonpath='{.data.client-secret}' | base64 -d)

# Get the access token
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
echo "Uploading homebanking SBOM"
echo ""
# Set the TPA endpoint
TPA_URL="https://server-student-tpa-operator.${INGRESS_DOMAIN}"

# upload the SBOM with additional labels
curl -X POST "${TPA_URL}/api/v2/sbom?labels.environment=verification&labels.team=students&labels.application=homebanking&labels.source=maven-plugin" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary @home-banking-sbom.json

echo ""
