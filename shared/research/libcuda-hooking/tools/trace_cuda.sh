#!/bin/bash
#
# trace_cuda.sh - All-in-One CUDA Tracing and Visualization
#
# Automatically traces CUDA applications and generates pipeline visualizations
#
# Usage:
#   ./trace_cuda.sh python inference.py
#   ./trace_cuda.sh --method=ebpf python inference.py
#   ./trace_cuda.sh --method=strace ./cuda_app
#

set -e

# Configuration
METHOD="${METHOD:-ld_preload}"  # ld_preload, ebpf, strace, or all
TRACE_DIR="./traces"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_PREFIX="${TRACE_DIR}/trace_${TIMESTAMP}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --method=*)
            METHOD="${1#*=}"
            shift
            ;;
        --output=*)
            OUTPUT_PREFIX="${1#*=}"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options] <command>"
            echo ""
            echo "Options:"
            echo "  --method=<method>   Tracing method: ld_preload, ebpf, strace, all (default: ld_preload)"
            echo "  --output=<prefix>   Output file prefix (default: ./traces/trace_<timestamp>)"
            echo "  --help              Show this help"
            echo ""
            echo "Methods:"
            echo "  ld_preload - Hook CUDA functions with LD_PRELOAD (no root needed)"
            echo "  ebpf       - Use eBPF uprobes to trace (requires root)"
            echo "  strace     - Trace system calls with strace (shows IOCTLs)"
            echo "  all        - Run all methods simultaneously"
            echo ""
            echo "Examples:"
            echo "  $0 python inference.py"
            echo "  $0 --method=ebpf python train.py"
            echo "  $0 --method=all ./cuda_benchmark"
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo -e "${RED}Error: No command specified${NC}"
    echo "Run with --help for usage information"
    exit 1
fi

# Create trace directory
mkdir -p "$TRACE_DIR"

echo -e "${BLUE}=== CUDA Execution Pipeline Tracer ===${NC}"
echo -e "${BLUE}Method: ${METHOD}${NC}"
echo -e "${BLUE}Output: ${OUTPUT_PREFIX}*${NC}"
echo -e "${BLUE}Command: $@${NC}"
echo ""

# Function to run LD_PRELOAD tracing
run_ld_preload() {
    echo -e "${GREEN}[LD_PRELOAD] Building hook library...${NC}"

    HOOK_DIR="$(dirname "$0")/../hooks"
    cd "$HOOK_DIR"

    if [ ! -f "libcuda_hook.so" ]; then
        echo -e "${YELLOW}Hook library not found, building...${NC}"
        make clean && make
    fi

    cd - > /dev/null

    echo -e "${GREEN}[LD_PRELOAD] Running traced application...${NC}"

    export CUDA_HOOK_TRACE="${OUTPUT_PREFIX}_ld_preload.jsonl"
    LD_PRELOAD="${HOOK_DIR}/libcuda_hook.so" "$@"

    echo -e "${GREEN}[LD_PRELOAD] Trace saved to: ${CUDA_HOOK_TRACE}${NC}"

    return 0
}

# Function to run eBPF tracing
run_ebpf() {
    if [ ! -w /sys/kernel/debug/tracing ]; then
        echo -e "${YELLOW}[eBPF] Requires root access. Run with sudo.${NC}"
        return 1
    fi

    echo -e "${GREEN}[eBPF] Starting bpftrace...${NC}"

    BPFTRACE_SCRIPT="$(dirname "$0")/trace_all_cuda.bt"

    if [ ! -f "$BPFTRACE_SCRIPT" ]; then
        echo -e "${RED}[eBPF] Script not found: $BPFTRACE_SCRIPT${NC}"
        return 1
    fi

    # Run bpftrace in background
    sudo bpftrace "$BPFTRACE_SCRIPT" > "${OUTPUT_PREFIX}_ebpf.log" 2>&1 &
    BPFTRACE_PID=$!

    sleep 2  # Give bpftrace time to attach

    echo -e "${GREEN}[eBPF] bpftrace running (PID: $BPFTRACE_PID)${NC}"

    # Run application
    "$@"

    # Stop bpftrace
    echo -e "${GREEN}[eBPF] Stopping bpftrace...${NC}"
    sudo kill -INT $BPFTRACE_PID
    wait $BPFTRACE_PID 2>/dev/null || true

    echo -e "${GREEN}[eBPF] Trace saved to: ${OUTPUT_PREFIX}_ebpf.log${NC}"

    return 0
}

# Function to run strace
run_strace() {
    echo -e "${GREEN}[STRACE] Tracing system calls...${NC}"

    strace -e ioctl -tt -T -o "${OUTPUT_PREFIX}_strace.log" "$@"

    echo -e "${GREEN}[STRACE] Trace saved to: ${OUTPUT_PREFIX}_strace.log${NC}"

    return 0
}

# Run selected tracing method(s)
case "$METHOD" in
    ld_preload)
        run_ld_preload "$@"
        TRACE_FILE="${OUTPUT_PREFIX}_ld_preload.jsonl"
        ;;
    ebpf)
        run_ebpf "$@"
        TRACE_FILE="${OUTPUT_PREFIX}_ebpf.log"
        ;;
    strace)
        run_strace "$@"
        TRACE_FILE="${OUTPUT_PREFIX}_strace.log"
        ;;
    all)
        echo -e "${YELLOW}Running all tracing methods...${NC}"
        # LD_PRELOAD doesn't require root, run it first
        run_ld_preload "$@" || true
        # strace
        run_strace "$@" || true
        # eBPF requires root
        run_ebpf "$@" || true
        TRACE_FILE="${OUTPUT_PREFIX}_ld_preload.jsonl"
        ;;
    *)
        echo -e "${RED}Unknown method: $METHOD${NC}"
        exit 1
        ;;
esac

# Visualize if we have a JSON trace
if [ -f "${OUTPUT_PREFIX}_ld_preload.jsonl" ]; then
    echo ""
    echo -e "${BLUE}=== Generating Visualization ===${NC}"

    VISUALIZER="$(dirname "$0")/visualize_pipeline.py"

    if [ -f "$VISUALIZER" ]; then
        python3 "$VISUALIZER" --format=all "${OUTPUT_PREFIX}_ld_preload.jsonl"

        echo ""
        echo -e "${GREEN}Visualization complete!${NC}"
        echo -e "${GREEN}Chrome trace: ${OUTPUT_PREFIX}_ld_preload.json${NC}"
        echo -e "${GREEN}View in Chrome: chrome://tracing${NC}"
    else
        echo -e "${YELLOW}Visualizer not found: $VISUALIZER${NC}"
    fi
fi

echo ""
echo -e "${BLUE}=== Tracing Complete ===${NC}"
echo -e "${GREEN}All trace files saved to: ${TRACE_DIR}/${NC}"
ls -lh "${OUTPUT_PREFIX}"* 2>/dev/null || true
