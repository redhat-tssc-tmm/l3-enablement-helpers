#!/bin/bash

echo "=========================================="
echo "ACS Signature Integration Configuration"
echo "=========================================="
echo ""

# ============================================================================
# Section: Cosign Public Key
# ============================================================================
echo "=========================================="
echo "Section: Cosign Public Key"
echo "=========================================="
echo ""

echo "Public Key Name: cosign.pub"
echo ""

echo "Public Key Value:"
echo "-------------------"
COSIGN_PUB=$(oc get secret signing-secrets -n openshift-pipelines -o jsonpath='{.data.cosign\.pub}' | base64 -d)

if [ -z "$COSIGN_PUB" ]; then
    echo "Error: Could not retrieve cosign.pub from signing-secrets secret"
    exit 1
fi

echo "$COSIGN_PUB"
echo ""

# ============================================================================
# Section: Transparency Log
# ============================================================================
echo "=========================================="
echo "Section: Transparency Log"
echo "=========================================="
echo ""

echo "Rekor URL:"
echo "-------------------"
if [ -z "$SIGSTORE_REKOR_URL" ]; then
    echo "Warning: SIGSTORE_REKOR_URL environment variable is not set"
    echo "Please set it before configuring ACS"
else
    echo "$SIGSTORE_REKOR_URL"
fi
echo ""

echo "Rekor Public Key:"
echo "-------------------"

# Initialize cosign silently
echo "Initializing cosign (this may take a moment)..."
cosign initialize &>/dev/null

if [ $? -eq 0 ]; then
    echo "Cosign initialized successfully"
    echo ""

    # Check if the rekor.pub file exists
    REKOR_PUB_PATH="/home/student/.sigstore/root/targets/rekor.pub"
    if [ -f "$REKOR_PUB_PATH" ]; then
        cat "$REKOR_PUB_PATH"
    else
        echo "Error: Rekor public key not found at $REKOR_PUB_PATH"
        exit 1
    fi
else
    echo "Error: Failed to initialize cosign"
    exit 1
fi

echo ""
echo ""
echo "=========================================="
echo "Configuration Information Complete"
echo "=========================================="
