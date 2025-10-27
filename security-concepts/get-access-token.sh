#!/bin/bash

# Get the cluster ingress domain
INGRESS_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')

# Construct the ISSUER_URL
ISSUER_URL="https://sso.${INGRESS_DOMAIN}/realms/trusted-artifact-signer"

# Set the client ID
CLIENT_ID="trusted-artifact-signer"

# Set username and password
USERNAME="pipeline-auth@demo.redhat.com"
PASSWORD="r3dh8t1!"

# Get the access token
TOKEN=$(curl -s -X POST "${ISSUER_URL}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=${CLIENT_ID}" \
  -d "username=${USERNAME}" \
  -d "password=${PASSWORD}" \
  | jq -r '.access_token')

echo "Access Token: "
echo "============================================================================================================="
echo ${TOKEN}
echo "============================================================================================================="
echo ""
echo "Decoded Token (it's a JWT, after all)"
echo "-------------------------------------------------------------------------------------------------------------"
# Decode the token payload
echo $TOKEN | jq -R 'split(".") | .[1] | @base64d | fromjson'

export SIGSTORE_ID_TOKEN=$TOKEN
