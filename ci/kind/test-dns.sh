#!/bin/bash
# test-dns.sh
# Simple CoreDNS / DNS resolution test in Kubernetes

NAMESPACE=${1:-default}
POD_NAME="dns-test-$(date +%s)"

echo "[*] Creating test pod in namespace: $NAMESPACE"
kubectl run $POD_NAME --namespace=$NAMESPACE --image=busybox:1.36 --restart=Never -it --rm -- \
    sh -c "
        echo '== Testing DNS Resolution ==';
        echo '1) Check cluster.local';
        nslookup kubernetes.default.svc.cluster.local;

        echo '2) Check gloo DNS';
        nslookup gloo.gloo-gateway-edge-ipv6-test.svc.cluster.local;
    "
