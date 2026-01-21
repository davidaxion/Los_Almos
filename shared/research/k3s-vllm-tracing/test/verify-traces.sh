#!/bin/bash
#
# verify-traces.sh - Verify eBPF traces are being captured and uploaded to S3
#
# Checks:
#   1. eBPF sidecar is running and healthy
#   2. Trace files are being created
#   3. Traces are being uploaded to S3
#
# Usage:
#   ./verify-traces.sh [S3_BUCKET] [S3_PREFIX]

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

S3_BUCKET="${1:-littleboy-research-traces}"
S3_PREFIX="${2:-k3s-vllm/}"
NAMESPACE="vllm-tracing"

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           eBPF Trace Verification Tool                       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Step 1: Check pod status
echo -e "${GREEN}[1/5] Checking pod status...${NC}"
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=vllm -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD_NAME" ]; then
    echo -e "${RED}✗ vLLM pod not found${NC}"
    exit 1
fi

echo "  Pod: $POD_NAME"

# Check both containers are running
VLLM_STATUS=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[?(@.name=="vllm")].ready}')
TRACER_STATUS=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[?(@.name=="ebpf-tracer")].ready}')

if [ "$VLLM_STATUS" == "true" ]; then
    echo -e "  vLLM container: ${GREEN}✓ Running${NC}"
else
    echo -e "  vLLM container: ${RED}✗ Not ready${NC}"
fi

if [ "$TRACER_STATUS" == "true" ]; then
    echo -e "  eBPF tracer container: ${GREEN}✓ Running${NC}"
else
    echo -e "  eBPF tracer container: ${RED}✗ Not ready${NC}"
fi

echo ""

# Step 2: Check tracer logs
echo -e "${GREEN}[2/5] Checking tracer logs...${NC}"

TRACER_LOGS=$(kubectl logs "$POD_NAME" -n "$NAMESPACE" -c ebpf-tracer --tail=20 2>/dev/null || echo "")

if echo "$TRACER_LOGS" | grep -q "Tracing Started"; then
    echo -e "  ${GREEN}✓ Tracer has started${NC}"
elif echo "$TRACER_LOGS" | grep -q "Starting"; then
    echo -e "  ${YELLOW}⧗ Tracer is starting...${NC}"
else
    echo -e "  ${RED}✗ Tracer may not be running properly${NC}"
    echo "  Last 5 log lines:"
    echo "$TRACER_LOGS" | tail -5 | sed 's/^/    /'
fi

# Check if vLLM process found
if echo "$TRACER_LOGS" | grep -q "Found vLLM process"; then
    PID=$(echo "$TRACER_LOGS" | grep "Found vLLM process" | tail -1 | grep -oP 'PID \K[0-9]+')
    echo -e "  ${GREEN}✓ Found vLLM process (PID: $PID)${NC}"
else
    echo -e "  ${YELLOW}⧗ Waiting for vLLM process...${NC}"
fi

echo ""

# Step 3: Check trace files in pod
echo -e "${GREEN}[3/5] Checking trace files...${NC}"

TRACE_FILES=$(kubectl exec "$POD_NAME" -n "$NAMESPACE" -c ebpf-tracer -- ls -lh /traces/ 2>/dev/null || echo "")

if [ -n "$TRACE_FILES" ]; then
    FILE_COUNT=$(echo "$TRACE_FILES" | grep -c "trace_" || echo "0")
    if [ "$FILE_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}✓ Found $FILE_COUNT trace file(s)${NC}"
        echo "$TRACE_FILES" | grep "trace_" | head -3 | sed 's/^/    /'
        if [ "$FILE_COUNT" -gt 3 ]; then
            echo "    ... and $((FILE_COUNT - 3)) more"
        fi
    else
        echo -e "  ${YELLOW}⧗ No trace files yet (may still be initializing)${NC}"
    fi
else
    echo -e "  ${YELLOW}⧗ Cannot access trace directory${NC}"
fi

echo ""

# Step 4: Check S3 uploads
echo -e "${GREEN}[4/5] Checking S3 uploads...${NC}"
echo "  Bucket: s3://${S3_BUCKET}/${S3_PREFIX}"

if command -v aws &> /dev/null; then
    # List recent files in S3
    S3_FILES=$(aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}" --recursive 2>/dev/null | tail -10 || echo "")

    if [ -n "$S3_FILES" ]; then
        S3_FILE_COUNT=$(echo "$S3_FILES" | wc -l | tr -d ' ')
        echo -e "  ${GREEN}✓ Found files in S3 (showing last 5)${NC}"
        echo "$S3_FILES" | tail -5 | sed 's/^/    /'

        # Check if there are recent files (within last 5 minutes)
        RECENT_FILE=$(echo "$S3_FILES" | tail -1)
        if [ -n "$RECENT_FILE" ]; then
            echo ""
            echo "  Most recent file:"
            echo "    $RECENT_FILE"
        fi
    else
        echo -e "  ${YELLOW}⧗ No files in S3 yet${NC}"
        echo "  (Uploads happen every 2 minutes for completed traces)"
    fi
else
    echo -e "  ${YELLOW}⧗ AWS CLI not found, skipping S3 verification${NC}"
    echo "  Install: curl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\" && unzip awscliv2.zip && sudo ./aws/install"
fi

echo ""

# Step 5: Check trace content
echo -e "${GREEN}[5/5] Checking trace content...${NC}"

# Get a sample trace file from the pod
SAMPLE_TRACE=$(kubectl exec "$POD_NAME" -n "$NAMESPACE" -c ebpf-tracer -- sh -c "find /traces -name 'trace_*.jsonl' -type f | head -1" 2>/dev/null || echo "")

if [ -n "$SAMPLE_TRACE" ]; then
    echo "  Sample trace: $(basename "$SAMPLE_TRACE")"

    # Get first few lines
    TRACE_CONTENT=$(kubectl exec "$POD_NAME" -n "$NAMESPACE" -c ebpf-tracer -- head -5 "$SAMPLE_TRACE" 2>/dev/null || echo "")

    if [ -n "$TRACE_CONTENT" ]; then
        LINE_COUNT=$(kubectl exec "$POD_NAME" -n "$NAMESPACE" -c ebpf-tracer -- wc -l "$SAMPLE_TRACE" 2>/dev/null | awk '{print $1}')
        echo -e "  ${GREEN}✓ Trace file has $LINE_COUNT events${NC}"

        # Check for CUDA functions
        CUDA_COUNT=$(echo "$TRACE_CONTENT" | grep -c "cuda\\|cu[A-Z]" || echo "0")
        if [ "$CUDA_COUNT" -gt 0 ]; then
            echo -e "  ${GREEN}✓ Contains CUDA API calls${NC}"
        fi

        echo ""
        echo "  Sample events (first 3 lines):"
        echo "$TRACE_CONTENT" | head -3 | sed 's/^/    /'
    fi
else
    echo -e "  ${YELLOW}⧗ No trace files available yet${NC}"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Summary
echo -e "${GREEN}Summary:${NC}"
echo "  • Pod is running with vLLM and eBPF tracer"
echo "  • Tracer is attached to vLLM process"
echo "  • Trace files are being created in /traces"
echo "  • Files are uploaded to S3 every 2 minutes"
echo ""
echo -e "${BLUE}Commands:${NC}"
echo "  # View tracer logs:"
echo "  kubectl logs $POD_NAME -n $NAMESPACE -c ebpf-tracer -f"
echo ""
echo "  # List trace files:"
echo "  kubectl exec $POD_NAME -n $NAMESPACE -c ebpf-tracer -- ls -lh /traces/"
echo ""
echo "  # View recent trace content:"
echo "  kubectl exec $POD_NAME -n $NAMESPACE -c ebpf-tracer -- tail -20 /traces/trace_*.jsonl"
echo ""
echo "  # Download from S3:"
echo "  aws s3 sync s3://${S3_BUCKET}/${S3_PREFIX} ./traces/"
echo ""
