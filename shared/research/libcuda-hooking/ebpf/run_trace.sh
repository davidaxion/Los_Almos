#!/bin/bash
#
# run_trace.sh - eBPF CUDA Tracer Runner
#
# Simplifies running eBPF traces with proper setup and error handling
#
# Usage:
#   sudo ./run_trace.sh python inference.py
#   sudo ./run_trace.sh --kernel python inference.py
#   sudo ./run_trace.sh --method=bpftrace python inference.py
#   sudo ./run_trace.sh --method=bcc --kernel python inference.py

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METHOD="bpftrace"
KERNEL_HOOKS=0
OUTPUT_DIR="./traces"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --method=*)
            METHOD="${1#*=}"
            shift
            ;;
        --kernel)
            KERNEL_HOOKS=1
            shift
            ;;
        --output-dir=*)
            OUTPUT_DIR="${1#*=}"
            shift
            ;;
        --help|-h)
            echo "Usage: sudo $0 [options] <command>"
            echo ""
            echo "Options:"
            echo "  --method=<method>      Tracing method: bpftrace or bcc (default: bpftrace)"
            echo "  --kernel               Enable kernel-level hooks (nvidia.ko)"
            echo "  --output-dir=<dir>     Output directory (default: ./traces)"
            echo "  --help                 Show this help"
            echo ""
            echo "Methods:"
            echo "  bpftrace - Simple, high-level tracing (recommended)"
            echo "  bcc      - More powerful, programmable tracing"
            echo ""
            echo "Examples:"
            echo "  sudo $0 python inference.py"
            echo "  sudo $0 --kernel python train.py"
            echo "  sudo $0 --method=bcc --kernel python benchmark.py"
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

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo -e "${BLUE}=== CUDA eBPF Tracer ===${NC}"
echo -e "${BLUE}Method: ${METHOD}${NC}"
echo -e "${BLUE}Kernel hooks: $([ $KERNEL_HOOKS -eq 1 ] && echo "Enabled" || echo "Disabled")${NC}"
echo -e "${BLUE}Output directory: ${OUTPUT_DIR}${NC}"
echo -e "${BLUE}Command: $@${NC}"
echo ""

# Check dependencies
check_dependency() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}Error: $1 is not installed${NC}"
        echo "Install with: sudo apt install $2"
        exit 1
    fi
}

if [ "$METHOD" = "bpftrace" ]; then
    check_dependency bpftrace bpftrace

    echo -e "${GREEN}Starting bpftrace...${NC}"

    TRACE_FILE="${OUTPUT_DIR}/trace_${TIMESTAMP}.jsonl"
    SCRIPT_FILE="${SCRIPT_DIR}/trace_cuda_full.bt"

    if [ ! -f "$SCRIPT_FILE" ]; then
        echo -e "${RED}Error: Trace script not found: $SCRIPT_FILE${NC}"
        exit 1
    fi

    # Start bpftrace in background
    bpftrace "$SCRIPT_FILE" > "$TRACE_FILE" 2>&1 &
    BPFTRACE_PID=$!

    # Give it time to attach
    sleep 3

    if ! ps -p $BPFTRACE_PID > /dev/null; then
        echo -e "${RED}Error: bpftrace failed to start${NC}"
        cat "$TRACE_FILE"
        exit 1
    fi

    echo -e "${GREEN}bpftrace attached (PID: $BPFTRACE_PID)${NC}"
    echo -e "${GREEN}Running target command...${NC}"
    echo ""

    # Run the target command
    "$@"
    EXIT_CODE=$?

    echo ""
    echo -e "${GREEN}Target command finished (exit code: $EXIT_CODE)${NC}"
    echo -e "${GREEN}Stopping bpftrace...${NC}"

    # Stop bpftrace
    kill -INT $BPFTRACE_PID
    wait $BPFTRACE_PID 2>/dev/null || true

    echo -e "${GREEN}Trace saved to: $TRACE_FILE${NC}"

elif [ "$METHOD" = "bcc" ]; then
    check_dependency python3 python3

    # Check for BCC Python bindings
    if ! python3 -c "import bcc" 2>/dev/null; then
        echo -e "${RED}Error: BCC Python bindings not installed${NC}"
        echo "Install with: sudo apt install python3-bpfcc"
        exit 1
    fi

    echo -e "${GREEN}Starting BCC tracer...${NC}"

    TRACE_FILE="${OUTPUT_DIR}/trace_${TIMESTAMP}.jsonl"
    TRACER_SCRIPT="${SCRIPT_DIR}/cuda_tracer.py"

    if [ ! -f "$TRACER_SCRIPT" ]; then
        echo -e "${RED}Error: Tracer script not found: $TRACER_SCRIPT${NC}"
        exit 1
    fi

    # Start tracer in background
    KERNEL_FLAG=""
    if [ $KERNEL_HOOKS -eq 1 ]; then
        KERNEL_FLAG="--kernel"
    fi

    python3 "$TRACER_SCRIPT" -o "$TRACE_FILE" $KERNEL_FLAG &
    TRACER_PID=$!

    sleep 3

    if ! ps -p $TRACER_PID > /dev/null; then
        echo -e "${RED}Error: BCC tracer failed to start${NC}"
        exit 1
    fi

    echo -e "${GREEN}BCC tracer attached (PID: $TRACER_PID)${NC}"
    echo -e "${GREEN}Running target command...${NC}"
    echo ""

    # Run the target command
    "$@"
    EXIT_CODE=$?

    echo ""
    echo -e "${GREEN}Target command finished (exit code: $EXIT_CODE)${NC}"
    echo -e "${GREEN}Stopping tracer...${NC}"

    # Stop tracer
    kill -INT $TRACER_PID
    wait $TRACER_PID 2>/dev/null || true

    echo -e "${GREEN}Trace saved to: $TRACE_FILE${NC}"

else
    echo -e "${RED}Error: Unknown method: $METHOD${NC}"
    exit 1
fi

# Visualize if possible
VISUALIZER="${SCRIPT_DIR}/../tools/visualize_pipeline.py"
if [ -f "$VISUALIZER" ] && [ -f "$TRACE_FILE" ]; then
    echo ""
    echo -e "${BLUE}=== Generating Visualization ===${NC}"

    # Extract just JSON lines (filter out non-JSON output)
    CLEAN_TRACE="${OUTPUT_DIR}/trace_${TIMESTAMP}_clean.jsonl"
    grep '^{' "$TRACE_FILE" > "$CLEAN_TRACE" 2>/dev/null || true

    if [ -s "$CLEAN_TRACE" ]; then
        python3 "$VISUALIZER" --format=all "$CLEAN_TRACE"
        echo ""
        echo -e "${GREEN}Visualization complete!${NC}"
        echo -e "${GREEN}Chrome trace: trace.json${NC}"
        echo -e "${GREEN}View in: chrome://tracing${NC}"
    else
        echo -e "${YELLOW}No JSON events found in trace${NC}"
    fi
fi

echo ""
echo -e "${BLUE}=== Tracing Complete ===${NC}"
echo -e "${GREEN}Trace files in: ${OUTPUT_DIR}${NC}"
ls -lh "${OUTPUT_DIR}"/trace_${TIMESTAMP}* 2>/dev/null || true
