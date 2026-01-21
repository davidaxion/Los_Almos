#!/bin/bash

echo "========================================="
echo "GPU Kubernetes Environment Status"
echo "========================================="

# Check cluster connection
echo -e "\n[1] Cluster Connection:"
if kubectl cluster-info >/dev/null 2>&1; then
    echo "✓ Connected to cluster"
    kubectl cluster-info | head -n 1
else
    echo "✗ Not connected to cluster"
    echo "Run: aws eks update-kubeconfig --region <region> --name <cluster-name>"
    exit 1
fi

# Check nodes with GPU
echo -e "\n[2] GPU Nodes:"
kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,GPU:.status.allocatable."nvidia\.com/gpu"

# Check NVIDIA device plugin
echo -e "\n[3] NVIDIA Device Plugin:"
if kubectl get daemonset -n kube-system nvidia-device-plugin-daemonset >/dev/null 2>&1; then
    echo "✓ NVIDIA device plugin is installed"
    kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds --no-headers | awk '{print "  Pod: "$1" | Status: "$3}'
else
    echo "✗ NVIDIA device plugin not found"
    echo "Install with: kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml"
fi

# Check GPU pods
echo -e "\n[4] GPU Development Pods:"
if kubectl get pod gpu-dev-pod-enhanced >/dev/null 2>&1; then
    POD_STATUS=$(kubectl get pod gpu-dev-pod-enhanced -o jsonpath='{.status.phase}')
    echo "✓ Pod 'gpu-dev-pod-enhanced' exists (Status: $POD_STATUS)"

    if [ "$POD_STATUS" == "Running" ]; then
        echo "  Testing GPU access in pod..."
        kubectl exec gpu-dev-pod-enhanced -- nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || echo "  (GPU test pending - pod may still be initializing)"
    fi
else
    echo "✗ GPU pod not deployed"
    echo "Deploy with: kubectl apply -f k8s-manifests/gpu-pod-enhanced.yaml"
fi

# Check SSH service
echo -e "\n[5] SSH Service:"
if kubectl get svc gpu-dev-ssh-enhanced >/dev/null 2>&1; then
    echo "✓ SSH service exists"
    LB_HOSTNAME=$(kubectl get svc gpu-dev-ssh-enhanced -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    LB_IP=$(kubectl get svc gpu-dev-ssh-enhanced -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [ -n "$LB_HOSTNAME" ]; then
        echo "  LoadBalancer: $LB_HOSTNAME"
    elif [ -n "$LB_IP" ]; then
        echo "  LoadBalancer: $LB_IP"
    else
        echo "  LoadBalancer: Pending..."
    fi
else
    echo "✗ SSH service not found"
fi

# Check SSH keys secret
echo -e "\n[6] SSH Keys:"
if kubectl get secret gpu-dev-ssh-keys >/dev/null 2>&1; then
    echo "✓ SSH keys secret exists"
else
    echo "✗ SSH keys not configured"
    echo "Setup with: ./scripts/setup-ssh-keys.sh"
fi

echo -e "\n========================================="
echo "Status Check Complete"
echo "========================================="
