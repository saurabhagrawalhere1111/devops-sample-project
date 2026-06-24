# NotesOps — Production-Grade GitOps Platform on AWS

A complete, modern DevOps pipeline built around a Django + React notes app:
GitHub Actions CI → security gates → ECR → Argo CD GitOps → EKS → full
observability → alerting → AI-driven incident triage. Cost-conscious demo sizing.

## Architecture

```
Developer → GitHub → GitHub Actions (test, Trivy/CodeQL/gitleaks, SBOM, cosign sign)
                          │ push signed images
                          ▼
                   Amazon ECR ──► (CI bumps image tag in gitops/)
                          │
                     Argo CD (pull-based sync)
                          ▼
        Amazon EKS ───────────────────────────────────────────────┐
          ├─ notes-backend (Django/gunicorn) + notes-frontend (nginx)
          ├─ ALB Ingress · cert-manager · HPA/Karpenter
          ├─ External Secrets ← AWS Secrets Manager  (DB + Django secrets)
          ├─ Prometheus + Grafana + Loki + Tempo (LGTM)
          ├─ Alertmanager → Slack / PagerDuty / AI agent
          ├─ Falco · Trivy Operator · Kyverno (signed-image admission)
          └─ AI triage agent → Amazon Bedrock (Claude)
                          │
                   Amazon RDS (Postgres)
```

## 📚 Start here
- **[docs/IMPLEMENTATION_GUIDE.md](docs/IMPLEMENTATION_GUIDE.md)** — zero-to-running: create the AWS + GitHub accounts, install tools, and every command in order.
- **[docs/TOOLS_EXPLAINED.md](docs/TOOLS_EXPLAINED.md)** — what every tool does and why it's in the stack.
- **[docs/operations.md](docs/operations.md)** — backups, runbooks, teardown.

## Repository layout
| Path | Phase | What |
|---|---|---|
| `django-notes-app/` | 0, 2 | The app: env-driven settings, probes, multi-stage Dockerfiles |
| `infra/terraform/` | 1 | VPC, EKS, ECR, RDS, Secrets Manager, IRSA, GitHub OIDC |
| `.github/workflows/` | 3, 9 | CI (test/scan/sign/push) + AI PR review |
| `gitops/` | 4 | Argo CD app-of-apps + the app's Helm chart |
| `platform/` | 5–8 | ALB controller, External Secrets, cert-manager, LGTM, Falco/Trivy/Kyverno |
| `ai/` | 9 | Bedrock incident-triage agent + k8sgpt |

## Build order (each dir has its own README)
1. **Phase 1** — `infra/terraform/` → `terraform apply`, then `update-kubeconfig`.
2. **Phase 5** — `platform/install.sh` (ALB controller, External Secrets, cert-manager).
3. **Phase 4** — `gitops/` → install Argo CD, apply `root-app.yaml`.
4. **Phase 6/7** — `platform/observability/install.sh`.
5. **Phase 8** — `platform/security/install.sh`.
6. **Phase 9** — build/push `ai/agent`, `kubectl apply -f ai/agent/k8s/`.
7. **Phase 3** — push to `main`; CI builds, signs, and promotes; Argo CD deploys.

> Replace `<ACCOUNT_ID>` placeholders with your AWS account ID, and the GitHub
> repo URLs in `gitops/` with your fork.

## Tools covered
GitHub Actions · Docker · Kubernetes (EKS) · Helm · Argo CD (GitOps) ·
Terraform · Prometheus · Grafana · Loki · Tempo · OpenTelemetry · Alertmanager ·
Trivy · Syft (SBOM) · cosign · CodeQL · gitleaks · Checkov · Falco · Kyverno ·
External Secrets · AWS Load Balancer Controller · cert-manager · Karpenter ·
Amazon Bedrock (Claude) · k8sgpt.

## Cost & teardown
SPOT nodes + single NAT + `db.t3.micro` keep this small. **`terraform destroy`
when idle.** See `docs/operations.md` for backups (Velero) and runbooks.

## Local dev
```bash
cd django-notes-app && docker compose up --build   # http://localhost:8080
```
