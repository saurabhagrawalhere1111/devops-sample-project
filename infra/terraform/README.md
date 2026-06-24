# Phase 1 — Terraform Foundation

Provisions the entire AWS base layer for NotesOps: remote state, VPC, EKS,
ECR, RDS Postgres, and Secrets Manager.

## Prerequisites
- `aws-cli` configured (`aws configure`) with admin for bootstrap.
- `terraform >= 1.6`, `kubectl`, `helm`, `eksctl` installed.

## Step 1 — Bootstrap the remote state backend (run once)
```bash
cd infra/terraform/bootstrap
terraform init
terraform apply
# Note the outputs: state_bucket and lock_table
```

## Step 2 — Wire the backend
Edit `../backend.tf` and uncomment/fill the `bucket`, `region`, and
`dynamodb_table` values with the bootstrap outputs.

## Step 3 — Provision the platform
```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # edit if needed
terraform init                                  # connects to S3 backend
terraform plan
terraform apply                                 # ~15-20 min (EKS + RDS)
```

## Step 4 — Connect kubectl
```bash
$(terraform output -raw configure_kubectl)
kubectl get nodes      # should list your worker nodes
```

## What you get
| Resource | Purpose |
|---|---|
| VPC (3 AZ, 1 NAT) | Networking |
| EKS 1.30 + node group (SPOT) | Kubernetes |
| ECR `notesops/notes-backend`, `notes-frontend` | Image registry (immutable, scan-on-push) |
| RDS Postgres 15 (`db.t3.micro`) | App database |
| Secrets Manager `notesops-dev/app` | DB + Django secrets (synced to K8s in Phase 5) |

## Tear down (stop the AWS bill)
```bash
terraform destroy
# bootstrap bucket has prevent_destroy; remove it manually if you truly want it gone
```

## Cost note
SPOT nodes + single NAT + db.t3.micro keeps this in the low-single-digit
dollars/day range. **Run `terraform destroy` when you're not actively using it.**
