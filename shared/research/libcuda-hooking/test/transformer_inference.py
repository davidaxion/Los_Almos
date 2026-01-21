#!/usr/bin/env python3
"""
transformer_inference.py - Realistic Transformer Inference Test

Simulates a real inference server workload with transformer model.
Traces the complete pipeline: model loading → tokenization → inference → response.

Usage:
    # Without tracing
    python transformer_inference.py

    # With eBPF tracing
    sudo ../ebpf/run_trace.sh --kernel python transformer_inference.py

    # With specific model
    python transformer_inference.py --model gpt2
"""

import torch
import time
import sys
import argparse

# Try to import transformers
try:
    from transformers import AutoTokenizer, AutoModelForCausalLM
    HAS_TRANSFORMERS = True
except ImportError:
    HAS_TRANSFORMERS = False
    print("Warning: transformers not installed. Using simple model instead.")
    print("Install with: pip install transformers")


def print_stage(stage_num, stage_name):
    """Print stage header"""
    print()
    print("=" * 80)
    print(f"[Stage {stage_num}] {stage_name}")
    print("=" * 80)


def simple_model_inference():
    """Fallback to simple model if transformers not available"""
    print_stage(1, "CUDA Initialization")

    if not torch.cuda.is_available():
        print("ERROR: CUDA not available")
        sys.exit(1)

    device = torch.device("cuda")
    print(f"Device: {torch.cuda.get_device_name(0)}")
    torch.cuda.init()

    print_stage(2, "Loading Model Weights")
    start = time.time()

    # Create a larger model to simulate transformer
    model = torch.nn.Sequential(
        torch.nn.Linear(768, 2048),
        torch.nn.GELU(),
        torch.nn.Linear(2048, 768),
        torch.nn.GELU(),
        torch.nn.Linear(768, 2048),
        torch.nn.GELU(),
        torch.nn.Linear(2048, 768),
    ).to(device)

    load_time = time.time() - start
    num_params = sum(p.numel() for p in model.parameters())
    print(f"✓ Model loaded: {num_params:,} parameters")
    print(f"✓ Time: {load_time:.3f}s")

    print_stage(3, "Preparing Input (Simulated Tokenization)")
    batch_size = 8
    seq_length = 128

    input_tensor = torch.randn(batch_size, seq_length, 768).to(device)
    print(f"✓ Input shape: {input_tensor.shape}")

    print_stage(4, "Running Inference")
    with torch.no_grad():
        output = model(input_tensor)
    torch.cuda.synchronize()

    print(f"✓ Output shape: {output.shape}")

    print_stage(5, "Transferring Results")
    result = output.cpu()
    print(f"✓ Results on CPU: {result.shape}")


def transformer_inference(model_name="gpt2", prompt="Hello, how are you?"):
    """Run real transformer inference"""

    print_stage(1, "CUDA Initialization")

    if not torch.cuda.is_available():
        print("ERROR: CUDA not available")
        sys.exit(1)

    device = torch.device("cuda")
    print(f"Device: {torch.cuda.get_device_name(0)}")
    print(f"Memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.2f} GB")
    torch.cuda.init()

    print_stage(2, "Loading Tokenizer")
    start = time.time()

    tokenizer = AutoTokenizer.from_pretrained(model_name)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    print(f"✓ Tokenizer loaded: {model_name}")
    print(f"✓ Time: {time.time() - start:.3f}s")

    print_stage(3, "Loading Model Weights to GPU")
    start = time.time()

    # This triggers extensive cuMemAlloc calls
    model = AutoModelForCausalLM.from_pretrained(
        model_name,
        torch_dtype=torch.float16,  # Use FP16 for faster inference
        device_map="auto"
    )
    model.eval()

    load_time = time.time() - start
    num_params = sum(p.numel() for p in model.parameters())
    param_size_gb = num_params * 2 / 1024 / 1024 / 1024  # 2 bytes for FP16

    print(f"✓ Model loaded: {model_name}")
    print(f"  Parameters: {num_params:,} ({param_size_gb:.2f} GB)")
    print(f"  Time: {load_time:.3f}s")
    print(f"  GPU Memory: {torch.cuda.memory_allocated() / 1e9:.2f} GB")

    print_stage(4, "Tokenizing Input (Prompt Processing)")
    start = time.time()

    print(f"Prompt: \"{prompt}\"")

    # Tokenize and move to GPU (triggers cuMemcpyHtoD)
    inputs = tokenizer(prompt, return_tensors="pt").to(device)

    print(f"✓ Tokenized: {inputs['input_ids'].shape[1]} tokens")
    print(f"  Token IDs: {inputs['input_ids'][0].tolist()[:20]}...")
    print(f"  Time: {time.time() - start:.3f}s")

    print_stage(5, "Warmup Inference (Kernel Compilation)")
    start = time.time()

    with torch.no_grad():
        _ = model.generate(
            **inputs,
            max_new_tokens=1,
            do_sample=False
        )

    torch.cuda.synchronize()
    print(f"✓ Warmup complete: {time.time() - start:.3f}s")

    print_stage(6, "Running Inference (Text Generation)")
    print("Generating response (20 tokens)...")
    print()

    start = time.time()

    with torch.no_grad():
        # This triggers many cuLaunchKernel calls (one per token generated)
        output_ids = model.generate(
            **inputs,
            max_new_tokens=20,
            do_sample=True,
            temperature=0.7,
            top_p=0.9,
            pad_token_id=tokenizer.eos_token_id
        )

    torch.cuda.synchronize()
    inference_time = time.time() - start

    print(f"✓ Inference complete: {inference_time:.3f}s")
    print(f"  Tokens generated: 20")
    print(f"  Tokens/second: {20 / inference_time:.2f}")

    print_stage(7, "Decoding Response (Output Processing)")
    start = time.time()

    # Transfer results back to CPU (cuMemcpyDtoH)
    output_ids_cpu = output_ids.cpu()

    # Decode
    response = tokenizer.decode(output_ids_cpu[0], skip_special_tokens=True)

    print(f"✓ Decoding complete: {time.time() - start:.3f}s")
    print()
    print("RESPONSE:")
    print("-" * 80)
    print(response)
    print("-" * 80)
    print()

    print_stage(8, "GPU Memory Statistics")

    allocated = torch.cuda.memory_allocated() / 1e9
    reserved = torch.cuda.memory_reserved() / 1e9
    max_allocated = torch.cuda.max_memory_allocated() / 1e9

    print(f"Current allocated: {allocated:.2f} GB")
    print(f"Current reserved: {reserved:.2f} GB")
    print(f"Peak allocated: {max_allocated:.2f} GB")

    print_stage(9, "Cleanup")

    del model
    del inputs
    del output_ids
    torch.cuda.empty_cache()

    print("✓ GPU memory freed")

    print()
    print("=" * 80)
    print("COMPLETE PIPELINE TRACED:")
    print("=" * 80)
    print()
    print("1. CUDA Init:        cuInit, cuDeviceGet, cuCtxCreate")
    print("2. Weight Loading:   cuMemAlloc (hundreds of calls for model params)")
    print("3. Input Transfer:   cuMemAlloc, cuMemcpyHtoD (prompt tokens)")
    print("4. Warmup:           cuLaunchKernel (kernel compilation)")
    print("5. Inference:        cuLaunchKernel × N (N = tokens generated)")
    print("   - Attention:      Matrix multiplies (cuLaunchKernel)")
    print("   - FFN:            GELU, linear layers (cuLaunchKernel)")
    print("   - Sampling:       Softmax, argmax (cuLaunchKernel)")
    print("6. Synchronization:  cuStreamSynchronize (wait for GPU)")
    print("7. Output Transfer:  cuMemcpyDtoH (generated token IDs)")
    print("8. Cleanup:          cuMemFree (free allocations)")
    print()


def main():
    parser = argparse.ArgumentParser(description='Transformer Inference Test')
    parser.add_argument('--model', default='gpt2',
                        help='Model name (default: gpt2)')
    parser.add_argument('--prompt', default='Hello, how are you?',
                        help='Input prompt')

    args = parser.parse_args()

    print("=" * 80)
    print("TRANSFORMER INFERENCE PIPELINE TEST")
    print("=" * 80)
    print()

    if HAS_TRANSFORMERS:
        print(f"Model: {args.model}")
        print(f"Prompt: {args.prompt}")
        print()
        transformer_inference(args.model, args.prompt)
    else:
        print("Using simple model (transformers not available)")
        print()
        simple_model_inference()

    print()
    print("=" * 80)
    print("Test Complete!")
    print("=" * 80)
    print()
    print("To view the trace:")
    print("  cat traces/trace_*.jsonl | jq -r '.name' | sort | uniq -c")
    print("  python ../tools/visualize_pipeline.py traces/trace_*.jsonl")
    print()


if __name__ == '__main__':
    main()
