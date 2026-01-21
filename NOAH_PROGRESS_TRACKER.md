# Noah's Progress Tracker

Track your learning journey through the Los Alamos GPU modules.

**Start Date**: _______________
**Target Completion**: _______________

---

## 📅 Phase 1: GPU Fundamentals (Day 1)

**Date Started**: _______________
**Date Completed**: _______________
**Time Spent**: _______________
**Cost**: $_______________

### Exercises
- [ ] 1.1: Hello GPU (30 mins)
  - [ ] Run basic script
  - [ ] Modify matrix size to 5000x5000
  - [ ] Record timing results
  - [ ] Write explanation of GPU advantage
  - **Notes**: _______________________________________________

- [ ] 1.2: First Inference (30 mins)
  - [ ] Run default inference
  - [ ] Change prompt
  - [ ] Modify max_tokens to 100
  - [ ] Record generation time
  - **Output quality**: ⭐⭐⭐⭐⭐
  - **Notes**: _______________________________________________

- [ ] 1.3: GPU Monitoring (30 mins)
  - [ ] Screenshot nvidia-smi
  - [ ] Monitor during inference
  - [ ] Record GPU utilization: ______%
  - [ ] Record memory used: ______GB
  - [ ] Record temperature: ______°C
  - **Notes**: _______________________________________________

- [ ] 1.4: Memory Management (30 mins)
  - [ ] Run original script
  - [ ] Trigger OOM error
  - [ ] Fix the error
  - [ ] Understand memory limits
  - **Notes**: _______________________________________________

### Checkpoint Questions
- [ ] Can you explain what CUDA is?
- [ ] Can you run inference on a GPU?
- [ ] Can you read nvidia-smi output?
- [ ] Do you understand GPU memory constraints?
- [ ] Can you name 3 GPU types and their use cases?

**Phase 1 Score**: _____ / 25

**Key Learnings**:
_________________________________________________________
_________________________________________________________
_________________________________________________________

**Challenges Faced**:
_________________________________________________________
_________________________________________________________

---

## 📅 Phase 2: SLURM Cluster (Day 2-3)

**Date Started**: _______________
**Date Completed**: _______________
**Time Spent**: _______________
**Cost**: $_______________

### Exercises
- [ ] 2.1: First SLURM Job (45 mins)
  - [ ] Create hello-slurm.sh
  - [ ] Submit with sbatch
  - [ ] Monitor with squeue
  - [ ] View output file
  - [ ] Submit 5 jobs at once
  - [ ] Cancel a job with scancel
  - **Job IDs used**: _______________
  - **Notes**: _______________________________________________

- [ ] 2.2: Interactive Session (30 mins)
  - [ ] Request interactive GPU
  - [ ] Run Python interactively
  - [ ] Load and run model
  - [ ] Exit and verify release
  - **Notes**: _______________________________________________

- [ ] 2.3: Multi-Node Job (45 mins)
  - [ ] Create multi-node.sh
  - [ ] Submit to 2 nodes
  - [ ] Observe outputs
  - [ ] Modify to use 3 nodes
  - **Nodes used**: _______________
  - **Notes**: _______________________________________________

- [ ] 2.4: Job Arrays (45 mins)
  - [ ] Create array-job.sh
  - [ ] Submit 4-task array
  - [ ] Test different learning rates
  - [ ] Compare outputs
  - **Best learning rate found**: _______________
  - **Notes**: _______________________________________________

### Checkpoint Questions
- [ ] Can you write SLURM job scripts?
- [ ] Can you submit and monitor jobs?
- [ ] Can you use interactive sessions?
- [ ] Can you run multi-node jobs?
- [ ] When would you use SLURM vs Kubernetes?

**Phase 2 Score**: _____ / 25

**Key Learnings**:
_________________________________________________________
_________________________________________________________
_________________________________________________________

**Challenges Faced**:
_________________________________________________________
_________________________________________________________

---

## 📅 Phase 3: Distributed Training (Day 4-5)

**Date Started**: _______________
**Date Completed**: _______________
**Time Spent**: _______________
**Cost**: $_______________

### Exercises
- [ ] 3.1: Distributed Hello World (45 mins)
  - [ ] Run on both nodes
  - [ ] Observe AllReduce
  - [ ] Modify tensor size
  - [ ] Record sync time: ______ms
  - **Rank 0 output**: _______________
  - **Rank 1 output**: _______________
  - **Notes**: _______________________________________________

- [ ] 3.2: DDP Training (1 hour)
  - [ ] Run ddp_training.py
  - [ ] Observe gradient sync
  - [ ] Test different batch sizes
  - [ ] Try different models
  - **Batch sizes tested**: _______________
  - **Training time (1 GPU)**: ______s
  - **Training time (2 GPUs)**: ______s
  - **Speedup**: ______x
  - **Notes**: _______________________________________________

- [ ] 3.3: Communication Profiling (45 mins)
  - [ ] Run profile_communication.py
  - [ ] Record bandwidth measurements
  - [ ] Create graph (on paper/spreadsheet)
  - [ ] Identify plateau point
  - **Max bandwidth**: ______GB/s
  - **Notes**: _______________________________________________

- [ ] 3.4: Real Training (30 mins)
  - [ ] Train CNN on fake data
  - [ ] Run on 1 GPU
  - [ ] Run on 2 GPUs
  - [ ] Calculate speedup
  - **1 GPU time**: ______s
  - **2 GPU time**: ______s
  - **Efficiency**: ______%
  - **Notes**: _______________________________________________

### Checkpoint Questions
- [ ] Can you initialize distributed process groups?
- [ ] Can you use DistributedDataParallel?
- [ ] Can you profile communication overhead?
- [ ] Do you understand AllReduce and Broadcast?
- [ ] Can you calculate scaling efficiency?

**Phase 3 Score**: _____ / 25

**Key Learnings**:
_________________________________________________________
_________________________________________________________
_________________________________________________________

**Challenges Faced**:
_________________________________________________________
_________________________________________________________

---

## 📅 Phase 4: Benchmarking (Day 6)

**Date Started**: _______________
**Date Completed**: _______________
**Time Spent**: _______________
**Cost**: $_______________

### Exercises
- [ ] 4.1: GPU Specifications (30 mins)
  - [ ] Run on T4
  - [ ] Record specs
  - [ ] Deploy L4 (optional)
  - [ ] Compare
  - **T4 VRAM**: ______GB
  - **L4 VRAM**: ______GB
  - **Notes**: _______________________________________________

- [ ] 4.2: TFLOPS Benchmark (30 mins)
  - [ ] Run on T4
  - [ ] Record TFLOPS
  - [ ] Optional: repeat on L4
  - **T4 TFLOPS**: ______
  - **L4 TFLOPS**: ______
  - **Notes**: _______________________________________________

- [ ] 4.3: Inference Throughput (45 mins)
  - [ ] Benchmark GPT-2
  - [ ] Test different batch sizes
  - [ ] Find optimal config
  - **Optimal batch size**: ______
  - **Max throughput**: ______tok/s
  - **Notes**: _______________________________________________

- [ ] 4.4: Cost Analysis (15 mins)
  - [ ] Calculate cost per 1M tokens
  - [ ] Compare GPU types
  - [ ] Make recommendation
  - **T4 cost/1M tokens**: $______
  - **L4 cost/1M tokens**: $______
  - **Recommendation**: _______________
  - **Notes**: _______________________________________________

### Checkpoint Questions
- [ ] Can you compare different GPU types?
- [ ] Can you benchmark inference performance?
- [ ] Can you calculate cost metrics?
- [ ] Can you recommend GPU for specific workloads?
- [ ] Can you optimize vLLM configurations?

**Phase 4 Score**: _____ / 25

**Key Learnings**:
_________________________________________________________
_________________________________________________________
_________________________________________________________

**Challenges Faced**:
_________________________________________________________
_________________________________________________________

---

## 🎓 Bonus Phase: eBPF Tracing (Optional)

**Date Started**: _______________
**Date Completed**: _______________
**Time Spent**: _______________
**Cost**: $_______________

### Exercises
- [ ] B.1: Deploy vLLM with eBPF (30 mins)
  - [ ] Deploy K8s manifests
  - [ ] Verify containers
  - [ ] View traces
  - **Notes**: _______________________________________________

- [ ] B.2: Analyze CUDA Calls (1 hour)
  - [ ] Send inference request
  - [ ] Capture traces
  - [ ] Identify kernel calls
  - [ ] Count cudaMalloc calls: ______
  - **Notes**: _______________________________________________

- [ ] B.3: Custom Tracing (30 mins)
  - [ ] Modify bpftrace script
  - [ ] Trace memory ops only
  - [ ] Count allocations: ______
  - **Notes**: _______________________________________________

**Bonus Score**: _____ / 10

---

## 📊 Final Summary

### Total Scores
- Phase 1: _____ / 25
- Phase 2: _____ / 25
- Phase 3: _____ / 25
- Phase 4: _____ / 25
- Bonus: _____ / 10
- **TOTAL**: _____ / 100 (110 with bonus)

### Time Investment
- Total hours: _______________
- Total cost: $_______________
- Cost per hour of learning: $_______________

### Overall Progress
- [ ] All core phases completed
- [ ] All deliverables submitted
- [ ] Bonus phase attempted
- [ ] Final project completed

### Top 3 Key Learnings
1. _________________________________________________________
2. _________________________________________________________
3. _________________________________________________________

### Biggest Challenges Overcome
1. _________________________________________________________
2. _________________________________________________________
3. _________________________________________________________

### Skills Acquired
- [ ] GPU fundamentals
- [ ] vLLM inference
- [ ] SLURM job scheduling
- [ ] Distributed training with PyTorch DDP
- [ ] Performance benchmarking
- [ ] Cost optimization
- [ ] eBPF tracing (bonus)

### Next Steps
_________________________________________________________
_________________________________________________________
_________________________________________________________

### Would Recommend This Course?
⭐⭐⭐⭐⭐

**Comments**:
_________________________________________________________
_________________________________________________________
_________________________________________________________

---

**Congratulations on completing the Los Alamos GPU Learning Path! 🎉**

**Certificate Earned**: GPU Computing Practitioner
**Date**: _______________
**Signature**: _______________
