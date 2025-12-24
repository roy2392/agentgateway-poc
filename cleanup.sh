#!/bin/bash

#######################################
# KGateway AI Agent POC - Cleanup Script
#######################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}KGateway AI Agent POC - Cleanup${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "This will remove:"
echo "  • AI Agents namespace and all components"
echo "  • AgentGateway and routes"
echo "  • KGateway installation"
echo ""
read -p "Continue? (yes/no): " confirm

if [[ $confirm != "yes" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Deleting AI Agents namespace...${NC}"
kubectl delete namespace ai-agents --ignore-not-found=true

echo ""
echo -e "${YELLOW}Deleting AgentGateway resources...${NC}"
kubectl delete httproutes --all -n kgateway-system 2>/dev/null || true
kubectl delete backends --all -n kgateway-system 2>/dev/null || true
kubectl delete gateways --all -n kgateway-system 2>/dev/null || true

echo ""
echo -e "${YELLOW}Uninstalling KGateway...${NC}"
helm uninstall kgateway -n kgateway-system 2>/dev/null || true
helm uninstall kgateway-crds -n kgateway-system 2>/dev/null || true

echo ""
echo -e "${YELLOW}Deleting Gateway API CRDs...${NC}"
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/experimental-install.yaml 2>/dev/null || true
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml 2>/dev/null || true

echo ""
echo -e "${YELLOW}Deleting kgateway-system namespace...${NC}"
kubectl delete namespace kgateway-system --ignore-not-found=true

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "To also delete the AKS cluster, run:"
echo "  az group delete --name kgateway-poc-rg --yes"
