#!/bin/bash

set -e
sudo snap install microk8s --classic --channel=1.29/stable
sudo microk8s status --wait-ready
sudo usermod -aG microk8s $USER
sudo chown -f -R $USER ~/.kube
sudo microk8s enable dns storage ingress helm3
sudo microk8s status --wait-ready
sudo snap alias microk8s.kubectl kubectl
sudo snap alias microk8s.helm3 helm
helm repo add awx-operator https://ansible-community.github.io/awx-operator-helm/
helm repo update
sudo usermod -aG microk8s $USER
sudo chown -f -R $USER ~/.kube
newgrp microk8s
kubectl create namespace awx
kubectl config set-context --current --namespace=awx
wget https://raw.githubusercontent.com/coyoteamos/awx-install/refs/heads/main/awx-demo.yaml
helm install my-awx-operator awx-operator/awx-operator -n awx --create-namespace -f awx-demo.yaml
kubectl apply -f awx-demo.yaml -n awx

wget https://raw.githubusercontent.com/coyoteamos/awx-install/refs/heads/main/awx-demo-ingress.yaml
kubectl apply -f awx-demo-ingress.yaml -n awx

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=itp.local/O=ITP"
kubectl create secret tls awx-demo-tls \
  --key tls.key --cert tls.crt \
  -n awx