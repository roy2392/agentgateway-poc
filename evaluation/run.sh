#!/bin/bash
#
# Run AgentGateway Evaluation with LLM-as-a-Judge
#

set -e

# Get Gateway IP
GATEWAY_IP=$(kubectl get gateway agentgateway -n kgateway-system -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)

if [ -z "$GATEWAY_IP" ]; then
    echo "Error: Could not get gateway IP"
    exit 1
fi

GATEWAY_URL="http://${GATEWAY_IP}:8080"

echo "=================================="
echo "AgentGateway Evaluation"
echo "=================================="
echo "Gateway URL: ${GATEWAY_URL}"
echo ""

# Check required env vars
if [ -z "$LANGFUSE_PUBLIC_KEY" ] || [ -z "$LANGFUSE_SECRET_KEY" ]; then
    echo "Error: LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY must be set"
    echo ""
    echo "Set them with:"
    echo "  export LANGFUSE_PUBLIC_KEY='pk-lf-...'"
    echo "  export LANGFUSE_SECRET_KEY='sk-lf-...'"
    exit 1
fi

if [ -z "$AZURE_OPENAI_ENDPOINT" ] || [ -z "$AZURE_OPENAI_API_KEY" ]; then
    echo "Error: AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_API_KEY must be set for LLM-as-a-judge"
    echo ""
    echo "Set them with:"
    echo "  export AZURE_OPENAI_ENDPOINT='https://your-resource.openai.azure.com'"
    echo "  export AZURE_OPENAI_API_KEY='your-key'"
    exit 1
fi

# Install dependencies
pip install -q -r evaluation/requirements.txt

# Run evaluation
python evaluation/run_evaluation.py \
    --gateway-url "$GATEWAY_URL" \
    --dataset evaluation/dataset.json \
    "$@"
