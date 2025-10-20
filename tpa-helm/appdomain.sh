#!/bin/bash
export NAMESPACE=$(oc project -q)
export APP_DOMAIN_URL=-$NAMESPACE.$(oc -n openshift-ingress-operator get ingresscontrollers.operator.openshift.io default -o jsonpath='{.status.domain}')


echo "NAMESPACE is: $NAMESPACE"

echo "APP_DOMAIN_URL (needed in helm values) set to: "
echo $APP_DOMAIN_URL
