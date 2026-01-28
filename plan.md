# GitOps Showcase - Complete Plan

## Architecture Flowchart

```
┌─────────────────────────────────────────────────────────────────────┐
│ ONE-TIME MANUAL SETUP (User)                                        │
├─────────────────────────────────────────────────────────────────────┤
│ 1. Create GCP Project + Enable Billing                              │
│ 2. Create Service Account + Download JSON Key                       │
│ 3. Fork Repo → Add GitHub Secrets                                   │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ GITHUB ACTIONS                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  terraform-deploy.yml                terraform-destroy.yml          │
│  ├─ Push → plan only                 ├─ Manual only                 │
│  └─ Manual → plan OR apply           └─ Requires "yes-destroy"      │
│                                                                      │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ TERRAFORM CREATES (Infrastructure Layer)                           │
├─────────────────────────────────────────────────────────────────────┤
│ Bootstrap job:                                                      │
│   • Enables GCP APIs                                                │
│                                                                      │
│ Deploy job:                                                         │
│   • GCS Bucket (via gcloud)                                        │
│   • GKE Cluster (managed node pool, e2-standard-2)                 │
│   • Kubernetes Namespaces (monitoring)                             │
│   • Flux (bootstrapped to this repo)                               │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ FLUX MANAGES (Application Layer)                                   │
├─────────────────────────────────────────────────────────────────────┤
│ Watches: kubernetes/apps/ directory                                │
│                                                                      │
│ Deploys:                                                            │
│   • Prometheus (monitoring namespace)                              │
│   • Grafana (monitoring namespace, with dashboards)                │
│   • hello-gitops (default namespace)                               │
│                                                                      │
│ Change Flow:                                                        │
│   Git Commit → Flux Polls (1m) → Reconciles → Updates Cluster      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Architecture Principles

| Layer | Managed By | Resources |
|-------|------------|-----------|
| Cloud Infrastructure | Terraform | GKE cluster, node pools, networking |
| Kubernetes Infrastructure | Terraform | Namespaces |
| Applications | Flux | HelmReleases, HelmRepositories |

**Why this separation?**
- Namespaces are infrastructure - they must exist before apps deploy
- Terraform ensures namespaces exist before Flux bootstrap begins
- Flux focuses purely on application deployment
- Clear ownership boundaries

---

## GitHub Actions Workflows

```
┌─────────────────────────────────────────────────────────────────────┐
│ WORKFLOW 1: terraform-deploy.yml                                   │
├─────────────────────────────────────────────────────────────────────┤
│ Triggers:                                                           │
│   • Push to main (terraform/** changes) → runs PLAN only           │
│   • Manual dispatch with input:                                     │
│       action: [plan, apply]  ← user selects                        │
│                                                                      │
│ Jobs:                                                                │
│   1. Bootstrap: Terraform enables GCP APIs                         │
│   2. Deploy: gcloud creates bucket, Terraform creates GKE + Flux   │
│                                                                      │
│ Behavior:                                                            │
│   • Push         → plan only (review in logs)                      │
│   • Manual+plan  → plan only                                        │
│   • Manual+apply → plan + apply                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ WORKFLOW 2: terraform-destroy.yml                                  │
├─────────────────────────────────────────────────────────────────────┤
│ Triggers:                                                           │
│   • Manual dispatch only                                           │
│       confirm: "yes-destroy"  ← user must type to confirm          │
└─────────────────────────────────────────────────────────────────────┘
```

**Flow:**
```
Push to main
     │
     ▼
  Plan only → Review output in Actions logs


Manual dispatch (deploy workflow)
     │
     ├─ action: "plan"  → Plan only
     │
     └─ action: "apply" → Plan + Apply


Manual dispatch (destroy workflow)
     │
     └─ confirm: "yes-destroy" → Destroy
```

---

## Setup Checklist

### GCP Setup (One-time, in browser)
- [ ] Create GCP project (or use existing)
- [ ] Enable billing
- [ ] Create Service Account with roles:
  - `Storage Admin`
  - `Kubernetes Engine Admin`
  - `Compute Admin`
  - `Service Account User`
  - `Service Usage Admin` (for enabling APIs)
- [ ] Download Service Account JSON key

### GitHub Setup (One-time)
- [ ] Fork/clone this repository
- [ ] Create GitHub PAT with `repo` scope
- [ ] Add repository secrets:
  - `GCP_SA_KEY` - JSON key content
  - `GCP_PROJECT_ID` - your GCP project ID
  - `GCP_REGION` - target region (e.g., `europe-west1`)
  - `FLUX_GITHUB_TOKEN` - GitHub PAT

### .gitignore (already in repo)
```
*.tfstate*
*.json
.terraform/
```

---

## Repository Structure

```
gitops/
├── .github/
│   └── workflows/
│       ├── terraform-deploy.yml     # Bootstrap + Deploy
│       └── terraform-destroy.yml    # Destroy only
│
├── terraform/
│   ├── bootstrap/                   # Enables GCP APIs
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   ├── main.tf                      # GKE cluster, node pool, namespaces
│   ├── flux.tf                      # Flux bootstrap
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
│
├── kubernetes/
│   ├── kustomization.yaml           # Root: flux-system + apps
│   ├── flux-system/                 # Auto-generated by Flux bootstrap
│   └── apps/
│       ├── kustomization.yaml       # Aggregates all apps
│       ├── prometheus/
│       │   ├── helmrepository.yaml
│       │   ├── helmrelease.yaml
│       │   └── kustomization.yaml
│       ├── grafana/
│       │   ├── helmrepository.yaml
│       │   ├── helmrelease.yaml
│       │   └── kustomization.yaml
│       └── hello-gitops/
│           ├── helmrelease.yaml     # Uses chart from Git
│           └── kustomization.yaml
│
├── charts/
│   └── hello-gitops/                # Custom Helm chart
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           └── service.yaml
│
├── .gitignore
├── plan.md
├── gitops-study-guide.md
└── README.md
```

---

## Terraform Scope

### Bootstrap (terraform/bootstrap/)
| Resource | Purpose |
|----------|---------|
| `google_project_service` | Enables required GCP APIs |

### Deploy (terraform/)
| Resource | Purpose |
|----------|---------|
| `google_container_cluster` | GKE cluster (removes default node pool) |
| `google_container_node_pool` | Managed node pool (e2-standard-2, single node) |
| `kubernetes_namespace` | Creates monitoring namespace |
| `time_sleep` | Ensures namespace propagation before Flux |
| `flux_bootstrap_git` | Installs Flux, configures GitRepository + Kustomization |

**Dependency Chain:**
```
GKE Cluster
    ↓
Node Pool
    ↓
Namespace (monitoring)
    ↓
time_sleep (10s)
    ↓
Flux Bootstrap
```

**State Backend:** GCS bucket created by gcloud before Terraform init

**Outputs:**
- Cluster name
- Cluster endpoint
- Kubeconfig command

---

## Flux Scope

| Component | What It Does |
|-----------|--------------|
| `HelmRepository` | Points to prometheus-community and grafana Helm repos |
| `HelmRelease` (Prometheus) | Deploys Prometheus to `monitoring` namespace |
| `HelmRelease` (Grafana) | Deploys Grafana to `monitoring` namespace with auto-provisioned dashboards |
| `HelmRelease` (hello-gitops) | Deploys custom app to `default` namespace using chart from Git |

**Note:** Namespaces are NOT managed by Flux - they're created by Terraform before Flux starts.

**Grafana Dashboards:**
- 7249: Kubernetes Cluster Monitoring
- 1860: Node Exporter Full
- 6417: Kubernetes Pods
- 315: Kubernetes Cluster Overview

**Reconciliation:**
- Flux polls Git every 1 minute
- Changes to `kubernetes/apps/` trigger reconciliation automatically

---

## Demo Scenario

**Setup:**
1. Complete one-time setup (GCP + GitHub secrets)
2. Run GitHub Action → select `apply`
3. Wait for Terraform to create GKE + namespaces + Flux
4. Flux automatically deploys Prometheus + Grafana (with dashboards) + hello-gitops

**Demonstrate GitOps:**

*Example 1: Scale Prometheus*
1. Edit `kubernetes/apps/prometheus/helmrelease.yaml`
2. Change replica count (e.g., `replicas: 1` → `replicas: 2`)
3. Commit and push to main
4. Watch Flux reconcile (~1 minute)
5. Pods scale automatically without manual intervention

*Example 2: Update hello-gitops Message*
1. Edit `kubernetes/apps/hello-gitops/helmrelease.yaml`
2. Change `message` value
3. Commit and push to main
4. Flux reconciles, pod restarts with new message
5. Visit LoadBalancer IP to see change

*Example 3: Add Grafana Dashboard*
1. Find dashboard on grafana.com
2. Edit `kubernetes/apps/grafana/helmrelease.yaml`
3. Add dashboard ID under `dashboards.default`
4. Commit and push
5. Dashboard appears in Grafana automatically

**Teardown:**
1. Run GitHub Action (destroy workflow)
2. Type `yes-destroy` to confirm
3. All GCP resources destroyed

---

## Cost Estimate

| Resource | Cost |
|----------|------|
| GKE cluster management | Free (1 zonal cluster) |
| 1x e2-standard-2 node | ~$49/month |
| 2x LoadBalancer (Grafana + hello-gitops) | ~$36-40/month |
| GCS bucket | ~$0.02/month |
| **Total** | **~$85-89/month** |

**Cost optimization tip:** Use Ingress instead of 2 LoadBalancers to save ~$18-20/month

Run `terraform destroy` after demo to avoid charges.
