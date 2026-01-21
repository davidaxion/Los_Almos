# AWS GPU Instance Types Reference

## Quick Reference for NODE_TYPE Selection

This file provides a quick reference for choosing GPU instance types when deploying the cluster.

## Usage

```bash
export NODE_TYPE=g6.2xlarge  # Your chosen instance type
./scripts/deploy-cluster.sh
```

---

## Recommended Instances

### **Default: L4 GPU (g6 family)** ⭐

| Instance Type | L4 GPUs | vCPUs | RAM | Cost/hr | Best For |
|--------------|---------|-------|-----|---------|----------|
| `g6.xlarge` | 1 | 4 | 16 GB | ~$0.84 | Budget L4 testing |
| **`g6.2xlarge`** | **1** | **8** | **32 GB** | **~$1.01** | **Balanced L4 (DEFAULT)** |
| `g6.4xlarge` | 1 | 16 | 64 GB | ~$1.35 | L4 with more CPU/RAM |
| `g6.12xlarge` | 4 | 48 | 192 GB | ~$4.06 | Multi-GPU L4 testing |
| `g6.48xlarge` | 8 | 192 | 768 GB | ~$16.24 | Max L4 deployment |

**Why L4?**
- 2x better inference performance vs T4
- Excellent FP8/INT8 support for LLMs
- Optimal for vLLM workloads
- Great price/performance ratio

---

## Alternative Options

### T4 GPU (g4dn family) - Budget

| Instance Type | T4 GPUs | vCPUs | RAM | Cost/hr | Best For |
|--------------|---------|-------|-----|---------|----------|
| `g4dn.xlarge` | 1 | 4 | 16 GB | ~$0.53 | Cheapest GPU option |
| `g4dn.2xlarge` | 1 | 8 | 32 GB | ~$0.75 | Budget balanced |
| `g4dn.4xlarge` | 1 | 16 | 64 GB | ~$1.20 | T4 with more resources |
| `g4dn.12xlarge` | 4 | 48 | 192 GB | ~$3.91 | Multi-GPU T4 |

**When to use T4:**
- Tight budget constraints
- Simple inference workloads
- Learning/experimentation

---

### V100 GPU (p3 family) - High Performance

| Instance Type | V100 GPUs | vCPUs | RAM | Cost/hr | Best For |
|--------------|-----------|-------|-----|---------|----------|
| `p3.2xlarge` | 1 | 8 | 61 GB | ~$3.06 | Single V100 |
| `p3.8xlarge` | 4 | 32 | 244 GB | ~$12.24 | Multi-GPU V100 |
| `p3.16xlarge` | 8 | 64 | 488 GB | ~$24.48 | Max V100 |

**When to use V100:**
- Training workloads
- Need high FP64 performance
- Established workflows requiring V100

---

### A100 GPU (p4d family) - Maximum Performance

| Instance Type | A100 GPUs | vCPUs | RAM | Cost/hr | Best For |
|--------------|-----------|-------|-----|---------|----------|
| `p4d.24xlarge` | 8 | 96 | 1152 GB | ~$32.77 | Production training/inference |

**When to use A100:**
- Largest models (70B+)
- Maximum throughput needed
- Multi-node distributed training

---

### A10G GPU (g5 family) - Balanced

| Instance Type | A10G GPUs | vCPUs | RAM | Cost/hr | Best For |
|--------------|-----------|-------|-----|---------|----------|
| `g5.xlarge` | 1 | 4 | 16 GB | ~$1.01 | Single A10G |
| `g5.2xlarge` | 1 | 8 | 32 GB | ~$1.21 | Balanced A10G |
| `g5.12xlarge` | 4 | 48 | 192 GB | ~$5.67 | Multi-GPU A10G |

**When to use A10G:**
- Good middle ground between T4 and V100
- Graphics + compute workloads
- Ray tracing requirements

---

## GPU Comparison Summary

| GPU Model | Generation | Memory | Best Use Case | Price Tier |
|-----------|-----------|--------|---------------|------------|
| **L4** | 2023 | 24 GB | **LLM inference, vLLM** | **Mid** |
| T4 | 2018 | 16 GB | Budget inference | Low |
| A10G | 2021 | 24 GB | Balanced workloads | Mid |
| V100 | 2017 | 16 GB | Training, FP64 | High |
| A100 | 2020 | 40 GB | Large-scale training | Very High |

---

## Quick Setup Examples

### Budget Testing (T4)
```bash
export NODE_TYPE=g4dn.xlarge
./scripts/deploy-cluster.sh
# Cost: ~$0.53/hr
```

### Recommended Default (L4 with 8 vCPUs)
```bash
export NODE_TYPE=g6.2xlarge
./scripts/deploy-cluster.sh
# Cost: ~$1.01/hr
```

### Multi-GPU Testing (4x L4)
```bash
export NODE_TYPE=g6.12xlarge
./scripts/deploy-cluster.sh
# Cost: ~$4.06/hr
# Don't forget to update gpu-pod-enhanced.yaml to request 4 GPUs
```

### High Performance (V100)
```bash
export NODE_TYPE=p3.2xlarge
./scripts/deploy-cluster.sh
# Cost: ~$3.06/hr
```

---

## Multi-GPU Pod Configuration

If using multi-GPU instances (g6.12xlarge, p3.8xlarge, etc.), update `k8s-manifests/gpu-pod-enhanced.yaml`:

```yaml
resources:
  limits:
    nvidia.com/gpu: 4  # Match number of GPUs on instance
    memory: "64Gi"     # Scale memory accordingly
    cpu: "16"          # Scale CPU accordingly
```

---

## Spot Instances (Cost Savings)

For non-critical workloads, add spot instance support to `deploy-cluster.sh`:

```bash
eksctl create cluster \
  --name "$CLUSTER_NAME" \
  --spot \  # Add this flag
  --instance-types "$NODE_TYPE" \
  # ... rest of flags
```

**Spot savings**: 60-70% off on-demand prices, but instances can be terminated with 2min notice.

---

## Regional Availability

Not all instance types are available in all regions. If deployment fails:

1. Check availability: [AWS Instance Types by Region](https://aws.amazon.com/ec2/instance-types/)
2. Try different region: `export AWS_REGION=us-east-1`
3. Use alternative instance type from same family

**Best regions for GPU availability**: us-east-1, us-west-2, eu-west-1

---

## Cost Management Tips

1. **Always cleanup when done**: `./scripts/cleanup.sh`
2. **Use smaller instances for testing**: Start with `g6.xlarge` before scaling to `g6.12xlarge`
3. **Consider spot instances**: 60-70% cheaper for non-critical workloads
4. **Set up billing alerts**: Configure AWS Budget alerts for your account
5. **Use auto-scaling wisely**: Set `MAX_NODES` appropriately to avoid surprise costs

---

## Quick Cost Calculator

| Instance | 1 Hour | 8 Hours | 24 Hours | Week | Month |
|----------|--------|---------|----------|------|-------|
| g4dn.xlarge (T4) | $0.53 | $4.24 | $12.72 | $89 | $382 |
| **g6.2xlarge (L4)** | **$1.01** | **$8.08** | **$24.24** | **$170** | **$728** |
| g6.12xlarge (4xL4) | $4.06 | $32.48 | $97.44 | $682 | $2,924 |
| p3.2xlarge (V100) | $3.06 | $24.48 | $73.44 | $514 | $2,203 |

**Remember**: These are approximate on-demand prices. Actual costs may vary by region and include additional charges for EBS, network transfer, etc.
