#!/usr/bin/env python3
"""
vLLM test script - Run LLM inference on GPU
This demonstrates how to use vLLM for efficient LLM inference with ModelLoader
"""

from vllm import LLM, SamplingParams
import time
import sys
import os

# Add shared-model-utils to path if available
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', '..', 'shared-model-utils'))

try:
    from model_loader import ModelLoader
    USE_MODEL_LOADER = True
except ImportError:
    print("ModelLoader not available, using direct model path")
    USE_MODEL_LOADER = False

def main():
    print("=" * 50)
    print("vLLM GPU Inference Test (with ModelLoader)")
    print("=" * 50)

    # Initialize model (using a small model for testing)
    # ModelLoader will auto-detect environment and use:
    # - EFS if in EKS with mounted volume
    # - S3 cache if in EC2
    # - HuggingFace if in local dev
    model_name = "gpt2"  # Use short name for ModelLoader

    print(f"\nLoading model: {model_name}")
    print("This may take a few minutes on first run...")

    # Get model path using ModelLoader
    if USE_MODEL_LOADER:
        loader = ModelLoader()
        model_path = loader.get_model_path(model_name)
        print(f"ModelLoader strategy: {loader._detect_environment()}")
        print(f"Model path: {model_path}")
    else:
        # Fallback to HuggingFace ID
        model_path = "gpt2"

    start = time.time()
    llm = LLM(
        model=model_path,  # Use path from ModelLoader
        gpu_memory_utilization=0.8,
        max_model_len=512,
    )
    load_time = time.time() - start

    print(f"Model loaded in {load_time:.2f} seconds")
    if USE_MODEL_LOADER:
        print(f"Loaded from: {model_path}")

    # Define sampling parameters
    sampling_params = SamplingParams(
        temperature=0.8,
        top_p=0.95,
        max_tokens=100,
    )

    # Test prompts
    prompts = [
        "The future of artificial intelligence is",
        "In a world where technology advances rapidly,",
        "Machine learning models can be used to",
        "The benefits of GPU computing include",
    ]

    print("\n" + "=" * 50)
    print("Generating responses...")
    print("=" * 50)

    # Generate
    start = time.time()
    outputs = llm.generate(prompts, sampling_params)
    gen_time = time.time() - start

    # Display results
    for i, output in enumerate(outputs, 1):
        print(f"\n--- Prompt {i} ---")
        print(f"Input: {output.prompt}")
        print(f"Output: {output.outputs[0].text}")
        print(f"Tokens: {len(output.outputs[0].token_ids)}")

    print("\n" + "=" * 50)
    print("Performance Statistics")
    print("=" * 50)
    total_tokens = sum(len(output.outputs[0].token_ids) for output in outputs)
    print(f"Total generation time: {gen_time:.2f} seconds")
    print(f"Total tokens generated: {total_tokens}")
    print(f"Tokens per second: {total_tokens/gen_time:.2f}")
    print(f"Average time per prompt: {gen_time/len(prompts):.2f} seconds")

    print("\n" + "=" * 50)
    print("vLLM test completed successfully!")
    print("=" * 50)
    print("\nTips:")
    print("- Try larger models for better quality")
    print("- Adjust temperature and top_p for different outputs")
    print("- Use gpu_memory_utilization to control memory usage")
    print("- Check vLLM docs: https://docs.vllm.ai/")

if __name__ == "__main__":
    main()
