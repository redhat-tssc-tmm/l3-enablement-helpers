#!/bin/bash

#set -e

echo "Setting up \"Podman Terminal\" with OAuth Configuration "
echo "========================================================"
echo "Extracting OAuth configuration from OpenShift cluster..."

# Get OIDC client ID from OAuth configuration
OIDC_CLIENT_ID=$(oc get oauth cluster -o jsonpath='{.spec.identityProviders[0].openID.clientID}')
if [ -z "$OIDC_CLIENT_ID" ]; then
    echo "Error: Could not extract OIDC client ID from OAuth configuration"
    exit 1
fi
echo "OIDC Client ID: $OIDC_CLIENT_ID"

# Get client secret name from OAuth configuration
CLIENT_SECRET_NAME=$(oc get oauth cluster -o jsonpath='{.spec.identityProviders[0].openID.clientSecret.name}')
if [ -z "$CLIENT_SECRET_NAME" ]; then
    echo "Error: Could not extract client secret name from OAuth configuration"
    exit 1
fi
echo "Client Secret Name: $CLIENT_SECRET_NAME"

# Get the actual client secret value
OIDC_CLIENT_SECRET=$(oc get secret "$CLIENT_SECRET_NAME" -n openshift-config -o jsonpath='{.data.clientSecret}' | base64 -d)
if [ -z "$OIDC_CLIENT_SECRET" ]; then
    echo "Error: Could not extract client secret value"
    exit 1
fi
echo "OIDC Client Secret: [REDACTED]"

# Get OIDC issuer URL from OAuth configuration
OIDC_ISSUER_URL=$(oc get oauth cluster -o jsonpath='{.spec.identityProviders[0].openID.issuer}')
if [ -z "$OIDC_ISSUER_URL" ]; then
    echo "Error: Could not extract OIDC issuer URL from OAuth configuration"
    exit 1
fi
echo "OIDC Issuer URL: $OIDC_ISSUER_URL"

# Get cluster ingress domain
CLUSTER_INGRESS_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
if [ -z "$CLUSTER_INGRESS_DOMAIN" ]; then
    echo "Error: Could not extract cluster ingress domain"
    exit 1
fi
echo "Cluster Ingress Domain: $CLUSTER_INGRESS_DOMAIN"

# Generate cookie secret (must be exactly 32 bytes for AES-256)
echo "Generating cookie secret..."
COOKIE_SECRET=$(openssl rand -base64 24)
if [ -z "$COOKIE_SECRET" ]; then
    echo "Error: Could not generate cookie secret"
    exit 1
fi
echo "Cookie Secret: [REDACTED]"

# Create podman-terminal.yaml from template
echo ""
echo "Creating podman-terminal.yaml from template-podman-terminal.yaml..."

if [ ! -f "template-podman-terminal.yaml" ]; then
    echo "Error: template-podman-terminal.yaml not found"
    exit 1
fi

# Use sed to replace all template variables
# Note: Using | as delimiter since URLs contain /
sed -e "s|{{oidc-client-id}}|$OIDC_CLIENT_ID|g" \
    -e "s|{{oidc-client-secret}}|$OIDC_CLIENT_SECRET|g" \
    -e "s|{{cookie-secret}}|$COOKIE_SECRET|g" \
    -e "s|{{oidc-issuer-url}}|$OIDC_ISSUER_URL|g" \
    -e "s|{{cluster-ingress-domain}}|.$CLUSTER_INGRESS_DOMAIN|g" \
    template-podman-terminal.yaml > podman-terminal.yaml

echo "Successfully created podman-terminal.yaml"
echo ""
echo "Summary:"
echo "  - OIDC Client ID: $OIDC_CLIENT_ID"
echo "  - OIDC Issuer URL: $OIDC_ISSUER_URL"
echo "  - Cluster Ingress Domain: $CLUSTER_INGRESS_DOMAIN"
echo "  - Generated cookie secret"
echo ""

# Apply the configuration to the cluster
echo "Deploying podman-terminal.yaml to OpenShift cluster..."
oc apply -f podman-terminal.yaml

echo ""
echo "Waiting for route to be created..."

# Retry loop to get the route URL
ROUTE_URL=""
MAX_RETRIES=5
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    ROUTE_URL=$(oc get route admin-terminal -n ttyd -o jsonpath='{.spec.host}' 2>/dev/null)
    if [ -n "$ROUTE_URL" ]; then
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo "Attempt $RETRY_COUNT/$MAX_RETRIES: Route not ready yet, waiting 2 seconds..."
        sleep 2
    fi
done

if [ -z "$ROUTE_URL" ]; then
    echo ""
    echo "Warning: Could not retrieve route URL after $MAX_RETRIES attempts."
    echo "Check manually with: oc get route admin-terminal -n ttyd"
    exit 1
fi

echo ""
echo "Route created: https://$ROUTE_URL"
echo ""
echo "Waiting for pod to be ready..."

# Wait for pod to be running and ready
POD_READY=false
MAX_POD_RETRIES=30
POD_RETRY_COUNT=0

while [ $POD_RETRY_COUNT -lt $MAX_POD_RETRIES ]; do
    # Get pod name and status
    POD_NAME=$(oc get pods -n ttyd -l app=ttyd-admin-terminal -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -n "$POD_NAME" ]; then
        # Check if pod is running
        POD_STATUS=$(oc get pod "$POD_NAME" -n ttyd -o jsonpath='{.status.phase}' 2>/dev/null)

        # Check if all containers are ready
        READY_STATUS=$(oc get pod "$POD_NAME" -n ttyd -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

        if [ "$POD_STATUS" = "Running" ] && [ "$READY_STATUS" = "True" ]; then
            POD_READY=true
            echo "Pod $POD_NAME is ready!"
            break
        else
            echo "Attempt $((POD_RETRY_COUNT + 1))/$MAX_POD_RETRIES: Pod status: $POD_STATUS, Ready: $READY_STATUS - waiting 2 seconds..."
        fi
    else
        echo "Attempt $((POD_RETRY_COUNT + 1))/$MAX_POD_RETRIES: Pod not found yet - waiting 2 seconds..."
    fi

    POD_RETRY_COUNT=$((POD_RETRY_COUNT + 1))
    sleep 2
done

if [ "$POD_READY" = true ]; then
    echo ""
    echo "================================"
    echo "Deployment successful!"
    echo "================================"
    echo "Terminal URL: https://$ROUTE_URL"
    echo "================================"
else
    echo ""
    echo "Warning: Pod did not become ready after $MAX_POD_RETRIES attempts ($(($MAX_POD_RETRIES * 2)) seconds)."
    echo "The route is available but the pod may still be initializing."
    echo "Check pod status with: oc get pods -n ttyd"
    echo "Terminal URL: https://$ROUTE_URL"
fi
