#!/bin/bash
set -e

POD_NAME="${POD_NAME:-gpu-dev-pod-enhanced}"
SSH_KEY="${SSH_KEY:-~/.ssh/id_rsa}"

echo "========================================="
echo "Connecting to GPU Pod via SSH"
echo "========================================="

# Check if pod exists and is running
echo "Checking pod status..."
if ! kubectl get pod "$POD_NAME" >/dev/null 2>&1; then
    echo "Error: Pod '$POD_NAME' not found."
    echo "Available pods:"
    kubectl get pods
    exit 1
fi

POD_STATUS=$(kubectl get pod "$POD_NAME" -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" != "Running" ]; then
    echo "Error: Pod is not running (status: $POD_STATUS)"
    echo "Waiting for pod to be ready..."
    kubectl wait --for=condition=ready pod/"$POD_NAME" --timeout=300s || {
        echo "Pod failed to become ready. Checking logs..."
        kubectl logs "$POD_NAME"
        exit 1
    }
fi

# Get the LoadBalancer hostname or IP
echo "Getting LoadBalancer address..."
SERVICE_NAME="gpu-dev-ssh-enhanced"

# Wait for LoadBalancer to be ready
echo "Waiting for LoadBalancer to be ready (this may take a few minutes)..."
timeout=180
elapsed=0
while [ $elapsed -lt $timeout ]; do
    LB_HOSTNAME=$(kubectl get svc "$SERVICE_NAME" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    LB_IP=$(kubectl get svc "$SERVICE_NAME" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [ -n "$LB_HOSTNAME" ] || [ -n "$LB_IP" ]; then
        break
    fi

    echo "Waiting for LoadBalancer... ($elapsed seconds)"
    sleep 5
    elapsed=$((elapsed + 5))
done

if [ -z "$LB_HOSTNAME" ] && [ -z "$LB_IP" ]; then
    echo "Error: LoadBalancer not ready after $timeout seconds"
    echo "Service details:"
    kubectl describe svc "$SERVICE_NAME"
    exit 1
fi

# Determine the address to use
if [ -n "$LB_HOSTNAME" ]; then
    LB_ADDRESS="$LB_HOSTNAME"
else
    LB_ADDRESS="$LB_IP"
fi

echo "LoadBalancer address: $LB_ADDRESS"
echo ""
echo "Connecting to SSH..."
echo "========================================="

# SSH into the pod
ssh -i "$SSH_KEY" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@"$LB_ADDRESS"
