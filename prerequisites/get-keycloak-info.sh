#!/bin/bash

# Get the route URL
ROUTE_URL=$(oc get route keycloak -n tssc-keycloak -o jsonpath='{.spec.host}')

# Get username from secret
USERNAME=$(oc get secret keycloak-initial-admin -n tssc-keycloak -o jsonpath='{.data.username}' | base64 -d)

# Get password from secret
PASSWORD=$(oc get secret keycloak-initial-admin -n tssc-keycloak -o jsonpath='{.data.password}' | base64 -d)

# Print the results
echo "Keycloak Route: https://$ROUTE_URL"
echo "Username: $USERNAME"
echo "Password: $PASSWORD"
