#!/usr/bin/env python3
"""
Single Prompt Test for vLLM with eBPF Tracing

Tests vLLM inference with a single prompt while eBPF sidecar
captures CUDA API calls in the background.

Usage:
    python3 single-prompt.py [--host HOST] [--port PORT]
"""

import argparse
import json
import time
from datetime import datetime

import requests


def send_prompt(host: str, port: int, prompt: str) -> dict:
    """Send a prompt to vLLM and return the response with timing."""
    url = f"http://{host}:{port}/v1/completions"

    payload = {
        "model": "meta-llama/Llama-2-7b-hf",
        "prompt": prompt,
        "max_tokens": 100,
        "temperature": 0.7,
        "top_p": 0.9,
        "stream": False
    }

    headers = {
        "Content-Type": "application/json"
    }

    print(f"[{datetime.now().strftime('%H:%M:%S')}] Sending prompt to vLLM...")
    print(f"Prompt: {prompt[:80]}{'...' if len(prompt) > 80 else ''}")
    print()

    start_time = time.time()

    try:
        response = requests.post(url, json=payload, headers=headers, timeout=120)
        response.raise_for_status()

        elapsed_time = time.time() - start_time

        result = response.json()

        return {
            "success": True,
            "elapsed_time": elapsed_time,
            "response": result,
            "timestamp": datetime.now().isoformat()
        }

    except requests.exceptions.RequestException as e:
        elapsed_time = time.time() - start_time

        return {
            "success": False,
            "elapsed_time": elapsed_time,
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }


def main():
    parser = argparse.ArgumentParser(description="Single prompt test for vLLM")
    parser.add_argument("--host", default="localhost", help="vLLM host")
    parser.add_argument("--port", type=int, default=30800, help="vLLM port")
    parser.add_argument("--prompt", default=None, help="Custom prompt to send")

    args = parser.parse_args()

    # Default test prompt
    if args.prompt:
        prompt = args.prompt
    else:
        prompt = (
            "Explain the concept of GPU virtualization in 3 sentences. "
            "Focus on how it enables multiple workloads to share a single GPU."
        )

    print("╔═══════════════════════════════════════════════════════════════╗")
    print("║          vLLM Single Prompt Test with eBPF Tracing           ║")
    print("╚═══════════════════════════════════════════════════════════════╝")
    print()
    print(f"Target: {args.host}:{args.port}")
    print(f"Model: meta-llama/Llama-2-7b-hf")
    print(f"Timestamp: {datetime.now().isoformat()}")
    print()

    # Wait for vLLM to be ready
    print("Checking if vLLM is ready...")
    max_retries = 30
    for i in range(max_retries):
        try:
            health_url = f"http://{args.host}:{args.port}/health"
            response = requests.get(health_url, timeout=5)
            if response.status_code == 200:
                print("✓ vLLM is ready")
                print()
                break
        except requests.exceptions.RequestException:
            pass

        if i < max_retries - 1:
            print(f"  Waiting for vLLM... ({i+1}/{max_retries})")
            time.sleep(5)
    else:
        print("✗ vLLM is not ready after 150 seconds")
        return 1

    # Send the prompt
    result = send_prompt(args.host, args.port, prompt)

    # Display results
    print("─" * 65)
    print("RESULTS:")
    print("─" * 65)

    if result["success"]:
        print(f"✓ Success")
        print(f"⏱  Elapsed Time: {result['elapsed_time']:.2f}s")
        print()

        response_data = result["response"]

        # Extract completion
        if "choices" in response_data and len(response_data["choices"]) > 0:
            completion = response_data["choices"][0]["text"]
            print("Generated Text:")
            print(completion)
            print()

        # Extract usage stats
        if "usage" in response_data:
            usage = response_data["usage"]
            print("Token Usage:")
            print(f"  Prompt Tokens: {usage.get('prompt_tokens', 'N/A')}")
            print(f"  Completion Tokens: {usage.get('completion_tokens', 'N/A')}")
            print(f"  Total Tokens: {usage.get('total_tokens', 'N/A')}")

            # Calculate tokens per second
            completion_tokens = usage.get('completion_tokens', 0)
            if completion_tokens > 0:
                tokens_per_sec = completion_tokens / result['elapsed_time']
                print(f"  Throughput: {tokens_per_sec:.2f} tokens/sec")

        print()
        print("─" * 65)

        # Save full result to file
        output_file = f"single_prompt_result_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(output_file, 'w') as f:
            json.dump(result, f, indent=2)

        print(f"✓ Full result saved to: {output_file}")
        print()
        print("Note: eBPF traces are being captured by the sidecar and will be")
        print("      uploaded to S3 automatically. Check your S3 bucket for trace files.")

        return 0

    else:
        print(f"✗ Failed")
        print(f"Error: {result['error']}")
        print(f"⏱  Time to failure: {result['elapsed_time']:.2f}s")
        return 1


if __name__ == "__main__":
    exit(main())
