#!/bin/bash
#===============================================================================
# AgentGateway Enterprise Demo Script
#
# Showcases:
# - A2A Protocol (Agent-to-Agent communication)
# - LLM-based intelligent routing
# - Multiple specialized AI agents
# - Full Langfuse observability
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Get Gateway IP
GATEWAY_IP=$(kubectl get gateway agentgateway -n kgateway-system -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)

if [ -z "$GATEWAY_IP" ]; then
    echo -e "${RED}Error: Could not get gateway IP. Is the cluster running?${NC}"
    exit 1
fi

BASE_URL="http://${GATEWAY_IP}:8080"

echo -e "${BOLD}${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                           ║"
echo "║                   🚀 AgentGateway Enterprise Demo                         ║"
echo "║                                                                           ║"
echo "║   Intelligent AI Agent Routing with Full Observability                    ║"
echo "║                                                                           ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${CYAN}Gateway URL: ${BOLD}${BASE_URL}${NC}"
echo -e "${CYAN}Langfuse Dashboard: ${BOLD}https://cloud.langfuse.com${NC}"
echo ""

pause() {
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read
}

section() {
    echo ""
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}  $1${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

#===============================================================================
# SECTION 1: Architecture Overview
#===============================================================================
section "1. Architecture Overview"

echo -e "This demo showcases an Enterprise AI Assistant built on ${BOLD}AgentGateway${NC}:"
echo ""
echo -e "  ${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
echo -e "  ${CYAN}│                     AgentGateway (${GATEWAY_IP}:8080)            │${NC}"
echo -e "  ${CYAN}│                                                                 │${NC}"
echo -e "  ${CYAN}│    /demo/ask  ──────►  Enterprise Orchestrator                  │${NC}"
echo -e "  ${CYAN}│                              │                                  │${NC}"
echo -e "  ${CYAN}│                              ▼ (LLM Routing)                    │${NC}"
echo -e "  ${CYAN}│         ┌──────────────────────────────────────────┐            │${NC}"
echo -e "  ${CYAN}│         │                    │                     │            │${NC}"
echo -e "  ${CYAN}│         ▼                    ▼                     ▼            │${NC}"
echo -e "  ${CYAN}│   Tech Support         HR Assistant         Knowledge Base     │${NC}"
echo -e "  ${CYAN}│   (IT Issues)          (Benefits/PTO)        (Company Info)     │${NC}"
echo -e "  ${CYAN}│                                                                 │${NC}"
echo -e "  ${CYAN}│                     All traces → Langfuse                       │${NC}"
echo -e "  ${CYAN}└─────────────────────────────────────────────────────────────────┘${NC}"
echo ""

pause

#===============================================================================
# SECTION 2: Discover Available Agents
#===============================================================================
section "2. Discover Available Agents (A2A Protocol)"

echo -e "Each agent exposes an ${BOLD}Agent Card${NC} at ${CYAN}/.well-known/agent.json${NC}"
echo -e "Let's list all available agents:"
echo ""
echo -e "${YELLOW}curl ${BASE_URL}/demo/agents | jq${NC}"
echo ""

curl -s "${BASE_URL}/demo/agents" | jq '.agents[] | {id, name, description, skills: [.card.skills[].name]}'

pause

#===============================================================================
# SECTION 3: Intelligent Routing Demo
#===============================================================================
section "3. Intelligent Routing - Tech Support Query"

echo -e "${BOLD}Scenario:${NC} An employee reports a VPN connection issue"
echo -e "The orchestrator uses ${BOLD}GPT-4o${NC} to decide which agent should handle it"
echo ""
echo -e "${YELLOW}Question: \"My VPN is not connecting, I get a timeout error\"${NC}"
echo ""

RESPONSE=$(curl -s -X POST "${BASE_URL}/demo/ask" \
    -H "Content-Type: application/json" \
    -d '{"message": "My VPN is not connecting, I get a timeout error"}')

echo -e "${CYAN}Routing Decision:${NC}"
echo "$RESPONSE" | jq '{routed_to, trace_id}'
echo ""
echo -e "${CYAN}Agent Response:${NC}"
echo "$RESPONSE" | jq -r '.response' | fold -s -w 80
echo ""
TRACE_ID=$(echo "$RESPONSE" | jq -r '.trace_id')
echo -e "${GREEN}✓ View trace in Langfuse: https://cloud.langfuse.com (search: ${TRACE_ID})${NC}"

pause

#===============================================================================
# SECTION 4: HR Query Routing
#===============================================================================
section "4. Intelligent Routing - HR Query"

echo -e "${BOLD}Scenario:${NC} An employee asks about PTO policy"
echo ""
echo -e "${YELLOW}Question: \"How many vacation days do I get after 4 years?\"${NC}"
echo ""

RESPONSE=$(curl -s -X POST "${BASE_URL}/demo/ask" \
    -H "Content-Type: application/json" \
    -d '{"message": "How many vacation days do I get after 4 years at the company?"}')

echo -e "${CYAN}Routing Decision:${NC}"
echo "$RESPONSE" | jq '{routed_to, trace_id}'
echo ""
echo -e "${CYAN}Agent Response:${NC}"
echo "$RESPONSE" | jq -r '.response' | fold -s -w 80
echo ""
TRACE_ID=$(echo "$RESPONSE" | jq -r '.trace_id')
echo -e "${GREEN}✓ View trace in Langfuse: https://cloud.langfuse.com (search: ${TRACE_ID})${NC}"

pause

#===============================================================================
# SECTION 5: Knowledge Base Query
#===============================================================================
section "5. Intelligent Routing - Knowledge Base Query"

echo -e "${BOLD}Scenario:${NC} An employee needs company information"
echo ""
echo -e "${YELLOW}Question: \"How do I submit an expense report?\"${NC}"
echo ""

RESPONSE=$(curl -s -X POST "${BASE_URL}/demo/ask" \
    -H "Content-Type: application/json" \
    -d '{"message": "How do I submit an expense report?"}')

echo -e "${CYAN}Routing Decision:${NC}"
echo "$RESPONSE" | jq '{routed_to, trace_id}'
echo ""
echo -e "${CYAN}Agent Response:${NC}"
echo "$RESPONSE" | jq -r '.response' | fold -s -w 80
echo ""
TRACE_ID=$(echo "$RESPONSE" | jq -r '.trace_id')
echo -e "${GREEN}✓ View trace in Langfuse: https://cloud.langfuse.com (search: ${TRACE_ID})${NC}"

pause

#===============================================================================
# SECTION 6: Direct Agent Access
#===============================================================================
section "6. Direct Agent Access (Bypassing Orchestrator)"

echo -e "You can also call agents directly without routing:"
echo ""
echo -e "${YELLOW}curl ${BASE_URL}/demo/ask/hr -d '{\"message\": \"What is the 401k match?\"}'{NC}"
echo ""

RESPONSE=$(curl -s -X POST "${BASE_URL}/demo/ask/hr" \
    -H "Content-Type: application/json" \
    -d '{"message": "What is the 401k match?"}')

echo -e "${CYAN}Direct HR Agent Response:${NC}"
echo "$RESPONSE" | jq -r '.response' | fold -s -w 80

pause

#===============================================================================
# SECTION 7: Langfuse Observability
#===============================================================================
section "7. Langfuse Observability"

echo -e "${BOLD}Every request is fully traced in Langfuse:${NC}"
echo ""
echo -e "  ${CYAN}╭─────────────────────────────────────────────────────────────╮${NC}"
echo -e "  ${CYAN}│  Trace: enterprise-assistant                                │${NC}"
echo -e "  ${CYAN}│    │                                                        │${NC}"
echo -e "  ${CYAN}│    ├── Generation: routing-decision                         │${NC}"
echo -e "  ${CYAN}│    │   └── Input/Output, Token usage, Model, Latency        │${NC}"
echo -e "  ${CYAN}│    │                                                        │${NC}"
echo -e "  ${CYAN}│    └── Span: agent-call                                     │${NC}"
echo -e "  ${CYAN}│        └── Nested trace in target agent                     │${NC}"
echo -e "  ${CYAN}│            └── Generation: {agent}-llm                      │${NC}"
echo -e "  ${CYAN}╰─────────────────────────────────────────────────────────────╯${NC}"
echo ""
echo -e "Features available in Langfuse dashboard:"
echo -e "  • ${GREEN}Full conversation traces${NC}"
echo -e "  • ${GREEN}Token usage and costs${NC}"
echo -e "  • ${GREEN}Latency breakdown${NC}"
echo -e "  • ${GREEN}Prompt/completion pairs${NC}"
echo -e "  • ${GREEN}Custom metadata and tags${NC}"
echo ""

pause

#===============================================================================
# SECTION 8: Quick Test Commands
#===============================================================================
section "8. Quick Test Commands"

echo -e "Use these commands to test the demo:"
echo ""
echo -e "${BOLD}List agents:${NC}"
echo -e "  ${YELLOW}curl ${BASE_URL}/demo/agents | jq${NC}"
echo ""
echo -e "${BOLD}Smart routing (auto-detect agent):${NC}"
echo -e "  ${YELLOW}curl -X POST ${BASE_URL}/demo/ask \\${NC}"
echo -e "  ${YELLOW}  -H 'Content-Type: application/json' \\${NC}"
echo -e "  ${YELLOW}  -d '{\"message\": \"Your question here\"}'${NC}"
echo ""
echo -e "${BOLD}Direct agent call:${NC}"
echo -e "  ${YELLOW}curl -X POST ${BASE_URL}/demo/ask/tech-support \\${NC}"
echo -e "  ${YELLOW}  -H 'Content-Type: application/json' \\${NC}"
echo -e "  ${YELLOW}  -d '{\"message\": \"Your IT question\"}'${NC}"
echo ""
echo -e "${BOLD}Langfuse Dashboard:${NC}"
echo -e "  ${CYAN}https://cloud.langfuse.com${NC}"
echo -e "  Project: ${CYAN}agentgateway-first${NC}"
echo ""

#===============================================================================
# SECTION 9: Summary
#===============================================================================
section "Demo Complete!"

echo -e "${BOLD}What we demonstrated:${NC}"
echo ""
echo -e "  ${GREEN}✓${NC} A2A Protocol - Agent discovery via .well-known/agent.json"
echo -e "  ${GREEN}✓${NC} LLM-based routing - GPT-4o decides which agent handles each request"
echo -e "  ${GREEN}✓${NC} Specialized agents - Tech Support, HR, Knowledge Base"
echo -e "  ${GREEN}✓${NC} Real LLM responses - Using Azure OpenAI GPT-4o"
echo -e "  ${GREEN}✓${NC} Full observability - Every call traced in Langfuse"
echo -e "  ${GREEN}✓${NC} Direct access - Option to bypass routing when needed"
echo ""
echo -e "${BOLD}${BLUE}Thank you for watching the AgentGateway demo!${NC}"
echo ""
