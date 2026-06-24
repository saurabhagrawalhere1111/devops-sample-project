# Phase 9 — AI Automation & Adoption

Three AI capabilities, all backed by Claude on **Amazon Bedrock** (keyless via
IRSA / GitHub OIDC):

## 1. Incident triage agent (`ai/agent/`)
A FastAPI service that receives Alertmanager webhooks (`/alert`), asks Claude
for a root-cause hypothesis + safe remediation, and posts the result to Slack.

- Alertmanager routes `critical` alerts to `http://ai-agent.aiops.svc:8080/alert`
  (configured in `platform/observability/values-kube-prometheus-stack.yaml`).
- Deploy: build/push the image, then `kubectl apply -f ai/agent/k8s/agent.yaml`
  (replace `<ACCOUNT_ID>`; create the Slack secret below).

```bash
kubectl -n aiops create secret generic ai-agent-slack \
  --from-literal=webhook-url="$SLACK_WEBHOOK_URL"
```

## 2. AI PR review (`.github/workflows/ai-pr-review.yml`)
On every PR, Claude reviews the diff via Bedrock and posts a comment. Uses the
same `AWS_CI_ROLE_ARN` OIDC role as CI (add `bedrock:InvokeModel` to it, or reuse
the AI-agent policy).

## 3. k8sgpt — plain-English cluster diagnostics
```bash
helm repo add k8sgpt https://charts.k8sgpt.ai/
helm install k8sgpt k8sgpt/k8sgpt-operator -n k8sgpt --create-namespace
```
Then create a `K8sGPT` CR pointing at Bedrock (`amazonbedrock` backend) to get
`kubectl get results -A` explanations of failing pods/events.

## Model notes
- Bedrock model IDs are provider-prefixed: `anthropic.claude-opus-4-8`, or the
  cross-region inference-profile form `us.anthropic.claude-opus-4-8` (the default
  here). Swap to `anthropic.claude-sonnet-4-6` for lower cost/latency.
- Invocation uses the Messages API body (`anthropic_version: bedrock-2023-05-31`)
  via `boto3` `bedrock-runtime.invoke_model`.
- Enable model access in the Bedrock console (one-time) before first use.
