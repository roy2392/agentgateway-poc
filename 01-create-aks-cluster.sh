#!/bin/bash
set -e

# KGateway Azure POC - AKS Cluster Setup
# This script creates an AKS cluster for the KGateway POC

# Configuration - Modify these values as needed
RESOURCE_GROUP="kgateway-poc-rg"
CLUSTER_NAME="kgateway-poc-aks"
LOCATION="eastus"  # Change to your preferred Azure region
NODE_COUNT=2
NODE_VM_SIZE="Standard_DS2_v2"
KUBERNETES_VERSION="1.30"  # KGateway requires Kubernetes 1.25+

echo "=========================================="
echo "KGateway Azure POC - AKS Cluster Setup"
echo "=========================================="

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is not installed. Please install it first:"
    echo "  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
    exit 1
fi

# Check if logged in to Azure
echo "Checking Azure login status..."
if ! az account show &> /dev/null; then
    echo "Not logged in to Azure. Please login..."
    az login
fi

# Display current subscription
echo ""
echo "Current Azure subscription:"
az account show --query "{Name:name, ID:id}" -o table
echo ""
read -p "Continue with this subscription? (y/n): " confirm
if [[ $confirm != "y" && $confirm != "Y" ]]; then
    echo "Please set the correct subscription using: az account set --subscription <subscription-id>"
    exit 1
fi

# Create Resource Group
echo ""
echo "Creating Resource Group: $RESOURCE_GROUP in $LOCATION..."
az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION

# Create AKS Cluster
echo ""
echo "Creating AKS Cluster: $CLUSTER_NAME..."
echo "This may take 5-10 minutes..."
az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --node-count $NODE_COUNT \
    --node-vm-size $NODE_VM_SIZE \
    --kubernetes-version $KUBERNETES_VERSION \
    --enable-managed-identity \
    --generate-ssh-keys \
    --network-plugin azure \
    --network-policy azure

# Get AKS credentials
echo ""
echo "Getting AKS credentials..."
az aks get-credentials \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --overwrite-existing

# Verify cluster connection
echo ""
echo "Verifying cluster connection..."
kubectl cluster-info
kubectl get nodes

echo ""
echo "=========================================="
echo "AKS Cluster created successfully!"
echo "=========================================="
echo ""
echo "Cluster Details:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Cluster Name: $CLUSTER_NAME"
echo "  Location: $LOCATION"
echo "  Node Count: $NODE_COUNT"
echo ""
echo "Next step: Run ./02-install-kgateway.sh to install KGateway"
