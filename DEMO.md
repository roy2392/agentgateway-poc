# AgentGateway Enterprise Demo Guide

## Overview

This demo showcases an **Enterprise AI Help Desk** built on AgentGateway, featuring:

- **A2A Protocol** - Agent-to-Agent communication standard
- **LLM-based Routing** - GPT-4o decides which specialist handles each request
- **Multiple AI Agents** - Tech Support, HR, Knowledge Base
- **Langfuse Observability** - Full tracing of all LLM calls

## Quick Start

```bash
# Run the automated demo script
./demo-script.sh
```

## Architecture

```
                    AgentGateway (External IP:8080)
                              │
                              ▼
                     /demo/* Route
                              │
                              ▼
                    ┌─────────────────┐
                    │   Orchestrator  │
                    │   (LLM Routing) │
                    └────────┬────────┘
                             │
           ┌─────────────────┼─────────────────┐
           ▼                 ▼                 ▼
    ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
    │Tech Support │   │HR Assistant │   │Knowledge Base│
    │  (GPT-4o)   │   │  (GPT-4o)   │   │   (GPT-4o)   │
    └─────────────┘   └─────────────┘   └─────────────┘
           │                 │                 │
           └─────────────────┼─────────────────┘
                             ▼
                         Langfuse
                    (All traces visible)
```

## Demo Scenarios

### Scenario 1: IT Support Request

**Employee asks about VPN issues → Routed to Tech Support**

```bash
curl -X POST "http://<GATEWAY_IP>:8080/demo/ask" \
  -H "Content-Type: application/json" \
  -d '{"message": "My VPN keeps disconnecting. What should I do?"}'
```

Expected routing: `tech-support`

### Scenario 2: HR Question

**Employee asks about benefits → Routed to HR Assistant**

```bash
curl -X POST "http://<GATEWAY_IP>:8080/demo/ask" \
  -H "Content-Type: application/json" \
  -d '{"message": "How many vacation days do I get after 3 years?"}'
```

Expected routing: `hr`

### Scenario 3: Company Information

**Employee asks about procedures → Routed to Knowledge Base**

```bash
curl -X POST "http://<GATEWAY_IP>:8080/demo/ask" \
  -H "Content-Type: application/json" \
  -d '{"message": "How do I submit an expense report?"}'
```

Expected routing: `knowledge-base`

## Key Talking Points

### 1. A2A Protocol
- Each agent has an **Agent Card** at `/.well-known/agent.json`
- Standardized discovery and communication
- List all agents: `GET /demo/agents`

### 2. Intelligent Routing
- Uses GPT-4o to analyze the request
- Automatically routes to the right specialist
- No keyword matching - true semantic understanding

### 3. Full Observability (Langfuse)
- Every request creates a trace
- See routing decisions
- Track token usage and costs
- View prompt/completion pairs

### 4. Direct Access
- Can bypass routing for specific agents
- `POST /demo/ask/tech-support` - Direct to tech support
- `POST /demo/ask/hr` - Direct to HR
- `POST /demo/ask/knowledge-base` - Direct to KB

## Langfuse Dashboard

- **URL**: https://cloud.langfuse.com
- **Project**: agentgateway-first

What you'll see in traces:
- `enterprise-assistant` - Main orchestration trace
- `routing-decision` - LLM generation for agent selection
- `agent-call` - Span showing agent communication
- `{agent}-llm` - Individual agent LLM calls

## Sample Questions by Agent

### Tech Support
- "My laptop is running slow"
- "I can't connect to WiFi"
- "How do I reset my password?"
- "Outlook keeps crashing"
- "The VPN is not working"

### HR Assistant
- "How many sick days do I have?"
- "What are the health insurance options?"
- "What's the 401k match?"
- "How do I request parental leave?"
- "What's the remote work policy?"

### Knowledge Base
- "Where is the London office?"
- "How do I book a meeting room?"
- "What's the expense report process?"
- "Who is the CEO?"
- "How do I register a visitor?"

## Commands Reference

```bash
# Get Gateway IP
GATEWAY_IP=$(kubectl get gateway agentgateway -n kgateway-system -o jsonpath='{.status.addresses[0].value}')

# List agents
curl "http://${GATEWAY_IP}:8080/demo/agents" | jq

# Smart routing
curl -X POST "http://${GATEWAY_IP}:8080/demo/ask" \
  -H "Content-Type: application/json" \
  -d '{"message": "Your question here"}'

# Direct agent call
curl -X POST "http://${GATEWAY_IP}:8080/demo/ask/hr" \
  -H "Content-Type: application/json" \
  -d '{"message": "What is the 401k match?"}'

# Check agent health
curl "http://${GATEWAY_IP}:8080/demo/health"
```

## Troubleshooting

```bash
# Check demo pods
kubectl get pods -n ai-agents -l demo=enterprise-assistant

# View orchestrator logs
kubectl logs -n ai-agents deploy/demo-orchestrator

# View agent logs
kubectl logs -n ai-agents deploy/demo-tech-support
kubectl logs -n ai-agents deploy/demo-hr-assistant
kubectl logs -n ai-agents deploy/demo-knowledge-base

# Check routes
kubectl get httproutes -n kgateway-system | grep demo
```
