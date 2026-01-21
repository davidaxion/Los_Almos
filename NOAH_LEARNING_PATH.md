# Noah's GPU Learning Path

A structured, hands-on learning journey for mastering GPU computing, from basics to advanced distributed training.

**Total Duration**: 8-12 hours over 4-6 days
**Total Cost**: ~$10-20 (if you stop instances between sessions)

---

## 📅 Phase 1: GPU Fundamentals (Day 1 - 2 hours)

**Module**: Basic GPU Setup (Module 1)
**Goal**: Understand GPU basics and run your first GPU workloads
**Cost**: ~$1 (2 hours of practice)

### Setup
```bash
cd modules/01-basic-gpu
./deploy.sh
# Wait 5 minutes, then SSH to instance
```

### Exercises

#### Exercise 1.1: Hello GPU (30 mins)
**File**: `exercises/01-hello-gpu.py`

**Tasks**:
1. Run the script and observe output
2. Modify to create a 5000x5000 matrix instead of 1000x1000
3. Time the difference - record results
4. Answer: Why is the GPU faster?

**Expected Learning**:
- GPU memory allocation
- CUDA availability check
- Basic tensor operations

**Deliverable**: Screenshot of output + written explanation

---

#### Exercise 1.2: First Inference (30 mins)
**File**: `exercises/02-vllm-inference.py`

**Tasks**:
1. Run the script with default settings
2. Change prompt to: "The future of GPU computing is"
3. Modify `max_tokens` to 100 (from 50)
4. Record: How long did generation take?

**Expected Learning**:
- Model loading on GPU
- Inference parameters
- Token generation

**Deliverable**: Generated text + time metrics

---

#### Exercise 1.3: GPU Monitoring (30 mins)
**File**: `exercises/03-monitor-gpu.sh`

**Tasks**:
1. Run `nvidia-smi` - screenshot the output
2. Run monitoring script in one terminal
3. In another terminal, run exercise 1.2
4. Observe GPU utilization during inference

**Questions to Answer**:
- What % GPU utilization did you see?
- How much memory was used?
- What's the GPU temperature?

**Expected Learning**:
- Reading nvidia-smi output
- Real-time GPU monitoring
- Resource utilization patterns

**Deliverable**: Annotated screenshots with observations

---

#### Exercise 1.4: Memory Management (30 mins)
**File**: `exercises/04-memory-management.py`

**Tasks**:
1. Run the script - observe memory allocation
2. Modify to create larger tensors (20000x20000)
3. What happens? (Hint: might get OOM error)
4. Fix by using smaller tensors or clearing cache

**Expected Learning**:
- GPU memory limits
- Memory cleanup
- OOM error handling

**Deliverable**: Code showing how you fixed OOM

---

### Phase 1 Checkpoint

**Before moving to Phase 2, you should be able to**:
- [ ] Explain what CUDA is
- [ ] Run inference on a GPU
- [ ] Read nvidia-smi output
- [ ] Understand GPU memory constraints
- [ ] Know the difference between T4, L4, V100

**Cleanup**: `terraform destroy` (save ~$0.50/hour)

---

## 📅 Phase 2: Job Scheduling (Day 2-3 - 3 hours)

**Module**: SLURM Cluster (Module 2)
**Goal**: Learn resource management and job scheduling
**Cost**: ~$5 (3 hours of practice)

### Setup
```bash
cd ../modules/02-slurm-cluster
./deploy.sh
# Wait 10-15 minutes for cluster initialization
```

### Exercises

#### Exercise 2.1: First SLURM Job (45 mins)

**Tasks**:
1. SSH to head node
2. Create `hello-slurm.sh` from Module 2 README
3. Submit with `sbatch hello-slurm.sh`
4. Monitor with `squeue`
5. Check output in `/tmp/hello-*.out`

**Advanced Tasks**:
- Submit 5 jobs at once
- Use `squeue` to see them queued
- Cancel one with `scancel <job-id>`

**Expected Learning**:
- SLURM job scripts
- Job submission
- Queue management
- Job output files

**Deliverable**: Job output file + screenshot of `squeue`

---

#### Exercise 2.2: Interactive Session (30 mins)

**Tasks**:
1. Request interactive GPU: `srun --partition=gpu --gres=gpu:1 --pty bash`
2. Run Python interactively
3. Load a model and run inference
4. Exit and see GPU released

**Expected Learning**:
- Interactive vs batch jobs
- Resource allocation
- GPU sharing

**Deliverable**: Commands used + explanation of when to use interactive

---

#### Exercise 2.3: Multi-Node Job (45 mins)

**Tasks**:
1. Create `multi-node.sh` from Module 2 README
2. Submit to run on 2 nodes
3. Observe output from both nodes
4. Modify to run on all 3 nodes

**Expected Learning**:
- Multi-node job submission
- Node allocation
- Distributed execution

**Deliverable**: Output showing execution on multiple nodes

---

#### Exercise 2.4: Job Arrays (45 mins)

**Tasks**:
1. Create `array-job.sh` for parameter sweep
2. Submit array job with 4 tasks
3. Each task tests different learning rate: 0.001, 0.002, 0.003, 0.004
4. Compare outputs

**Real-world application**:
Create a parameter sweep for batch sizes: [16, 32, 64, 128]

**Expected Learning**:
- Parallel experimentation
- Parameter sweeps
- Job arrays

**Deliverable**: Results comparing all 4 experiments

---

### Phase 2 Checkpoint

**Before moving to Phase 3, you should be able to**:
- [ ] Write SLURM job scripts
- [ ] Submit and monitor jobs
- [ ] Use interactive sessions
- [ ] Run multi-node jobs
- [ ] Understand when to use SLURM vs Kubernetes

**Cleanup**: `terraform destroy`

---

## 📅 Phase 3: Distributed Training (Day 4-5 - 3 hours)

**Module**: Parallel Computing (Module 3)
**Goal**: Master multi-GPU distributed training
**Cost**: ~$5 (3 hours of practice)

### Setup
```bash
cd ../modules/03-parallel-computing
./deploy.sh
# Wait 10 minutes
```

### Exercises

#### Exercise 3.1: Distributed Hello World (45 mins)

**Tasks**:
1. SSH to both nodes (use 2 terminal windows)
2. Run `distributed_hello.py` on both nodes simultaneously
3. Observe AllReduce synchronization
4. Modify tensor size - see how sync time changes

**Questions**:
- What is the rank of each process?
- What does AllReduce do?
- How long does sync take?

**Expected Learning**:
- Process groups
- Rank and world_size
- Collective operations

**Deliverable**: Output from both nodes showing sync

---

#### Exercise 3.2: DDP Training (1 hour)

**Tasks**:
1. Run `ddp_training.py` on both nodes
2. Observe automatic gradient synchronization
3. Modify batch size - see impact on performance
4. Try different models (change layer sizes)

**Advanced**:
- Add timing to measure speedup vs single GPU
- Calculate scaling efficiency

**Expected Learning**:
- Data parallel training
- Gradient synchronization
- DistributedSampler

**Deliverable**: Training logs + performance comparison

---

#### Exercise 3.3: Communication Profiling (45 mins)

**Tasks**:
1. Run `profile_communication.py`
2. Record bandwidth for different tensor sizes
3. Plot results (on paper or spreadsheet)
4. Identify at what size bandwidth plateaus

**Expected Learning**:
- Communication overhead
- Bandwidth vs latency
- Network bottlenecks

**Deliverable**: Bandwidth measurements + graph

---

#### Exercise 3.4: Real Training (30 mins)

**Tasks**:
1. Train a simple CNN on fake image data (32x32)
2. Run on 1 GPU, then 2 GPUs
3. Compare training time
4. Calculate speedup

**Expected Learning**:
- End-to-end distributed training
- Scaling efficiency
- When distributed training helps

**Deliverable**: Training times + speedup calculation

---

### Phase 3 Checkpoint

**Before moving to Phase 4, you should be able to**:
- [ ] Initialize distributed process groups
- [ ] Use DistributedDataParallel
- [ ] Profile communication overhead
- [ ] Understand AllReduce, Broadcast
- [ ] Calculate scaling efficiency

**Cleanup**: `terraform destroy`

---

## 📅 Phase 4: GPU Comparison & Optimization (Day 6 - 2 hours)

**Module**: NVIDIA Benchmarking (Module 4)
**Goal**: Compare GPUs and optimize configurations
**Cost**: ~$3-6 (depending on GPU types tested)

### Setup
```bash
cd ../modules/04-nvidia-benchmarking
./deploy.sh
```

### Exercises

#### Exercise 4.1: GPU Specifications (30 mins)

**Tasks**:
1. Run `gpu_specs.py` on default GPU (T4)
2. Record all specs
3. Change `instance_type` in terraform.tfvars to `g6.2xlarge` (L4)
4. Redeploy and compare specs

**Expected Learning**:
- GPU architectures
- VRAM differences
- Compute capability

**Deliverable**: Comparison table of T4 vs L4

---

#### Exercise 4.2: TFLOPS Benchmark (30 mins)

**Tasks**:
1. Run `tflops_benchmark.py` on T4
2. Record TFLOPS for each matrix size
3. If budget allows, repeat on L4
4. Compare theoretical vs actual performance

**Expected Learning**:
- Raw compute performance
- Architecture differences
- TFLOPS metric

**Deliverable**: TFLOPS comparison chart

---

#### Exercise 4.3: Inference Throughput (45 mins)

**Tasks**:
1. Run `vllm_benchmark.py` with GPT-2
2. Record tokens/second
3. Run with different batch sizes
4. Find optimal configuration

**Advanced**:
- Test with larger model (opt-1.3b)
- Compare memory usage

**Expected Learning**:
- Inference optimization
- Batch size impact
- Memory-performance tradeoff

**Deliverable**: Throughput vs batch size graph

---

#### Exercise 4.4: Cost Analysis (15 mins)

**Tasks**:
1. Run `cost_analysis.py`
2. Calculate cost per 1M tokens for your GPU
3. Compare with other GPU types (from data)
4. Make recommendation: which GPU for production?

**Expected Learning**:
- Cost optimization
- Performance per dollar
- GPU selection criteria

**Deliverable**: Cost comparison + recommendation

---

### Phase 4 Checkpoint

**Final assessment - you should be able to**:
- [ ] Compare different GPU types
- [ ] Benchmark inference performance
- [ ] Calculate cost metrics
- [ ] Recommend GPU for specific workloads
- [ ] Optimize vLLM configurations

**Cleanup**: `terraform destroy`

---

## 🎓 Bonus Phase: eBPF Tracing (Optional - 2 hours)

**Goal**: Deep-dive into GPU operations with eBPF
**Cost**: ~$1 (1-2 hours)

### Setup
```bash
cd ..  # Back to Los_Alamos root
./quick-deploy-ebpf-tracing.sh
```

### Exercises

#### Exercise B.1: Deploy vLLM with eBPF Sidecar (30 mins)

**Tasks**:
1. SSH to instance
2. Deploy K8s manifests from `shared/research/k3s-vllm-tracing/`
3. Verify both containers running
4. View eBPF traces

**Expected Learning**:
- Sidecar pattern
- eBPF basics
- CUDA tracing

---

#### Exercise B.2: Analyze CUDA Calls (1 hour)

**Tasks**:
1. Send inference request to vLLM
2. Capture eBPF traces
3. Identify CUDA kernel calls
4. Count cudaMalloc calls

**Expected Learning**:
- CUDA API calls
- Memory operations
- Kernel launches

---

#### Exercise B.3: Custom Tracing (30 mins)

**Tasks**:
1. Modify bpftrace script to filter specific functions
2. Trace only memory operations
3. Count total memory allocations

**Expected Learning**:
- bpftrace syntax
- Custom filtering
- Advanced profiling

---

## 📊 Final Project: Comprehensive Benchmark Report

**Objective**: Create a professional benchmark report comparing 2+ GPUs

**Requirements**:
1. Test 2 GPU types (e.g., T4 vs L4)
2. Benchmark 2-3 models
3. Include:
   - TFLOPS comparison
   - Inference throughput
   - Cost analysis
   - Recommendation

**Format**: 2-3 page document with graphs

**Time**: 3-4 hours
**Cost**: ~$3-5

---

## 📝 Grading Rubric

### Phase 1: GPU Fundamentals (25 points)
- [ ] All exercises completed (10 pts)
- [ ] Deliverables submitted (5 pts)
- [ ] Understanding demonstrated (10 pts)

### Phase 2: SLURM (25 points)
- [ ] All exercises completed (10 pts)
- [ ] Job scripts working (5 pts)
- [ ] Multi-node execution (10 pts)

### Phase 3: Distributed Training (25 points)
- [ ] DDP working (10 pts)
- [ ] Performance analysis (5 pts)
- [ ] Scaling efficiency calculated (10 pts)

### Phase 4: Benchmarking (25 points)
- [ ] Benchmarks completed (10 pts)
- [ ] Cost analysis (5 pts)
- [ ] Recommendations (10 pts)

### Bonus: eBPF (+10 points)
- [ ] eBPF tracing working (10 pts)

**Total**: 100 points (110 with bonus)

---

## 💡 Tips for Success

1. **Don't Rush**: Take breaks between phases
2. **Document Everything**: Screenshot outputs, save logs
3. **Ask Questions**: Write down what you don't understand
4. **Cost Control**: Always run `terraform destroy` when done
5. **Experiment**: Modify parameters, break things, learn

## 🆘 Getting Help

If stuck:
1. Check module README.md
2. Review troubleshooting sections
3. Check terraform output messages
4. Verify SSH connectivity
5. Check GPU with `nvidia-smi`

## 📚 Additional Challenges

After completing all phases:

1. **Challenge 1**: Implement gradient accumulation
2. **Challenge 2**: Train a model on real dataset (MNIST)
3. **Challenge 3**: Profile a production workload
4. **Challenge 4**: Set up automated benchmarking pipeline
5. **Challenge 5**: Write a blog post explaining what you learned

---

**Good luck, Noah! You've got this! 🚀**
