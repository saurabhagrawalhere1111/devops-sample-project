# Phase 4 — GitOps with Argo CD

Argo CD continuously syncs this Git repo to the cluster. CI never runs
`kubectl apply`; it only bumps the image tag in `apps/notesapp/values.yaml`,
and Argo CD rolls the change out (pull-based GitOps).

## Layout
```
gitops/
├── argocd/
│   ├── root-app.yaml          # app-of-apps (manages everything below)
│   └── apps/
│       └── notesapp.yaml      # Application -> the Helm chart
└── apps/
    └── notesapp/              # Helm chart for the app
        ├── Chart.yaml
        ├── values.yaml        # <- CI updates image tags here
        └── templates/
```

## Install Argo CD (run once)
```bash
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd

# Get the initial admin password + port-forward the UI
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:443
# open https://localhost:8080  (user: admin)
```

## Bootstrap the app-of-apps
```bash
# Edit repoURL in root-app.yaml / apps/*.yaml to your fork first.
kubectl apply -f gitops/argocd/root-app.yaml
```
Argo CD now discovers `apps/notesapp.yaml` and deploys the chart. Every push to
`main` that changes `values.yaml` auto-syncs.

> Before the first sync, finish Phase 5 (External Secrets + ALB controller) so
> the `ExternalSecret` and `Ingress` resolve. Replace `<ACCOUNT_ID>` in
> `apps/notesapp/values.yaml` with your AWS account ID.
