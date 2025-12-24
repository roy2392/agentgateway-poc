# KGateway AI Agent Gateway POC

A production-ready Proof of Concept for deploying an AI Agent Gateway on Kubernetes using [KGateway](https://github.com/kgateway-dev/kgateway). Features multi-LLM support, A2A (Agent-to-Agent) protocol, MCP (Model Context Protocol) servers, and Langfuse observability.

## Features

- **Multi-LLM Support**: Azure OpenAI (GPT-4o) and Google Gemini (2.5 Flash)
- **A2A Protocol**: Agent-to-Agent communication with LLM-based routing
- **MCP Servers**: Web Fetch, Time Tools, and Prompt Management
- **Langfuse Integration**: Full LLM observability and tracing
- **Dynamic Agent**: Agent that fetches system prompts from MCP server
- **AgentGateway UI**: Built-in dashboard for managing routes and testing

## Architecture

```
                            AgentGateway (External IP:8080)
                                         │
    ┌──────────┬──────────┬──────────┬───┴───┬──────────┬──────────┬──────────┐
    │          │          │          │       │          │          │          │
 /a2a-llm   /azure    /gemini   /dynamic  /mcp/*   /a2a-traced  /azure-traced
    │          │          │          │       │          │          │
    ▼          ▼          ▼          ▼       ▼          ▼          ▼
┌────────┐ ┌───────┐ ┌───────┐ ┌────────┐ ┌─────┐  ┌─────────────────────┐
│  A2A   │ │ Azure │ │Gemini │ │Dynamic │ │ MCP │  │  Langfuse Traced    │
│Orchestr│ │GPT-4o │ │ Flash │ │ Agent  │ │Servs│  │     Endpoints       │
└───┬────┘ └───────┘ └───────┘ └────────┘ └─────┘  └─────────────────────┘
    │
    ├── Research Agent (LLM + MCP Fetch)
    ├── Coding Agent (LLM)
    └── Support Agent (LLM)
```

## Prerequisites

- **Kubernetes Cluster** (AKS, GKE, EKS, or local)
- **kubectl** configured
- **Helm 3**
- **kubelogin** (for Azure AD enabled AKS)
  ```bash
  brew install Azure/kubelogin/kubelogin
  ```
- **LLM API Keys**:
  - Azure OpenAI endpoint and API key
  - Google Gemini API key (optional)
  - Langfuse API keys (optional, for observability)

## Quick Start

### One-Click Deploy

```bash
# Clone the repository
git clone https://github.com/your-org/kgateway-azure-poc.git
cd kgateway-azure-poc

# Set your API keys
export AZURE_ENDPOINT="https://your-resource.openai.azure.com"
export AZURE_API_KEY="your-azure-api-key"
export GEMINI_API_KEY="your-gemini-api-key"  # optional

# Deploy everything
./deploy.sh
```

### Step-by-Step

```bash
# 1. Create AKS cluster (if needed)
./01-create-aks-cluster.sh

# 2. Install KGateway
./02-install-kgateway.sh

# 3. Deploy AI components
kubectl apply -f manifests/
```

## Endpoints

| Endpoint | Description | Features |
|----------|-------------|----------|
| `/azure` | Azure OpenAI GPT-4o | Direct LLM access |
| `/gemini` | Google Gemini Flash | Direct LLM access |
| `/a2a-llm/*` | A2A with Real LLMs | LLM routing, multi-agent |
| `/dynamic/*` | Dynamic Agent | MCP prompts, multi-persona |
| `/mcp/fetch` | MCP Fetch Server | Web content fetching |
| `/mcp/time` | MCP Time Server | Timezone tools |
| `/mcp/prompts` | MCP Prompts | Centralized prompts |
| `/a2a-traced/*` | A2A + Langfuse | Full tracing |
| `/azure-traced` | Azure + Langfuse | LLM tracing |

## A2A Protocol (Agent-to-Agent)

The POC implements a production-ready A2A setup with:

- **LLM-based routing**: Orchestrator uses AI to decide which agent handles each request
- **Real LLM responses**: All agents use Azure OpenAI or Gemini
- **MCP integration**: Research agent can fetch web content
- **Langfuse tracing**: Full observability

### A2A Agents

| Agent | Skills | Use Cases |
|-------|--------|-----------|
| Research Agent | research, web-fetch | Topic research, web summaries |
| Coding Agent | code-review, generate, debug | Code assistance |
| Support Agent | inquiries, issues, accounts | Customer support |

### Using A2A

```bash
# Get gateway IP
GATEWAY_IP=$(kubectl get gateway agentgateway -n kgateway-system -o jsonpath='{.status.addresses[0].value}')

# Smart routing (LLM decides which agent)
curl -X POST "http://${GATEWAY_IP}:8080/a2a-llm/orchestrate" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Explain Kubernetes networking",
    "provider": "azure"
  }'

# Direct delegation
curl -X POST "http://${GATEWAY_IP}:8080/a2a-llm/delegate" \
  -H "Content-Type: application/json" \
  -d '{
    "agent": "coding",
    "message": "Write a Python quicksort",
    "provider": "azure"
  }'

# List agents and their capabilities
curl "http://${GATEWAY_IP}:8080/a2a-llm/agents"
```

### A2A Agent Cards

Each agent exposes capabilities via `/.well-known/agent.json`:

```bash
curl "http://${GATEWAY_IP}:8080/a2a-llm/agents" | jq '.agents[].card'
```

## Langfuse Observability

### Setup

```bash
# Create Langfuse secrets
kubectl create secret generic langfuse-secrets \
  --namespace ai-agents \
  --from-literal=langfuse-public-key="pk-lf-xxx" \
  --from-literal=langfuse-secret-key="sk-lf-xxx" \
  --from-literal=langfuse-host="https://cloud.langfuse.com"

# Deploy Langfuse-enabled components
kubectl apply -f manifests/10-langfuse-integration.yaml
kubectl apply -f manifests/11-a2a-production.yaml
```

### Traced Endpoints

```bash
# A2A with full tracing
curl -X POST "http://${GATEWAY_IP}:8080/a2a-llm/orchestrate" \
  -H "Content-Type: application/json" \
  -d '{"message": "Help with billing", "provider": "azure"}'

# Response includes trace_id for Langfuse lookup
```

### What's Traced

- **`a2a-orchestration`**: Main trace with input/output
- **`routing-llm-call`**: Generation span showing agent selection
- **`a2a-agent-call`**: Span with agent response

## MCP Servers

### Fetch Server
```bash
# Fetch and process web content
curl -X POST "http://${GATEWAY_IP}:8080/mcp/fetch/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"fetch","arguments":{"url":"https://example.com"}}}'
```

### Time Server
```bash
# Get current time in timezone
curl -X POST "http://${GATEWAY_IP}:8080/mcp/time/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_current_time","arguments":{"timezone":"America/New_York"}}}'
```

### Prompts Server
```bash
# List available prompts/personas
curl "http://${GATEWAY_IP}:8080/dynamic/prompts"
```

## Dynamic Agent

Multi-persona agent that fetches prompts from MCP server:

```bash
# Chat as Research Agent
curl -X POST "http://${GATEWAY_IP}:8080/dynamic/chat" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Explain microservices",
    "agent_type": "research-agent",
    "llm_provider": "azure"
  }'

# Available personas: research-agent, coding-agent, customer-support-agent, data-analyst-agent
```

## Configuration

### Update LLM API Keys

```bash
kubectl create secret generic llm-secrets \
  --namespace ai-agents \
  --from-literal=azure-endpoint="YOUR_ENDPOINT" \
  --from-literal=azure-api-key="YOUR_KEY" \
  --from-literal=azure-deployment="gpt-4o" \
  --from-literal=gemini-api-key="YOUR_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment -n ai-agents
```

### Access AgentGateway UI

```bash
kubectl port-forward -n kgateway-system deploy/agentgateway 15000:15000
# Open http://localhost:15000/ui
```

## Project Structure

```
kgateway-azure-poc/
├── deploy.sh                     # One-click deploy
├── cleanup.sh                    # Remove all resources
├── grant-access.sh               # Grant AKS access to users
├── 01-create-aks-cluster.sh      # Create AKS cluster
├── 02-install-kgateway.sh        # Install KGateway
├── manifests/
│   ├── 01-namespace.yaml         # ai-agents namespace
│   ├── 02-mcp-servers.yaml       # MCP Fetch & Time servers
│   ├── 03-llm-proxies.yaml       # Azure & Gemini proxies
│   ├── 04-mcp-prompts.yaml       # MCP Prompts server
│   ├── 05-dynamic-agent.yaml     # Dynamic multi-persona agent
│   ├── 06-agentgateway.yaml      # AgentGateway resource
│   ├── 07-backends.yaml          # Backend configurations
│   ├── 08-routes.yaml            # HTTP routes
│   ├── 09-a2a-agents.yaml        # Basic A2A agents (mock)
│   ├── 10-langfuse-integration.yaml  # Langfuse tracing
│   └── 11-a2a-production.yaml    # Production A2A with real LLMs
└── README.md
```

## Cleanup

```bash
# Remove POC resources (keeps cluster)
./cleanup.sh

# Delete entire resource group (including cluster)
az group delete --name kgateway-poc-rg --yes
```

## Granting Access

```bash
# Grant access to team member
./grant-access.sh user@company.com

# User can then access with:
az login
az aks get-credentials --resource-group kgateway-poc-rg --name kgateway-poc-aks
```

## Troubleshooting

```bash
# Check pods
kubectl get pods -n ai-agents
kubectl get pods -n kgateway-system

# View logs
kubectl logs -n ai-agents deploy/a2a-orchestrator-llm
kubectl logs -n kgateway-system deploy/agentgateway

# Check routes
kubectl get httproutes -n kgateway-system
kubectl get backends -n kgateway-system

# Test connectivity
GATEWAY_IP=$(kubectl get gateway agentgateway -n kgateway-system -o jsonpath='{.status.addresses[0].value}')
curl "http://${GATEWAY_IP}:8080/a2a-llm/health"
```

## Resources

- [KGateway Documentation](https://kgateway.dev/docs/)
- [AgentGateway Documentation](https://agentgateway.dev/docs/)
- [A2A Protocol](https://google.github.io/A2A/)
- [MCP Protocol](https://modelcontextprotocol.io/)
- [Langfuse Documentation](https://langfuse.com/docs)

## License

MIT
