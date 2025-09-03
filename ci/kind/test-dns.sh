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

        echo '\n2) Check external DNS (google.com)';
        nslookup google.com;

        echo '\n3) Dig with @kube-dns (CoreDNS)';
        KUBE_DNS=\$(getent hosts kube-dns.kube-system.svc.cluster.local | awk '{print \$1}');
        echo 'Using kube-dns at' \$KUBE_DNS;
        nslookup google.com \$KUBE_DNS;

        echo '\n4) Curl test (if wget available)';
        wget -qO- http://example.com || echo 'wget not available';
    "
