# GitOps Study Guide

> **Note**: All examples in this guide are from your actual gitops repository and can be run/tested on your GKE cluster.

## Table of Contents
1. [GitHub Actions](#1-github-actions)
2. [Flux CD](#2-flux-cd)
3. [Kubernetes Concepts](#3-kubernetes-concepts)
4. [GitOps Principles](#4-gitops-principles)
5. [Interview Questions](#5-interview-questions)

---

## 1. GitHub Actions

### What is GitHub Actions?

GitHub Actions is a CI/CD platform integrated into GitHub that automates software workflows. It allows you to build, test, and deploy code directly from your repository using event-driven automation.

### Key Concepts

#### Workflows
- YAML files stored in `.github/workflows/` directory
- Define automated processes triggered by events
- Can contain one or more jobs
- Each workflow runs in its own context

### Your Actual Workflows

You have two workflows in your repository:

```
.github/workflows/
├── terraform-deploy.yml    # Bootstrap + Deploy infrastructure
└── terraform-destroy.yml   # Destroy infrastructure (manual only)
```

---

### Example 1: Deploy Workflow with Multiple Triggers

**File**: `.github/workflows/terraform-deploy.yml`

```yaml
name: Terraform Infrastructure

# Dynamic run name based on action type
run-name: "Terraform ${{ github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'apply' && '🚀 APPLY' || '📋 PLAN' }} - ${{ github.actor }}"

on:
  # Trigger 1: Automatic on push to master (plan only)
  push:
    branches:
      - master
    paths:
      - 'terraform/**'  # Only when terraform files change

  # Trigger 2: Manual dispatch with action selection
  workflow_dispatch:
    inputs:
      action:
        description: 'Terraform action to perform'
        required: true
        default: 'plan'
        type: choice
        options:
          - plan
          - apply
```

**What this demonstrates**:
- **Multiple triggers**: `push` for automatic runs, `workflow_dispatch` for manual control
- **Path filtering**: Only runs when `terraform/**` files change
- **Input parameters**: User can choose between `plan` and `apply`
- **Dynamic run name**: Shows whether it's a PLAN or APPLY run in the UI

---

### Example 2: Environment Variables and Secrets

**File**: `.github/workflows/terraform-deploy.yml`

```yaml
env:
  # Terraform variables from GitHub Secrets
  TF_VAR_project_id: ${{ secrets.GCP_PROJECT_ID }}
  TF_VAR_region: ${{ secrets.GCP_REGION }}

  # Variables from GitHub context
  TF_VAR_github_owner: ${{ github.repository_owner }}
  TF_VAR_github_repository: ${{ github.event.repository.name }}

  # Token for Flux to access this repo
  TF_VAR_github_token: ${{ secrets.FLUX_GITHUB_TOKEN }}
```

**What this demonstrates**:
- **Secrets**: Sensitive data stored encrypted in GitHub (`secrets.GCP_PROJECT_ID`)
- **TF_VAR_ prefix**: Automatically passed to Terraform as variables
- **GitHub context**: Access repo metadata (`github.repository_owner`)
- **Token management**: PAT stored as secret for Flux authentication

---

### Example 3: Job Dependencies with `needs`

**File**: `.github/workflows/terraform-deploy.yml`

```yaml
jobs:
  bootstrap:
    name: "${{ github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'apply' && '🚀 Bootstrap - APPLY' || '📋 Bootstrap - PLAN' }}"
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: terraform/bootstrap
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      # ... bootstrap steps

  deploy:
    name: "${{ github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'apply' && '🚀 Infrastructure - APPLY' || '📋 Infrastructure - PLAN' }}"
    needs: bootstrap  # ← WAIT for bootstrap to complete
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: terraform
    steps:
      # ... deploy steps
```

**What this demonstrates**:
- **Job dependencies**: `needs: bootstrap` ensures deploy waits for bootstrap
- **Dynamic job names**: Different names for PLAN vs APPLY runs
- **Working directory**: Each job operates in different directories
- **Execution order**: bootstrap → deploy (sequential, not parallel)

---

### Example 4: Conditional Step Execution

**File**: `.github/workflows/terraform-deploy.yml`

```yaml
steps:
  - name: Terraform Plan
    run: terraform plan -out=tfplan
    # Always runs (no condition)

  - name: Terraform Apply
    if: github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'apply'
    run: terraform apply -auto-approve tfplan
    # Only runs when: manual trigger AND user selected "apply"
```

**What this demonstrates**:
- **Conditional execution**: `if:` controls when step runs
- **Event type check**: `github.event_name == 'workflow_dispatch'`
- **Input value check**: `github.event.inputs.action == 'apply'`
- **Safe defaults**: Push triggers only run plan, never apply

---

### Example 5: Safety Pattern for Destructive Operations

**File**: `.github/workflows/terraform-destroy.yml`

```yaml
name: Terraform Destroy

on:
  workflow_dispatch:
    inputs:
      confirm:
        description: 'Type "yes-destroy" to confirm destruction'
        required: true
        type: string  # Free text, not choice

jobs:
  destroy:
    name: Terraform Destroy
    runs-on: ubuntu-latest
    steps:
      - name: Validate confirmation
        if: github.event.inputs.confirm != 'yes-destroy'
        run: |
          echo "Error: You must type 'yes-destroy' to confirm destruction"
          exit 1

      # ... destruction steps only run if validation passes
```

**What this demonstrates**:
- **Manual-only trigger**: No `push` event, only `workflow_dispatch`
- **Confirmation pattern**: User must type exact string to proceed
- **Early exit**: Fails immediately if confirmation doesn't match
- **Defense in depth**: Multiple barriers before destructive action

---

### Example 6: Using Actions and Multi-line Scripts

**File**: `.github/workflows/terraform-deploy.yml`

```yaml
steps:
  - name: Checkout
    uses: actions/checkout@v4  # Pre-built action

  - name: Authenticate to Google Cloud
    uses: google-github-actions/auth@v2
    with:
      credentials_json: ${{ secrets.GCP_SA_KEY }}

  - name: Setup gcloud CLI
    uses: google-github-actions/setup-gcloud@v2

  - name: Ensure GCS bucket exists
    run: |  # Multi-line script
      BUCKET_NAME="${{ secrets.GCP_PROJECT_ID }}-tfstate"
      if ! gcloud storage buckets describe gs://${BUCKET_NAME} &>/dev/null; then
        echo "Creating bucket ${BUCKET_NAME}..."
        gcloud storage buckets create gs://${BUCKET_NAME} \
          --location=${{ secrets.GCP_REGION }} \
          --uniform-bucket-level-access
      else
        echo "Bucket ${BUCKET_NAME} already exists"
      fi

  - name: Setup Terraform
    uses: hashicorp/setup-terraform@v3
    with:
      terraform_version: 1.7.0
```

**What this demonstrates**:
- **Pre-built actions**: `uses:` to leverage community actions
- **Action inputs**: `with:` passes parameters to actions
- **Version pinning**: `@v4`, `@v2`, `1.7.0` for reproducibility
- **Multi-line scripts**: `run: |` for complex bash logic
- **Idempotent operations**: Check before create (bucket exists check)

---

### GitHub Actions Syntax Reference

| Key | Purpose | Your Example |
|-----|---------|--------------|
| `name` | Workflow display name | `name: Terraform Infrastructure` |
| `run-name` | Dynamic run name | Shows PLAN or APPLY based on input |
| `on.push` | Trigger on code push | Triggers on master + terraform/** |
| `on.workflow_dispatch` | Manual trigger | With action input (plan/apply) |
| `on.workflow_dispatch.inputs` | User inputs | Choice or string type |
| `env` | Environment variables | TF_VAR_* for Terraform |
| `jobs.<id>.needs` | Job dependencies | `needs: bootstrap` |
| `jobs.<id>.defaults.run.working-directory` | Default directory | `terraform/bootstrap` |
| `steps[*].uses` | Use an action | `actions/checkout@v4` |
| `steps[*].with` | Action inputs | `terraform_version: 1.7.0` |
| `steps[*].run` | Execute command | `terraform plan -out=tfplan` |
| `steps[*].if` | Conditional execution | `if: github.event.inputs.action == 'apply'` |

---

### Best Practices (Demonstrated in Your Workflows)

1. **Pin action versions**: `@v4` not `@main` for reproducibility
2. **Use secrets**: Never commit credentials, use `${{ secrets.* }}`
3. **Path filtering**: Only trigger on relevant file changes
4. **Conditional apply**: Manual approval for destructive operations
5. **Confirmation patterns**: Require explicit confirmation for destroy
6. **Dynamic naming**: Clear indication of what workflow is doing
7. **Job dependencies**: Ensure correct execution order
8. **Idempotent scripts**: Check state before making changes

---

## 2. Flux CD

### What is Flux CD?

Flux is a GitOps operator that runs inside your Kubernetes cluster and continuously synchronizes cluster state with Git. It automatically deploys applications when you commit changes to Git.

### Your Flux Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Git Repository (github.com/Gagrio/gitops)                       │
├─────────────────────────────────────────────────────────────────┤
│ kubernetes/                                                     │
│ ├── kustomization.yaml      → Root: includes flux-system + apps │
│ ├── flux-system/            → Flux manages itself               │
│ │   ├── gotk-components.yaml                                   │
│ │   ├── gotk-sync.yaml      → GitRepository + Kustomization    │
│ │   └── kustomization.yaml                                     │
│ └── apps/                   → Your applications                 │
│     ├── kustomization.yaml  → Includes prometheus + grafana     │
│     ├── prometheus/                                             │
│     │   ├── kustomization.yaml                                 │
│     │   ├── helmrepository.yaml                                │
│     │   └── helmrelease.yaml                                   │
│     └── grafana/                                                │
│         ├── kustomization.yaml                                 │
│         ├── helmrepository.yaml                                │
│         └── helmrelease.yaml                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Flux polls every 1m
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ GKE Cluster                                                     │
├─────────────────────────────────────────────────────────────────┤
│ flux-system namespace:                                          │
│   • source-controller (watches Git + Helm repos)               │
│   • kustomize-controller (applies Kustomizations)              │
│   • helm-controller (manages HelmReleases)                     │
│                                                                 │
│ monitoring namespace:                                           │
│   • Prometheus (deployed by HelmRelease)                       │
│   • Grafana (deployed by HelmRelease)                          │
└─────────────────────────────────────────────────────────────────┘
```

---

### Example 7: GitRepository - Connecting Flux to Git

**File**: `kubernetes/flux-system/gotk-sync.yaml`

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 1m0s              # Poll Git every 1 minute
  ref:
    branch: master            # Track master branch
  secretRef:
    name: flux-system         # Auth credentials (GitHub token)
  url: https://github.com/Gagrio/gitops.git
```

**What this demonstrates**:
- **Source definition**: Tells Flux where to find manifests
- **Polling interval**: `1m0s` - checks for changes every minute
- **Branch tracking**: Watches `master` branch
- **Authentication**: Uses secret for private repo access
- **Your actual repo URL**: `https://github.com/Gagrio/gitops.git`

---

### Example 8: Flux Kustomization - What to Apply

**File**: `kubernetes/flux-system/gotk-sync.yaml`

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 10m0s             # Reconcile every 10 minutes
  path: ./kubernetes          # Apply manifests from this path
  prune: true                 # Delete resources removed from Git
  sourceRef:
    kind: GitRepository
    name: flux-system         # Use the GitRepository above
```

**What this demonstrates**:
- **Path selection**: `./kubernetes` - root of your Kubernetes manifests
- **Reconciliation interval**: `10m0s` - ensures drift is corrected
- **Pruning enabled**: Resources deleted from Git are deleted from cluster
- **Source reference**: Links to GitRepository for manifest source

---

### Example 9: HelmRepository - Adding Helm Chart Sources

**File**: `kubernetes/apps/prometheus/helmrepository.yaml`

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: flux-system       # ← Note: in flux-system, not monitoring
spec:
  interval: 1h                 # Check for new chart versions hourly
  url: https://prometheus-community.github.io/helm-charts
```

**File**: `kubernetes/apps/grafana/helmrepository.yaml`

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: grafana
  namespace: flux-system
spec:
  interval: 1h
  url: https://grafana.github.io/helm-charts
```

**What this demonstrates**:
- **Chart source**: URL to Helm repository index
- **Namespace placement**: HelmRepositories in `flux-system` (shared)
- **Update interval**: `1h` - checks for new chart versions hourly
- **Naming**: Matches the sourceRef name in HelmRelease

---

### Example 10: HelmRelease - Installing Prometheus

**File**: `kubernetes/apps/prometheus/helmrelease.yaml`

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: prometheus
  namespace: monitoring        # ← Deployed TO monitoring namespace
spec:
  interval: 5m                 # Reconcile every 5 minutes
  chart:
    spec:
      chart: prometheus        # Chart name in repository
      version: "25.x"          # Semver range: any 25.x.x version
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: flux-system  # ← HelmRepository is in flux-system
  values:
    # Minimal configuration for showcase
    server:
      replicaCount: 1
      persistentVolume:
        enabled: false          # No persistent storage (demo only)
      resources:
        limits:
          cpu: 500m
          memory: 512Mi
        requests:
          cpu: 100m
          memory: 256Mi
    alertmanager:
      enabled: false            # Disabled for simplicity
    kube-state-metrics:
      enabled: true             # Kubernetes metrics
    prometheus-node-exporter:
      enabled: true             # Node metrics
    prometheus-pushgateway:
      enabled: false            # Not needed for demo
```

**What this demonstrates**:
- **Namespace separation**: HelmRelease in `monitoring`, HelmRepository in `flux-system`
- **Semver versioning**: `"25.x"` allows automatic minor/patch updates
- **Values override**: Customize chart defaults for your use case
- **Resource limits**: Good practice for cluster resource management
- **Feature toggles**: Enable/disable chart components as needed

---

### Example 11: HelmRelease - Installing Grafana with Datasource

**File**: `kubernetes/apps/grafana/helmrelease.yaml`

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: grafana
  namespace: monitoring
spec:
  interval: 5m
  chart:
    spec:
      chart: grafana
      version: "8.x"
      sourceRef:
        kind: HelmRepository
        name: grafana
        namespace: flux-system
  values:
    replicas: 1
    persistence:
      enabled: false
    resources:
      limits:
        cpu: 200m
        memory: 256Mi
      requests:
        cpu: 100m
        memory: 128Mi

    # Admin credentials (change in production!)
    adminUser: admin
    adminPassword: gitops-showcase

    # Expose via LoadBalancer
    service:
      type: LoadBalancer

    # Pre-configure Prometheus datasource
    datasources:
      datasources.yaml:
        apiVersion: 1
        datasources:
          - name: Prometheus
            type: prometheus
            url: http://prometheus-server.monitoring.svc.cluster.local
            access: proxy
            isDefault: true
```

**What this demonstrates**:
- **Service exposure**: `type: LoadBalancer` for external access
- **Credentials in values**: (Note: use secrets in production!)
- **Cross-service reference**: Grafana connects to Prometheus using Kubernetes DNS
- **DNS format**: `<service>.<namespace>.svc.cluster.local`
- **Datasource provisioning**: Grafana auto-configured with Prometheus

---

### Example 12: Kustomization Files - Aggregating Resources

**File**: `kubernetes/kustomization.yaml` (Root)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - flux-system    # Include flux-system directory
  - apps           # Include apps directory
```

**File**: `kubernetes/apps/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - prometheus     # Include prometheus directory
  - grafana        # Include grafana directory
```

**File**: `kubernetes/apps/prometheus/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrepository.yaml
  - helmrelease.yaml
```

**What this demonstrates**:
- **Hierarchical structure**: Root → apps → individual apps
- **Simple aggregation**: Just lists what resources to include
- **Directory references**: Can include entire directories
- **File references**: Can include specific files
- **Build order**: Kustomize builds from leaf to root

---

### Reconciliation Loop

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Source Controller polls Git (every 1m)                       │
│    GitRepository: github.com/Gagrio/gitops.git @ master         │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Detect changes (compare commit SHA)                          │
│    If new commit found, fetch kubernetes/ directory             │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Kustomize Controller builds manifests                        │
│    Follows kustomization.yaml hierarchy                         │
│    kubernetes/ → apps/ → prometheus/, grafana/                  │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. Helm Controller processes HelmReleases                       │
│    - Fetches charts from HelmRepositories                       │
│    - Renders templates with your values                         │
│    - Applies to cluster                                         │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Resources deployed to monitoring namespace                   │
│    - Prometheus server, node-exporter, kube-state-metrics      │
│    - Grafana with Prometheus datasource                        │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. Continuous reconciliation (every 10m for Kustomization)      │
│    Even without Git changes, ensures cluster matches Git        │
│    Manual kubectl changes are reverted                          │
└─────────────────────────────────────────────────────────────────┘
```

---

### Flux CLI Commands (for your cluster)

```bash
# Check Flux installation status
flux check

# View all Flux resources
flux get all -A

# Check GitRepository status (is it fetching your repo?)
flux get sources git -A
# Expected: flux-system   True    Fetched revision: master@sha1:xxxxx

# Check HelmRepository status
flux get sources helm -A
# Expected: prometheus-community, grafana

# Check Kustomization status
flux get kustomizations -A
# Expected: flux-system   True    Applied revision: master@sha1:xxxxx

# Check HelmRelease status
flux get helmreleases -A
# Expected: prometheus, grafana in monitoring namespace

# Force immediate reconciliation (don't wait for interval)
flux reconcile kustomization flux-system --with-source

# Force HelmRelease reconciliation
flux reconcile helmrelease prometheus -n monitoring

# View Flux logs for debugging
flux logs --level=error

# Suspend reconciliation (for maintenance)
flux suspend helmrelease prometheus -n monitoring

# Resume reconciliation
flux resume helmrelease prometheus -n monitoring
```

---

## 3. Kubernetes Concepts

### Kustomize

Kustomize is a template-free way to customize Kubernetes YAML. It uses overlays and aggregation rather than templating.

#### Your Kustomize Structure

```
kubernetes/
├── kustomization.yaml           # Root aggregator
│   resources:
│     - flux-system
│     - apps
│
├── flux-system/
│   └── kustomization.yaml       # Flux components
│
└── apps/
    ├── kustomization.yaml       # App aggregator
    │   resources:
    │     - prometheus
    │     - grafana
    │
    ├── prometheus/
    │   └── kustomization.yaml   # Prometheus resources
    │       resources:
    │         - helmrepository.yaml
    │         - helmrelease.yaml
    │
    └── grafana/
        └── kustomization.yaml   # Grafana resources
            resources:
              - helmrepository.yaml
              - helmrelease.yaml
```

**Your pattern**: Simple resource aggregation. Each `kustomization.yaml` just lists what to include.

#### Building Locally

```bash
# See what Kustomize produces
kustomize build kubernetes/

# Or with kubectl
kubectl kustomize kubernetes/

# Apply directly (but Flux does this automatically)
kubectl apply -k kubernetes/
```

#### Advanced Kustomize Features (not in your setup, but useful to know)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Basic aggregation (what you use)
resources:
  - prometheus
  - grafana

# Add labels to all resources
commonLabels:
  environment: production
  managed-by: flux

# Add namespace to all resources
namespace: monitoring

# Name prefix/suffix
namePrefix: prod-

# Image replacement
images:
  - name: nginx
    newTag: 1.21.0

# Patches
patchesStrategicMerge:
  - increase-replicas.yaml
```

---

### Helm

Helm is a package manager for Kubernetes. Charts are packages of pre-configured resources.

#### How Your Setup Uses Helm

You don't run `helm install` commands. Instead, Flux manages Helm declaratively:

| Traditional Helm | Your GitOps Setup |
|-----------------|-------------------|
| `helm repo add prometheus-community ...` | HelmRepository YAML in Git |
| `helm install prometheus ...` | HelmRelease YAML in Git |
| `helm upgrade prometheus ...` | Edit HelmRelease, commit, Flux applies |
| `helm rollback prometheus` | `git revert`, Flux applies |

#### Helm Values Explained

Your `helmrelease.yaml` `values:` section overrides chart defaults:

```yaml
# Chart default (in prometheus chart's values.yaml):
server:
  replicaCount: 1
  persistentVolume:
    enabled: true
    size: 8Gi

# Your override (in helmrelease.yaml):
values:
  server:
    replicaCount: 1           # Keep default
    persistentVolume:
      enabled: false          # Override: disable persistence
```

Only specify values you want to change from defaults.

#### Useful Helm Commands (for debugging)

```bash
# See what values a release is using
helm get values prometheus -n monitoring

# See all values (including defaults)
helm get values prometheus -n monitoring --all

# See the rendered manifests
helm get manifest prometheus -n monitoring

# List releases
helm list -n monitoring

# See release history
helm history prometheus -n monitoring
```

---

### Namespaces

Namespaces provide logical isolation within your cluster.

#### Your Namespace Structure

```
┌─────────────────────────────────────────────────────────────────┐
│ Cluster                                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────┐  ┌─────────────────────────────┐  │
│  │ flux-system             │  │ monitoring                  │  │
│  │                         │  │                             │  │
│  │ • source-controller     │  │ • prometheus-server         │  │
│  │ • kustomize-controller  │  │ • prometheus-node-exporter  │  │
│  │ • helm-controller       │  │ • kube-state-metrics        │  │
│  │ • notification-ctrl     │  │ • grafana                   │  │
│  │                         │  │                             │  │
│  │ HelmRepositories:       │  │                             │  │
│  │ • prometheus-community  │  │                             │  │
│  │ • grafana               │  │                             │  │
│  └─────────────────────────┘  └─────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Key insight**: HelmRepositories live in `flux-system` (shared infrastructure), but HelmReleases and their deployed resources live in `monitoring` (application namespace).

#### Cross-Namespace Reference in Your Setup

Grafana's datasource uses Kubernetes DNS to reach Prometheus:

```yaml
# In grafana's helmrelease.yaml
url: http://prometheus-server.monitoring.svc.cluster.local
#         └─────────────┘ └────────┘ └──┘ └───────────────┘
#          service name   namespace  svc   cluster domain
```

This DNS format allows any pod in any namespace to reach the Prometheus service.

#### Namespace Commands

```bash
# List namespaces
kubectl get namespaces

# List all resources in monitoring namespace
kubectl get all -n monitoring

# List pods across all namespaces
kubectl get pods -A

# Describe namespace
kubectl describe namespace monitoring
```

---

### How Everything Fits Together

```
┌──────────────────────────────────────────────────────────────────────┐
│                        YOUR GITOPS FLOW                               │
└──────────────────────────────────────────────────────────────────────┘

1. YOU COMMIT TO GIT
   └─→ Edit kubernetes/apps/prometheus/helmrelease.yaml
   └─→ Change: replicaCount: 1 → replicaCount: 2
   └─→ git commit && git push

2. FLUX DETECTS CHANGE (within 1 minute)
   └─→ GitRepository polls github.com/Gagrio/gitops.git
   └─→ Sees new commit SHA on master branch
   └─→ Fetches updated kubernetes/ directory

3. KUSTOMIZE CONTROLLER BUILDS MANIFESTS
   └─→ Reads kubernetes/kustomization.yaml
   └─→ Follows: flux-system, apps
   └─→ Follows: apps/prometheus, apps/grafana
   └─→ Collects: helmrepository.yaml, helmrelease.yaml

4. HELM CONTROLLER PROCESSES HELMRELEASE
   └─→ Sees prometheus HelmRelease changed
   └─→ Fetches prometheus chart from prometheus-community repo
   └─→ Renders chart with your values (replicaCount: 2)
   └─→ Applies to cluster (like helm upgrade)

5. KUBERNETES ACTS
   └─→ Deployment spec changed (replicas: 2)
   └─→ Scheduler creates second pod
   └─→ Pod starts on available node

6. CLUSTER STATE = GIT STATE
   └─→ Prometheus now has 2 replicas
   └─→ This matches what's declared in Git
   └─→ GitOps achieved!

7. CONTINUOUS RECONCILIATION
   └─→ If someone runs: kubectl scale deploy prometheus-server --replicas=1
   └─→ Next reconciliation (within 10 minutes)
   └─→ Flux sees drift: cluster has 1, Git says 2
   └─→ Flux corrects: scales back to 2
   └─→ Self-healing!
```

---

## 4. GitOps Principles

### The Four Principles

#### 1. Declarative

Everything is described as YAML (what), not scripts (how).

**Your example**:
```yaml
# Declarative: "I want Prometheus with 1 replica"
spec:
  values:
    server:
      replicaCount: 1
```

Not imperative: `helm install prometheus ... && kubectl scale ...`

#### 2. Versioned and Immutable

All configuration lives in Git with full history.

**Your example**:
- All manifests in `kubernetes/` directory
- Every change is a commit
- Can see who changed what and when
- Rollback = `git revert`

#### 3. Pulled Automatically

Cluster pulls from Git; nothing pushes to cluster.

**Your example**:
```yaml
# GitRepository pulls from your repo
spec:
  interval: 1m0s
  url: https://github.com/Gagrio/gitops.git
```

GitHub Actions doesn't push to cluster. Flux pulls.

#### 4. Continuously Reconciled

System constantly ensures actual state matches desired state.

**Your example**:
```yaml
# Kustomization reconciles every 10 minutes
spec:
  interval: 10m0s
  prune: true  # Delete resources removed from Git
```

---

### Push vs Pull Model

```
TRADITIONAL (Push-based CI/CD):
┌─────────┐     ┌─────────┐     ┌─────────────┐
│   Git   │────▶│   CI    │────▶│   Cluster   │
└─────────┘     └─────────┘     └─────────────┘
                    │
                    └─ CI has cluster credentials (security risk)
                    └─ CI pushes to cluster (needs network access)
                    └─ No drift detection

YOUR SETUP (Pull-based GitOps):
┌─────────┐     ┌─────────────────────────────────┐
│   Git   │◀────│   Cluster (Flux inside)         │
└─────────┘     └─────────────────────────────────┘
                    │
                    └─ Credentials never leave cluster
                    └─ Cluster pulls from Git
                    └─ Automatic drift correction
```

---

### Benefits Demonstrated in Your Setup

| Benefit | How Your Setup Achieves It |
|---------|---------------------------|
| **Security** | GitHub Actions never has cluster credentials. Flux has Git read access only. |
| **Audit trail** | All changes are Git commits. See history with `git log kubernetes/` |
| **Easy rollback** | Run `git revert <commit>` and push. Flux automatically rolls back. |
| **Self-healing** | Manual `kubectl` changes are reverted by Flux within 10 minutes |
| **Disaster recovery** | Lose cluster? Create new one, bootstrap Flux, everything restored from Git |
| **Reproducibility** | Same Git state = same cluster state, every time |

---

### Demonstrating GitOps (Try These!)

**1. Make a change via Git**:
```bash
# Edit prometheus replicas
vim kubernetes/apps/prometheus/helmrelease.yaml
# Change replicaCount: 1 to replicaCount: 2

git add kubernetes/apps/prometheus/helmrelease.yaml
git commit -m "Scale prometheus to 2 replicas"
git push

# Watch Flux reconcile (within 1 minute)
watch flux get helmreleases -n monitoring

# See pods scale
kubectl get pods -n monitoring -w
```

**2. Try manual change (will be reverted)**:
```bash
# Manually scale down
kubectl scale deployment prometheus-server -n monitoring --replicas=1

# Watch - Flux will scale it back up within 10 minutes
kubectl get pods -n monitoring -w
```

**3. Rollback via Git**:
```bash
# See commit history
git log --oneline kubernetes/apps/prometheus/

# Revert last change
git revert HEAD
git push

# Flux automatically scales back to 1 replica
```

---

## 5. Interview Questions

### GitHub Actions

**Q: Explain your CI/CD workflow. What triggers deployments?**

A: We have two workflows:
1. **terraform-deploy.yml**: Triggered by push to master (plan only) or manual dispatch (plan or apply). It bootstraps GCP APIs, creates the GKE cluster, and installs Flux.
2. **terraform-destroy.yml**: Manual only with confirmation. User must type "yes-destroy" to proceed.

Push triggers only run `terraform plan` for safety. Actual infrastructure changes require manual `workflow_dispatch` with `apply` selected.

---

**Q: How do you handle secrets in your workflows?**

A: Secrets are stored encrypted in GitHub Secrets, never in code:
- `GCP_SA_KEY`: Service account JSON for GCP authentication
- `GCP_PROJECT_ID`, `GCP_REGION`: Configuration values
- `FLUX_GITHUB_TOKEN`: PAT for Flux to access the Git repo

They're accessed as `${{ secrets.SECRET_NAME }}` and automatically masked in logs. We use `TF_VAR_` prefix so Terraform picks them up automatically.

---

**Q: Why use `needs: bootstrap` in your deploy job?**

A: The `bootstrap` job enables required GCP APIs. The `deploy` job creates the GKE cluster which depends on those APIs being enabled. Without `needs: bootstrap`, both jobs would run in parallel and `deploy` would fail because APIs aren't ready. The `needs` keyword ensures sequential execution.

---

### Flux CD

**Q: Explain how Flux deploys Prometheus in your setup.**

A:
1. GitRepository polls `github.com/Gagrio/gitops.git` every minute
2. Kustomize Controller reads `kubernetes/kustomization.yaml`, which includes `apps/prometheus/`
3. In prometheus folder, there's a HelmRepository (points to prometheus-community charts) and HelmRelease (defines chart version and values)
4. Helm Controller fetches the prometheus chart, renders it with our values (1 replica, no persistence, specific resource limits), and applies to the monitoring namespace
5. This repeats every 5 minutes (HelmRelease interval) to ensure the deployment matches our specification

---

**Q: What happens if someone runs `kubectl delete deployment prometheus-server`?**

A: Within the reconciliation interval (10 minutes for Kustomization, 5 minutes for HelmRelease), Flux will detect that the deployment is missing and recreate it. This is self-healing - the cluster always converges to match Git state.

---

**Q: Why are your HelmRepositories in flux-system but HelmReleases in monitoring?**

A: Separation of concerns:
- **HelmRepositories** are shared infrastructure - any HelmRelease can reference them. Placing them in `flux-system` makes them available cluster-wide.
- **HelmReleases** are application-specific and deploy to their target namespace (`monitoring`). The namespace in the HelmRelease metadata determines where the Helm chart resources are created.

The `sourceRef` in HelmRelease explicitly specifies `namespace: flux-system` to find the HelmRepository.

---

**Q: What does `prune: true` do in your Kustomization?**

A: When `prune: true`, if you delete a file from Git (e.g., remove `grafana/` folder), Flux will delete those resources from the cluster. Without pruning, orphaned resources would remain. It ensures Git is truly the single source of truth - nothing exists in the cluster that isn't defined in Git.

---

**Q: How would you rollback a bad Prometheus deployment?**

A:
```bash
# Find the last good commit
git log --oneline kubernetes/apps/prometheus/

# Revert the bad commit
git revert <bad-commit-sha>
git push

# Flux automatically applies the reverted state
# Or force immediate reconciliation:
flux reconcile helmrelease prometheus -n monitoring
```

No `helm rollback` needed - Git history IS our rollback mechanism.

---

### Kubernetes Concepts

**Q: Explain the kustomization.yaml hierarchy in your setup.**

A: It's a tree structure:
1. **Root** (`kubernetes/kustomization.yaml`): Includes `flux-system` and `apps`
2. **Apps** (`apps/kustomization.yaml`): Includes `prometheus` and `grafana`
3. **Leaf** (`apps/prometheus/kustomization.yaml`): Includes actual resource files (`helmrepository.yaml`, `helmrelease.yaml`)

Kustomize builds bottom-up, collecting all resources. Flux's Kustomization resource points to the root, so everything gets applied.

---

**Q: How does Grafana connect to Prometheus?**

A: Using Kubernetes DNS. In the HelmRelease values:
```yaml
url: http://prometheus-server.monitoring.svc.cluster.local
```

Format: `<service-name>.<namespace>.svc.cluster.local`

Kubernetes DNS resolves this to the prometheus-server Service IP. This works from any namespace because it's a fully qualified domain name.

---

**Q: Why use HelmRelease instead of `helm install`?**

A:
| `helm install` | HelmRelease |
|----------------|-------------|
| Imperative command | Declarative YAML |
| Run once, manual updates | Continuous reconciliation |
| No drift detection | Self-healing |
| State in cluster only | State in Git |
| Rollback via `helm rollback` | Rollback via `git revert` |

HelmRelease gives us GitOps benefits: version control, audit trail, self-healing, and disaster recovery.

---

### GitOps Principles

**Q: What are the core principles of GitOps and how does your setup implement them?**

A:
1. **Declarative**: All resources defined as YAML in `kubernetes/` directory
2. **Versioned**: Everything in Git with full commit history
3. **Pulled automatically**: Flux polls Git every minute, no CI pushes to cluster
4. **Continuously reconciled**: Flux reconciles every 5-10 minutes, reverting drift

---

**Q: How is your setup more secure than traditional CI/CD?**

A:
1. **Cluster credentials never leave cluster**: Flux runs inside GKE, only needs Git read access
2. **GitHub Actions never touches cluster**: It only manages Terraform (infrastructure), not applications
3. **Pull-based**: Cluster pulls from Git; nothing external pushes to cluster
4. **Minimal permissions**: Flux only needs to read Git, not write

If GitHub Actions is compromised, attacker can't directly access the cluster.

---

**Q: How would you recover from a complete cluster loss?**

A:
1. Run terraform-deploy workflow with `apply` → Creates new GKE cluster
2. Terraform bootstraps Flux, pointing to same Git repo
3. Flux reads Git state and deploys everything:
   - HelmRepositories (prometheus-community, grafana)
   - HelmReleases (prometheus, grafana with all values)
4. Full application state restored from Git

Recovery time depends on Terraform + Helm deployments. No manual reconfiguration needed because Git has everything.

---

**Q: What's the difference between Flux's Kustomization and kustomize's kustomization.yaml?**

A: Confusingly similar names, different things:

| Flux Kustomization | kustomize kustomization.yaml |
|-------------------|------------------------------|
| CRD: `kustomize.toolkit.fluxcd.io/v1` | Config file: `kustomize.config.k8s.io/v1beta1` |
| Tells Flux WHAT to apply and HOW OFTEN | Tells kustomize WHICH files to include |
| Has `interval`, `prune`, `sourceRef` | Has `resources`, `patches`, `commonLabels` |
| Runs in cluster | Runs locally or in CI |

In your setup: Flux's Kustomization reads the kustomize kustomization.yaml files to know what manifests to apply.

---

## Quick Reference

### Your Repository Structure

```
gitops/
├── .github/workflows/
│   ├── terraform-deploy.yml     # Push: plan only, Manual: plan OR apply
│   └── terraform-destroy.yml    # Manual only, requires "yes-destroy"
├── terraform/                   # Creates GKE + bootstraps Flux
├── kubernetes/
│   ├── kustomization.yaml       # Root: flux-system + apps
│   ├── flux-system/             # Flux manages itself
│   └── apps/
│       ├── kustomization.yaml   # prometheus + grafana
│       ├── prometheus/
│       │   ├── kustomization.yaml
│       │   ├── helmrepository.yaml  → flux-system namespace
│       │   └── helmrelease.yaml     → monitoring namespace
│       └── grafana/
│           ├── kustomization.yaml
│           ├── helmrepository.yaml  → flux-system namespace
│           └── helmrelease.yaml     → monitoring namespace
└── plan.md, README.md
```

### Key Commands

```bash
# Flux status
flux get all -A

# Force reconciliation
flux reconcile kustomization flux-system --with-source

# View HelmRelease status
flux get helmreleases -n monitoring

# Debug Flux
flux logs --level=error

# View deployed resources
kubectl get all -n monitoring

# Rollback (via Git)
git revert HEAD && git push
```

### Key Intervals in Your Setup

| Resource | Interval | Purpose |
|----------|----------|---------|
| GitRepository | 1m | Poll Git for changes |
| Kustomization | 10m | Reconcile manifests, detect drift |
| HelmRepository | 1h | Check for new chart versions |
| HelmRelease | 5m | Reconcile Helm releases |

---

Good luck with your preparation!
