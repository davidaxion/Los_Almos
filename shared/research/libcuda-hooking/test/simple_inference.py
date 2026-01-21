#!/usr/bin/env python3
"""
simple_inference.py - Simple Inference Test for CUDA Tracing

Tests the complete pipeline from model loading to inference response.
Designed to be traced with eBPF to show the full CUDA execution flow.

Usage:
    # Without tracing
    python simple_inference.py

    # With eBPF tracing
    sudo ../ebpf/run_trace.sh python simple_inference.py
"""

import torch
import time
import sys

print("=" * 80)
print("CUDA Inference Pipeline Test")
print("=" * 80)
print()

# Check CUDA availability
print("[1] Checking CUDA availability...")
if not torch.cuda.is_available():
    print("ERROR: CUDA is not available!")
    print("This test requires a CUDA-capable GPU")
    sys.exit(1)

device = torch.device("cuda")
print(f"✓ CUDA available: {torch.cuda.get_device_name(0)}")
print(f"  Memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.2f} GB")
print()

# Initialize CUDA (triggers cuInit, cuDeviceGet, cuCtxCreate)
print("[2] Initializing CUDA context...")
start = time.time()
torch.cuda.init()
print(f"✓ CUDA initialized ({time.time() - start:.3f}s)")
print()

# Create a simple model (triggers cuMemAlloc for weights)
print("[3] Loading model weights to GPU...")
start = time.time()

# Simple 2-layer MLP (small enough to load quickly)
model = torch.nn.Sequential(
    torch.nn.Linear(512, 1024),
    torch.nn.ReLU(),
    torch.nn.Linear(1024, 512),
    torch.nn.ReLU(),
    torch.nn.Linear(512, 256),
).to(device)

print(f"✓ Model loaded to GPU ({time.time() - start:.3f}s)")

# Count parameters
num_params = sum(p.numel() for p in model.parameters())
param_size_mb = num_params * 4 / 1024 / 1024  # 4 bytes per float32
print(f"  Parameters: {num_params:,} ({param_size_mb:.2f} MB)")
print()

# Prepare input data (triggers cuMemAlloc + cuMemcpyHtoD)
print("[4] Preparing input data...")
start = time.time()

batch_size = 32
input_data = torch.randn(batch_size, 512).to(device)

print(f"✓ Input data transferred to GPU ({time.time() - start:.3f}s)")
print(f"  Batch size: {batch_size}")
print(f"  Input shape: {input_data.shape}")
print()

# Warmup run (first run includes kernel compilation)
print("[5] Warmup run (compiles kernels)...")
start = time.time()

with torch.no_grad():
    _ = model(input_data)

torch.cuda.synchronize()  # Wait for GPU to finish
warmup_time = time.time() - start
print(f"✓ Warmup complete ({warmup_time:.3f}s)")
print()

# Run inference multiple times
print("[6] Running inference...")
num_iterations = 10
timings = []

for i in range(num_iterations):
    start = time.time()

    with torch.no_grad():
        output = model(input_data)

    torch.cuda.synchronize()
    elapsed = time.time() - start
    timings.append(elapsed)

    print(f"  Iteration {i+1}/{num_iterations}: {elapsed*1000:.3f} ms")

avg_time = sum(timings) / len(timings)
print()
print(f"✓ Inference complete")
print(f"  Average time: {avg_time*1000:.3f} ms")
print(f"  Throughput: {batch_size/avg_time:.2f} samples/sec")
print()

# Transfer results back to CPU (triggers cuMemcpyDtoH)
print("[7] Retrieving results from GPU...")
start = time.time()

output_cpu = output.cpu()

print(f"✓ Results transferred to CPU ({time.time() - start:.3f}s)")
print(f"  Output shape: {output_cpu.shape}")
print(f"  Sample output (first 5): {output_cpu[0, :5].tolist()}")
print()

# Memory stats
print("[8] GPU Memory Statistics...")
allocated = torch.cuda.memory_allocated() / 1024 / 1024
reserved = torch.cuda.memory_reserved() / 1024 / 1024
print(f"  Allocated: {allocated:.2f} MB")
print(f"  Reserved: {reserved:.2f} MB")
print()

# Cleanup
print("[9] Cleaning up...")
del model
del input_data
del output
torch.cuda.empty_cache()
print("✓ GPU memory freed")
print()

print("=" * 80)
print("Test Complete!")
print("=" * 80)
print()
print("PIPELINE STAGES TRACED:")
print("  1. CUDA Initialization (cuInit, cuDeviceGet, cuCtxCreate)")
print("  2. Model Weight Loading (cuMemAlloc)")
print("  3. Input Transfer H2D (cuMemAlloc, cuMemcpyHtoD)")
print("  4. Kernel Compilation (first run only)")
print("  5. Inference Kernels (cuLaunchKernel × multiple)")
print("  6. Synchronization (cuStreamSynchronize)")
print("  7. Output Transfer D2H (cuMemcpyDtoH)")
print("  8. Memory Cleanup (cuMemFree)")
print()
