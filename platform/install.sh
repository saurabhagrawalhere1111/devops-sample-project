#!/usr/bin/env bash
# Phase 5 — install core platform add-ons. Run after Terraform apply + kubeconfig.
# Replace ACCOUNT_ID / CLUSTER / REGION or export them first.
set -euo pipefail

REGION="${REGION:-us-east-1}"
CLUSTER="${CLUSTER:-notesops-dev-eks}"
ACCOUNT_ID="${ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

# IRSA role ARNs (from: terraform output)
ALB_ROLE_ARN="${ALB_ROLE_ARN:?set to terraform output alb_controller_role_arn}"
ESO_ROLE_ARN="${ESO_ROLE_ARN:?set to terraform output external_secrets_role_arn}"

helm repo add eks https://aws.github.io/eks-charts
helm repo add external-secrets https://charts.external-secrets.io
helm repo add jetstack https://charts.jetstack.io
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

# --- metrics-server (needed by HPA) ---
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system

# --- AWS Load Balancer Controller (ALB ingress) ---
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$ALB_ROLE_ARN"

# --- External Secrets Operator ---
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  --set installCRDs=true \
  --set serviceAccount.name=external-secrets \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$ESO_ROLE_ARN"

# --- cert-manager (TLS) ---
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --set crds.enabled=true

# --- ClusterSecretStore pointing at AWS Secrets Manager ---
kubectl apply -f platform/cluster-secret-store.yaml

echo "Platform add-ons installed."
