#!/bin/bash -ex

# 0. Assign default values to some of our environment variables
# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# The name of the kind cluster to deploy to
CLUSTER_NAME="${CLUSTER_NAME:-kind}"
# The version of the Node Docker image to use for booting the cluster
CLUSTER_NODE_VERSION="${CLUSTER_NODE_VERSION:-v1.31.0}"
# The version used to tag images
VERSION="${VERSION:-1.0.0-ci1}"
# Skip building docker images if we are testing a released version
SKIP_DOCKER="${SKIP_DOCKER:-false}"
# Stop after creating the kind cluster
JUST_KIND="${JUST_KIND:-false}"
# Set the default image variant to standard
IMAGE_VARIANT="${IMAGE_VARIANT:-standard}"
# If true, run extra steps to set up k8s gateway api conformance test environment
CONFORMANCE="${CONFORMANCE:-false}"
# The version of the k8s gateway api conformance tests to run. Requires CONFORMANCE=true
CONFORMANCE_VERSION="${CONFORMANCE_VERSION:-v1.3.0}"
# The channel of the k8s gateway api conformance tests to run. Requires CONFORMANCE=true
CONFORMANCE_CHANNEL="${CONFORMANCE_CHANNEL:-"experimental"}"
# The version of Cilium to install.
CILIUM_VERSION="${CILIUM_VERSION:-1.15.5}"
# Set the ip family
SUPPORTED_IP_FAMILY="${SUPPORTED_IP_FAMILY:-v6}"

setup_kind_network() {
  # check if network already exists
  local existing_network_id
  existing_network_id="$(docker network list --filter=name=^kind$ --format='{{.ID}}')"

  if [ -n "$existing_network_id" ]; then
    # ensure the network is configured correctly
    local network network_options network_ipam expected_network_ipam
    network="$(docker network inspect $existing_network_id | yq '.[]')"
    network_options="$(echo "$network" | yq '.EnableIPv6 + "," + .Options["com.docker.network.bridge.enable_ip_masquerade"]')"
    network_ipam="$(echo "$network" | yq '.IPAM.Config' -o=json -I=0)"
    expected_network_ipam='[{"Subnet":"172.18.0.0/16","Gateway":"172.18.0.1"},{"Subnet":"fd00:10::/64","Gateway":"fd00:10::1"}]'

    if [ "$network_options" = 'true,true' ] && [ "$network_ipam" = "$expected_network_ipam" ]; then
      # kind network is already configured correctly, nothing to do
      return 0
    else
      echo "kind network is not configured correctly for local gardener setup, recreating network with correct configuration..."
      docker network rm $existing_network_id
    fi
  fi

  # (re-)create kind network with expected settings
  docker network create kind --driver=bridge \
    --subnet 172.18.0.0/16 --gateway 172.18.0.1 \
    --ipv6 --subnet fd00:10::/64 --gateway fd00:10::1 \
    --opt com.docker.network.bridge.enable_ip_masquerade=true
}

function create_kind_cluster_or_skip() {
  ip_family=$1

  activeClusters=$(kind get clusters)

  # if the kind cluster exists already, return
  if [[ "$activeClusters" =~ .*"$CLUSTER_NAME".* ]]; then
    echo "cluster exists, skipping cluster creation"
    return
  fi

  if [[ "$ip_family" = "v6" ]]; then
    echo "creating ipv6 based cluster ${CLUSTER_NAME}"

    setup_kind_network

    kind create cluster \
      --name "$CLUSTER_NAME" \
      --image "kindest/node:$CLUSTER_NODE_VERSION" \
      --config="$SCRIPT_DIR/cluster-ipv6.yaml"

    # this is a hack to bypass lack of a docker ipv6 dns resolver.
    # see https://github.com/kubernetes-sigs/kind/issues/1736
    # and https://github.com/moby/moby/issues/41651
    #original_coredns=$(kubectl get cm -n kube-system coredns -o jsonpath='{.data.Corefile}')
    # | sed -E 's,forward . /etc/resolv.conf( ?\{)?,forward . [64:ff9b::8.8.8.8]:53 [64:ff9b::8.8.4.4]:53\1,' | sed -z 's/\n/\\n/g')
    original_coredns=$(kubectl get -oyaml -n=kube-system configmap/coredns)
    echo $original_coredns
    fixed_coredns=$(
      printf '%s' "${original_coredns}" | sed \
        -e 's/^.*kubernetes cluster\.local/& internal/' \
        -e '/^.*upstream$/d' \
        -e '/^.*fallthrough.*$/d' \
        -e '/forward \. \/etc\/resolv\.conf {/,/}/d' \
        -e '/^.*loop$/d'
    )
    echo "about to patch coredns"
    printf '%s' "${fixed_coredns}" | kubectl apply -f -
    #kubectl patch configmap/coredns -n kube-system --type merge -p '{"data":{"Corefile": "'"$fixed_coredns"'"}}'
  elif [[ "$ip_family" = "dual" ]]; then
    echo "creating dual stack based cluster ${CLUSTER_NAME}"
    kind create cluster \
      --name "$CLUSTER_NAME" \
      --image "kindest/node:$CLUSTER_NODE_VERSION" \
      --config="$SCRIPT_DIR/cluster-dual.yaml"
  else
    echo "creating cluster ${CLUSTER_NAME}"
    kind create cluster \
      --name "$CLUSTER_NAME" \
      --image "kindest/node:$CLUSTER_NODE_VERSION" \
      --config="$SCRIPT_DIR/cluster.yaml"
  fi

  # Install cilium as we need to define custom network policies to simulate kube api server unavailability
  # in some of our kube2e tests
  helm repo add cilium-setup-kind https://helm.cilium.io/
  helm repo update
  # Note here, if running locally then you might want to tweak the subnet range to match your local host
  if [[ "$ip_family" = "v6" ]]; then
    helm install cilium cilium-setup-kind/cilium \
      --version $CILIUM_VERSION \
      --namespace kube-system \
      --set image.pullPolicy=IfNotPresent \
      --set operator.replicas=1 \
      --set ipv6.enabled=true \
      --set ipv4.enabled=false \
      --set ipam.mode=kubernetes \
      --set routingMode=native \
      --set autoDirectNodeRoutes=true \
      --set ipv6NativeRoutingCIDR=fd00:10:1::/56 \
      --set enableIPv6Masquerade=true
  elif [[ "$ip_family" = "dual" ]]; then
    # Check https://github.com/kubernetes-sigs/kind/blob/main/pkg/apis/config/v1alpha4/default.go#L59C57-L59C60 for the default subnets
    helm install cilium cilium-setup-kind/cilium \
      --version $CILIUM_VERSION \
      --namespace kube-system \
      --set image.pullPolicy=IfNotPresent \
      --set operator.replicas=1 \
      --set ipv6.enabled=true \
      --set ipv4.enabled=true \
      --set ipam.mode=kubernetes \
      --set routingMode=native \
      --set autoDirectNodeRoutes=true \
      --set ipv6NativeRoutingCIDR=fd00:10:244::/56 \
      --set enableIPv6Masquerade=true
  else
    helm install cilium cilium-setup-kind/cilium \
      --version $CILIUM_VERSION \
      --namespace kube-system \
      --set image.pullPolicy=IfNotPresent \
      --set ipam.mode=kubernetes \
      --set operator.replicas=1
  fi
  helm repo remove cilium-setup-kind
  echo "Finished setting up cluster $CLUSTER_NAME"

  # make sure cilium is ready before moving on
  kubectl -n kube-system \
    wait --for=condition=Ready \
    pod -l k8s-app=cilium --timeout=5m

  # so that you can just build the kind image alone if needed
  if [[ $JUST_KIND == 'true' ]]; then
    echo "JUST_KIND=true, not building images"
    exit
  fi
}

# 1. Create a kind cluster (or skip creation if a cluster with name=CLUSTER_NAME already exists)
# This config is roughly based on: https://kind.sigs.k8s.io/docs/user/ingress/
create_kind_cluster_or_skip $SUPPORTED_IP_FAMILY

# cat /etc/resolv.conf

# kubectl get cm -n kube-system coredns -o yaml

# kubectl get po -A
# kubectl get daemonset -A
# kubectl get deploy -A
# sleep 5
# kubectl get replicaset -A --show-labels
# kubectl -n kube-system describe rs -l k8s-app=kube-dns

# kubectl logs -n kube-system deploy/coredns

# sleep 5

# if [[ $SKIP_DOCKER == 'true' ]]; then
#   # TODO(tim): refactor the Makefile & CI scripts so we're loading local
#   # charts to real helm repos, and then we can remove this block.
#   echo "SKIP_DOCKER=true, not building images or chart"
#   helm repo add gloo https://storage.googleapis.com/solo-public-helm
#   helm repo update
# else
#   # 2. Make all the docker images and load them to the kind cluster
#   VERSION=$VERSION CLUSTER_NAME=$CLUSTER_NAME IMAGE_VARIANT=$IMAGE_VARIANT make kind-build-and-load

#   # 3. Build the test helm chart, ensuring we have a chart in the `_test` folder
#   VERSION=$VERSION make build-test-chart
# fi

# # 4. Build the gloo command line tool, ensuring we have one in the `_output` folder
# make -s build-cli-local

# # 5. Apply the Kubernetes Gateway API CRDs
# # Note, we're using kustomize to apply the CRDs from the k8s gateway api repo as
# # kustomize supports remote GH URLs and provides more flexibility compared to
# # alternatives like running a series of `kubectl apply -f <url>` commands. This
# # approach is largely necessary since upstream hasn't adopted a helm chart for
# # the CRDs yet, or won't be for the foreseeable future.
# kubectl apply --kustomize "https://github.com/kubernetes-sigs/gateway-api/config/crd/$CONFORMANCE_CHANNEL?ref=$CONFORMANCE_VERSION"

# # 6. Conformance test setup
# if [[ $CONFORMANCE == "true" ]]; then
#   echo "Running conformance test setup"

#   . $SCRIPT_DIR/setup-metalllb-on-kind.sh
# fi
