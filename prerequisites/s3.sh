#!/bin/bash 


CLAIM="tpa-bucket-claim"

echo "Access Key ID:"
oc get secret $CLAIM -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d
echo -e "\n\nSecret Access Key:"
oc get secret $CLAIM -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d
echo -e "\n\nEndpoint:"
oc get route s3 -n openshift-storage -o jsonpath='https://{.spec.host}'
echo -e "\n\nBucket Name:"
oc get configmap $CLAIM -o jsonpath='{.data.BUCKET_NAME}'
echo -e "\n"
