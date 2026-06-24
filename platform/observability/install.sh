#!/usr/bin/env bash
# Phase 6 + 7 — self-hosted LGTM observability stack + alerting.
set -euo pipefail

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

NS=monitoring

# --- Metrics + Grafana + Alertmanager (kube-prometheus-stack) ---
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n "$NS" --create-namespace \
  -f platform/observability/values-kube-prometheus-stack.yaml

# --- Logs (Loki + Promtail) ---
helm upgrade --install loki grafana/loki-stack \
  -n "$NS" \
  --set promtail.enabled=true \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=10Gi

# --- Traces (Tempo) ---
helm upgrade --install tempo grafana/tempo -n "$NS"

echo "Observability stack installed. Grafana admin password:"
kubectl -n "$NS" get secret kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d; echo
echo "Port-forward Grafana:  kubectl -n $NS port-forward svc/kube-prometheus-stack-grafana 3000:80"
