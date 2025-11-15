#!/bin/bash

#set -e

######### Creating the user in Keycloak ############################################

echo "Setting up Keycloak Users and Groups"
echo "====================================="
echo ""

# Get Keycloak admin credentials from secret
echo "Retrieving Keycloak admin credentials..."
KEYCLOAK_ADMIN_USER=$(oc get secret keycloak-initial-admin -n tssc-keycloak -o jsonpath='{.data.username}' | base64 -d)
KEYCLOAK_ADMIN_PASSWORD=$(oc get secret keycloak-initial-admin -n tssc-keycloak -o jsonpath='{.data.password}' | base64 -d)

if [ -z "$KEYCLOAK_ADMIN_USER" ] || [ -z "$KEYCLOAK_ADMIN_PASSWORD" ]; then
    echo "Error: Could not extract Keycloak admin credentials"
    exit 1
fi
echo "Keycloak Admin User: $KEYCLOAK_ADMIN_USER"
echo "Keycloak Admin Password: [REDACTED]"

# Get Keycloak route URL
echo "Retrieving Keycloak route URL..."
KEYCLOAK_HOST=$(oc get route keycloak -n tssc-keycloak -o jsonpath='{.spec.host}')
if [ -z "$KEYCLOAK_HOST" ]; then
    echo "Error: Could not extract Keycloak route URL"
    exit 1
fi
KEYCLOAK_URL="https://$KEYCLOAK_HOST"
echo "Keycloak URL: $KEYCLOAK_URL"
echo ""

# Authenticate and get access token
echo "Authenticating with Keycloak..."
TOKEN_RESPONSE=$(curl -k -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$KEYCLOAK_ADMIN_USER" \
    -d "password=$KEYCLOAK_ADMIN_PASSWORD" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
    "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
    -s)

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

if [ -z "$ACCESS_TOKEN" ]; then
    echo "Error: Failed to obtain access token"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi
echo "Access token obtained successfully"
echo ""

REALM="trusted-artifact-signer"

# Create group "technical-users"
echo "Creating group 'technical-users' in realm '$REALM'..."
GROUP_RESPONSE=$(curl -k -X POST \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name": "technical-users"}' \
    "$KEYCLOAK_URL/admin/realms/$REALM/groups" \
    -w "\n%{http_code}" \
    -s)

GROUP_HTTP_CODE=$(echo "$GROUP_RESPONSE" | tail -n1)
GROUP_RESPONSE_BODY=$(echo "$GROUP_RESPONSE" | sed '$d')

if [ "$GROUP_HTTP_CODE" -eq 201 ]; then
    echo "Group 'technical-users' created successfully"
    # Get the Location header to find the group ID
    GROUP_LOCATION=$(curl -k -X POST \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"name": "technical-users-temp"}' \
        "$KEYCLOAK_URL/admin/realms/$REALM/groups" \
        -s -D - -o /dev/null | grep -i "^Location:" | cut -d' ' -f2 | tr -d '\r')
    # Delete the temp group
    if [ -n "$GROUP_LOCATION" ]; then
        curl -k -X DELETE \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            "$GROUP_LOCATION" \
            -s > /dev/null
    fi
elif [ "$GROUP_HTTP_CODE" -eq 409 ]; then
    echo "Group 'technical-users' already exists"
else
    echo "Warning: Unexpected response when creating group (HTTP $GROUP_HTTP_CODE)"
    echo "Response: $GROUP_RESPONSE_BODY"
fi

# Get group ID
echo "Retrieving group ID..."
GROUPS_LIST=$(curl -k -X GET \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$KEYCLOAK_URL/admin/realms/$REALM/groups" \
    -s)

GROUP_ID=$(echo "$GROUPS_LIST" | jq -r '.[] | select(.name=="technical-users") | .id // empty')

if [ -z "$GROUP_ID" ]; then
    echo "Error: Could not retrieve group ID for 'technical-users'"
    exit 1
fi
echo "Group ID: $GROUP_ID"
echo ""

# Create user "pipeline"
echo "Creating user 'pipeline'..."
USER_DATA='{
  "username": "pipeline",
  "email": "pipeline-auth@demo.redhat.com",
  "emailVerified": true,
  "enabled": true,
  "credentials": [{
    "type": "password",
    "value": "r3dh8t1!",
    "temporary": false
  }]
}'

USER_RESPONSE=$(curl -k -X POST \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$USER_DATA" \
    "$KEYCLOAK_URL/admin/realms/$REALM/users" \
    -w "\n%{http_code}" \
    -s)

USER_HTTP_CODE=$(echo "$USER_RESPONSE" | tail -n1)
USER_RESPONSE_BODY=$(echo "$USER_RESPONSE" | sed '$d')

if [ "$USER_HTTP_CODE" -eq 201 ]; then
    echo "User 'pipeline' created successfully"
elif [ "$USER_HTTP_CODE" -eq 409 ]; then
    echo "User 'pipeline' already exists"
else
    echo "Warning: Unexpected response when creating user (HTTP $USER_HTTP_CODE)"
    echo "Response: $USER_RESPONSE_BODY"
fi

# Get user ID
echo "Retrieving user ID for 'pipeline'..."
USER_INFO=$(curl -k -X GET \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$KEYCLOAK_URL/admin/realms/$REALM/users?username=pipeline" \
    -s)

USER_ID=$(echo "$USER_INFO" | jq -r '.[0].id // empty')

if [ -z "$USER_ID" ]; then
    echo "Error: Could not retrieve user ID for 'pipeline'"
    exit 1
fi
echo "User ID: $USER_ID"
echo ""

# Add user to group
echo "Adding user 'pipeline' to group 'technical-users'..."
ADD_TO_GROUP_RESPONSE=$(curl -k -X PUT \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    "$KEYCLOAK_URL/admin/realms/$REALM/users/$USER_ID/groups/$GROUP_ID" \
    -w "\n%{http_code}" \
    -s)

ADD_GROUP_HTTP_CODE=$(echo "$ADD_TO_GROUP_RESPONSE" | tail -n1)

if [ "$ADD_GROUP_HTTP_CODE" -eq 204 ] || [ "$ADD_GROUP_HTTP_CODE" -eq 200 ]; then
    echo "User 'pipeline' added to group 'technical-users' successfully"
else
    echo "Warning: Unexpected response when adding user to group (HTTP $ADD_GROUP_HTTP_CODE)"
fi

echo ""
echo "================================"
echo "Success!"
echo "================================"
echo "Keycloak setup completed:"
echo "  - Realm: $REALM"
echo "  - Group created: technical-users"
echo "  - User created: pipeline"
echo "  - Email: pipeline-auth@demo.redhat.com"
echo "  - User added to group: technical-users"
echo "================================"


######### Getting the OIDC access token for that user ##############################


# Construct the ISSUER_URL
ISSUER_URL="${KEYCLOAK_URL}/realms/trusted-artifact-signer"

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

echo "Access Token retrieved: "

export SIGSTORE_ID_TOKEN=$TOKEN


####################################################################################

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
IMAGE="${QUAY_HOST}/l3-students/l3-rhads-signed-keylessly"

echo "Building image: $IMAGE_TAG"
podman build -t "$IMAGE:${TIMESTAMP}" -t "$IMAGE:latest" .

# Push the image
echo "Pushing image to registry..."
podman push "$IMAGE:${TIMESTAMP}"
podman push "$IMAGE:latest"

echo "Successfully built and pushed: $IMAGE"
echo ""
echo "initializing the TUF root for keyless signing"
echo ""
cosign initialize
echo ""
echo "Signing with cosign"

### Cosign uses the SIGSTORE_ID_TOKEN environment variable, if present 
### we exported that above, this is the user's OIDC token.
### So, effectively user `pipeline-auth@demo.redhat.com` is signing the image
cosign sign "$IMAGE:${TIMESTAMP}"
