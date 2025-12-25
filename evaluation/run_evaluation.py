#!/usr/bin/env python3
"""
AgentGateway Evaluation Script with LLM-as-a-Judge

This script:
1. Loads the evaluation dataset
2. Runs each test case against the demo endpoint
3. Uses LLM-as-a-judge to evaluate responses
4. Uploads results to Langfuse for analysis

Usage:
    pip install langfuse requests openai
    export LANGFUSE_PUBLIC_KEY="pk-lf-..."
    export LANGFUSE_SECRET_KEY="sk-lf-..."
    export AZURE_OPENAI_ENDPOINT="https://..."
    export AZURE_OPENAI_API_KEY="..."
    python run_evaluation.py --gateway-url http://52.147.214.252:8080
"""

import os
import json
import time
import argparse
import requests
from datetime import datetime
from langfuse import Langfuse

# Initialize Langfuse
langfuse = Langfuse(
    public_key=os.environ.get('LANGFUSE_PUBLIC_KEY'),
    secret_key=os.environ.get('LANGFUSE_SECRET_KEY'),
    host=os.environ.get('LANGFUSE_HOST', 'https://cloud.langfuse.com')
)

# LLM-as-a-Judge prompts
ROUTING_JUDGE_PROMPT = """You are evaluating an AI routing system that directs user queries to specialized agents.

User Query: {input}
Expected Agent: {expected_agent}
Actual Agent: {actual_agent}

Evaluate whether the routing decision was correct.

Score from 0-1:
- 1.0: Correct routing to expected agent
- 0.5: Reasonable alternative routing (query could go to multiple agents)
- 0.0: Incorrect routing

Respond with ONLY a JSON object:
{{"score": <number>, "reasoning": "<brief explanation>"}}"""

QUALITY_JUDGE_PROMPT = """You are evaluating an AI assistant's response quality for an enterprise help desk.

User Query: {input}
Agent Response: {response}
Quality Criteria: {criteria}
Expected Content (if any): {expected_content}

Evaluate the response on these dimensions:
1. Relevance: Does it address the user's question?
2. Accuracy: Is the information correct based on expected content?
3. Helpfulness: Does it provide actionable guidance?
4. Professionalism: Is the tone appropriate for enterprise support?

Score from 0-1 (average of all dimensions).

Respond with ONLY a JSON object:
{{"score": <number>, "relevance": <0-1>, "accuracy": <0-1>, "helpfulness": <0-1>, "professionalism": <0-1>, "reasoning": "<brief explanation>"}}"""

FACTUALITY_JUDGE_PROMPT = """You are checking if an AI response contains specific required information.

User Query: {input}
Agent Response: {response}
Must Contain: {expected_content}

Check if the response contains the expected content (exact or semantic match).

Score:
- 1.0: All expected content present
- 0.5: Partial match
- 0.0: Missing expected content

Respond with ONLY a JSON object:
{{"score": <number>, "found": [<list of found items>], "missing": [<list of missing items>], "reasoning": "<brief explanation>"}}"""


def call_azure_openai(prompt: str) -> dict:
    """Call Azure OpenAI for LLM-as-a-judge evaluation"""
    endpoint = os.environ.get('AZURE_OPENAI_ENDPOINT')
    api_key = os.environ.get('AZURE_OPENAI_API_KEY')
    deployment = os.environ.get('AZURE_OPENAI_DEPLOYMENT', 'gpt-4o')

    if not endpoint or not api_key:
        raise ValueError("AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_API_KEY must be set")

    url = f"{endpoint}/openai/deployments/{deployment}/chat/completions?api-version=2024-02-15-preview"

    response = requests.post(
        url,
        headers={
            "Content-Type": "application/json",
            "api-key": api_key
        },
        json={
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 500,
            "temperature": 0
        },
        timeout=60
    )
    response.raise_for_status()

    content = response.json()['choices'][0]['message']['content']

    # Parse JSON from response
    try:
        # Handle potential markdown code blocks
        if '```json' in content:
            content = content.split('```json')[1].split('```')[0]
        elif '```' in content:
            content = content.split('```')[1].split('```')[0]
        return json.loads(content.strip())
    except json.JSONDecodeError:
        return {"score": 0, "reasoning": f"Failed to parse: {content}"}


def run_demo_query(gateway_url: str, message: str) -> dict:
    """Run a query against the demo endpoint"""
    response = requests.post(
        f"{gateway_url}/demo/ask",
        headers={"Content-Type": "application/json"},
        json={"message": message},
        timeout=120
    )
    response.raise_for_status()
    return response.json()


def evaluate_routing(item: dict, result: dict) -> dict:
    """Evaluate if the query was routed to the correct agent"""
    prompt = ROUTING_JUDGE_PROMPT.format(
        input=item['input'],
        expected_agent=item['expected_agent'],
        actual_agent=result.get('routed_to', {}).get('agent', 'unknown')
    )

    return call_azure_openai(prompt)


def evaluate_quality(item: dict, result: dict) -> dict:
    """Evaluate the quality of the response"""
    expected_content = item.get('expected_answer_contains', 'N/A')
    if isinstance(expected_content, list):
        expected_content = ', '.join(expected_content)

    prompt = QUALITY_JUDGE_PROMPT.format(
        input=item['input'],
        response=result.get('response', 'No response'),
        criteria=item.get('quality_criteria', 'Provide helpful response'),
        expected_content=expected_content
    )

    return call_azure_openai(prompt)


def evaluate_factuality(item: dict, result: dict) -> dict:
    """Check if response contains expected content"""
    expected_content = item.get('expected_answer_contains')
    if not expected_content:
        return {"score": 1.0, "reasoning": "No expected content specified"}

    if isinstance(expected_content, str):
        expected_content = [expected_content]

    prompt = FACTUALITY_JUDGE_PROMPT.format(
        input=item['input'],
        response=result.get('response', 'No response'),
        expected_content=', '.join(expected_content)
    )

    return call_azure_openai(prompt)


def run_evaluation(gateway_url: str, dataset_path: str, run_name: str = None):
    """Run full evaluation suite"""

    # Load dataset
    with open(dataset_path, 'r') as f:
        dataset = json.load(f)

    if not run_name:
        run_name = f"eval-{datetime.now().strftime('%Y%m%d-%H%M%S')}"

    print(f"\n{'='*60}")
    print(f"  AgentGateway Evaluation: {run_name}")
    print(f"  Dataset: {dataset['name']}")
    print(f"  Items: {len(dataset['items'])}")
    print(f"{'='*60}\n")

    results = []

    for i, item in enumerate(dataset['items']):
        print(f"[{i+1}/{len(dataset['items'])}] Testing: {item['id']}")
        print(f"    Query: {item['input'][:50]}...")

        # Create trace for this evaluation
        trace = langfuse.trace(
            name="evaluation-run",
            metadata={
                "run_name": run_name,
                "item_id": item['id'],
                "category": item['category'],
                "expected_agent": item['expected_agent']
            },
            tags=["evaluation", item['category'], run_name]
        )

        try:
            # Run the query
            start_time = time.time()
            demo_result = run_demo_query(gateway_url, item['input'])
            latency = time.time() - start_time

            actual_agent = demo_result.get('routed_to', {}).get('agent', 'unknown')
            response_text = demo_result.get('response', '')

            print(f"    Routed to: {actual_agent} ({latency:.2f}s)")

            # Create span for the demo call
            demo_span = langfuse.span(
                trace_id=trace.id,
                name="demo-api-call",
                input={"message": item['input']},
                output=demo_result,
                metadata={"latency_seconds": latency}
            )
            demo_span.end()

            # Run evaluations
            eval_results = {}

            # 1. Routing evaluation
            if item['expected_agent'] != 'any':
                routing_eval = evaluate_routing(item, demo_result)
                eval_results['routing'] = routing_eval

                langfuse.score(
                    trace_id=trace.id,
                    name="routing-accuracy",
                    value=routing_eval.get('score', 0),
                    comment=routing_eval.get('reasoning', '')
                )
                print(f"    Routing Score: {routing_eval.get('score', 0):.2f}")

            # 2. Quality evaluation
            quality_eval = evaluate_quality(item, demo_result)
            eval_results['quality'] = quality_eval

            langfuse.score(
                trace_id=trace.id,
                name="response-quality",
                value=quality_eval.get('score', 0),
                comment=quality_eval.get('reasoning', '')
            )
            print(f"    Quality Score: {quality_eval.get('score', 0):.2f}")

            # 3. Factuality evaluation (if expected content specified)
            if item.get('expected_answer_contains'):
                factuality_eval = evaluate_factuality(item, demo_result)
                eval_results['factuality'] = factuality_eval

                langfuse.score(
                    trace_id=trace.id,
                    name="factuality",
                    value=factuality_eval.get('score', 0),
                    comment=factuality_eval.get('reasoning', '')
                )
                print(f"    Factuality Score: {factuality_eval.get('score', 0):.2f}")

            # Calculate overall score
            scores = [e.get('score', 0) for e in eval_results.values()]
            overall_score = sum(scores) / len(scores) if scores else 0

            langfuse.score(
                trace_id=trace.id,
                name="overall",
                value=overall_score,
                comment="Average of all evaluation dimensions"
            )

            results.append({
                "item_id": item['id'],
                "category": item['category'],
                "input": item['input'],
                "actual_agent": actual_agent,
                "expected_agent": item['expected_agent'],
                "response_preview": response_text[:200],
                "latency": latency,
                "evaluations": eval_results,
                "overall_score": overall_score,
                "trace_id": trace.id,
                "status": "success"
            })

        except Exception as e:
            print(f"    ERROR: {str(e)}")
            results.append({
                "item_id": item['id'],
                "category": item['category'],
                "input": item['input'],
                "status": "error",
                "error": str(e)
            })

        # Flush after each item
        langfuse.flush()
        print()

    # Summary
    print(f"\n{'='*60}")
    print("  EVALUATION SUMMARY")
    print(f"{'='*60}")

    successful = [r for r in results if r['status'] == 'success']

    if successful:
        avg_overall = sum(r['overall_score'] for r in successful) / len(successful)
        avg_latency = sum(r['latency'] for r in successful) / len(successful)

        routing_scores = [r['evaluations'].get('routing', {}).get('score', 0)
                         for r in successful if 'routing' in r.get('evaluations', {})]
        quality_scores = [r['evaluations'].get('quality', {}).get('score', 0)
                         for r in successful]
        factuality_scores = [r['evaluations'].get('factuality', {}).get('score', 0)
                            for r in successful if 'factuality' in r.get('evaluations', {})]

        print(f"\n  Total Items: {len(results)}")
        print(f"  Successful: {len(successful)}")
        print(f"  Failed: {len(results) - len(successful)}")
        print(f"\n  Average Scores:")
        print(f"    Overall:    {avg_overall:.2%}")
        if routing_scores:
            print(f"    Routing:    {sum(routing_scores)/len(routing_scores):.2%}")
        print(f"    Quality:    {sum(quality_scores)/len(quality_scores):.2%}")
        if factuality_scores:
            print(f"    Factuality: {sum(factuality_scores)/len(factuality_scores):.2%}")
        print(f"\n  Average Latency: {avg_latency:.2f}s")

        # By category
        categories = set(r['category'] for r in successful)
        print(f"\n  By Category:")
        for cat in sorted(categories):
            cat_results = [r for r in successful if r['category'] == cat]
            cat_avg = sum(r['overall_score'] for r in cat_results) / len(cat_results)
            print(f"    {cat}: {cat_avg:.2%} ({len(cat_results)} items)")

    print(f"\n  View results in Langfuse: https://cloud.langfuse.com")
    print(f"  Filter by tag: {run_name}")
    print(f"{'='*60}\n")

    # Save results to file
    output_file = f"evaluation/results-{run_name}.json"
    with open(output_file, 'w') as f:
        json.dump({
            "run_name": run_name,
            "timestamp": datetime.now().isoformat(),
            "gateway_url": gateway_url,
            "dataset": dataset['name'],
            "results": results,
            "summary": {
                "total": len(results),
                "successful": len(successful),
                "average_overall_score": avg_overall if successful else 0
            }
        }, f, indent=2)
    print(f"  Results saved to: {output_file}\n")

    return results


def create_dataset_in_langfuse(dataset_path: str):
    """Upload dataset to Langfuse for tracking"""
    with open(dataset_path, 'r') as f:
        dataset = json.load(f)

    # Create or get dataset
    langfuse_dataset = langfuse.create_dataset(
        name=dataset['name'],
        description=dataset['description'],
        metadata={"source": "evaluation/dataset.json"}
    )

    # Add items
    for item in dataset['items']:
        langfuse_dataset.create_item(
            input={"message": item['input']},
            expected_output={
                "agent": item['expected_agent'],
                "topics": item['expected_topics'],
                "quality_criteria": item['quality_criteria'],
                "expected_content": item.get('expected_answer_contains')
            },
            metadata={
                "id": item['id'],
                "category": item['category']
            }
        )

    print(f"Dataset '{dataset['name']}' created in Langfuse with {len(dataset['items'])} items")
    return langfuse_dataset


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Run AgentGateway Evaluation')
    parser.add_argument('--gateway-url', required=True, help='Gateway URL (e.g., http://52.147.214.252:8080)')
    parser.add_argument('--dataset', default='evaluation/dataset.json', help='Path to dataset JSON')
    parser.add_argument('--run-name', help='Name for this evaluation run')
    parser.add_argument('--upload-dataset', action='store_true', help='Upload dataset to Langfuse')

    args = parser.parse_args()

    if args.upload_dataset:
        create_dataset_in_langfuse(args.dataset)
    else:
        run_evaluation(args.gateway_url, args.dataset, args.run_name)
