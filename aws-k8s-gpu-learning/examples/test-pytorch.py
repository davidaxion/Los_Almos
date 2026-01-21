#!/usr/bin/env python3
"""
Simple PyTorch GPU test script
Run this inside the GPU pod to verify GPU functionality
"""

import torch
import time

def main():
    print("=" * 50)
    print("PyTorch GPU Test")
    print("=" * 50)

    # Check CUDA availability
    print(f"\nPyTorch version: {torch.__version__}")
    print(f"CUDA available: {torch.cuda.is_available()}")

    if not torch.cuda.is_available():
        print("ERROR: CUDA is not available!")
        return

    # GPU information
    print(f"\nCUDA version: {torch.version.cuda}")
    print(f"Number of GPUs: {torch.cuda.device_count()}")

    for i in range(torch.cuda.device_count()):
        print(f"\nGPU {i}: {torch.cuda.get_device_name(i)}")
        props = torch.cuda.get_device_properties(i)
        print(f"  Memory: {props.total_memory / 1e9:.2f} GB")
        print(f"  Compute Capability: {props.major}.{props.minor}")
        print(f"  Multiprocessors: {props.multi_processor_count}")

    # Simple computation test
    print("\n" + "=" * 50)
    print("Running computation test...")
    print("=" * 50)

    device = torch.device("cuda")

    # Test 1: Simple tensor operations
    print("\nTest 1: Tensor operations")
    x = torch.randn(1000, 1000, device=device)
    y = torch.randn(1000, 1000, device=device)

    start = time.time()
    z = torch.matmul(x, y)
    torch.cuda.synchronize()
    elapsed = time.time() - start

    print(f"Matrix multiplication (1000x1000): {elapsed*1000:.2f} ms")

    # Test 2: Larger matrix
    print("\nTest 2: Larger matrix operations")
    size = 5000
    a = torch.randn(size, size, device=device)
    b = torch.randn(size, size, device=device)

    torch.cuda.synchronize()
    start = time.time()
    c = torch.matmul(a, b)
    torch.cuda.synchronize()
    elapsed = time.time() - start

    print(f"Matrix multiplication ({size}x{size}): {elapsed*1000:.2f} ms")

    # Test 3: Neural network layer
    print("\nTest 3: Neural network operations")
    batch_size = 128
    input_size = 1024
    hidden_size = 2048

    linear = torch.nn.Linear(input_size, hidden_size).to(device)
    x = torch.randn(batch_size, input_size, device=device)

    # Warm up
    with torch.no_grad():
        _ = linear(x)

    torch.cuda.synchronize()
    start = time.time()
    with torch.no_grad():
        for _ in range(100):
            y = linear(x)
            y = torch.relu(y)
    torch.cuda.synchronize()
    elapsed = time.time() - start

    print(f"100 forward passes: {elapsed*1000:.2f} ms")
    print(f"Average per pass: {elapsed*10:.2f} ms")

    # Memory info
    print("\n" + "=" * 50)
    print("GPU Memory Usage")
    print("=" * 50)
    memory_allocated = torch.cuda.memory_allocated() / 1e9
    memory_reserved = torch.cuda.memory_reserved() / 1e9
    max_memory = torch.cuda.max_memory_allocated() / 1e9

    print(f"Allocated: {memory_allocated:.2f} GB")
    print(f"Reserved: {memory_reserved:.2f} GB")
    print(f"Max allocated: {max_memory:.2f} GB")

    print("\n" + "=" * 50)
    print("All tests completed successfully!")
    print("=" * 50)

if __name__ == "__main__":
    main()
