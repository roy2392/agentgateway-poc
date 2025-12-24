#!/bin/bash
set -e

#######################################
# KGateway AI Agent POC - One-Click Deploy
# This script deploys the complete AI agent environment
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KGATEWAY_VERSION="v2.1.2"
GATEWAY_API_VERSION="v1.4.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        exit 1
    fi
    print_success "kubectl is installed"

    if ! command -v helm &> /dev/null; then
        print_error "helm is not installed"
        exit 1
    fi
    print_success "helm is installed"

    # Check for kubelogin (required for Azure AD enabled AKS clusters)
    if ! command -v kubelogin &> /dev/null; then
        print_warning "kubelogin is not installed (required for Azure AD auth)"
        echo "Install with: brew install Azure/kubelogin/kubelogin"
        echo "Or download from: https://github.com/Azure/kubelogin/releases"
    else
        print_success "kubelogin is installed"
    fi

    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        echo "Please ensure you are connected to a Kubernetes cluster"
        exit 1
    fi
    print_success "Connected to Kubernetes cluster"
}

# Create secrets
create_secrets() {
    print_header "Configuring LLM API Keys"

    # Check for environment variables or prompt
    if [ -z "$AZURE_ENDPOINT" ]; then
        echo -e "${YELLOW}Enter Azure OpenAI Endpoint (or press Enter to skip):${NC}"
        read -r AZURE_ENDPOINT
    fi

    if [ -z "$AZURE_API_KEY" ]; then
        echo -e "${YELLOW}Enter Azure OpenAI API Key (or press Enter to skip):${NC}"
        read -r -s AZURE_API_KEY
        echo ""
    fi

    if [ -z "$GEMINI_API_KEY" ]; then
        echo -e "${YELLOW}Enter Google Gemini API Key (or press Enter to skip):${NC}"
        read -r -s GEMINI_API_KEY
        echo ""
    fi

    # Create namespace first
    kubectl apply -f "${SCRIPT_DIR}/manifests/01-namespace.yaml"

    # Create secrets
    kubectl create secret generic llm-secrets \
        --namespace ai-agents \
        --from-literal=azure-endpoint="${AZURE_ENDPOINT:-https://placeholder.openai.azure.com}" \
        --from-literal=azure-api-key="${AZURE_API_KEY:-placeholder}" \
        --from-literal=azure-deployment="${AZURE_DEPLOYMENT:-gpt-4o}" \
        --from-literal=gemini-api-key="${GEMINI_API_KEY:-placeholder}" \
        --dry-run=client -o yaml | kubectl apply -f -

    print_success "Secrets configured"
}

# Install KGateway
install_kgateway() {
    print_header "Installing KGateway"

    echo "Installing Kubernetes Gateway API CRDs..."
    kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
    kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/experimental-install.yaml"
    print_success "Gateway API CRDs installed"

    echo "Installing KGateway CRDs..."
    helm upgrade -i --create-namespace \
        --namespace kgateway-system \
        --version ${KGATEWAY_VERSION} \
        kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds
    print_success "KGateway CRDs installed"

    echo "Installing KGateway control plane with AgentGateway..."
    helm upgrade -i \
        --namespace kgateway-system \
        --version ${KGATEWAY_VERSION} \
        --set agentgateway.enabled=true \
        kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway
    print_success "KGateway installed"

    echo "Waiting for KGateway to be ready..."
    kubectl wait --namespace kgateway-system \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=kgateway \
        --timeout=120s
    print_success "KGateway is ready"

    # Wait for agentgateway GatewayClass
    echo "Waiting for AgentGateway GatewayClass..."
    for i in {1..30}; do
        if kubectl get gatewayclass agentgateway &> /dev/null; then
            print_success "AgentGateway GatewayClass is ready"
            break
        fi
        sleep 2
    done
}

# Deploy AI components
deploy_components() {
    print_header "Deploying AI Components"

    echo "Deploying MCP Servers..."
    kubectl apply -f "${SCRIPT_DIR}/manifests/02-mcp-servers.yaml"
    print_success "MCP Servers deployed"

    echo "Deploying LLM Proxies..."
    kubectl apply -f "${SCRIPT_DIR}/manifests/03-llm-proxies.yaml"
    print_success "LLM Proxies deployed"

    echo "Deploying MCP Prompts Server..."
    kubectl apply -f "${SCRIPT_DIR}/manifests/04-mcp-prompts.yaml"
    print_success "MCP Prompts Server deployed"

    echo "Deploying Dynamic Agent..."
    kubectl apply -f "${SCRIPT_DIR}/manifests/05-dynamic-agent.yaml"
    print_success "Dynamic Agent deployed"

    echo "Waiting for pods to be ready..."
    kubectl wait --namespace ai-agents \
        --for=condition=ready pod \
        --all \
        --timeout=180s || true
    print_success "AI Components deployed"
}

# Configure AgentGateway
configure_gateway() {
    print_header "Configuring AgentGateway"

    echo "Creating AgentGateway..."
    kubectl apply -f "${SCRIPT_DIR}/manifests/06-agentgateway.yaml"
    print_success "AgentGateway created"

    echo "Creating Backends..."
    kubectl apply -f "${SCRIPT_DIR}/manifests/07-backends.yaml"
    print_success "Backends created"

    echo "Creating Routes..."
    kubectl apply -f "${SCRIPT_DIR}/manifests/08-routes.yaml"
    print_success "Routes created"

    echo "Waiting for AgentGateway pod..."
    kubectl wait --namespace kgateway-system \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=agentgateway \
        --timeout=120s || true

    # Wait for external IP
    echo "Waiting for external IP..."
    for i in {1..30}; do
        GATEWAY_IP=$(kubectl get gateway agentgateway -n kgateway-system -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
        if [ -n "$GATEWAY_IP" ] && [ "$GATEWAY_IP" != "null" ]; then
            print_success "External IP: $GATEWAY_IP"
            break
        fi
        sleep 10
    done
}

# Print summary
print_summary() {
    print_header "Deployment Complete!"

    GATEWAY_IP=$(kubectl get gateway agentgateway -n kgateway-system -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "pending")

    echo ""
    echo -e "${GREEN}Your AI Agent Environment is ready!${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}AgentGateway Endpoints:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Azure GPT-4o:      http://${GATEWAY_IP}:8080/azure"
    echo "  Gemini 2.5 Flash:  http://${GATEWAY_IP}:8080/gemini"
    echo "  Dynamic Agent:     http://${GATEWAY_IP}:8080/dynamic"
    echo "  MCP Prompts:       http://${GATEWAY_IP}:8080/mcp/prompts"
    echo "  MCP Fetch:         http://${GATEWAY_IP}:8080/mcp/fetch"
    echo "  MCP Time:          http://${GATEWAY_IP}:8080/mcp/time"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}AgentGateway UI:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Run: kubectl port-forward -n kgateway-system deploy/agentgateway 15000:15000"
    echo "  Then open: http://localhost:15000/ui"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}Quick Test:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  curl -X POST \"http://${GATEWAY_IP}:8080/dynamic/chat\" \\"
    echo "    -H \"Content-Type: application/json\" \\"
    echo "    -d '{\"message\": \"Hello!\", \"agent_type\": \"research-agent\", \"llm_provider\": \"azure\"}'"
    echo ""
}

# Main
main() {
    print_header "KGateway AI Agent POC Deployment"
    echo ""
    echo "This script will deploy:"
    echo "  • KGateway with AgentGateway"
    echo "  • MCP Servers (Fetch, Time, Prompts)"
    echo "  • LLM Proxies (Azure OpenAI, Google Gemini)"
    echo "  • Dynamic Agent with centralized prompts"
    echo ""

    check_prerequisites
    create_secrets
    install_kgateway
    deploy_components
    configure_gateway
    print_summary
}

main "$@"
