#!/bin/bash
set -e

POD_NAME="${POD_NAME:-gpu-dev-pod-enhanced}"

echo "========================================="
echo "Testing GPU in Pod: $POD_NAME"
echo "========================================="

# Check if pod exists
if ! kubectl get pod "$POD_NAME" >/dev/null 2>&1; then
    echo "Error: Pod '$POD_NAME' not found."
    exit 1
fi

# Wait for pod to be ready
echo "Waiting for pod to be ready..."
kubectl wait --for=condition=ready pod/"$POD_NAME" --timeout=300s

echo -e "\n[1] Testing nvidia-smi..."
kubectl exec "$POD_NAME" -- nvidia-smi

echo -e "\n[2] Testing CUDA availability in Python..."
kubectl exec "$POD_NAME" -- python3 -c "
import torch
print(f'PyTorch version: {torch.__version__}')
print(f'CUDA available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'CUDA version: {torch.version.cuda}')
    print(f'GPU device: {torch.cuda.get_device_name(0)}')
    print(f'GPU memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.2f} GB')
"

echo -e "\n[3] Running simple GPU computation..."
kubectl exec "$POD_NAME" -- python3 -c "
import torch
import time

if torch.cuda.is_available():
    # Create large tensors
    size = 10000
    a = torch.randn(size, size).cuda()
    b = torch.randn(size, size).cuda()

    # Warm up
    _ = torch.matmul(a, b)
    torch.cuda.synchronize()

    # Time the operation
    start = time.time()
    c = torch.matmul(a, b)
    torch.cuda.synchronize()
    end = time.time()

    print(f'Matrix multiplication ({size}x{size}): {(end-start)*1000:.2f} ms')
    print('✓ GPU computation successful!')
else:
    print('✗ CUDA not available')
"

echo -e "\n========================================="
echo "GPU Test Complete!"
echo "========================================="
