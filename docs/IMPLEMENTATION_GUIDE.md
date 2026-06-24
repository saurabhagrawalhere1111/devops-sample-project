# NotesOps — Complete Step-by-Step Implementation Guide

From **zero** (no accounts, nothing installed) to a **fully running pipeline**.
Read `TOOLS_EXPLAINED.md` alongside this to understand *why* each step exists.

> **Cost warning up front.** This runs real AWS resources (EKS + RDS + NAT).
> Expect roughly **$5–10/day** with the cost-conscious defaults. **Run
> `terraform destroy` whenever you stop working** (Part 12). Set a billing alarm
> in Part 1.

> **Conventions.** Commands in `code blocks` are run in your terminal.
> "Console" means a web page in a browser. Replace anything in `<ANGLE_BRACKETS>`.

---

## PART 0 — Create your accounts

### 0.1 Create a GitHub account
1. Go to **https://github.com/signup** → create a free account.
2. Verify your email.
3. (Recommended) Enable 2FA: Settings → Password and authentication.

### 0.2 Create an AWS account
1. Go to **https://aws.amazon.com** → **Create an AWS Account**.
2. You'll need an email, a password, and a **credit/debit card** (AWS requires it even on free tier).
3. Choose the **Basic (free) support plan**.
4. This first identity is the **root user** — extremely powerful. You'll stop using it almost immediately (next step).

### 0.3 Lock down the root user + set a billing alarm (do this now)
1. Sign in to the **AWS Console** as root.
2. Top-right → your name → **Security credentials** → enable **MFA** on the root user.
3. Search **"Billing"** → **Billing preferences** → turn on **"Receive Billing Alerts."**
4. Search **"CloudWatch"** → region **US East (N. Virginia)** → **Alarms → Create alarm** → metric **Billing → Total Estimated Charge** → threshold e.g. **$20** → notify your email. This emails you if spend crosses $20.

---

## PART 1 — Create an admin IAM user (stop using root)

You should never do daily work as root. Create an admin user instead.

1. Console → search **IAM** → **Users → Create user**.
2. Name: `notesops-admin`. Check **"Provide user access to the AWS Management Console"** (optional).
3. Permissions → **Attach policies directly** → check **AdministratorAccess** → Create.
4. Open the user → **Security credentials** → **Create access key** → choose **Command Line Interface (CLI)** → copy the **Access key ID** and **Secret access key** (you'll only see the secret once).

> These keys are for the *bootstrap* only. Later, CI uses keyless OIDC and pods use IRSA — no static keys in the running system.

---

## PART 2 — Install the tools on your computer

You're on macOS (this repo's environment). Install **Homebrew** first if you don't have it:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then install everything:

```bash
brew install awscli terraform kubernetes-cli helm eksctl trivy cosign git
brew install --cask docker          # Docker Desktop — open it once so the daemon starts
brew install argocd k9s             # Argo CD CLI + a friendly cluster TUI (optional but great)
```

Verify:

```bash
aws --version && terraform version && kubectl version --client && helm version && docker --version
```

> If `docker` says "cannot connect to the daemon," **open the Docker Desktop app** and wait for the whale icon to settle.

---

## PART 3 — Connect your laptop to AWS

```bash
aws configure
# AWS Access Key ID:     <paste from Part 1>
# AWS Secret Access Key: <paste from Part 1>
# Default region name:   us-east-1
# Default output format:  json

aws sts get-caller-identity     # should print your account ID + the notesops-admin user
```

Write down your **12-digit account ID** — you'll paste it into a few config files (every `<ACCOUNT_ID>` placeholder).

---

## PART 4 — Put this project on GitHub

1. On GitHub: **New repository** → name it `devops-sample-project` → **Private** → Create. **Do not** add a README (you already have one).
2. In your terminal, from the project root:

```bash
cd /Users/saurabhagarwal/Desktop/devops-sample-project

# The app was a separate cloned repo — flatten it so it's all ONE repo:
rm -rf django-notes-app/.git

git add -A
git commit -m "NotesOps platform: initial commit"
git branch -M main
git remote add origin https://github.com/<YOUR_GITHUB_USERNAME>/devops-sample-project.git
git push -u origin main
```

3. Now find-and-replace the placeholders across the repo with your real values:
   - `<ACCOUNT_ID>` → your 12-digit AWS account ID (in `gitops/apps/notesapp/values.yaml`, `ai/agent/k8s/agent.yaml`).
   - `saurabhagrawalhere1111/devops-sample-project` → `<YOUR_GITHUB_USERNAME>/devops-sample-project` (in `gitops/argocd/*.yaml`, `infra/terraform/github-oidc.tf`, `platform/security/kyverno-policies.yaml`).

```bash
# macOS sed — edit USERNAME/ACCOUNT then run:
grep -rl 'saurabhagrawalhere1111/devops-sample-project' . --exclude-dir=.git \
  | xargs sed -i '' 's#saurabhagrawalhere1111/devops-sample-project#<YOUR_GITHUB_USERNAME>/devops-sample-project#g'
grep -rl '<ACCOUNT_ID>' . --exclude-dir=.git \
  | xargs sed -i '' 's/<ACCOUNT_ID>/<YOUR_12_DIGIT_ACCOUNT_ID>/g'
git commit -am "wire in account id + repo url" && git push
```

---

## PART 5 — Test the app locally (sanity check before the cloud)

```bash
cd django-notes-app
docker compose up --build
# wait for build, then open:  http://localhost:8080
# Ctrl-C to stop, then:
docker compose down
```

If you can create/see notes, the app + containers work. Move on.

---

## PART 6 — Phase 1: Build the AWS infrastructure (Terraform)

### 6.1 Create the remote-state backend (once)
```bash
cd infra/terraform/bootstrap
terraform init
terraform apply        # type "yes"
# Copy the two outputs it prints: state_bucket and lock_table
```

### 6.2 Wire the backend
Edit `infra/terraform/backend.tf` and uncomment/fill the block with those outputs:
```hcl
backend "s3" {
  bucket         = "notesops-tfstate-<YOUR_ACCOUNT_ID>"
  key            = "platform/terraform.tfstate"
  region         = "us-east-1"
  dynamodb_table = "notesops-tflock"
  encrypt        = true
}
```

### 6.3 Provision everything
```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars      # defaults are fine for a demo
terraform init                                     # connects to the S3 backend
terraform plan                                     # review what it will create
terraform apply                                    # type "yes" — takes ~15–20 min (EKS + RDS are slow)
```

This creates: VPC, EKS cluster + worker nodes, ECR repos, RDS Postgres, Secrets Manager secret, and all the IAM/IRSA roles.

### 6.4 Point kubectl at your new cluster
```bash
$(terraform output -raw configure_kubectl)
kubectl get nodes        # you should see your worker node(s) as "Ready"
```

Save these outputs — you'll need them in later parts:
```bash
terraform output github_ci_role_arn        # for GitHub Actions (Part 9)
terraform output alb_controller_role_arn
terraform output external_secrets_role_arn
terraform output ai_agent_role_arn
```

---

## PART 7 — Phase 5: Install the platform add-ons

These make the cluster able to expose apps and read secrets.

```bash
cd ../..        # back to project root
export CLUSTER=notesops-dev-eks
export REGION=us-east-1
export ALB_ROLE_ARN=$(cd infra/terraform && terraform output -raw alb_controller_role_arn)
export ESO_ROLE_ARN=$(cd infra/terraform && terraform output -raw external_secrets_role_arn)

bash platform/install.sh
```

This installs: metrics-server, AWS Load Balancer Controller (so Ingress works),
External Secrets Operator + the ClusterSecretStore (so pods get DB creds from
Secrets Manager), and cert-manager.

Verify:
```bash
kubectl get pods -n kube-system | grep load-balancer
kubectl get clustersecretstore        # should show aws-secrets-manager = Valid
```

---

## PART 8 — Phase 4: Install Argo CD (GitOps)

```bash
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm install argocd argo/argo-cd -n argocd

# Get the admin password and open the UI:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:443
# In a browser: https://localhost:8080   (user: admin, password: from above)
```

Now hand the whole platform to Argo CD:
```bash
kubectl apply -f gitops/argocd/root-app.yaml
```

Argo CD reads your repo and deploys the `notesapp` chart. In the UI you'll see
the `root` and `notesapp` Applications syncing. (If the app secret isn't synced
yet, that's expected until External Secrets pulls it — which Part 7 enabled.)

---

## PART 9 — Phase 3: Turn on CI (GitHub Actions)

CI needs to authenticate to AWS *without* storing keys. We use **OIDC** (the
`github-oidc.tf` already created the role in Part 6).

### 9.1 Add the role ARN as a GitHub secret
1. GitHub repo → **Settings → Secrets and variables → Actions → New repository secret**.
2. Name: `AWS_CI_ROLE_ARN` — Value: paste `terraform output github_ci_role_arn`.

### 9.2 Trigger the pipeline
```bash
git commit --allow-empty -m "trigger CI" && git push
```
Watch **GitHub repo → Actions**. The `CI` workflow runs: test → security scans →
build → SBOM → cosign sign → push to ECR → and the `promote` job bumps the image
tag in `gitops/apps/notesapp/values.yaml` and commits it. Argo CD then deploys
the new image automatically.

> If the `verify-image-signatures` Kyverno policy is in **Enforce** mode before
> the first signed image exists, pods will be blocked. It ships in **Audit**
> mode — flip it to Enforce only after you confirm CI signing works (Part 11).

---

## PART 10 — Phase 6 & 7: Observability + Alerting

```bash
bash platform/observability/install.sh
```
Installs Prometheus + Grafana + Alertmanager (kube-prometheus-stack), Loki + Promtail (logs), and Tempo (traces). It prints the Grafana password.

Open Grafana:
```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000   (user: admin, password: printed by the script)
```
You'll find prebuilt Kubernetes dashboards, plus your app's `/metrics` via the ServiceMonitor.

### Hook up Slack alerts (optional but recommended)
1. In Slack: **https://api.slack.com/messaging/webhooks** → create an Incoming Webhook for a channel → copy the URL.
2. Provide it to Alertmanager. The values file references `${SLACK_WEBHOOK_URL}` / `${PAGERDUTY_ROUTING_KEY}` — the simplest path is to put real values in a copy of `platform/observability/values-kube-prometheus-stack.yaml` and re-run the helm upgrade, **or** store them in a secret and reference it. For a demo, edit the file, replace the two `${...}` placeholders, and:
```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f platform/observability/values-kube-prometheus-stack.yaml
```

---

## PART 11 — Phase 8: Security stack

```bash
export SLACK_WEBHOOK_URL=<your-slack-webhook>     # optional, for Falco alerts
bash platform/security/install.sh
```
Installs Falco (runtime threat detection), Trivy Operator (continuous scanning), and Kyverno (admission policies).

Check it's working:
```bash
kubectl get clusterpolicy                 # the Kyverno policies
kubectl get vulnerabilityreports -A       # Trivy Operator findings (after a minute)
```

Once your CI has pushed at least one **signed** image and pods run fine, tighten
the supply-chain policy:
```bash
# edit platform/security/kyverno-policies.yaml:
#   change validationFailureAction: Audit  →  Enforce
#   on the verify-image-signatures policy, then:
kubectl apply -f platform/security/kyverno-policies.yaml
```
Now only cosign-signed images from your pipeline can run.

---

## PART 12 — Phase 9: AI automation (Amazon Bedrock)

### 12.1 Enable Claude in Bedrock (one-time, per region)
1. Console → search **Bedrock** → region **us-east-1**.
2. Left nav → **Model access** → **Manage model access** → enable the **Anthropic Claude** models → Save. (Approval is usually instant.)

### 12.2 Build & push the AI agent image
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Create the repo (or add 'ai-agent' to ecr.tf and re-apply Terraform):
aws ecr create-repository --repository-name notesops/ai-agent --region us-east-1 || true

docker build -t $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/notesops/ai-agent:latest ai/agent
docker push $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/notesops/ai-agent:latest
```

### 12.3 Deploy the agent
```bash
# Slack secret the agent posts to:
kubectl create namespace aiops 2>/dev/null
kubectl -n aiops create secret generic ai-agent-slack \
  --from-literal=webhook-url="$SLACK_WEBHOOK_URL"

kubectl apply -f ai/agent/k8s/agent.yaml
kubectl -n aiops get pods        # ai-agent should be Running
```
Now when a `critical` alert fires, Alertmanager POSTs it to the agent, which asks
Claude for a root-cause summary and posts it to Slack.

### 12.4 AI PR review
Already wired (`.github/workflows/ai-pr-review.yml`). It reuses `AWS_CI_ROLE_ARN`
— just make sure that role has `bedrock:InvokeModel` (the `ai-agent` policy grants
it; attach the same policy to the CI role, or add the action to `github-oidc.tf`).
Open a pull request and Claude comments on the diff.

### 12.5 k8sgpt (plain-English diagnostics)
```bash
helm repo add k8sgpt https://charts.k8sgpt.ai/ && helm repo update
helm install k8sgpt k8sgpt/k8sgpt-operator -n k8sgpt --create-namespace
# then create a K8sGPT CR with the amazonbedrock backend (see ai/README.md)
```

---

## PART 13 — Get a real URL (optional)

To reach the app on a domain with HTTPS:
1. Buy/route a domain in **Route 53** (or use one you own).
2. Request a cert in **ACM** (us-east-1) for `notes.<yourdomain>`.
3. Put the cert ARN + host into `gitops/apps/notesapp/values.yaml` (`ingress.certificateArn`, `ingress.host`), commit — Argo CD redeploys the Ingress, and the ALB controller provisions a load balancer.
4. Find the ALB address: `kubectl -n notesapp get ingress` → create a Route 53 record pointing your host at it.

For a quick demo without DNS, just port-forward:
```bash
kubectl -n notesapp port-forward svc/notes-frontend 8088:80   # http://localhost:8088
```

---

## PART 14 — The everyday loop (how you actually use it)

```
1. Edit code in django-notes-app/
2. git push (or open a PR — AI reviews it)
3. GitHub Actions: tests + scans + build + sign + push + bump gitops tag
4. Argo CD syncs the new image to EKS automatically
5. Grafana shows metrics/logs/traces; Alertmanager + the AI agent watch for trouble
```
You never run `kubectl apply` by hand for the app — git is the control panel.

---

## PART 15 — TEARDOWN (do this to stop the bill!)

```bash
# 1. Remove cluster add-ons that created AWS load balancers (so nothing is orphaned)
kubectl delete -f gitops/argocd/root-app.yaml
kubectl -n notesapp delete ingress --all

# 2. Destroy all infrastructure
cd infra/terraform
terraform destroy        # type "yes"

# 3. (Optional) the state bucket has prevent_destroy — delete manually only if you're fully done:
#    aws s3 rb s3://notesops-tfstate-<ACCOUNT_ID> --force
```
Confirm in the AWS Console (EKS, RDS, EC2, Load Balancers) that nothing is left running.

---

## Quick troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `docker` can't connect | Open Docker Desktop; wait for it to start. |
| `terraform apply` fails on permissions | Your CLI user isn't admin, or wrong region — re-check Part 1/3. |
| EKS nodes not `Ready` | Wait a few minutes; `kubectl get nodes -w`. SPOT capacity can take time. |
| Pods stuck `CreateContainerError` (secret) | External Secrets not installed/working — see Part 7; `kubectl describe externalsecret -n notesapp`. |
| Pods blocked by Kyverno | `verify-image-signatures` is Enforce but image isn't signed yet — keep it Audit until CI signing works (Part 11). |
| CI can't push to ECR | `AWS_CI_ROLE_ARN` secret missing/wrong (Part 9), or repo URL mismatch in `github-oidc.tf`. |
| Argo CD won't sync | Repo URL in `gitops/argocd/*.yaml` doesn't match your fork; or repo is private — add credentials in Argo CD settings. |
| Bedrock `AccessDenied` | Enable model access (Part 12.1) and confirm the pod's IRSA role has `bedrock:InvokeModel`. |

---

## Build-order cheat sheet

```
Part 0–3   Accounts + tools + AWS login
Part 4–5   Repo on GitHub + local app test
Part 6     Terraform  → VPC/EKS/ECR/RDS/Secrets        (foundation)
Part 7     platform/install.sh → ALB, ExternalSecrets, cert-manager
Part 8     Argo CD + root-app                          (GitOps engine)
Part 9     GitHub Actions secret + first CI run        (pipeline)
Part 10    observability/install.sh                    (Prometheus/Grafana/Loki/Tempo)
Part 11    security/install.sh                         (Falco/Trivy/Kyverno)
Part 12    AI agent + Bedrock                          (AI automation)
Part 13    Domain/HTTPS (optional)
Part 15    terraform destroy                           (STOP THE BILL)
```
