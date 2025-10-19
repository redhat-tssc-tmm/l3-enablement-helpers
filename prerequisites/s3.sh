#!/bin/bash

CLAIM="tpa-bucket-claim"

echo -n "Access Key ID: "
oc get secret $CLAIM -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d
echo ""

echo -n "Secret Access Key: "
oc get secret $CLAIM -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d
echo ""

echo -n "Endpoint: "
oc get route s3 -n openshift-storage -o jsonpath='https://{.spec.host}'
echo ""

echo -n "Bucket Name: "
oc get configmap $CLAIM -o jsonpath='{.data.BUCKET_NAME}'
echo ""
