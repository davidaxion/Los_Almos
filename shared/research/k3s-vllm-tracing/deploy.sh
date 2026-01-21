#!/bin/bash
#
# deploy.sh - One-command deployment for vLLM with eBPF Tracing on K3s
#
# Orchestrates the complete deployment:
#   1. Build and push eBPF sidecar Docker image
#   2. Deploy Kubernetes manifests
#   3. Wait for pods to be ready
#   4. Run tests
#   5. Verify traces
#
# Usage:
#   ./deploy.sh build          # Build Docker image
#   ./deploy.sh deploy         # Deploy to K3s
#   ./deploy.sh test           # Run tests
#   ./deploy.sh verify         # Verify traces
#   ./deploy.sh all            # Do everything
#   ./deploy.sh destroy        # Clean up
#   ./deploy.sh logs           # View logs

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DOCKER_IMAGE="littleboy/ebpf-cuda-tracer:latest"
NAMESPACE="vllm-tracing"
S3_BUCKET="${S3_BUCKET:-littleboy-research-traces}"
S3_PREFIX="${S3_PREFIX:-k3s-vllm/}"

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"
}

log_step() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Build Docker image
build_image() {
    log_step "Building eBPF Sidecar Docker Image"

    cd docker/ebpf-sidecar

    log "Building image: $DOCKER_IMAGE"
    docker build -t "$DOCKER_IMAGE" .

    log "✓ Image built successfully"

    # Option to push to registry (uncomment if using remote registry)
    # log "Pushing to registry..."
    # docker push "$DOCKER_IMAGE"

    # For K3s, we can import directly
    if command -v k3s &> /dev/null; then
        log "Importing image to K3s..."
        docker save "$DOCKER_IMAGE" | sudo k3s ctr images import -
        log "✓ Image imported to K3s"
    fi

    cd ../..
}

# Deploy to K3s
deploy_k3s() {
    log_step "Deploying vLLM with eBPF Tracing to K3s"

    # Check if K3s is running
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install K3s first."
        log_error "Run: sudo ./infrastructure/k3s-install.sh"
        exit 1
    fi

    # Check Hugging Face token
    if ! kubectl get secret hf-token -n "$NAMESPACE" &>/dev/null; then
        log_warn "Hugging Face token not found"
        echo ""
        echo "To use Llama-2-7b-hf, you need a Hugging Face token with access."
        echo "Get token from: https://huggingface.co/settings/tokens"
        echo ""
        echo "Create secret with:"
        echo "  kubectl create namespace $NAMESPACE"
        echo "  kubectl create secret generic hf-token --from-literal=token=YOUR_TOKEN -n $NAMESPACE"
        echo ""
        read -p "Press Enter to continue (or Ctrl+C to cancel)..."
    fi

    # Create namespace if it doesn't exist
    log "Creating namespace..."
    kubectl apply -f kubernetes/00-namespace.yaml

    # Update ConfigMap with S3 settings
    log "Configuring S3 settings..."
    kubectl create configmap vllm-tracing-config \
        --from-literal=S3_BUCKET="$S3_BUCKET" \
        --from-literal=S3_PREFIX="$S3_PREFIX" \
        --from-literal=TRACE_INTERVAL="60" \
        --from-literal=TARGET_PROCESS="python" \
        --from-literal=UPLOAD_ENABLED="true" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Deploy storage
    log "Deploying storage..."
    kubectl apply -f kubernetes/01-storage.yaml

    # Deploy service account
    log "Deploying service account..."
    kubectl apply -f kubernetes/02-serviceaccount.yaml

    # Deploy vLLM with sidecar
    log "Deploying vLLM with eBPF sidecar..."
    kubectl apply -f kubernetes/03-vllm-deployment.yaml

    # Deploy service
    log "Deploying service..."
    kubectl apply -f kubernetes/04-service.yaml

    log "✓ All manifests applied"

    # Wait for pod to be ready
    log "Waiting for vLLM pod to be ready (this may take 5-10 minutes)..."
    log "The pod needs to download the model (~13GB) and load it into GPU memory"

    kubectl wait --for=condition=ready pod \
        -l app=vllm,model=llama2-7b \
        -n "$NAMESPACE" \
        --timeout=600s || {
        log_warn "Pod not ready after 10 minutes"
        log "Checking pod status..."
        kubectl get pods -n "$NAMESPACE"
        log "Checking events..."
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
        return 1
    }

    log "✓ vLLM pod is ready"

    # Show deployment info
    echo ""
    log "Deployment Information:"
    kubectl get pods -n "$NAMESPACE" -o wide
    echo ""

    # Get node port
    NODE_PORT=$(kubectl get svc vllm-api -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

    log "vLLM API available at: http://${NODE_IP}:${NODE_PORT}"
    log "Try: curl http://${NODE_IP}:${NODE_PORT}/health"
}

# Run tests
run_tests() {
    log_step "Running Tests"

    # Get service endpoint
    NODE_PORT=$(kubectl get svc vllm-api -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

    # Determine host (use localhost if on same machine)
    if [ "$NODE_IP" == "127.0.0.1" ] || [ "$NODE_IP" == "$(hostname -I | awk '{print $1}')" ]; then
        TEST_HOST="localhost"
    else
        TEST_HOST="$NODE_IP"
    fi

    cd test

    # Install Python dependencies if needed
    if ! python3 -c "import requests" 2>/dev/null; then
        log "Installing Python dependencies..."
        pip3 install requests
    fi

    # Run single prompt test
    log "Running single prompt test..."
    python3 single-prompt.py --host "$TEST_HOST" --port "$NODE_PORT" || {
        log_error "Single prompt test failed"
        return 1
    }

    echo ""
    read -p "Press Enter to continue with batch test (or Ctrl+C to skip)..."
    echo ""

    # Run batch test
    log "Running batch prompts test (15 prompts)..."
    python3 batch-prompts.py --host "$TEST_HOST" --port "$NODE_PORT" --count 15 || {
        log_error "Batch test failed"
        return 1
    }

    cd ..

    log "✓ All tests completed"
}

# Verify traces
verify_traces() {
    log_step "Verifying eBPF Traces"

    cd test
    chmod +x verify-traces.sh
    ./verify-traces.sh "$S3_BUCKET" "$S3_PREFIX"
    cd ..
}

# View logs
view_logs() {
    log_step "Viewing Logs"

    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=vllm -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$POD_NAME" ]; then
        log_error "No vLLM pod found"
        exit 1
    fi

    echo "Select container:"
    echo "  1) vLLM (inference server)"
    echo "  2) eBPF tracer (sidecar)"
    echo "  3) Both (split view)"
    echo ""
    read -p "Choice [1-3]: " choice

    case $choice in
        1)
            log "Showing vLLM logs (Ctrl+C to exit)..."
            kubectl logs -f "$POD_NAME" -n "$NAMESPACE" -c vllm
            ;;
        2)
            log "Showing eBPF tracer logs (Ctrl+C to exit)..."
            kubectl logs -f "$POD_NAME" -n "$NAMESPACE" -c ebpf-tracer
            ;;
        3)
            log "Showing both logs (Ctrl+C to exit)..."
            kubectl logs -f "$POD_NAME" -n "$NAMESPACE" --all-containers=true
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
}

# Clean up
destroy() {
    log_step "Cleaning Up Deployment"

    log "Deleting Kubernetes resources..."
    kubectl delete namespace "$NAMESPACE" --wait=true 2>/dev/null || true

    log "✓ Cleanup complete"
}

# Show usage
usage() {
    cat << EOF
Usage: ./deploy.sh [COMMAND]

Commands:
  build       Build eBPF sidecar Docker image
  deploy      Deploy vLLM with eBPF tracing to K3s
  test        Run inference tests (single + batch)
  verify      Verify traces are being captured and uploaded
  logs        View pod logs (vLLM or tracer)
  all         Run all steps (build -> deploy -> test -> verify)
  destroy     Delete all Kubernetes resources
  status      Show deployment status

Environment Variables:
  S3_BUCKET   S3 bucket for traces (default: littleboy-research-traces)
  S3_PREFIX   S3 key prefix (default: k3s-vllm/)

Examples:
  # Full deployment
  ./deploy.sh all

  # Step by step
  ./deploy.sh build
  ./deploy.sh deploy
  ./deploy.sh test
  ./deploy.sh verify

  # Custom S3 bucket
  S3_BUCKET=my-traces ./deploy.sh deploy

  # View logs
  ./deploy.sh logs

  # Clean up
  ./deploy.sh destroy

Prerequisites:
  - K3s installed with GPU support (run: ./infrastructure/k3s-install.sh)
  - Docker installed
  - Hugging Face token for Llama-2 access
  - AWS credentials configured (for S3 upload)

EOF
}

# Show status
show_status() {
    log_step "Deployment Status"

    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        echo "Status: Not deployed"
        echo ""
        echo "Run: ./deploy.sh deploy"
        return
    fi

    echo "Namespace: $NAMESPACE"
    echo ""

    echo "Pods:"
    kubectl get pods -n "$NAMESPACE" -o wide
    echo ""

    echo "Services:"
    kubectl get svc -n "$NAMESPACE"
    echo ""

    echo "PVCs:"
    kubectl get pvc -n "$NAMESPACE"
    echo ""

    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=vllm -o jsonpath='{.items[0].metadata.name}')
    if [ -n "$POD_NAME" ]; then
        echo "Pod Status:"
        kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{range .status.containerStatuses[*]}{"  "}{.name}{": "}{.state}{"\n"}{end}'
        echo ""
    fi

    NODE_PORT=$(kubectl get svc vllm-api -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
    if [ -n "$NODE_PORT" ]; then
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        echo "API Endpoint: http://${NODE_IP}:${NODE_PORT}"
        echo ""
    fi
}

# Main
main() {
    case "${1:-}" in
        build)
            build_image
            ;;
        deploy)
            deploy_k3s
            ;;
        test)
            run_tests
            ;;
        verify)
            verify_traces
            ;;
        logs)
            view_logs
            ;;
        all)
            build_image
            deploy_k3s
            echo ""
            log "Waiting 30 seconds for system to stabilize..."
            sleep 30
            run_tests
            verify_traces
            ;;
        destroy)
            destroy
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            echo -e "${RED}Unknown command: ${1:-}${NC}"
            echo ""
            usage
            exit 1
            ;;
    esac
}

# Print banner
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║       vLLM with eBPF CUDA Tracing Deployment Tool            ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

main "$@"
