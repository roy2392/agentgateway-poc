#!/bin/bash

#######################################
# KGateway AI Agent POC - Grant User Access
# Usage: ./grant-access.sh <user-email>
#######################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo -e "${YELLOW}Usage: ./grant-access.sh <user-email>${NC}"
    echo ""
    echo "Examples:"
    echo "  ./grant-access.sh user@company.com"
    echo "  ./grant-access.sh --all   # Grant to all users in tenant (requires admin)"
    echo ""
    exit 1
fi

USER_EMAIL="$1"
RESOURCE_GROUP="kgateway-poc-rg"
CLUSTER_NAME="kgateway-poc-aks"

# Get subscription and cluster info
SUB_ID=$(az account show --query id -o tsv)
CLUSTER_ID="/subscriptions/${SUB_ID}/resourcegroups/${RESOURCE_GROUP}/providers/Microsoft.ContainerService/managedClusters/${CLUSTER_NAME}"

if [ "$USER_EMAIL" == "--all" ]; then
    echo -e "${YELLOW}Granting access to all users in tenant...${NC}"
    echo "This requires Global Administrator or Privileged Role Administrator permissions."
    echo ""

    # Get the default directory's "All Users" equivalent
    TENANT_ID=$(az account show --query tenantId -o tsv)

    echo -e "${YELLOW}For broad access, assign roles at subscription level:${NC}"
    echo ""
    echo "az role assignment create \\"
    echo "  --role 'Azure Kubernetes Service Cluster User Role' \\"
    echo "  --scope '/subscriptions/${SUB_ID}' \\"
    echo "  --assignee-object-id <GROUP_OR_USER_ID>"
    echo ""
    exit 0
fi

echo -e "${YELLOW}Granting cluster access to: ${USER_EMAIL}${NC}"
echo ""

# Get user's object ID
USER_ID=$(az ad user show --id "$USER_EMAIL" --query id -o tsv 2>/dev/null)

if [ -z "$USER_ID" ]; then
    echo -e "${RED}User not found: ${USER_EMAIL}${NC}"
    echo "Make sure the user exists in your Azure AD tenant."
    exit 1
fi

echo "User Object ID: $USER_ID"
echo ""

# Assign Azure Kubernetes Service Cluster User Role (for az aks get-credentials)
echo "Assigning 'Azure Kubernetes Service Cluster User Role'..."
az role assignment create \
  --role "Azure Kubernetes Service Cluster User Role" \
  --scope "$CLUSTER_ID" \
  --assignee "$USER_ID" \
  --output none 2>/dev/null || echo "  (already assigned or insufficient permissions)"

# Assign Azure Kubernetes Service RBAC Cluster Admin (for kubectl access)
echo "Assigning 'Azure Kubernetes Service RBAC Cluster Admin'..."
az role assignment create \
  --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --scope "$CLUSTER_ID" \
  --assignee "$USER_ID" \
  --output none 2>/dev/null || echo "  (already assigned or insufficient permissions)"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Access granted to: ${USER_EMAIL}${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "The user can now access the cluster by running:"
echo ""
echo "  az login"
echo "  az aks get-credentials --resource-group ${RESOURCE_GROUP} --name ${CLUSTER_NAME}"
echo "  kubectl get pods -A"
echo ""
