#!/bin/bash

set -e

echo "Copying signing pubkey from openshift-pipelines to policy-controller-operator"
echo "============================================================================="
echo ""

# Extract the cosign.pub value from the signing-secrets secret
echo "Retrieving cosign.pub from signing-secrets in openshift-pipelines namespace..."
COSIGN_PUB=$(oc get secret signing-secrets -n openshift-pipelines -o jsonpath='{.data.cosign\.pub}')

if [ -z "$COSIGN_PUB" ]; then
    echo "Error: Could not extract cosign.pub from signing-secrets secret"
    exit 1
fi

echo "Successfully retrieved cosign.pub"
echo ""

# Check if the secret already exists in the policy-controller-operator namespace
echo "Checking if chains-cosign-pubkey secret exists in policy-controller-operator namespace..."
if oc get secret chains-cosign-pubkey -n policy-controller-operator &>/dev/null; then
    echo "Secret already exists. Deleting it first..."
    oc delete secret chains-cosign-pubkey -n policy-controller-operator
fi

# Create the new secret in the policy-controller-operator namespace
echo "Creating chains-cosign-pubkey secret in policy-controller-operator namespace..."
oc create secret generic chains-cosign-pubkey \
    -n policy-controller-operator \
    --from-literal=cosign.pub="$(echo $COSIGN_PUB | base64 -d)"

if [ $? -eq 0 ]; then
    echo "Successfully created chains-cosign-pubkey secret"
else
    echo "Error: Failed to create chains-cosign-pubkey secret"
    exit 1
fi

echo ""
echo "================================"
echo "Success!"
echo "================================"
echo "Public cosign key copied from:"
echo "  - Source: openshift-pipelines/signing-secrets"
echo "  - Destination: policy-controller-operator/chains-cosign-pubkey"
echo "================================"
