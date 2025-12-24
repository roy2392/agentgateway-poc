#!/bin/bash
set -e

# KGateway Azure POC - KGateway Installation
# This script installs KGateway on the AKS cluster

KGATEWAY_VERSION="v2.1.2"
GATEWAY_API_VERSION="v1.4.0"

echo "=========================================="
echo "KGateway Azure POC - KGateway Installation"
echo "=========================================="

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed"
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "Error: Helm is not installed. Please install it first:"
    echo "  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    exit 1
fi

# Verify cluster connection
echo "Verifying cluster connection..."
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    echo "Please run the AKS setup script first or configure kubectl"
    exit 1
fi

echo ""
echo "Step 1: Installing Kubernetes Gateway API CRDs (${GATEWAY_API_VERSION})..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml

echo ""
echo "Step 2: Installing KGateway CRDs via Helm..."
helm upgrade -i --create-namespace \
    --namespace kgateway-system \
    --version ${KGATEWAY_VERSION} \
    kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds

echo ""
echo "Step 3: Installing KGateway control plane..."
helm upgrade -i \
    --namespace kgateway-system \
    --version ${KGATEWAY_VERSION} \
    kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway

# Wait for KGateway to be ready
echo ""
echo "Waiting for KGateway pods to be ready..."
kubectl wait --namespace kgateway-system \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=kgateway \
    --timeout=120s || true

echo ""
echo "Step 4: Verifying installation..."
echo ""
echo "KGateway Pods:"
kubectl get pods -n kgateway-system

echo ""
echo "KGateway Services:"
kubectl get svc -n kgateway-system

echo ""
echo "Gateway API CRDs installed:"
kubectl get crds | grep gateway || true

echo ""
echo "=========================================="
echo "KGateway installed successfully!"
echo "=========================================="
echo ""
echo "Version: ${KGATEWAY_VERSION}"
echo ""
echo "Next step: Run ./03-deploy-sample-app.sh to deploy a sample application"
