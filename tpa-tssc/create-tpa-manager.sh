#!/bin/bash

#set -e

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

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ -z "$ACCESS_TOKEN" ]; then
    echo "Error: Failed to obtain access token"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi
echo "Access token obtained successfully"
echo ""

REALM="chicken"



# Create user "tpa-manager"
echo "Creating user 'tpa-manager'..."
USER_DATA='{
  "username": "tpa-manager",
  "email": "tpa-manager@demo.redhat.com",
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
    echo "User 'tpa-manager' created successfully"
elif [ "$USER_HTTP_CODE" -eq 409 ]; then
    echo "User 'tpa-manager' already exists"
else
    echo "Warning: Unexpected response when creating user (HTTP $USER_HTTP_CODE)"
    echo "Response: $USER_RESPONSE_BODY"
fi

# Get user ID
echo "Retrieving user ID for 'tpa-manager'..."
USER_INFO=$(curl -k -X GET \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$KEYCLOAK_URL/admin/realms/$REALM/users?username=tpa-manager" \
    -s)

USER_ID=$(echo "$USER_INFO" | jq -r '.[0].id')

if [ -z "$USER_ID" ]; then
    echo "Error: Could not retrieve user ID for 'tpa-manager'"
    exit 1
fi
echo "User ID: $USER_ID"
echo ""

# Get the "chicken-admin" realm role
echo "Retrieving 'chicken-admin' realm role..."
ADMIN_ROLE_INFO=$(curl -k -X GET \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$KEYCLOAK_URL/admin/realms/$REALM/roles/chicken-admin" \
    -s)

ADMIN_ROLE_ID=$(echo "$ADMIN_ROLE_INFO" | jq -r '.id')
ADMIN_ROLE_NAME=$(echo "$ADMIN_ROLE_INFO" | jq -r '.name')

if [ -z "$ADMIN_ROLE_ID" ]; then
    echo "Error: Could not retrieve 'chicken-admin' role"
    exit 1
fi
echo "Admin Role ID: $ADMIN_ROLE_ID"
echo "Admin Role Name: $ADMIN_ROLE_NAME"
echo ""

# Get the "chicken-manager" realm role
echo "Retrieving 'chicken-manager' realm role..."
MANAGER_ROLE_INFO=$(curl -k -X GET \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$KEYCLOAK_URL/admin/realms/$REALM/roles/chicken-manager" \
    -s)

MANAGER_ROLE_ID=$(echo "$MANAGER_ROLE_INFO" | jq -r '.id')
MANAGER_ROLE_NAME=$(echo "$MANAGER_ROLE_INFO" | jq -r '.name')

if [ -z "$MANAGER_ROLE_ID" ]; then
    echo "Error: Could not retrieve 'chicken-manager' role"
    exit 1
fi
echo "Manager Role ID: $MANAGER_ROLE_ID"
echo "Manager Role Name: $MANAGER_ROLE_NAME"
echo ""

# Assign both realm roles to the user
echo "Assigning 'chicken-admin' and 'chicken-manager' roles to user 'tpa-manager'..."
ROLE_ASSIGNMENT='[{
  "id": "'"$ADMIN_ROLE_ID"'",
  "name": "'"$ADMIN_ROLE_NAME"'"
},{
  "id": "'"$MANAGER_ROLE_ID"'",
  "name": "'"$MANAGER_ROLE_NAME"'"
}]'

ROLE_ASSIGN_RESPONSE=$(curl -k -X POST \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$ROLE_ASSIGNMENT" \
    "$KEYCLOAK_URL/admin/realms/$REALM/users/$USER_ID/role-mappings/realm" \
    -w "\n%{http_code}" \
    -s)

ROLE_HTTP_CODE=$(echo "$ROLE_ASSIGN_RESPONSE" | tail -n1)
ROLE_RESPONSE_BODY=$(echo "$ROLE_ASSIGN_RESPONSE" | sed '$d')

if [ "$ROLE_HTTP_CODE" -eq 204 ]; then
    echo "Roles 'chicken-admin' and 'chicken-manager' assigned successfully to user 'tpa-manager'"
else
    echo "Warning: Unexpected response when assigning roles (HTTP $ROLE_HTTP_CODE)"
    echo "Response: $ROLE_RESPONSE_BODY"
fi
echo ""
