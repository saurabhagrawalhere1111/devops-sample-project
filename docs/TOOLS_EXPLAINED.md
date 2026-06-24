# NotesOps — What Every Tool Does (and Why It's Here)

This is the "concepts" companion to `IMPLEMENTATION_GUIDE.md`. Read this to
understand *why* each piece exists; read the guide to actually build it.

The whole system answers one question: **how does a code change get safely from
a developer's laptop to running, observed, and secured in production — with as
little manual work as possible?**

---

## The big picture (the flow of one code change)

```
You write code
   └─► git push to GitHub
          └─► GitHub Actions runs CI:
                 test → scan for vulns/secrets → build image → SBOM → sign → push to ECR
                    └─► CI edits the image tag in the gitops/ folder and commits it
                           └─► Argo CD notices the git change and syncs it to Kubernetes (EKS)
                                  └─► The new pods start, pull secrets, register with the load balancer
                                         └─► Prometheus scrapes metrics, Loki collects logs, Tempo traces
                                                └─► If something breaks, Alertmanager fires →
                                                       Slack + PagerDuty + an AI agent that explains it
```

Everything below is one link in that chain.

---

## 1. The application (what we're shipping)

**Django (Python) + React (JavaScript) notes app.**
- **Django REST** = the backend API (create/read/update/delete notes).
- **React** = the frontend single-page app the user sees.
- **gunicorn** = the production web server that runs Django (the dev server isn't safe for production).
- **nginx** = serves the built React files and forwards `/api` calls to the backend.
- **WhiteNoise** = lets Django serve its own static files (admin CSS, etc.) without a separate server.

We made it **"12-factor"**: every environment-specific value (database password, secret key, debug on/off) comes from environment variables, so the *same* container image runs on your laptop, in CI, and in production — only the env vars differ.

---

## 2. Docker — packaging

**What it does:** bundles the app + its dependencies into a single immutable **image** that runs identically everywhere. A running image is a **container**.

**Why multi-stage builds:** we use one stage with the full build toolchain (compilers, npm) to *build*, then copy only the result into a tiny final image. Smaller image = faster pulls, fewer vulnerabilities, less attack surface.

**Why non-root:** if an attacker breaks into the container, running as a non-root user limits what they can do.

**docker-compose** = runs several containers together locally (app + database + frontend) so you can test the whole thing on your laptop before touching the cloud.

---

## 3. Terraform — Infrastructure as Code (IaC)

**What it does:** describes your *entire* AWS infrastructure (network, cluster, database) in text files. You run `terraform apply` and it creates everything; `terraform destroy` deletes everything.

**Why it matters:**
- **Reproducible** — rebuild the whole platform from scratch identically.
- **Reviewable** — infra changes go through pull requests like code.
- **No "click-ops"** — you never have to remember which 40 buttons you clicked in the AWS console.

**Remote state** = Terraform records what it created in a file called "state." We store that file in an S3 bucket (with a DynamoDB lock so two people can't apply at once and corrupt it).

---

## 4. AWS services — the cloud foundation

| Service | Plain-English job |
|---|---|
| **IAM** | Identity & permissions. *Who* can do *what*. The root of all AWS security. |
| **VPC** | Your private network in the cloud — subnets, routing, firewalls. |
| **EKS** | Managed **Kubernetes**. AWS runs the cluster control plane; you run apps on it. |
| **EC2 nodes** | The virtual machines (worker nodes) that actually run your containers. |
| **ECR** | Private **Docker image registry** — where your built images live. |
| **RDS** | Managed **PostgreSQL** database. AWS handles backups, patching, failover. |
| **Secrets Manager** | Encrypted store for passwords/keys. Apps fetch them at runtime; they're never in git. |
| **ACM + Route 53** | TLS certificates (HTTPS) + DNS (domain names). |
| **CloudWatch** | AWS-native logs/metrics (a backstop alongside our self-hosted observability). |
| **Bedrock** | Runs AI models (Claude) inside AWS, accessed with IAM — no external API key. |
| **S3 + DynamoDB** | Object storage + a key-value table — here, used for Terraform state + locking. |

---

## 5. Kubernetes (EKS) — the runtime

**What it does:** runs your containers, keeps the right number alive, restarts crashed ones, replaces dead nodes, and routes traffic to them. You declare *desired state* ("run 2 copies of the backend") and Kubernetes makes reality match.

**Key objects:**
- **Pod** = one running instance of your container(s).
- **Deployment** = "keep N pods running, and roll out new versions safely."
- **Service** = a stable internal address for a set of pods (pods come and go; the Service stays).
- **Ingress** = rules for routing outside traffic to Services (which URL → which app).
- **Namespace** = a folder to group/isolate resources (`notesapp`, `monitoring`, etc.).
- **Secret / ConfigMap** = config data injected into pods.
- **HPA (Horizontal Pod Autoscaler)** = adds/removes pods based on CPU/load.

---

## 6. Helm — Kubernetes package manager

**What it does:** templates your Kubernetes YAML so you don't copy-paste. One chart + a `values.yaml` produces all the manifests, and you can install complex third-party software (Prometheus, Argo CD, Falco) with one command. Think "apt/npm for Kubernetes."

---

## 7. GitHub + GitHub Actions — source control & CI

**GitHub** = where the code lives (git hosting) + pull requests, reviews, issues.

**GitHub Actions** = GitHub's built-in **CI/CD** (Continuous Integration). A workflow (`.github/workflows/*.yml`) runs automatically on events (push, PR). Our CI pipeline, in order:

1. **Test** — run Django + React tests so broken code never ships.
2. **Scan** — security gates (below).
3. **Build** — produce the Docker images.
4. **SBOM** — generate a Software Bill of Materials (a list of everything in the image).
5. **Sign** — cryptographically sign the image (proves it came from *our* pipeline).
6. **Push** — upload to ECR.
7. **Promote** — edit the image tag in `gitops/` and commit, which triggers deployment.

**OIDC (keyless auth)** = instead of storing long-lived AWS keys in GitHub (dangerous), GitHub proves its identity to AWS with a short-lived token. No secrets to leak.

---

## 8. Security tooling (DevSecOps)

Security is checked at **build time** (CI) and **run time** (in the cluster).

**In CI (catch problems before they ship):**
- **Trivy** — scans images & code for known vulnerabilities (CVEs).
- **gitleaks** — catches passwords/keys accidentally committed to git.
- **CodeQL** — SAST (Static Application Security Testing): finds bug/security patterns in source code.
- **Checkov** — scans Terraform for misconfigurations (e.g. an open security group).
- **Syft** — builds the SBOM.
- **cosign** — signs images and verifies signatures (supply-chain integrity).

**In the cluster (catch problems while running):**
- **Falco** — watches kernel syscalls for suspicious runtime behavior (e.g. a shell spawning in a container).
- **Trivy Operator** — continuously re-scans running images for newly-discovered CVEs.
- **Kyverno** — admission control: *rejects* pods that violate policy (privileged containers, unsigned images, missing resource limits) *before* they start.

**IRSA (IAM Roles for Service Accounts)** = each pod gets exactly the AWS permissions it needs (e.g. the AI agent can call Bedrock, nothing else). Least privilege, no shared keys.

---

## 9. GitOps with Argo CD — deployment

**What it does:** Argo CD continuously compares "what git says should be running" (the `gitops/` folder) with "what's actually running in the cluster," and makes them match.

**Why this is better than CI running `kubectl apply`:**
- **Git is the single source of truth** — the repo always reflects production.
- **Auditable** — every change is a git commit; rollback = revert a commit.
- **Pull-based & secure** — the cluster pulls changes; CI never needs cluster credentials.
- **Self-healing** — if someone manually changes something in the cluster, Argo CD reverts it back to what git says.

**App-of-apps** = one top-level Argo CD "Application" that manages all the others, so the whole platform is declared in git.

---

## 10. Observability — knowing what's happening

You can't operate what you can't see. Three pillars:

| Pillar | Tool | Question it answers |
|---|---|---|
| **Metrics** | **Prometheus** | "How many requests/sec? What's the error rate? CPU?" (numbers over time) |
| **Logs** | **Loki** (+ Promtail) | "What did the app actually print when it failed?" |
| **Traces** | **Tempo** (+ OpenTelemetry) | "This one slow request — where did the time go across services?" |

- **Grafana** = the dashboards/UI that visualizes all three in one place.
- **OpenTelemetry** = the vendor-neutral standard for emitting traces/metrics from the app.
- This combo is nicknamed **LGTM** (Loki, Grafana, Tempo, Mimir/Prometheus).

---

## 11. Alerting — being told when it breaks

- **Alertmanager** (ships with Prometheus) — takes firing alerts and **routes** them: groups them, de-duplicates, and sends to the right place.
- **Slack / PagerDuty** — where humans get notified (chat vs. wake-someone-up paging).
- **SLO / burn-rate alerts** — alert on *user-facing* symptoms ("error rate > 5% for 5 min") rather than noise, so on-call isn't spammed.

---

## 12. AI automation — reducing toil

- **Incident-triage agent** — when a critical alert fires, Alertmanager also POSTs it to a small service that asks **Claude (via Amazon Bedrock)** for a root-cause hypothesis + a safe next step, and posts that to Slack. The on-call engineer starts with a summary instead of a blank page.
- **AI PR review** — on every pull request, Claude reviews the diff for bugs/security issues and comments.
- **k8sgpt** — explains failing Kubernetes resources in plain English (`kubectl get results`).

**Why Bedrock:** the AI runs *inside* your AWS account, authenticated with IAM (via IRSA) — no external API key to manage, and your data stays in AWS.

---

## 13. Operations — keeping it healthy

- **Velero** — scheduled backups of the cluster's state (and a restore path) for disaster recovery.
- **Karpenter / Cluster Autoscaler** — adds/removes EC2 nodes automatically as load changes (cost + capacity).
- **Runbooks** — written "if this alert fires, do these steps" guides (in `operations.md`).

---

## How the security layers stack up (defense in depth)

```
Commit  → gitleaks (no secrets) + CodeQL (no bad code)
Build   → Trivy (no known CVEs) + Checkov (no bad infra)
Publish → Syft SBOM + cosign signature (provenance)
Admit   → Kyverno (only signed, non-privileged, limited pods get in)
Run     → Falco (watch behavior) + Trivy Operator (re-scan) + IRSA (least privilege)
Secrets → Secrets Manager + External Secrets (never in git or images)
```

If one layer misses something, the next is likely to catch it. That's the point.
