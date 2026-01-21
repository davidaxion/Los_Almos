#!/bin/bash
set -e

echo "========================================="
echo "Setting up SSH Keys for GPU Pod"
echo "========================================="

# Check if SSH key exists
if [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo "No SSH key found at ~/.ssh/id_rsa.pub"
    read -p "Would you like to generate a new SSH key? (yes/no): " generate
    if [ "$generate" == "yes" ]; then
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        echo "SSH key generated successfully!"
    else
        echo "Please generate an SSH key first: ssh-keygen -t rsa -b 4096"
        exit 1
    fi
fi

# Read the public key
PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub)

echo "Your SSH public key:"
echo "$PUBLIC_KEY"
echo ""

# Create or update the Kubernetes secret
echo "Creating Kubernetes secret with your SSH public key..."

# Check if secret exists
if kubectl get secret gpu-dev-ssh-keys >/dev/null 2>&1; then
    echo "Secret already exists. Deleting and recreating..."
    kubectl delete secret gpu-dev-ssh-keys
fi

# Create the secret
kubectl create secret generic gpu-dev-ssh-keys \
    --from-literal=authorized_keys="$PUBLIC_KEY"

echo "========================================="
echo "SSH keys setup complete!"
echo "========================================="
echo "Your public key has been added to the gpu-dev-ssh-keys secret."
echo "When you deploy the pod, you'll be able to SSH using your private key."
echo "========================================="
