#!/usr/bin/env bash
# Phase 8 — runtime + supply-chain security.
set -euo pipefail

helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# --- Falco: runtime threat detection (syscall-level) ---
helm upgrade --install falco falcosecurity/falco \
  -n falco --create-namespace \
  --set tty=true \
  --set falcosidekick.enabled=true \
  --set falcosidekick.config.slack.webhookurl="${SLACK_WEBHOOK_URL:-}"

# --- Trivy Operator: continuous in-cluster vuln + config scanning ---
helm upgrade --install trivy-operator aqua/trivy-operator \
  -n trivy-system --create-namespace \
  --set="trivy.severity=HIGH,CRITICAL"

# --- Kyverno: admission policies ---
helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace
kubectl apply -f platform/security/kyverno-policies.yaml

echo "Security stack installed. Check findings:"
echo "  kubectl get vulnerabilityreports -A"
echo "  kubectl get clusterpolicy"
