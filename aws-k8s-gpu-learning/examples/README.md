# Example Scripts

This directory contains example scripts to test and learn GPU computing.

## Available Examples

### 1. test-pytorch.py

Basic PyTorch GPU test that verifies:
- CUDA availability
- GPU information
- Matrix operations performance
- Neural network operations
- Memory usage

**Usage:**
```bash
# Inside the GPU pod
cd /workspace
python3 test-pytorch.py
```

### 2. test-vllm.py

vLLM inference test that demonstrates:
- Loading LLM models
- Running inference on GPU
- Measuring performance
- Generating text

**Usage:**
```bash
# Inside the GPU pod
cd /workspace
python3 test-vllm.py
```

**Note:** First run will download the model (~500MB for opt-125m)

## Copying Examples to Pod

From your local machine:

```bash
# Copy all examples to the pod
kubectl cp examples/ gpu-dev-pod-enhanced:/workspace/

# Or copy individual files
kubectl cp examples/test-pytorch.py gpu-dev-pod-enhanced:/workspace/test-pytorch.py
```

Then SSH into the pod and run them:

```bash
./scripts/connect-ssh.sh
cd /workspace
python3 test-pytorch.py
python3 test-vllm.py
```

## Creating Your Own Scripts

1. SSH into the pod
2. Create scripts in `/workspace`
3. Your scripts will have access to:
   - CUDA/GPU
   - PyTorch, Transformers
   - vLLM
   - All installed Python packages

Example:
```bash
# Inside the pod
cd /workspace
cat > my_script.py << 'EOF'
import torch
print(f"GPU: {torch.cuda.get_device_name(0)}")
EOF

python3 my_script.py
```

## Advanced Examples

### Multi-GPU Training

```python
import torch
import torch.nn as nn
import torch.distributed as dist

# Check for multiple GPUs
if torch.cuda.device_count() > 1:
    print(f"Using {torch.cuda.device_count()} GPUs")
    model = nn.DataParallel(model)
```

### Model Fine-tuning

```python
from transformers import AutoModelForCausalLM, AutoTokenizer, Trainer

model = AutoModelForCausalLM.from_pretrained("model-name")
tokenizer = AutoTokenizer.from_pretrained("model-name")

# Your training code here
```

### vLLM Server Mode

```bash
# Start vLLM as an API server
python3 -m vllm.entrypoints.api_server \
    --model facebook/opt-125m \
    --port 8000

# Query from another terminal
curl http://localhost:8000/generate \
    -d '{"prompt": "Hello, world!", "max_tokens": 50}'
```

## Learning Resources

- [PyTorch Tutorials](https://pytorch.org/tutorials/)
- [vLLM Documentation](https://docs.vllm.ai/)
- [Hugging Face Transformers](https://huggingface.co/docs/transformers/)
- [CUDA Programming Guide](https://docs.nvidia.com/cuda/)
