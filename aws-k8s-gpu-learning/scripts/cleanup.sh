#!/bin/bash
set -e

CLUSTER_NAME="${CLUSTER_NAME:-gpu-learning-cluster}"
REGION="${AWS_REGION:-us-west-2}"

echo "========================================="
echo "Cleaning up EKS Cluster"
echo "========================================="
echo "Cluster Name: $CLUSTER_NAME"
echo "Region: $REGION"
echo "========================================="

read -p "Are you sure you want to delete the cluster? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

# Delete the pod first
echo "Deleting GPU pod..."
kubectl delete -f ../k8s-manifests/gpu-pod.yaml --ignore-not-found=true || true

# Delete the cluster
echo "Deleting EKS cluster (this will take 10-15 minutes)..."
eksctl delete cluster --name "$CLUSTER_NAME" --region "$REGION" --wait

echo "========================================="
echo "Cleanup complete!"
echo "========================================="
