#!/usr/bin/env python3
"""
Batch Prompts Test for vLLM with eBPF Tracing

Tests vLLM inference with multiple prompts to stress the system
and capture comprehensive CUDA traces.

Usage:
    python3 batch-prompts.py [--host HOST] [--port PORT] [--count COUNT] [--parallel]
"""

import argparse
import json
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from typing import List, Dict

import requests


# Test prompts covering various inference patterns
TEST_PROMPTS = [
    "Explain how neural networks process information in 2-3 sentences.",
    "What are the main advantages of using GPUs for machine learning?",
    "Describe the transformer architecture in simple terms.",
    "How does attention mechanism work in language models?",
    "What is the difference between training and inference in deep learning?",
    "Explain the concept of batch processing in GPU computing.",
    "What are the key components of a modern AI inference server?",
    "How do language models generate text one token at a time?",
    "What is memory bandwidth and why does it matter for GPUs?",
    "Describe the role of tensor cores in NVIDIA GPUs.",
    "How does quantization help reduce model size?",
    "What is the purpose of KV cache in transformer inference?",
    "Explain the concept of continuous batching in vLLM.",
    "What are the trade-offs between latency and throughput?",
    "How do GPU schedulers manage concurrent workloads?",
    "What is the difference between CUDA cores and tensor cores?",
    "Explain the concept of model parallelism.",
    "What is pipeline parallelism in distributed inference?",
    "How does PagedAttention improve memory efficiency?",
    "What are the benefits of asynchronous execution in CUDA?",
]


def send_single_prompt(
    host: str,
    port: int,
    prompt: str,
    prompt_id: int
) -> Dict:
    """Send a single prompt and return result with timing."""
    url = f"http://{host}:{port}/v1/completions"

    payload = {
        "model": "meta-llama/Llama-2-7b-hf",
        "prompt": prompt,
        "max_tokens": 80,
        "temperature": 0.7,
        "top_p": 0.9,
        "stream": False
    }

    headers = {"Content-Type": "application/json"}

    start_time = time.time()
    timestamp_start = datetime.now().isoformat()

    try:
        response = requests.post(url, json=payload, headers=headers, timeout=120)
        response.raise_for_status()

        elapsed_time = time.time() - start_time
        result = response.json()

        # Extract tokens and text
        tokens_generated = 0
        text = ""
        if "choices" in result and len(result["choices"]) > 0:
            text = result["choices"][0]["text"]

        if "usage" in result:
            tokens_generated = result["usage"].get("completion_tokens", 0)

        return {
            "prompt_id": prompt_id,
            "success": True,
            "elapsed_time": elapsed_time,
            "timestamp_start": timestamp_start,
            "timestamp_end": datetime.now().isoformat(),
            "tokens_generated": tokens_generated,
            "tokens_per_sec": tokens_generated / elapsed_time if elapsed_time > 0 else 0,
            "text": text[:200],  # First 200 chars
            "prompt": prompt[:80],  # First 80 chars
        }

    except requests.exceptions.RequestException as e:
        elapsed_time = time.time() - start_time

        return {
            "prompt_id": prompt_id,
            "success": False,
            "elapsed_time": elapsed_time,
            "timestamp_start": timestamp_start,
            "timestamp_end": datetime.now().isoformat(),
            "error": str(e),
            "prompt": prompt[:80],
        }


def run_sequential_test(host: str, port: int, prompts: List[str]) -> List[Dict]:
    """Run prompts sequentially."""
    print(f"Running {len(prompts)} prompts sequentially...")
    print()

    results = []
    for i, prompt in enumerate(prompts, 1):
        print(f"[{i}/{len(prompts)}] Processing prompt {i}...", end=" ", flush=True)

        result = send_single_prompt(host, port, prompt, i)

        if result["success"]:
            print(f"✓ {result['elapsed_time']:.2f}s ({result['tokens_per_sec']:.1f} tok/s)")
        else:
            print(f"✗ Failed: {result['error']}")

        results.append(result)

        # Small delay between requests
        time.sleep(0.5)

    return results


def run_parallel_test(host: str, port: int, prompts: List[str], max_workers: int = 4) -> List[Dict]:
    """Run prompts in parallel."""
    print(f"Running {len(prompts)} prompts in parallel (workers={max_workers})...")
    print()

    results = []

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Submit all tasks
        future_to_id = {
            executor.submit(send_single_prompt, host, port, prompt, i): i
            for i, prompt in enumerate(prompts, 1)
        }

        # Process as they complete
        for future in as_completed(future_to_id):
            prompt_id = future_to_id[future]

            try:
                result = future.result()
                results.append(result)

                if result["success"]:
                    print(f"[{prompt_id}] ✓ {result['elapsed_time']:.2f}s ({result['tokens_per_sec']:.1f} tok/s)")
                else:
                    print(f"[{prompt_id}] ✗ Failed: {result['error']}")

            except Exception as e:
                print(f"[{prompt_id}] ✗ Exception: {str(e)}")
                results.append({
                    "prompt_id": prompt_id,
                    "success": False,
                    "error": str(e)
                })

    # Sort results by prompt_id
    results.sort(key=lambda x: x["prompt_id"])

    return results


def print_summary(results: List[Dict]):
    """Print summary statistics."""
    print()
    print("═" * 65)
    print("SUMMARY STATISTICS")
    print("═" * 65)
    print()

    successful = [r for r in results if r["success"]]
    failed = [r for r in results if not r["success"]]

    print(f"Total Prompts: {len(results)}")
    print(f"✓ Successful: {len(successful)}")
    print(f"✗ Failed: {len(failed)}")
    print()

    if successful:
        latencies = [r["elapsed_time"] for r in successful]
        tokens_per_sec = [r["tokens_per_sec"] for r in successful]
        total_tokens = sum(r["tokens_generated"] for r in successful)

        print("Latency:")
        print(f"  Min: {min(latencies):.2f}s")
        print(f"  Max: {max(latencies):.2f}s")
        print(f"  Mean: {sum(latencies) / len(latencies):.2f}s")
        print()

        print("Throughput:")
        print(f"  Min: {min(tokens_per_sec):.2f} tok/s")
        print(f"  Max: {max(tokens_per_sec):.2f} tok/s")
        print(f"  Mean: {sum(tokens_per_sec) / len(tokens_per_sec):.2f} tok/s")
        print()

        print(f"Total Tokens Generated: {total_tokens}")
        print()

    # Total time
    if results:
        start_times = [datetime.fromisoformat(r["timestamp_start"]) for r in results if "timestamp_start" in r]
        end_times = [datetime.fromisoformat(r["timestamp_end"]) for r in results if "timestamp_end" in r]

        if start_times and end_times:
            total_duration = (max(end_times) - min(start_times)).total_seconds()
            print(f"Total Test Duration: {total_duration:.2f}s")

            if len(successful) > 0:
                overall_throughput = sum(r["tokens_generated"] for r in successful) / total_duration
                print(f"Overall Throughput: {overall_throughput:.2f} tok/s")

    print()
    print("─" * 65)


def main():
    parser = argparse.ArgumentParser(description="Batch prompts test for vLLM")
    parser.add_argument("--host", default="localhost", help="vLLM host")
    parser.add_argument("--port", type=int, default=30800, help="vLLM port")
    parser.add_argument("--count", type=int, default=15, help="Number of prompts (default: 15)")
    parser.add_argument("--parallel", action="store_true", help="Run prompts in parallel")
    parser.add_argument("--workers", type=int, default=4, help="Number of parallel workers (default: 4)")

    args = parser.parse_args()

    print("╔═══════════════════════════════════════════════════════════════╗")
    print("║          vLLM Batch Prompts Test with eBPF Tracing           ║")
    print("╚═══════════════════════════════════════════════════════════════╝")
    print()
    print(f"Target: {args.host}:{args.port}")
    print(f"Model: meta-llama/Llama-2-7b-hf")
    print(f"Prompts: {args.count}")
    print(f"Mode: {'Parallel' if args.parallel else 'Sequential'}")
    if args.parallel:
        print(f"Workers: {args.workers}")
    print(f"Timestamp: {datetime.now().isoformat()}")
    print()

    # Check vLLM health
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

    # Select prompts
    prompts = TEST_PROMPTS[:args.count]

    # Run test
    test_start = time.time()

    if args.parallel:
        results = run_parallel_test(args.host, args.port, prompts, args.workers)
    else:
        results = run_sequential_test(args.host, args.port, prompts)

    test_duration = time.time() - test_start

    # Print summary
    print_summary(results)

    # Save results
    output_data = {
        "test_config": {
            "host": args.host,
            "port": args.port,
            "prompts_count": args.count,
            "mode": "parallel" if args.parallel else "sequential",
            "workers": args.workers if args.parallel else 1,
            "timestamp": datetime.now().isoformat(),
            "duration": test_duration,
        },
        "results": results
    }

    output_file = f"batch_prompts_result_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(output_file, 'w') as f:
        json.dump(output_data, f, indent=2)

    print(f"✓ Full results saved to: {output_file}")
    print()
    print("Note: eBPF traces are being captured by the sidecar and will be")
    print("      uploaded to S3 automatically. Check your S3 bucket for trace files.")
    print()

    return 0


if __name__ == "__main__":
    exit(main())
