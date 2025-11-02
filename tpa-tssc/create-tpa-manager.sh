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

# Create client scope "update:document"
echo "Creating client scope 'update:document'..."
SCOPE_DATA='{
  "name": "update:document",
  "description": "Client scope for document update permissions",
  "protocol": "openid-connect",
  "attributes": {
    "include.in.token.scope": "true",
    "display.on.consent.screen": "true"
  }
}'

SCOPE_RESPONSE=$(curl -k -X POST \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$SCOPE_DATA" \
    "$KEYCLOAK_URL/admin/realms/$REALM/client-scopes" \
    -w "\n%{http_code}" \
    -s)

SCOPE_HTTP_CODE=$(echo "$SCOPE_RESPONSE" | tail -n1)
SCOPE_RESPONSE_BODY=$(echo "$SCOPE_RESPONSE" | sed '$d')

if [ "$SCOPE_HTTP_CODE" -eq 201 ]; then
    echo "Client scope 'update:document' created successfully"
elif [ "$SCOPE_HTTP_CODE" -eq 409 ]; then
    echo "Client scope 'update:document' already exists"
else
    echo "Warning: Unexpected response when creating client scope (HTTP $SCOPE_HTTP_CODE)"
    echo "Response: $SCOPE_RESPONSE_BODY"
fi

# Get client scope ID
echo "Retrieving client scope ID for 'update:document'..."
SCOPE_INFO=$(curl -k -X GET \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$KEYCLOAK_URL/admin/realms/$REALM/client-scopes" \
    -s)

CLIENT_SCOPE_ID=$(echo "$SCOPE_INFO" | jq -r '.[] | select(.name=="update:document") | .id')

if [ -z "$CLIENT_SCOPE_ID" ]; then
    echo "Error: Could not retrieve client scope ID for 'update:document'"
    exit 1
fi
echo "Client Scope ID: $CLIENT_SCOPE_ID"
echo ""

# Get the "chicken-manager" realm role for scope assignment
echo "Retrieving 'chicken-manager' realm role for scope assignment..."
MANAGER_SCOPE_ROLE_INFO=$(curl -k -X GET \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$KEYCLOAK_URL/admin/realms/$REALM/roles/chicken-manager" \
    -s)

MANAGER_SCOPE_ROLE_ID=$(echo "$MANAGER_SCOPE_ROLE_INFO" | jq -r '.id')
MANAGER_SCOPE_ROLE_NAME=$(echo "$MANAGER_SCOPE_ROLE_INFO" | jq -r '.name')

if [ -z "$MANAGER_SCOPE_ROLE_ID" ]; then
    echo "Error: Could not retrieve 'chicken-manager' role for scope assignment"
    exit 1
fi
echo "Role ID for scope: $MANAGER_SCOPE_ROLE_ID"
echo ""

# Assign the "chicken-manager" role to the client scope
echo "Assigning 'chicken-manager' role to client scope 'update:document'..."
SCOPE_ROLE_ASSIGNMENT='[{
  "id": "'"$MANAGER_SCOPE_ROLE_ID"'",
  "name": "'"$MANAGER_SCOPE_ROLE_NAME"'"
}]'

SCOPE_ROLE_RESPONSE=$(curl -k -X POST \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$SCOPE_ROLE_ASSIGNMENT" \
    "$KEYCLOAK_URL/admin/realms/$REALM/client-scopes/$CLIENT_SCOPE_ID/scope-mappings/realm" \
    -w "\n%{http_code}" \
    -s)

SCOPE_ROLE_HTTP_CODE=$(echo "$SCOPE_ROLE_RESPONSE" | tail -n1)
SCOPE_ROLE_RESPONSE_BODY=$(echo "$SCOPE_ROLE_RESPONSE" | sed '$d')

if [ "$SCOPE_ROLE_HTTP_CODE" -eq 204 ]; then
    echo "Role 'chicken-manager' assigned successfully to client scope 'update:document'"
else
    echo "Warning: Unexpected response when assigning role to scope (HTTP $SCOPE_ROLE_HTTP_CODE)"
    echo "Response: $SCOPE_ROLE_RESPONSE_BODY"
fi
echo ""

# Get client IDs for 'frontend' and 'cli'
echo "Retrieving client IDs..."
CLIENTS_INFO=$(curl -k -X GET \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    "$KEYCLOAK_URL/admin/realms/$REALM/clients" \
    -s)

FRONTEND_CLIENT_ID=$(echo "$CLIENTS_INFO" | jq -r '.[] | select(.clientId=="frontend") | .id')
CLI_CLIENT_ID=$(echo "$CLIENTS_INFO" | jq -r '.[] | select(.clientId=="cli") | .id')

if [ -z "$FRONTEND_CLIENT_ID" ]; then
    echo "Warning: Could not retrieve 'frontend' client ID"
else
    echo "Frontend Client ID: $FRONTEND_CLIENT_ID"
fi

if [ -z "$CLI_CLIENT_ID" ]; then
    echo "Warning: Could not retrieve 'cli' client ID"
else
    echo "CLI Client ID: $CLI_CLIENT_ID"
fi
echo ""

# Add client scope to 'frontend' client
if [ -n "$FRONTEND_CLIENT_ID" ]; then
    echo "Adding 'update:document' client scope to 'frontend' client..."
    FRONTEND_SCOPE_RESPONSE=$(curl -k -X PUT \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "$KEYCLOAK_URL/admin/realms/$REALM/clients/$FRONTEND_CLIENT_ID/default-client-scopes/$CLIENT_SCOPE_ID" \
        -w "\n%{http_code}" \
        -s)

    FRONTEND_SCOPE_HTTP_CODE=$(echo "$FRONTEND_SCOPE_RESPONSE" | tail -n1)

    if [ "$FRONTEND_SCOPE_HTTP_CODE" -eq 204 ]; then
        echo "Client scope added successfully to 'frontend' client"
    else
        echo "Warning: Unexpected response when adding scope to 'frontend' (HTTP $FRONTEND_SCOPE_HTTP_CODE)"
    fi
fi

# Add client scope to 'cli' client
if [ -n "$CLI_CLIENT_ID" ]; then
    echo "Adding 'update:document' client scope to 'cli' client..."
    CLI_SCOPE_RESPONSE=$(curl -k -X PUT \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "$KEYCLOAK_URL/admin/realms/$REALM/clients/$CLI_CLIENT_ID/default-client-scopes/$CLIENT_SCOPE_ID" \
        -w "\n%{http_code}" \
        -s)

    CLI_SCOPE_HTTP_CODE=$(echo "$CLI_SCOPE_RESPONSE" | tail -n1)

    if [ "$CLI_SCOPE_HTTP_CODE" -eq 204 ]; then
        echo "Client scope added successfully to 'cli' client"
    else
        echo "Warning: Unexpected response when adding scope to 'cli' (HTTP $CLI_SCOPE_HTTP_CODE)"
    fi
fi
echo ""

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
