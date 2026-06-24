# Phase 10 — Operations, DR & Runbooks

## Backups & disaster recovery (Velero)
```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero -n velero --create-namespace \
  --set configuration.backupStorageLocation[0].provider=aws \
  --set configuration.backupStorageLocation[0].bucket=<velero-bucket> \
  --set configuration.backupStorageLocation[0].config.region=us-east-1 \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.10.0 \
  --set initContainers[0].volumeMounts[0].mountPath=/target \
  --set initContainers[0].volumeMounts[0].name=plugins

velero schedule create daily --schedule="0 2 * * *"   # nightly cluster backup
```
- **RDS**: automated backups are on (7-day retention, see `rds.tf`).
- **Terraform state**: versioned S3 bucket (see `bootstrap/`).

## Runbooks
| Alert | First steps |
|---|---|
| `NotesBackendHighErrorRate` | `kubectl -n notesapp logs deploy/notes-backend --tail=100`; check RDS reachability via `/readyz`; check recent Argo CD sync. |
| `PodCrashLooping` | `kubectl -n notesapp describe pod <pod>`; check image tag, secret sync (`kubectl get externalsecret -n notesapp`). |
| `NotesBackendHighLatencyP99` | Grafana → app dashboard; check HPA (`kubectl get hpa -n notesapp`) and RDS Performance Insights. |
| Rollback | Argo CD UI → History → roll back, or revert the image-tag commit in `gitops/`. |

## Cost controls
- SPOT nodes, single NAT, `db.t3.micro`, ECR lifecycle expiry (14d untagged).
- Tag everything via Terraform `default_tags` for cost allocation.
- **`terraform destroy` when not in use.**

## Security posture checklist
- [ ] Kyverno `verify-image-signatures` flipped from Audit → Enforce once CI signing is verified
- [ ] `disallow-privileged` is Enforce
- [ ] IRSA roles are least-privilege (no node-wide IAM)
- [ ] Secrets only in Secrets Manager, never in git (gitleaks gate in CI)
- [ ] EKS endpoint set to private + VPN for production
