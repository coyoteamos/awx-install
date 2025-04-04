#!/bin/bash
set -e

echo "=== Starting Unattended AWX Installation ==="

# Install MicroK8s if it's not installed
if ! command -v microk8s >/dev/null 2>&1; then
  echo "Installing MicroK8s..."
  sudo snap install microk8s --classic --channel=1.29/stable
fi

# Wait until MicroK8s is ready
sudo microk8s status --wait-ready

# Add current user to the microk8s group if not already a member
if ! groups "amos" | grep -qw microk8s; then
  echo "Adding amos to microk8s group..."
  sudo usermod -aG microk8s "amos"
  echo "Re-executing script under new group membership..."
  exec sg microk8s "bash $0"
fi

# Ensure ownership of the kube config directory
sudo chown -f -R "amos" ~/.kube

# Enable required MicroK8s add-ons
echo "Enabling MicroK8s add-ons: dns, storage, ingress, and helm3..."
sudo microk8s enable dns storage ingress helm3

# Wait until the add-ons are ready
sudo microk8s status --wait-ready

# Set up command aliases for convenience
sudo snap alias microk8s.kubectl kubectl
sudo snap alias microk8s.helm3 helm

sleep 10

# Add the AWX Operator Helm repository and update
echo "Adding AWX Operator Helm repository..."
helm repo add awx-operator https://ansible-community.github.io/awx-operator-helm/
helm repo update

# Create (or ensure) the awx namespace exists and set the current context
kubectl create namespace awx 2>/dev/null || echo "Namespace 'awx' already exists."
kubectl config set-context --current --namespace=awx

# Download the AWX demo custom resource manifest
echo "Downloading AWX demo manifest..."
wget -O awx-demo.yaml https://raw.githubusercontent.com/coyoteamos/awx-install/refs/heads/main/awx-demo.yaml

# Install the AWX Operator via Helm (with the AWX demo manifest)
echo "Installing AWX Operator..."
helm install my-awx-operator awx-operator/awx-operator -n awx --create-namespace -f awx-demo.yaml

# Wait for the AWX Operator deployment to become available
echo "Waiting for AWX Operator deployment to be available..."
kubectl wait --for=condition=Available deployment/my-awx-operator-awx-operator -n awx --timeout=300s

# Apply the AWX demo custom resource to trigger AWX installation
echo "Deploying AWX instance..."
kubectl apply -f awx-demo.yaml -n awx

# Download and apply the Ingress manifest for AWX
echo "Downloading AWX Ingress manifest..."
wget -O awx-demo-ingress.yaml https://raw.githubusercontent.com/coyoteamos/awx-install/refs/heads/main/awx-demo-ingress.yaml
kubectl apply -f awx-demo-ingress.yaml -n awx

# Generate a self-signed TLS certificate and create a Kubernetes TLS secret
echo "Creating TLS certificate and secret..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=itp.local/O=ITP"
kubectl create secret tls awx-demo-tls \
  --key tls.key --cert tls.crt \
  -n awx

echo "AWX installation initiated. Check pod statuses with 'kubectl get pods -n awx'."
