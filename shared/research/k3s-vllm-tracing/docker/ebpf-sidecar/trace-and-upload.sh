#!/bin/bash
#
# trace-and-upload.sh - eBPF CUDA Tracing with S3 Upload
#
# Traces CUDA API calls from vLLM process and uploads results to S3
#
# Environment Variables:
#   TARGET_PROCESS    - Process name to trace (default: python)
#   S3_BUCKET         - S3 bucket for uploads (required)
#   S3_PREFIX         - S3 key prefix (default: k3s-vllm/)
#   TRACE_INTERVAL    - Seconds between trace rotations (default: 60)
#   TRACE_DIR         - Directory for trace files (default: /traces)
#   UPLOAD_ENABLED    - Enable S3 upload (default: true)

set -e

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log "╔═══════════════════════════════════════════════════════════════╗"
log "║         eBPF CUDA Tracer Sidecar Starting                    ║"
log "╚═══════════════════════════════════════════════════════════════╝"

# Configuration
TARGET_PROCESS="${TARGET_PROCESS:-python}"
S3_BUCKET="${S3_BUCKET:-}"
S3_PREFIX="${S3_PREFIX:-k3s-vllm/}"
TRACE_INTERVAL="${TRACE_INTERVAL:-60}"
TRACE_DIR="${TRACE_DIR:-/traces}"
UPLOAD_ENABLED="${UPLOAD_ENABLED:-true}"

log "Configuration:"
log "  Target Process: $TARGET_PROCESS"
log "  S3 Bucket: ${S3_BUCKET:-not set}"
log "  S3 Prefix: $S3_PREFIX"
log "  Trace Interval: ${TRACE_INTERVAL}s"
log "  Trace Directory: $TRACE_DIR"
log "  Upload Enabled: $UPLOAD_ENABLED"

# Create trace directory
mkdir -p "$TRACE_DIR"

# Mark as healthy
touch /tmp/tracer-healthy

# Function to find vLLM process
find_target_process() {
    local pid=""
    local attempt=0
    local max_attempts=30

    log "Searching for target process: $TARGET_PROCESS"

    while [ $attempt -lt $max_attempts ]; do
        # Look for Python process running vLLM
        pid=$(pgrep -f "python.*vllm" | head -1)

        if [ -n "$pid" ]; then
            log "✓ Found vLLM process: PID $pid"

            # Verify it has CUDA libraries loaded
            if grep -q "libcuda\|libcudart" /proc/$pid/maps 2>/dev/null; then
                log "✓ Process has CUDA libraries loaded"
                echo "$pid"
                return 0
            else
                log_warn "Process found but CUDA not loaded yet, waiting..."
            fi
        fi

        attempt=$((attempt + 1))
        sleep 5
    done

    log_error "Could not find target process after $max_attempts attempts"
    return 1
}

# Function to upload trace to S3
upload_to_s3() {
    local file="$1"

    if [ "$UPLOAD_ENABLED" != "true" ] || [ -z "$S3_BUCKET" ]; then
        return 0
    fi

    if [ ! -f "$file" ]; then
        log_warn "File not found for upload: $file"
        return 1
    fi

    local filename=$(basename "$file")
    local s3_key="${S3_PREFIX}${filename}"

    log "Uploading to S3: s3://${S3_BUCKET}/${s3_key}"

    if aws s3 cp "$file" "s3://${S3_BUCKET}/${s3_key}" --quiet; then
        log "✓ Uploaded: $filename"
        # Remove local file after successful upload
        rm -f "$file"
        return 0
    else
        log_error "Failed to upload: $filename"
        return 1
    fi
}

# Function to start background uploader
start_uploader() {
    if [ "$UPLOAD_ENABLED" != "true" ] || [ -z "$S3_BUCKET" ]; then
        log "S3 upload disabled"
        return 0
    fi

    log "Starting background S3 uploader..."

    (
        while true; do
            # Find trace files older than 2 minutes
            find "$TRACE_DIR" -name "trace_*.jsonl" -type f -mmin +2 2>/dev/null | while read -r file; do
                upload_to_s3 "$file"
            done

            # Cleanup very old files (7 days) to prevent disk full
            find "$TRACE_DIR" -name "trace_*.jsonl" -type f -mtime +7 -delete 2>/dev/null

            sleep 30
        done
    ) &

    UPLOADER_PID=$!
    log "✓ Uploader started (PID: $UPLOADER_PID)"
}

# Function to run bpftrace
run_trace() {
    local target_pid="$1"
    local trace_file="$TRACE_DIR/trace_$(date +%Y%m%d_%H%M%S).jsonl"

    log "Starting trace: $trace_file"

    # bpftrace script to capture CUDA calls
    timeout ${TRACE_INTERVAL}s bpftrace -p "$target_pid" <<'BPFTRACE_EOF' -o "$trace_file" 2>/dev/null || true
BEGIN {
    printf("Starting CUDA API trace for PID %d\n", pid);
    @start_time = nsecs;
}

// Hook CUDA Driver API functions (libcuda.so)
uprobe:/usr/local/cuda/lib64/libcuda.so:cuInit,
uprobe:/usr/local/cuda/lib64/libcuda.so:cuDeviceGet*,
uprobe:/usr/local/cuda/lib64/libcuda.so:cuCtx*,
uprobe:/usr/local/cuda/lib64/libcuda.so:cuMem*,
uprobe:/usr/local/cuda/lib64/libcuda.so:cuLaunch*,
uprobe:/usr/local/cuda/lib64/libcuda.so:cuStream*,
uprobe:/usr/local/cuda/lib64/libcuda.so:cuModule*,
uprobe:/lib/x86_64-linux-gnu/libcuda.so*:cuInit,
uprobe:/lib/x86_64-linux-gnu/libcuda.so*:cuDeviceGet*,
uprobe:/lib/x86_64-linux-gnu/libcuda.so*:cuCtx*,
uprobe:/lib/x86_64-linux-gnu/libcuda.so*:cuMem*,
uprobe:/lib/x86_64-linux-gnu/libcuda.so*:cuLaunch*,
uprobe:/lib/x86_64-linux-gnu/libcuda.so*:cuStream*,
uprobe:/lib/x86_64-linux-gnu/libcuda.so*:cuModule*
{
    $ts = (nsecs - @start_time) / 1000000.0;  // milliseconds
    $func = str(probe);

    printf("{\"ts\":%.3f,\"pid\":%d,\"type\":\"cuda_api\",\"func\":\"%s\",\"phase\":\"entry\"}\n",
           $ts, pid, $func);
}

// Hook CUDA Runtime API functions (libcudart.so)
uprobe:/usr/local/cuda/lib64/libcudart.so:cudaMalloc*,
uprobe:/usr/local/cuda/lib64/libcudart.so:cudaMemcpy*,
uprobe:/usr/local/cuda/lib64/libcudart.so:cudaLaunch*,
uprobe:/usr/local/cuda/lib64/libcudart.so:cudaStreamSynchronize,
uprobe:/lib/x86_64-linux-gnu/libcudart.so*:cudaMalloc*,
uprobe:/lib/x86_64-linux-gnu/libcudart.so*:cudaMemcpy*,
uprobe:/lib/x86_64-linux-gnu/libcudart.so*:cudaLaunch*,
uprobe:/lib/x86_64-linux-gnu/libcudart.so*:cudaStreamSynchronize
{
    $ts = (nsecs - @start_time) / 1000000.0;
    $func = str(probe);

    printf("{\"ts\":%.3f,\"pid\":%d,\"type\":\"cuda_runtime\",\"func\":\"%s\",\"phase\":\"entry\"}\n",
           $ts, pid, $func);
}

END {
    printf("Trace complete\n");
}
BPFTRACE_EOF

    if [ -f "$trace_file" ]; then
        local line_count=$(wc -l < "$trace_file")
        log "✓ Trace complete: $line_count events captured"
    else
        log_warn "Trace file not created"
    fi
}

# Main loop
main() {
    # Find vLLM process
    TARGET_PID=$(find_target_process)
    if [ -z "$TARGET_PID" ]; then
        log_error "Failed to find target process"
        exit 1
    fi

    # Start background uploader
    start_uploader

    log "╔═══════════════════════════════════════════════════════════════╗"
    log "║                 Tracing Started                               ║"
    log "╚═══════════════════════════════════════════════════════════════╝"

    # Continuous tracing loop
    while true; do
        # Check if process still exists
        if ! kill -0 "$TARGET_PID" 2>/dev/null; then
            log_warn "Target process (PID $TARGET_PID) no longer exists"
            log "Searching for new process..."

            TARGET_PID=$(find_target_process)
            if [ -z "$TARGET_PID" ]; then
                log_error "No process found, exiting"
                break
            fi
        fi

        # Run trace for TRACE_INTERVAL seconds
        run_trace "$TARGET_PID"

        # Small pause between traces
        sleep 2
    done

    log "Tracing stopped"

    # Upload any remaining files
    if [ "$UPLOAD_ENABLED" = "true" ]; then
        log "Uploading remaining trace files..."
        find "$TRACE_DIR" -name "trace_*.jsonl" -type f | while read -r file; do
            upload_to_s3 "$file"
        done
    fi

    # Clean up
    if [ -n "$UPLOADER_PID" ]; then
        kill "$UPLOADER_PID" 2>/dev/null || true
    fi
}

# Trap signals for graceful shutdown
trap 'log "Received shutdown signal, cleaning up..."; exit 0' SIGTERM SIGINT

# Run main function
main
