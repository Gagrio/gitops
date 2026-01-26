# GitOps Showcase - Complete Plan

## Architecture Flowchart

```
┌─────────────────────────────────────────────────────────────────────┐
│ ONE-TIME MANUAL SETUP (User)                                        │
├─────────────────────────────────────────────────────────────────────┤
│ 1. Create GCP Project + Enable APIs                                 │
│ 2. Create Service Account + Download JSON Key                       │
│ 3. Fork Repo → Add GitHub Secrets (GCP_SA_KEY, GCP_PROJECT_ID)     │
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
│ TERRAFORM CREATES                                                   │
├─────────────────────────────────────────────────────────────────────┤
│ • GCS Bucket (Terraform state storage)                             │
│ • GKE Cluster (1 node, e2-medium)                                  │
│ • Flux (bootstrapped to this repo)                                 │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ FLUX MANAGES (via Helm)                                            │
├─────────────────────────────────────────────────────────────────────┤
│ Watches: kubernetes/apps/ directory                                │
│                                                                      │
│ Deploys:                                                            │
│   • Prometheus (monitoring namespace)                              │
│   • Grafana (monitoring namespace)                                 │
│                                                                      │
│ Change Flow:                                                        │
│   Git Commit → Flux Polls (1m) → Reconciles → Updates Cluster      │
└─────────────────────────────────────────────────────────────────────┘
```

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

### GCP Setup (One-time)
- [ ] Create GCP project (or use existing)
- [ ] Enable APIs:
  - Compute Engine API
  - Kubernetes Engine API
  - Cloud Storage API
- [ ] Create Service Account with roles:
  - `roles/storage.admin`
  - `roles/container.admin`
  - `roles/compute.admin`
  - `roles/iam.serviceAccountUser`
- [ ] Download Service Account JSON key

### GitHub Setup (One-time)
- [ ] Fork/clone this repository
- [ ] Add repository secrets:
  - `GCP_SA_KEY` - JSON key content
  - `GCP_PROJECT_ID` - your GCP project ID
  - `GCP_REGION` - target region (e.g., us-central1)

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
│       ├── terraform-deploy.yml     # plan + apply
│       └── terraform-destroy.yml    # destroy only
│
├── terraform/
│   ├── main.tf                      # GCS bucket, GKE cluster
│   ├── flux.tf                      # Flux bootstrap
│   ├── variables.tf                 # Input variables
│   ├── outputs.tf                   # Cluster info, bucket name
│   └── versions.tf                  # Provider versions
│
├── kubernetes/
│   ├── flux-system/                 # Auto-generated by Flux bootstrap
│   │   ├── gotk-components.yaml
│   │   ├── gotk-sync.yaml
│   │   └── kustomization.yaml
│   │
│   └── apps/
│       ├── kustomization.yaml       # Flux entrypoint
│       ├── prometheus/
│       │   ├── namespace.yaml
│       │   ├── helmrepository.yaml
│       │   └── helmrelease.yaml
│       └── grafana/
│           ├── namespace.yaml
│           ├── helmrepository.yaml
│           └── helmrelease.yaml
│
├── .gitignore
└── README.md
```

---

## Terraform Scope

| Resource | Purpose |
|----------|---------|
| `google_storage_bucket` | Terraform state storage (versioning enabled) |
| `google_container_cluster` | GKE cluster (1 node, e2-medium, single zone) |
| `flux_bootstrap_git` | Installs Flux, configures GitRepository + Kustomization |

**State Backend:** GCS bucket created by Terraform

**Outputs:**
- Cluster name
- Cluster endpoint
- State bucket name

---

## Flux Scope

| Component | What It Does |
|-----------|--------------|
| `HelmRepository` | Points to prometheus-community and grafana Helm repos |
| `HelmRelease` (Prometheus) | Deploys Prometheus to `monitoring` namespace |
| `HelmRelease` (Grafana) | Deploys Grafana to `monitoring` namespace |
| `Namespace` | Creates `monitoring` namespace |

**Reconciliation:**
- Flux polls Git every 1 minute
- Changes to `kubernetes/apps/` trigger reconciliation automatically

---

## Demo Scenario

**Setup:**
1. Complete one-time setup (GCP + GitHub secrets)
2. Run GitHub Action → select `apply`
3. Wait for Terraform to create GKE + Flux
4. Flux automatically deploys Prometheus + Grafana

**Demonstrate GitOps:**
1. Edit `kubernetes/apps/prometheus/helmrelease.yaml`
2. Change replica count (e.g., `replicas: 1` → `replicas: 2`)
3. Commit and push to main
4. Watch Flux reconcile (~1 minute)
5. Pods scale automatically without manual intervention

**Teardown:**
1. Run GitHub Action (destroy workflow)
2. Type `yes-destroy` to confirm
3. All GCP resources destroyed

---

## Cost Estimate

| Resource | Cost |
|----------|------|
| GKE cluster management | Free (1 zonal cluster) |
| 1x e2-medium node | ~$25/month |
| GCS bucket | ~$0.02/month |
| **Total** | **~$25/month** |

Run `terraform destroy` after demo to avoid charges.
