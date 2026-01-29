# GitOps Study Guide

> **Note**: All examples in this guide are from your actual gitops repository and can be run/tested on your GKE cluster.

## Table of Contents
1. [GitHub Actions](#GitHub%20Actions)
2. [Flux CD](#Flux%20CD)
3. [Kubernetes Concepts](#Kubernetes%20Concepts)
4. [GitOps Principles](#GitOps%20Principles)
5. [Deployment Strategies](#Deployment%20Strategies)
6. [Secrets Management](#Secrets%20Management)
7. [Exposing Applications](#Exposing%20Applications)
8. [Grafana Dashboard Provisioning](#Grafana%20Dashboard%20Provisioning)
9. [Troubleshooting](#Troubleshooting)
10. [Interview Questions](#Interview%20Questions)
11. [Quick Reference](#Quick%20Reference)

---

## GitHub Actions

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

## Flux CD

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
- **Cross-namespace reference**: `namespace: flux-system` in sourceRef is **required** when referencing resources in different namespaces
- **Semver versioning**: `"25.x"` allows automatic minor/patch updates
- **Values override**: Customize chart defaults for your use case
- **Resource limits**: Good practice for cluster resource management
- **Feature toggles**: Enable/disable chart components as needed

**Important note on cross-namespace references:** When a HelmRelease references a HelmRepository (or GitRepository) in a different namespace, you must specify `namespace: flux-system` in the `sourceRef`. If omitted, Flux looks for the source in the same namespace as the HelmRelease and fails.

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

### Flux CLI: Generating Resources (No YAML Memorization Needed!)

You don't need to write Flux YAML from scratch. The `flux create` command generates it for you:

```bash
# Generate HelmRelease for REMOTE chart (from HelmRepository)
flux create helmrelease prometheus \
  --source=HelmRepository/prometheus-community \
  --chart=prometheus \
  --chart-version="25.x" \
  --namespace=monitoring \
  --target-namespace=monitoring \
  --export > helmrelease.yaml

# Generate HelmRelease for LOCAL chart (from GitRepository)
flux create helmrelease hello-gitops \
  --source=GitRepository/flux-system \
  --chart=./charts/hello-gitops \
  --namespace=default \
  --export > helmrelease.yaml

# Generate HelmRepository
flux create source helm prometheus-community \
  --url=https://prometheus-community.github.io/helm-charts \
  --interval=1h \
  --namespace=flux-system \
  --export > helmrepository.yaml

# Generate GitRepository
flux create source git my-repo \
  --url=https://github.com/myorg/myrepo \
  --branch=main \
  --interval=1m \
  --export > gitrepository.yaml

# Generate Kustomization (Flux kind, not kustomize)
flux create kustomization apps \
  --source=GitRepository/flux-system \
  --path=./kubernetes/apps \
  --prune=true \
  --interval=10m \
  --export > kustomization.yaml
```

**Key flag**: `--export` outputs YAML to stdout instead of applying to cluster. Pipe to a file with `> filename.yaml`.

**Quick reference**:

| What you need | Command |
|---------------|---------|
| HelmRelease (remote chart) | `flux create helmrelease NAME --source=HelmRepository/REPO --chart=CHART --export` |
| HelmRelease (local chart) | `flux create helmrelease NAME --source=GitRepository/REPO --chart=./path --export` |
| HelmRepository | `flux create source helm NAME --url=URL --export` |
| GitRepository | `flux create source git NAME --url=URL --branch=BRANCH --export` |
| Kustomization | `flux create kustomization NAME --source=GitRepository/REPO --path=PATH --export` |

---

## Kubernetes Concepts

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

#### Creating kustomization.yaml Files

**For simple aggregation** (what your repo uses), just list resources:

```bash
# Create manually - it's simple enough
cat > kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - prometheus
  - grafana
EOF
```

**Or use kustomize CLI**:

```bash
# Initialize kustomization.yaml in current directory
kustomize init

# Add resources to it
kustomize edit add resource prometheus/
kustomize edit add resource grafana/

# Result: kustomization.yaml with resources listed
```

#### Building Locally

```bash
# See what Kustomize produces (rendered output)
kustomize build kubernetes/

# Or with kubectl (kustomize is built-in)
kubectl kustomize kubernetes/

# Apply directly (but Flux does this automatically)
kubectl apply -k kubernetes/

# Dry-run to see what would be applied
kubectl apply -k kubernetes/ --dry-run=client -o yaml
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

Helm is the package manager for Kubernetes. It uses **charts** (packages of pre-configured Kubernetes resources) to deploy applications.

#### Key Concepts

| Term | Description |
|------|-------------|
| **Chart** | A package containing Kubernetes resource templates and default values |
| **Release** | An instance of a chart running in a cluster |
| **Repository** | A collection of charts (like npm registry or Docker Hub) |
| **Values** | Configuration parameters that customize a chart |
| **Templates** | Kubernetes manifests with Go template placeholders |

---

#### Helm Chart Structure

Every Helm chart follows this structure:

```
mychart/
├── Chart.yaml          # Chart metadata (name, version, description)
├── values.yaml         # Default configuration values
├── charts/             # Dependencies (sub-charts)
├── templates/          # Kubernetes manifest templates
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── _helpers.tpl    # Reusable template snippets
│   └── NOTES.txt       # Post-install instructions
├── .helmignore         # Files to ignore when packaging
└── README.md           # Documentation
```

---

#### Chart.yaml Explained

**File**: `charts/hello-gitops/Chart.yaml` (from your repo)

```yaml
apiVersion: v2                    # Helm 3 uses apiVersion v2
name: hello-gitops                # Chart name (used in templates)
description: A simple Helm chart to demonstrate GitOps with Flux
type: application                 # "application" or "library"

# Chart version - bump this when you change the chart
version: 0.1.0

# Application version - the version of the app being deployed
appVersion: "1.0.0"

keywords:
  - demo
  - gitops
  - learning

maintainers:
  - name: GitOps Learner
    email: learner@example.com
```

**Key fields**:
- `version`: Chart version (SemVer). Bump when chart changes.
- `appVersion`: Version of the application inside. Informational only.
- `type`: `application` (deployable) or `library` (shared templates only)

---

#### values.yaml Explained

Default values that users can override. **File**: `charts/hello-gitops/values.yaml`

```yaml
# Number of pod replicas
replicaCount: 1

# Container image configuration
image:
  repository: nginx
  tag: "1.25-alpine"
  pullPolicy: IfNotPresent

# Custom message displayed on the page
message: "Hello from GitOps!"

# Service configuration
service:
  type: ClusterIP
  port: 80

# Resource limits and requests
resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 50m
    memory: 64Mi
```

**Best practices**:
- Use sensible defaults that work out of the box
- Group related values (image.*, service.*, resources.*)
- Document with comments
- Don't include secrets (use external secrets management)

---

#### Helm Templating Syntax (Go Templates)

Helm uses Go's `text/template` package with additional functions.

##### Basic Syntax

```yaml
# Access values from values.yaml
replicas: {{ .Values.replicaCount }}

# Access chart metadata
name: {{ .Chart.Name }}
version: {{ .Chart.Version }}

# Access release information
release: {{ .Release.Name }}
namespace: {{ .Release.Namespace }}

# String with quotes
image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
```

##### Conditionals

```yaml
# if/else
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
# ... ingress spec
{{- end }}

# if/else with comparison
{{- if eq .Values.service.type "LoadBalancer" }}
  # LoadBalancer specific config
{{- else }}
  # Default config
{{- end }}
```

##### Loops

```yaml
# Range over a list
{{- range .Values.env }}
- name: {{ .name }}
  value: {{ .value | quote }}
{{- end }}

# Range with index
{{- range $index, $host := .Values.ingress.hosts }}
- host: {{ $host }}
{{- end }}
```

##### Built-in Functions

```yaml
# quote - wrap in quotes
value: {{ .Values.message | quote }}
# Result: value: "Hello from GitOps!"

# default - fallback value
image: {{ .Values.image.tag | default "latest" }}

# toYaml - convert to YAML (with nindent for indentation)
resources:
  {{- toYaml .Values.resources | nindent 2 }}

# include - call a named template
labels:
  {{- include "hello-gitops.labels" . | nindent 4 }}

# required - fail if value is empty
name: {{ required "A name is required" .Values.name }}

# trim, lower, upper, title
name: {{ .Values.name | lower | trim }}
```

##### Whitespace Control

```yaml
# {{- removes whitespace before
# -}} removes whitespace after

{{- if .Values.enabled }}
key: value
{{- end }}
```

---

#### _helpers.tpl - Reusable Templates

**File**: `charts/hello-gitops/templates/_helpers.tpl`

```yaml
{{/*
Expand the name of the chart.
*/}}
{{- define "hello-gitops.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncate at 63 chars (Kubernetes name limit).
*/}}
{{- define "hello-gitops.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels - used on all resources
*/}}
{{- define "hello-gitops.labels" -}}
helm.sh/chart: {{ include "hello-gitops.chart" . }}
{{ include "hello-gitops.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels - used for pod selection
*/}}
{{- define "hello-gitops.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hello-gitops.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

**Why use helpers?**
- **DRY**: Define once, use everywhere
- **Consistency**: Same labels/names across all resources
- **Kubernetes compliance**: Handle name length limits (63 chars)

---

#### Template Example: Deployment

**File**: `charts/hello-gitops/templates/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "hello-gitops.fullname" . }}
  labels:
    {{- include "hello-gitops.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "hello-gitops.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "hello-gitops.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 80
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

**Template flow**:
1. `include "hello-gitops.fullname"` → Calls helper, returns `release-name-hello-gitops`
2. `nindent 4` → Adds newline + 4 spaces indent
3. `.Values.replicaCount` → Gets value from values.yaml (or override)
4. `toYaml .Values.resources` → Converts YAML object to string

---

#### Helm Hooks (Lifecycle Events)

Hooks let you run actions at specific points in a release lifecycle.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-db-migrate
  annotations:
    # This is a hook
    "helm.sh/hook": pre-upgrade,pre-install
    "helm.sh/hook-weight": "0"
    "helm.sh/hook-delete-policy": hook-succeeded
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: myapp:migrate
          command: ["./migrate.sh"]
      restartPolicy: Never
```

**Available hooks**:
| Hook | When it runs |
|------|--------------|
| `pre-install` | Before any resources are installed |
| `post-install` | After all resources are installed |
| `pre-upgrade` | Before upgrade begins |
| `post-upgrade` | After upgrade completes |
| `pre-delete` | Before deletion begins |
| `post-delete` | After deletion completes |
| `pre-rollback` | Before rollback begins |
| `post-rollback` | After rollback completes |

**Common uses**:
- Database migrations (pre-upgrade)
- Backup before upgrade (pre-upgrade)
- Cache warming (post-install)
- Cleanup jobs (post-delete)

---

#### Creating Your Own Chart (No YAML Memorization Needed!)

**You don't write Helm charts from scratch.** Use `helm create` to scaffold everything:

```bash
# Create new chart from template - THIS IS HOW YOU START
helm create mychart
```

This generates a complete, working chart with best practices:

```
mychart/
├── Chart.yaml           # Pre-filled with name, version
├── values.yaml          # Common patterns (image, service, resources)
├── charts/              # For dependencies
├── templates/
│   ├── deployment.yaml  # Full deployment with all the template syntax
│   ├── service.yaml     # Service template
│   ├── ingress.yaml     # Ingress (delete if not needed)
│   ├── hpa.yaml         # HorizontalPodAutoscaler (delete if not needed)
│   ├── serviceaccount.yaml
│   ├── _helpers.tpl     # All standard helpers pre-written!
│   ├── NOTES.txt        # Post-install message template
│   └── tests/
│       └── test-connection.yaml
└── .helmignore
```

**Workflow**:
1. `helm create mychart` - Generate scaffold
2. Edit `Chart.yaml` - Update description, version
3. Edit `values.yaml` - Set your defaults
4. Edit/delete templates - Keep what you need, delete the rest
5. `helm lint mychart` - Check for errors
6. `helm template myrelease mychart` - Preview rendered output

```bash
# Validate your chart
helm lint mychart

# Preview what Kubernetes will receive (rendered templates)
helm template myrelease mychart --values custom-values.yaml

# Preview with debug info
helm template myrelease mychart --debug

# Package for distribution (creates .tgz)
helm package mychart
# Creates: mychart-0.1.0.tgz

# Install to cluster (for testing without Flux)
helm install myrelease mychart

# Install with value overrides
helm install myrelease mychart --set replicaCount=3

# Install with values file
helm install myrelease mychart -f production-values.yaml

# Dry-run (see what would happen without applying)
helm install myrelease mychart --dry-run
```

#### IDE Support (Even Less Typing!)

**VSCode Extensions** that help:

| Extension | What it does |
|-----------|--------------|
| **Kubernetes** | Snippets, validation, hover documentation |
| **YAML** (Red Hat) | Schema validation, autocomplete for K8s resources |
| **Helm Intellisense** | Autocomplete for `.Values`, `.Chart`, `.Release` |

With these installed:
- Type `dep` → autocomplete to full Deployment template
- Type `.Values.` → see all available values
- Hover over any field → see documentation
- Red squiggles → syntax errors caught immediately

---

## Tutorial: Creating and Deploying a Custom Helm Chart with Flux

This tutorial walks you through creating your own Helm chart and deploying it via Flux GitOps. By the end, you'll understand the complete process.

### Why Create Custom Charts?

| Use Case | Solution |
|----------|----------|
| Deploy third-party apps (Prometheus, Grafana) | Use **remote charts** from HelmRepository |
| Deploy your own applications | Create **local charts** in your Git repo |
| Customize third-party apps heavily | Fork chart or create wrapper chart |

**Your repo now has both**:
- Remote charts: Prometheus, Grafana (from HelmRepository)
- Local chart: hello-gitops (from GitRepository)

---

### Step 1: Scaffold the Chart with `helm create`

**Don't create files manually!** Use the Helm CLI to generate a complete scaffold:

```bash
# Create the chart scaffold
helm create charts/hello-gitops

# This generates a complete, working chart:
charts/hello-gitops/
├── Chart.yaml           # Pre-filled metadata
├── values.yaml          # Common defaults (image, service, resources)
├── charts/              # For dependencies (empty)
├── templates/
│   ├── deployment.yaml  # Full deployment template
│   ├── service.yaml     # Service template
│   ├── ingress.yaml     # Ingress (we'll delete this)
│   ├── hpa.yaml         # HorizontalPodAutoscaler (we'll delete this)
│   ├── serviceaccount.yaml  # (we'll delete this)
│   ├── _helpers.tpl     # All helpers pre-written!
│   ├── NOTES.txt        # Post-install instructions
│   └── tests/           # (we'll delete this)
└── .helmignore
```

**What you get for free**:
- `_helpers.tpl` with fullname, labels, selectorLabels already defined
- Best-practice templates with proper indentation
- Working defaults that deploy nginx out of the box

---

### Step 2: Clean Up - Delete What You Don't Need

```bash
# Remove templates we don't need for this simple app
rm charts/hello-gitops/templates/ingress.yaml
rm charts/hello-gitops/templates/hpa.yaml
rm charts/hello-gitops/templates/serviceaccount.yaml
rm -rf charts/hello-gitops/templates/tests/

# Now we have a cleaner structure:
charts/hello-gitops/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── _helpers.tpl     # Keep - has useful helpers
    ├── deployment.yaml  # Keep - we'll modify
    ├── service.yaml     # Keep - we'll modify
    └── NOTES.txt        # Keep - modify for our app
```

---

### Step 3: Edit Chart.yaml (Chart Identity)

Open the generated `Chart.yaml` and customize it:

```bash
# Edit the chart metadata
vim charts/hello-gitops/Chart.yaml
```

**Change from generated defaults to**:

```yaml
apiVersion: v2
name: hello-gitops                # Chart name (already correct from helm create)
description: A simple Helm chart to demonstrate GitOps with Flux  # Update this
type: application

version: 0.1.0                    # Keep or update
appVersion: "1.0.0"               # Keep or update
```

**Key points**:
- `name`: Used as default for resource names (already set by `helm create`)
- `version`: Semantic versioning. Bump this when you change the chart.
- `appVersion`: Informational - shows in `helm list`

---

### Step 4: Edit values.yaml (Configuration)

The generated `values.yaml` has common patterns. Edit it for your needs:

```bash
vim charts/hello-gitops/values.yaml
```

**Simplify to what we need**:

```yaml
# These are DEFAULTS that users can override
replicaCount: 1

image:
  repository: nginx
  tag: "1.25-alpine"
  pullPolicy: IfNotPresent

# Custom value - add this for our configmap
message: "Hello from GitOps!"

service:
  type: ClusterIP
  port: 80

resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 50m
    memory: 64Mi
```

**How it works**:
- Templates access these via `{{ .Values.replicaCount }}`, `{{ .Values.image.repository }}`, etc.
- Users override by:
  - `helm install --set replicaCount=3`
  - `helm install -f custom-values.yaml`
  - In Flux: the `values:` section of HelmRelease

---

### Step 5: Review _helpers.tpl (Already Generated!)

**Good news**: `helm create` already generated `_helpers.tpl` with all standard helpers!

Open it to understand what's available:

```bash
cat charts/hello-gitops/templates/_helpers.tpl
```

**What you get for free**:

```yaml
{{/* Already defined by helm create: */}}

{{- define "hello-gitops.name" -}}         {{/* Chart name */}}
{{- define "hello-gitops.fullname" -}}     {{/* release-chartname (truncated to 63 chars) */}}
{{- define "hello-gitops.chart" -}}        {{/* chartname-version */}}
{{- define "hello-gitops.labels" -}}       {{/* Standard Kubernetes labels */}}
{{- define "hello-gitops.selectorLabels" -}} {{/* Labels for pod selection */}}
```

**You don't need to write these** - they're ready to use in your templates with:
```yaml
name: {{ include "hello-gitops.fullname" . }}
labels:
  {{- include "hello-gitops.labels" . | nindent 4 }}
```

---

### Step 6: Modify the Templates

The generated templates are functional but generic. Let's customize them.

#### deployment.yaml - Review and Modify

**File**: `charts/hello-gitops/templates/deployment.yaml`

The generated file already has proper structure. Main changes needed:
- Add volume mount for our configmap (custom HTML)

```bash
vim charts/hello-gitops/templates/deployment.yaml
```

**Key parts to understand** (already generated):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "hello-gitops.fullname" . }}       # Uses helper from _helpers.tpl
  labels:
    {{- include "hello-gitops.labels" . | nindent 4 }} # Uses helper
spec:
  replicas: {{ .Values.replicaCount }}                 # From values.yaml
  selector:
    matchLabels:
      {{- include "hello-gitops.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "hello-gitops.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: {{ .Chart.Name }}                      # From Chart.yaml
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 80
          resources:
            {{- toYaml .Values.resources | nindent 12 }} # Converts YAML object
          # ADD THIS: Mount our custom HTML
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
      # ADD THIS: ConfigMap volume
      volumes:
        - name: html
          configMap:
            name: {{ include "hello-gitops.fullname" . }}
```

**Template syntax explained**:
- `{{ include "hello-gitops.fullname" . }}` - Call helper, returns e.g. "release-hello-gitops"
- `| nindent 4` - Pipe result, add newline + 4 spaces (YAML indentation)
- `{{- ... }}` - The `-` removes whitespace before the tag (cleaner YAML)
- `toYaml .Values.resources` - Converts the resources object to YAML string

#### service.yaml

#### service.yaml - Already Generated!

**File**: `charts/hello-gitops/templates/service.yaml`

The generated service.yaml is already perfect. Just review it:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "hello-gitops.fullname" . }}
  labels:
    {{- include "hello-gitops.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}      # ClusterIP, LoadBalancer, etc.
  ports:
    - port: {{ .Values.service.port }}  # 80
      targetPort: http                   # References container port name
      protocol: TCP
      name: http
  selector:
    {{- include "hello-gitops.selectorLabels" . | nindent 4 }}
```

**No changes needed** - it already uses values from `values.yaml`.

#### configmap.yaml - Create This One (Not Generated)

This is the one file we need to **create** - it's custom for our app:

```bash
vim charts/hello-gitops/templates/configmap.yaml
```

**Create this file**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "hello-gitops.fullname" . }}
  labels:
    {{- include "hello-gitops.labels" . | nindent 4 }}
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head><title>Hello GitOps</title></head>
    <body>
        <h1>{{ .Values.message }}</h1>
        <p>Chart: {{ .Chart.Name }} v{{ .Chart.Version }}</p>
    </body>
    </html>
```

**This is the magic**: The HTML contains `{{ .Values.message }}`. When you change the message in your HelmRelease and push to Git, Flux re-renders the template with the new value.

---

### Step 7: Test the Chart Locally

Before deploying via Flux, validate your chart:

```bash
# Check for syntax errors
helm lint charts/hello-gitops/
# Expected: "1 chart(s) linted, 0 chart(s) failed"

# See the rendered output (what Kubernetes will receive)
helm template myrelease charts/hello-gitops/

# See with custom values
helm template myrelease charts/hello-gitops/ --set message="Testing!"

# Dry-run install (validates against Kubernetes API if connected)
helm install myrelease charts/hello-gitops/ --dry-run
```

**Fix any errors before proceeding.**

---

### Step 8: Create the Flux HelmRelease

Now tell Flux to deploy this chart. **Use the Flux CLI** to generate the YAML:

```bash
# Create the directory
mkdir -p kubernetes/apps/hello-gitops

# Generate HelmRelease using Flux CLI
flux create helmrelease hello-gitops \
  --source=GitRepository/flux-system \
  --chart=./charts/hello-gitops \
  --namespace=default \
  --interval=5m \
  --export > kubernetes/apps/hello-gitops/helmrelease.yaml
```

**Then edit to add your values**:

```bash
vim kubernetes/apps/hello-gitops/helmrelease.yaml
```

**Add the values section at the end**:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: hello-gitops
  namespace: default
spec:
  chart:
    spec:
      chart: ./charts/hello-gitops
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: GitRepository
        name: flux-system
        namespace: flux-system     # ← Note: may need to add this
  interval: 5m0s
  # ADD THIS VALUES SECTION:
  values:
    replicaCount: 1
    message: "Hello from GitOps! Deployed by Flux."
    service:
      type: ClusterIP
```

**Create the kustomization.yaml** (for the hello-gitops directory):

```bash
# Option 1: Simple manual creation
cat > kubernetes/apps/hello-gitops/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrelease.yaml
EOF

# Option 2: Using kustomize CLI
cd kubernetes/apps/hello-gitops
kustomize init
kustomize edit add resource helmrelease.yaml
cd ../../..
```

---

### Step 9: Register with Flux

Add hello-gitops to the apps kustomization so Flux includes it:

```bash
# Option 1: Using kustomize CLI (recommended)
cd kubernetes/apps
kustomize edit add resource hello-gitops
cd ../..

# Option 2: Manual edit
vim kubernetes/apps/kustomization.yaml
# Add "- hello-gitops" to resources
```

**Result** - `kubernetes/apps/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - prometheus
  - grafana
  - hello-gitops    # ← Added by kustomize edit (or manually)
```

---

### Step 10: Commit and Push

```bash
# Stage all the new files
git add charts/ kubernetes/apps/hello-gitops/ kubernetes/apps/kustomization.yaml

# Commit with descriptive message
git commit -m "Add hello-gitops custom Helm chart with Flux deployment"

# Push to trigger Flux reconciliation
git push
```

**What happens next**: Flux detects the push within 1 minute and deploys your chart automatically.

---

### How Flux Deploys Your Local Chart

Here's the complete flow:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. GIT PUSH                                                                 │
│    You commit charts/hello-gitops/ and kubernetes/apps/hello-gitops/        │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 2. FLUX SOURCE CONTROLLER (polls every 1 minute)                            │
│    GitRepository "flux-system" detects new commit                           │
│    Downloads entire repo including charts/ directory                        │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 3. FLUX KUSTOMIZE CONTROLLER                                                │
│    Reads kubernetes/kustomization.yaml                                      │
│    → Follows to kubernetes/apps/kustomization.yaml                          │
│    → Finds kubernetes/apps/hello-gitops/helmrelease.yaml                    │
│    → Applies the HelmRelease resource to cluster                            │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 4. FLUX HELM CONTROLLER                                                     │
│    Sees new HelmRelease "hello-gitops"                                      │
│    Reads chart.spec.chart: "./charts/hello-gitops"                          │
│    Reads chart.spec.sourceRef: GitRepository "flux-system"                  │
│    Fetches chart from Git repo (not HelmRepository!)                        │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 5. HELM RENDERING                                                           │
│    Helm Controller renders templates:                                       │
│    - Reads charts/hello-gitops/values.yaml (defaults)                       │
│    - Merges with HelmRelease.spec.values (overrides)                        │
│    - Processes templates: {{ .Values.message }} → "Hello from GitOps!..."   │
│    - Generates final Kubernetes manifests                                   │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 6. KUBERNETES APPLIES                                                       │
│    Creates in "default" namespace:                                          │
│    - ConfigMap (with rendered HTML)                                         │
│    - Deployment (nginx mounting the ConfigMap)                              │
│    - Service (ClusterIP exposing port 80)                                   │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 7. APP RUNNING                                                              │
│    nginx pod serves your custom HTML page                                   │
│    Access via: kubectl port-forward svc/hello-gitops 8080:80                │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### Making Changes (The GitOps Way)

#### Change 1: Update the message (values change)

```bash
# Edit the HelmRelease values
vim kubernetes/apps/hello-gitops/helmrelease.yaml
```

Change:
```yaml
  values:
    message: "GitOps is awesome!"   # ← New message
```

```bash
git add kubernetes/apps/hello-gitops/helmrelease.yaml
git commit -m "Update hello-gitops message"
git push

# Flux detects change, re-renders templates, updates ConfigMap
# Pod restarts with new HTML
```

#### Change 2: Scale the app (values change)

```bash
vim kubernetes/apps/hello-gitops/helmrelease.yaml
```

Change:
```yaml
  values:
    replicaCount: 3   # ← Scale to 3 replicas
```

```bash
git commit -am "Scale hello-gitops to 3 replicas"
git push
# Deployment scales to 3 pods
```

#### Change 3: Modify the chart itself (chart change)

```bash
# Edit the chart template
vim charts/hello-gitops/templates/configmap.yaml
# Change the HTML styling, add new elements, etc.

# Bump the chart version (important!)
vim charts/hello-gitops/Chart.yaml
# Change version: 0.1.0 → version: 0.2.0

git add charts/
git commit -m "Update hello-gitops chart styling"
git push
# Flux detects chart change, re-deploys
```

---

### Key Differences: Remote vs Local Charts

| Aspect | Remote (Prometheus) | Local (hello-gitops) |
|--------|--------------------|--------------------|
| Chart location | External HTTPS URL | In your Git repo |
| Source type | HelmRepository | GitRepository |
| Chart reference | `chart: prometheus` (name) | `chart: ./charts/hello-gitops` (path) |
| Extra resources | Need HelmRepository YAML | None (uses existing GitRepository) |
| Updates | Controlled by `version: "25.x"` | Automatic on any Git change |
| When to use | Third-party apps | Your own apps |

---

### Hands-On Exercises

**1. Deploy and access** (after pushing):
```bash
# Check Flux deployed it
flux get helmreleases -A

# Wait for pods
kubectl get pods -l app.kubernetes.io/name=hello-gitops -w

# Access the app
kubectl port-forward svc/hello-gitops 8080:80
# Open http://localhost:8080 - see your message!
```

**2. Change message via Git**:
```bash
# Edit HelmRelease values.message
# Commit and push
# Refresh browser - message changes!
```

**3. Create a second chart**:
```bash
# Copy the pattern:
cp -r charts/hello-gitops charts/my-app
# Edit Chart.yaml (change name)
# Edit templates as needed
# Create kubernetes/apps/my-app/helmrelease.yaml
# Add to kubernetes/apps/kustomization.yaml
# Commit and push
```

---

### Tutorial Quick Reference: All CLI Commands

Here's a copy-paste summary of all commands from the tutorial:

```bash
# ============================================
# STEP 1: Create chart scaffold
# ============================================
helm create charts/hello-gitops

# ============================================
# STEP 2: Clean up (remove what you don't need)
# ============================================
rm charts/hello-gitops/templates/ingress.yaml
rm charts/hello-gitops/templates/hpa.yaml
rm charts/hello-gitops/templates/serviceaccount.yaml
rm -rf charts/hello-gitops/templates/tests/

# ============================================
# STEPS 3-6: Edit files
# ============================================
# Edit Chart.yaml, values.yaml, templates as needed
# Create configmap.yaml for custom content

# ============================================
# STEP 7: Validate chart
# ============================================
helm lint charts/hello-gitops/
helm template myrelease charts/hello-gitops/

# ============================================
# STEP 8: Generate Flux HelmRelease
# ============================================
mkdir -p kubernetes/apps/hello-gitops

flux create helmrelease hello-gitops \
  --source=GitRepository/flux-system \
  --chart=./charts/hello-gitops \
  --namespace=default \
  --interval=5m \
  --export > kubernetes/apps/hello-gitops/helmrelease.yaml

# Add values section manually to the generated file

# Create kustomization.yaml
cat > kubernetes/apps/hello-gitops/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrelease.yaml
EOF

# ============================================
# STEP 9: Register with parent kustomization
# ============================================
cd kubernetes/apps && kustomize edit add resource hello-gitops && cd ../..

# ============================================
# STEP 10: Commit and push
# ============================================
git add charts/ kubernetes/apps/hello-gitops/ kubernetes/apps/kustomization.yaml
git commit -m "Add hello-gitops custom Helm chart with Flux deployment"
git push

# ============================================
# VERIFY: Check deployment
# ============================================
flux get helmreleases -A
kubectl get pods -l app.kubernetes.io/name=hello-gitops
kubectl port-forward svc/hello-gitops 8080:80
```

---

#### How Your Setup Uses Helm

| Traditional Helm | Your GitOps Setup |
|-----------------|-------------------|
| `helm repo add prometheus-community ...` | HelmRepository YAML in Git |
| `helm install prometheus ...` | HelmRelease YAML in Git |
| `helm upgrade prometheus ...` | Edit HelmRelease, commit, Flux applies |
| `helm rollback prometheus` | `git revert`, Flux applies |
| `helm create mychart` | Create chart in `charts/` directory |
| `helm install mychart ./mychart` | HelmRelease with GitRepository source |

---

#### Flux HelmRelease vs Terraform Helm Provider

You can deploy Helm charts two ways: **Flux HelmRelease** (what your setup uses) or **Terraform Helm Provider**. Here's when to use each:

##### Comparison Table

| Aspect | Flux HelmRelease | Terraform Helm Provider |
|--------|------------------|------------------------|
| **Model** | Pull-based (GitOps) | Push-based |
| **Where it runs** | Inside the cluster | Outside (CI/CD, local machine) |
| **Credentials** | Cluster has Git read access | CI/CD needs cluster credentials |
| **State storage** | Kubernetes (HelmRelease CRD) | Terraform state file |
| **Drift detection** | Continuous (every 5-10 min) | Only when you run `terraform plan` |
| **Self-healing** | Yes - auto-corrects drift | No - manual `terraform apply` needed |
| **Rollback** | `git revert` + auto-reconcile | `terraform apply` with previous state |
| **Dependencies** | Flux controllers running | Terraform + kubeconfig |
| **Lifecycle** | Continuous reconciliation | One-time apply |

##### When to Use Terraform Helm Provider

```hcl
# Example: Terraform Helm Provider
resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"

  set {
    name  = "controller.replicaCount"
    value = "2"
  }
}
```

**Best for**:
- **Cluster bootstrap**: Installing Flux itself, CNI plugins, critical infrastructure
- **Infrastructure-tied components**: Things that should be created/destroyed with the cluster
- **Cross-resource dependencies**: When Helm release depends on Terraform resources (e.g., install cert-manager after creating DNS zone)
- **One-time setup**: Components you don't expect to change frequently

**Your setup uses this for**: Bootstrapping Flux via `flux_bootstrap_git` Terraform resource

##### When to Use Flux HelmRelease

```yaml
# Example: Flux HelmRelease
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: prometheus
  namespace: monitoring
spec:
  interval: 5m
  chart:
    spec:
      chart: prometheus
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
```

**Best for**:
- **Application deployments**: Prometheus, Grafana, your apps
- **Frequently changing configs**: Easy to update via Git
- **Team collaboration**: Developers can update values via PR
- **Self-healing requirements**: Critical apps that must stay running
- **Multi-environment**: Same chart, different values per environment

**Your setup uses this for**: Prometheus, Grafana, hello-gitops

##### The Hybrid Pattern (Your Setup!)

Your repository demonstrates the **recommended hybrid pattern**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TERRAFORM (Push)                                  │
│  Creates:                                                                   │
│  • GKE cluster                                                             │
│  • GCS bucket for state                                                    │
│  • Flux bootstrap (installs Flux, creates GitRepository)                   │
│                                                                             │
│  Why Terraform: Cluster must exist before Flux can run inside it           │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │ Terraform creates cluster + installs Flux
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           FLUX (Pull)                                       │
│  Manages:                                                                   │
│  • Prometheus (HelmRelease)                                                │
│  • Grafana (HelmRelease)                                                   │
│  • hello-gitops (HelmRelease from local chart)                             │
│  • Future applications...                                                  │
│                                                                             │
│  Why Flux: Continuous reconciliation, self-healing, Git-based workflows    │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Rule of thumb**:
- **Terraform**: Infrastructure that applications run ON (cluster, networking, Flux itself)
- **Flux**: Applications that run IN the cluster

##### Code Comparison: Same Chart, Different Approaches

**Terraform Helm Provider**:
```hcl
resource "helm_release" "prometheus" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  version          = "25.8.0"
  namespace        = "monitoring"
  create_namespace = true

  values = [
    yamlencode({
      server = {
        replicaCount = 1
        persistentVolume = {
          enabled = false
        }
      }
    })
  ]
}
```

**Flux HelmRelease**:
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: flux-system
spec:
  interval: 1h
  url: https://prometheus-community.github.io/helm-charts
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: prometheus
  namespace: monitoring
spec:
  interval: 5m
  chart:
    spec:
      chart: prometheus
      version: "25.x"
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: flux-system
  values:
    server:
      replicaCount: 1
      persistentVolume:
        enabled: false
```

**Key differences in practice**:

| Scenario | Terraform | Flux |
|----------|-----------|------|
| Update replicas | Edit .tf → `terraform apply` | Edit YAML → `git push` |
| Someone deletes pods | Pods stay deleted until `terraform apply` | Flux recreates within minutes |
| View change history | Terraform state + Git history of .tf files | Git history of YAML |
| Rollback | `terraform apply` with old state/code | `git revert` → auto-applies |
| CI/CD needs | Cluster credentials in CI | Only Git access |

##### Interview Question

**Q: Why do you use Terraform for Flux but Flux for Prometheus?**

A: It's about lifecycle and dependencies:

1. **Flux needs a cluster to run in**. Terraform creates the GKE cluster first, then installs Flux into it. You can't use Flux to install Flux - it's a chicken-and-egg problem.

2. **Prometheus is an application**. Once Flux is running, it's better suited for managing applications because:
   - Self-healing: If someone accidentally deletes Prometheus, Flux recreates it
   - GitOps workflow: Developers can update Prometheus config via PR
   - No credentials in CI: Changes flow through Git, not kubectl

3. **Separation of concerns**:
   - Terraform = Infrastructure team manages cluster lifecycle
   - Flux = Application teams manage their deployments via Git

---

#### Useful Helm Commands (for debugging)

```bash
# See what values a release is using
helm get values prometheus -n monitoring

# See all values (including defaults)
helm get values prometheus -n monitoring --all

# See the rendered manifests
helm get manifest prometheus -n monitoring

# List releases
helm list -A

# See release history
helm history prometheus -n monitoring

# Rollback to previous revision (in emergencies only - prefer git revert)
helm rollback prometheus 1 -n monitoring

# Template locally without installing
helm template myrelease ./charts/hello-gitops --values custom.yaml

# Lint chart for errors
helm lint ./charts/hello-gitops

# Show chart info
helm show chart ./charts/hello-gitops
helm show values ./charts/hello-gitops
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

## GitOps Principles

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

## Deployment Strategies

### Overview

Deployment strategies determine how you roll out new versions of applications with different trade-offs for downtime, risk, resource usage, and complexity.

---

### Recreate

**How it works:**
1. Stop all old version pods
2. Start new version pods
3. Wait for new pods to be ready

**Kubernetes Configuration:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 3
  strategy:
    type: Recreate  # No rolling update
  template:
    spec:
      containers:
        - name: myapp
          image: myapp:2.0.0
```

**Pros:**
- Simplest strategy
- No version mixing (never have v1 and v2 running simultaneously)
- No resource overhead (don't need extra pods)
- Good for stateful apps that can't handle multiple versions

**Cons:**
- **Downtime**: Application unavailable during deployment
- High risk: If new version fails, rollback requires another downtime window

**Use when:**
- Application cannot handle multiple versions running
- Stateful applications with incompatible state changes
- Development/testing environments where downtime is acceptable
- Database schema migrations require downtime

**Interview tip:** "Recreate is like turning it off and on again. Simple but has downtime. Use it when you can't have two versions running or when downtime is acceptable."

---

### Rolling Update

**How it works:**
1. Create new pods one at a time (or in batches)
2. Wait for new pod to be ready
3. Terminate old pod
4. Repeat until all pods are new version

**Kubernetes Configuration:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 3
  strategy:
    type: RollingUpdate  # Default strategy
    rollingUpdate:
      maxSurge: 1        # Max 1 extra pod during rollout
      maxUnavailable: 1  # Max 1 pod can be unavailable
  template:
    spec:
      containers:
        - name: myapp
          image: myapp:2.0.0
```

**Pros:**
- Zero downtime
- Gradual rollout reduces blast radius
- Automatic rollback on failure (via readiness probes)
- Resource-efficient (controlled by maxSurge)

**Cons:**
- Both versions run simultaneously (must be compatible)
- Slower than Recreate
- Partial rollout state can complicate debugging
- No traffic control (K8s just distributes based on ready pods)

**Key parameters:**
- `maxSurge`: Max pods above desired count during update (absolute or %)
- `maxUnavailable`: Max pods that can be unavailable during update

**Example calculation** (replicas: 10, maxSurge: 2, maxUnavailable: 1):
- Can have up to 12 pods during rollout (10 + 2)
- Must have at least 9 pods available (10 - 1)

**Use when:**
- Standard web applications
- Versions are backward compatible
- Zero downtime required
- Don't need fine-grained traffic control

**Your setup uses this:** Kubernetes default for all Deployments created by Helm charts (Prometheus, Grafana, hello-gitops).

**Interview tip:** "Rolling update is Kubernetes default. Zero downtime, gradual rollout, but you can't control traffic percentage—just how many pods update at once."

---

### Blue-Green

**How it works:**
1. Deploy new version (Green) alongside old version (Blue)
2. Green runs fully, not receiving traffic
3. Test Green environment
4. Switch traffic from Blue to Green instantly (update Service selector or LoadBalancer)
5. Keep Blue running for quick rollback
6. Terminate Blue after validation period

**Kubernetes Implementation:**
```yaml
# Blue deployment (current)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-blue
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: blue
  template:
    metadata:
      labels:
        app: myapp
        version: blue
    spec:
      containers:
        - name: myapp
          image: myapp:1.0.0
---
# Green deployment (new)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-green
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: green
  template:
    metadata:
      labels:
        app: myapp
        version: green
    spec:
      containers:
        - name: myapp
          image: myapp:2.0.0
---
# Service (initially points to blue)
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp
    version: blue  # Change to "green" to switch traffic
  ports:
    - port: 80
```

**Traffic switch:**
```bash
# Test green deployment directly
kubectl port-forward deployment/myapp-green 8080:80

# Switch traffic (edit service selector)
kubectl patch service myapp -p '{"spec":{"selector":{"version":"green"}}}'

# Instant rollback if needed
kubectl patch service myapp -p '{"spec":{"selector":{"version":"blue"}}}'
```

**Pros:**
- Instant traffic switch (seconds)
- Instant rollback
- Green can be fully tested before traffic switch
- No version mixing
- Zero downtime

**Cons:**
- **2x resource cost** (full Blue + full Green environments)
- Requires infrastructure for two environments
- Database migrations tricky (must be compatible with both versions)
- Wasted resources while both run

**Use when:**
- High-risk deployments requiring extensive pre-production testing
- Need instant rollback capability
- Resource cost is acceptable
- Cannot tolerate any version mixing
- Compliance requires testing in production-like environment

**Flux Implementation:**
```yaml
# Create two HelmReleases
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: myapp-blue
  namespace: production
spec:
  releaseName: myapp-blue
  chart:
    spec:
      chart: ./charts/myapp
  values:
    version: blue
    image:
      tag: "1.0.0"
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: myapp-green
  namespace: production
spec:
  releaseName: myapp-green
  chart:
    spec:
      chart: ./charts/myapp
  values:
    version: green
    image:
      tag: "2.0.0"
```

**Interview tip:** "Blue-Green is instant switchover between two full environments. Great for high-risk deploys, but costs double the resources. Common in financial services."

---

### Canary

**How it works:**
1. Deploy new version to small subset of pods (e.g., 10%)
2. Route small percentage of traffic to new version
3. Monitor metrics (error rate, latency, etc.)
4. Gradually increase traffic to new version (20%, 50%, 100%)
5. Rollback if metrics degrade

**Manual Kubernetes Implementation:**
```yaml
# Stable deployment (90% of traffic)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-stable
spec:
  replicas: 9
  selector:
    matchLabels:
      app: myapp
      track: stable
  template:
    metadata:
      labels:
        app: myapp
        track: stable
    spec:
      containers:
        - name: myapp
          image: myapp:1.0.0
---
# Canary deployment (10% of traffic)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
      track: canary
  template:
    metadata:
      labels:
        app: myapp
        track: canary
    spec:
      containers:
        - name: myapp
          image: myapp:2.0.0
---
# Service selects both (traffic distributed by pod count)
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp  # Matches both stable and canary
  ports:
    - port: 80
```

**Traffic distribution:** With 9 stable pods and 1 canary pod, roughly 10% of requests go to canary (based on load balancing across 10 total pods).

**Pros:**
- Gradual rollout reduces risk
- Real production traffic testing with minimal impact
- Can detect issues early with small user percentage
- Easy rollback (just delete canary deployment)

**Cons:**
- Manual traffic distribution is imprecise (based on pod count)
- No automatic rollback
- Manual monitoring required
- Complex to implement properly without tooling

**Automated Canary with Flagger:**

[Flagger](https://flagger.app/) is a progressive delivery tool that automates canary deployments for Flux.

```yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: myapp
  namespace: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  service:
    port: 80
  analysis:
    interval: 1m
    threshold: 5         # Rollback after 5 failed checks
    maxWeight: 50        # Max 50% traffic to canary
    stepWeight: 10       # Increase by 10% each step
    metrics:
      - name: request-success-rate
        thresholdRange:
          min: 99        # Must maintain 99% success rate
      - name: request-duration
        thresholdRange:
          max: 500       # Max 500ms latency
  webhooks:
    - name: load-test
      url: http://flagger-loadtester/
      metadata:
        cmd: "hey -z 1m -q 10 -c 2 http://myapp-canary/"
```

**How Flagger works:**
1. Detects Deployment change (new image)
2. Creates canary deployment with new version
3. Gradually shifts traffic: 0% → 10% → 20% → 30% → 40% → 50%
4. At each step, checks metrics from Prometheus
5. If metrics good: continue progression
6. If metrics bad: automatic rollback
7. On success: promotes canary to stable, deletes canary deployment

**Use when:**
- High-traffic production applications
- Want to minimize blast radius
- Have metrics/observability in place
- Can afford complexity of canary infrastructure
- Need automated rollback based on metrics

**Flagger + Flux Integration:**
```bash
# Install Flagger via Flux
flux create source helm flagger \
  --url=https://flagger.app \
  --namespace=flux-system \
  --export > kubernetes/apps/flagger/helmrepository.yaml

flux create helmrelease flagger \
  --source=HelmRepository/flagger \
  --chart=flagger \
  --namespace=flux-system \
  --export > kubernetes/apps/flagger/helmrelease.yaml
```

**Interview tip:** "Canary is gradual traffic shifting with automated metrics checks. Manual canary is hard to get right. Flagger automates it with Prometheus integration. Netflix and Google use canary heavily."

---

### A/B Testing

**How it works:**
1. Run two versions simultaneously (A and B)
2. Route traffic based on user attributes (header, cookie, geolocation)
3. Measure business metrics (conversion, engagement)
4. Keep the winning version

**Key difference from Canary:** A/B testing is about **business metrics** and **user segmentation**, not just technical health.

**Implementation (requires Service Mesh or Ingress):**

**With Istio VirtualService:**
```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: myapp
spec:
  hosts:
    - myapp
  http:
    - match:
        - headers:
            user-type:
              exact: premium    # Premium users see version B
      route:
        - destination:
            host: myapp
            subset: version-b
    - route:
        - destination:
            host: myapp
            subset: version-a  # Everyone else sees version A
```

**With Nginx Ingress (cookie-based):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ab
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-by-cookie: "ab_test"
    nginx.ingress.kubernetes.io/canary-by-cookie-value: "version-b"
spec:
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp-version-b
                port:
                  number: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-main
spec:
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp-version-a
                port:
                  number: 80
```

**Pros:**
- Test business hypotheses with real users
- Precise traffic control based on attributes
- Multiple versions can run for extended periods
- Data-driven decision making

**Cons:**
- Requires service mesh or advanced ingress controller
- Complex analytics infrastructure needed
- Operational overhead (multiple versions in production)
- Not about deployment—about feature experimentation

**Use when:**
- Testing UX changes (button color, layout)
- Feature flag rollout to specific user segments
- Need business metrics, not just technical health
- Have service mesh infrastructure

**Interview tip:** "A/B testing is about user segmentation and business metrics, not deployment health. Often confused with canary, but canary is technical rollout, A/B is business experimentation. Requires service mesh like Istio or smart ingress."

---

### Strategy Comparison Table

| Strategy | Downtime | Resource Cost | Rollback Speed | Complexity | Traffic Control | Use Case |
|----------|----------|---------------|----------------|------------|-----------------|----------|
| **Recreate** | Yes | 1x | Slow (redeploy) | Low | N/A | Dev/test, stateful apps |
| **Rolling Update** | No | 1x + small surge | Medium (gradual) | Low | None (pod-based) | Standard web apps |
| **Blue-Green** | No | 2x | Instant | Medium | Instant switch | High-risk deploys |
| **Canary** | No | 1x + canary pods | Fast (delete canary) | High | Gradual % shift | Production apps with metrics |
| **A/B Testing** | No | 1x per variant | N/A (not for rollback) | High | User attribute-based | Feature experimentation |

---

### Implementation Decision Tree

```
Do you need zero downtime?
├─ No → Use Recreate (simplest)
└─ Yes
   ├─ Can versions run together?
   │  ├─ No → Use Blue-Green (instant switch, but 2x cost)
   │  └─ Yes
   │     ├─ Need gradual rollout with metrics?
   │     │  ├─ Yes → Use Canary (with Flagger for automation)
   │     │  └─ No → Use Rolling Update (Kubernetes default)
   │     └─ Need user segmentation for business metrics?
   │        └─ Yes → Use A/B Testing (requires service mesh)
```

---

### Deployment Strategies in Your Setup

**Current state:** Your GitOps setup uses **Rolling Update** (Kubernetes default) for all applications deployed via Helm:
- Prometheus: Rolling update with default settings
- Grafana: Rolling update with default settings
- hello-gitops: Rolling update with default settings

**How to change strategy in HelmRelease:**

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: myapp
  namespace: production
spec:
  chart:
    spec:
      chart: ./charts/myapp
  values:
    # Override deployment strategy
    strategy:
      type: Recreate  # or RollingUpdate
      # rollingUpdate:  # Only for RollingUpdate
      #   maxSurge: 1
      #   maxUnavailable: 0
```

**Note:** This requires your chart's `deployment.yaml` template to respect `{{ .Values.strategy }}`. Most standard charts (including helm create scaffold) support this.

---

### Interview Questions on Deployment Strategies

**Q: What deployment strategy does Kubernetes use by default?**

A: Rolling Update with `maxSurge: 25%` and `maxUnavailable: 25%`. This means during rollout, you can have up to 25% extra pods, and at most 25% can be unavailable.

---

**Q: When would you choose Blue-Green over Canary?**

A:
- **Blue-Green**: When you need instant rollback, can afford 2x resources, and want to fully test the new version before any user sees it. Common in regulated industries (finance, healthcare).
- **Canary**: When you want to expose real users to new version gradually, have good observability, and want to minimize resource overhead.

---

**Q: How would you implement Blue-Green deployments in your GitOps setup?**

A:
1. Create two HelmReleases: `myapp-blue` and `myapp-green`
2. Both reference the same chart but with different values (especially image tag and version label)
3. Create a Service with a selector that matches only one version
4. To switch: update Service selector in Git, Flux reconciles within minutes
5. For instant switch: manually patch the Service, then update Git

Alternatively, use Flagger's Blue-Green mode for automation.

---

**Q: What's the difference between Canary deployments and A/B testing?**

A:
| Aspect | Canary | A/B Testing |
|--------|--------|-------------|
| **Purpose** | Safe rollout, technical validation | Feature experimentation, business validation |
| **Metrics** | Error rate, latency, resource usage | Conversion rate, engagement, revenue |
| **Duration** | Minutes to hours | Days to weeks |
| **Goal** | Deploy new version safely | Choose best feature variant |
| **Rollback** | Yes (if metrics fail) | No rollback—pick winner based on data |
| **Traffic split** | Percentage-based (10%, 50%) | User attribute-based (location, device) |

---

## Secrets Management

### The Challenge: Why Secrets Are Hard in GitOps

GitOps principle: **Everything in Git**. But secrets break this:

```yaml
# THIS IS TERRIBLE (never do this)
apiVersion: v1
kind: Secret
metadata:
  name: database-password
data:
  password: cGFzc3dvcmQxMjM=  # base64 encoded, NOT encrypted
```

**Problems:**
1. **Base64 is encoding, not encryption**: Anyone with Git access can decode
2. **Git history is forever**: Even if you delete the secret, it's in history
3. **Compliance violations**: PCI-DSS, HIPAA, SOC2 prohibit secrets in version control
4. **Access control**: Git access = secret access (no granular permissions)

**The dilemma:**
- GitOps wants everything in Git
- Security wants secrets out of Git

**Solution:** Store encrypted or external references in Git, decrypt only in the cluster.

---

### Solutions Overview

| Solution | How it works | Encryption | Secret storage | Complexity |
|----------|--------------|------------|----------------|------------|
| **Sealed Secrets** | Encrypt secrets, store encrypted in Git | Asymmetric (public/private key) | Git (encrypted) | Low |
| **SOPS** | Encrypt YAML values, store in Git | KMS (AWS/GCP/Azure) or PGP | Git (encrypted) | Medium |
| **External Secrets Operator** | Reference external secret managers | N/A (managed by provider) | Vault, AWS Secrets Manager, GCP Secret Manager | Medium-High |

---

### Sealed Secrets

**Concept:** Encrypt secrets with a public key, store encrypted version in Git. Only the cluster has the private key to decrypt.

**Architecture:**
```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Developer encrypts secret with PUBLIC key                    │
│    kubeseal --cert=public-key.pem < secret.yaml > sealed.yaml   │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Commit SealedSecret (encrypted) to Git                       │
│    apiVersion: bitnami.com/v1alpha1                             │
│    kind: SealedSecret                                           │
│    spec:                                                        │
│      encryptedData:                                             │
│        password: AgBv8dH2... (encrypted, safe to commit)        │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Flux applies SealedSecret to cluster                         │
│    Sealed Secrets controller decrypts with PRIVATE key          │
│    Creates normal Secret in cluster                             │
└─────────────────────────────────────────────────────────────────┘
```

**Installation with Flux:**

```bash
# Create HelmRepository
flux create source helm sealed-secrets \
  --url=https://bitnami-labs.github.io/sealed-secrets \
  --namespace=flux-system \
  --export > kubernetes/apps/sealed-secrets/helmrepository.yaml

# Create HelmRelease
flux create helmrelease sealed-secrets \
  --source=HelmRepository/sealed-secrets \
  --chart=sealed-secrets \
  --namespace=kube-system \
  --export > kubernetes/apps/sealed-secrets/helmrelease.yaml
```

**Install kubeseal CLI:**
```bash
# macOS
brew install kubeseal

# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar xfz kubeseal-0.24.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

**Usage:**

```bash
# 1. Create normal Secret (DO NOT COMMIT THIS)
kubectl create secret generic db-password \
  --from-literal=password=supersecret \
  --dry-run=client -o yaml > secret.yaml

# 2. Fetch public key from cluster
kubeseal --fetch-cert > public-key.pem

# 3. Seal the secret (encrypt)
kubeseal --cert=public-key.pem < secret.yaml > sealed-secret.yaml

# 4. Commit sealed-secret.yaml to Git
git add sealed-secret.yaml
git commit -m "Add sealed database password"
git push

# 5. Flux applies, Sealed Secrets controller decrypts in cluster
# Result: normal Secret "db-password" exists in cluster
```

**SealedSecret YAML example:**

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: db-password
  namespace: production
spec:
  encryptedData:
    password: AgBv8dH2Pq3fJ9... # Long encrypted string (safe in Git)
  template:
    metadata:
      name: db-password
    type: Opaque
```

**After applying, normal Secret is created:**

```bash
$ kubectl get secret db-password -n production -o yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-password
  ownerReferences:
    - apiVersion: bitnami.com/v1alpha1
      kind: SealedSecret
      name: db-password
data:
  password: c3VwZXJzZWNyZXQ=  # base64 encoded "supersecret"
```

**Pros:**
- Simple mental model: encrypt before commit
- No external dependencies (no KMS)
- Works with any Kubernetes cluster
- Fast decryption (local to cluster)

**Cons:**
- Private key is in cluster (if cluster compromised, secrets exposed)
- Rotating encryption key is complex
- No audit trail of secret access
- Secret values not sharable across clusters (each needs re-encryption)

**Use when:**
- Getting started with GitOps secrets
- No cloud KMS available
- Single cluster setup
- Want simplicity over enterprise features

---

### SOPS (Secrets OPerationS) with Flux

**Concept:** Encrypt specific values in YAML files using cloud KMS or PGP. Store encrypted YAML in Git. Flux decrypts using KMS during reconciliation.

**Architecture:**
```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Developer encrypts with SOPS + KMS                           │
│    sops --encrypt --gcp-kms projects/my-project/keyRings/...    │
│    secret.yaml > secret.enc.yaml                                │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Commit encrypted YAML to Git                                 │
│    apiVersion: v1                                               │
│    kind: Secret                                                 │
│    data:                                                        │
│      password: ENC[AES256_GCM,data:xyz...,type:str]  ← encrypted│
│    sops:                                                        │
│      kms:                                                       │
│        - arn: arn:aws:kms:...                                   │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Flux Kustomization decrypts using KMS                        │
│    spec:                                                        │
│      decryption:                                                │
│        provider: sops                                           │
│        secretRef:                                               │
│          name: sops-kms  # KMS credentials                      │
└─────────────────────────────────────────────────────────────────┘
```

**Installation:**

```bash
# Install SOPS CLI
# macOS
brew install sops

# Linux
wget https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops
```

**Setup with GCP KMS:**

```bash
# 1. Create KMS key ring and key
gcloud kms keyrings create sops --location=global
gcloud kms keys create sops-key --location=global --keyring=sops --purpose=encryption

# 2. Create .sops.yaml config (in repo root)
cat > .sops.yaml << EOF
creation_rules:
  - path_regex: kubernetes/.*\.yaml$
    gcp_kms: projects/my-project/locations/global/keyRings/sops/cryptoKeys/sops-key
EOF

# 3. Encrypt a secret
kubectl create secret generic db-password \
  --from-literal=password=supersecret \
  --dry-run=client -o yaml | sops --encrypt /dev/stdin > secret.enc.yaml

# 4. Commit encrypted file
git add secret.enc.yaml .sops.yaml
git commit -m "Add encrypted database password"
```

**Example encrypted file:**

```yaml
apiVersion: v1
kind: Secret
metadata:
    name: db-password
type: Opaque
data:
    password: ENC[AES256_GCM,data:Tr7o1,type:str]
sops:
    kms:
    -   arn: ""
        created_at: "2024-01-15T10:30:00Z"
        enc: CiC...
        gcp_kms: projects/my-project/locations/global/keyRings/sops/cryptoKeys/sops-key
    version: 3.8.1
```

**Configure Flux to decrypt:**

```yaml
# Create ServiceAccount with KMS access (via Workload Identity or Secret)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flux-sops
  namespace: flux-system
  annotations:
    iam.gke.io/gcp-service-account: flux-sops@my-project.iam.gserviceaccount.com
---
# Update Kustomization to use SOPS decryption
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./kubernetes
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  decryption:
    provider: sops
    secretRef:
      name: sops-kms  # Optional: KMS credentials if not using Workload Identity
```

**Edit encrypted files:**

```bash
# Edit in-place (decrypts, opens editor, re-encrypts on save)
sops secret.enc.yaml

# Decrypt to view
sops --decrypt secret.enc.yaml

# Rotate keys (re-encrypt with new KMS key)
sops --rotate --in-place secret.enc.yaml
```

**Pros:**
- Cloud KMS provides enterprise-grade encryption
- Audit trail via KMS (who accessed keys, when)
- Key rotation built-in
- Can encrypt specific fields (not whole file)
- Same encrypted file works across clusters (if KMS access granted)
- PGP option for non-cloud scenarios

**Cons:**
- Requires cloud KMS or PGP key management
- More complex than Sealed Secrets
- KMS API calls add latency (minimal)
- Need to manage KMS permissions

**Use when:**
- Already using cloud provider (AWS/GCP/Azure)
- Need audit trail and compliance
- Multi-cluster with centralized KMS
- Want fine-grained field encryption
- Enterprise security requirements

---

### External Secrets Operator

**Concept:** Store secrets in external secret manager (Vault, AWS Secrets Manager, GCP Secret Manager). Store **reference** in Git. ESO syncs external secret to Kubernetes Secret.

**Architecture:**
```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Store secret in external system (e.g., GCP Secret Manager)   │
│    $ gcloud secrets create db-password --data-file=-             │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Commit ExternalSecret (reference) to Git                     │
│    apiVersion: external-secrets.io/v1beta1                      │
│    kind: ExternalSecret                                         │
│    spec:                                                        │
│      secretStoreRef:                                            │
│        name: gcp-secret-manager                                 │
│      data:                                                      │
│        - secretKey: password                                    │
│          remoteRef:                                             │
│            key: db-password  ← reference, not actual secret     │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. ESO fetches from GCP Secret Manager, creates K8s Secret      │
│    External Secrets Operator polls external system              │
│    Creates/updates Secret in cluster                            │
└─────────────────────────────────────────────────────────────────┘
```

**Installation:**

```yaml
# kubernetes/apps/external-secrets/helmrepository.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: external-secrets
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.external-secrets.io
---
# kubernetes/apps/external-secrets/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: external-secrets
  namespace: external-secrets
spec:
  interval: 5m
  chart:
    spec:
      chart: external-secrets
      sourceRef:
        kind: HelmRepository
        name: external-secrets
        namespace: flux-system
```

**Setup SecretStore (GCP example):**

```yaml
# Configure how to access GCP Secret Manager
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: gcp-secret-manager
  namespace: production
spec:
  provider:
    gcpsm:
      projectID: my-gcp-project
      auth:
        workloadIdentity:
          clusterLocation: us-central1
          clusterName: my-gke-cluster
          serviceAccountRef:
            name: external-secrets-sa
```

**Create ExternalSecret:**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-password
  namespace: production
spec:
  refreshInterval: 1h  # Sync from external system every hour
  secretStoreRef:
    name: gcp-secret-manager
    kind: SecretStore
  target:
    name: db-password  # Name of K8s Secret to create
    creationPolicy: Owner
  data:
    - secretKey: password      # Key in K8s Secret
      remoteRef:
        key: db-password       # Secret name in GCP Secret Manager
```

**Result:** ESO creates this Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-password
  namespace: production
  ownerReferences:
    - apiVersion: external-secrets.io/v1beta1
      kind: ExternalSecret
      name: db-password
data:
  password: c3VwZXJzZWNyZXQ=  # Fetched from GCP Secret Manager
```

**Pros:**
- Centralized secret management (single source of truth)
- Secrets never in Git (even encrypted)
- Native integration with cloud secret managers
- Automatic rotation (when external secret updates)
- Granular access control via IAM
- Audit trail via secret manager
- Works with Vault, AWS, GCP, Azure, 1Password, etc.

**Cons:**
- External dependency (secret manager must be available)
- More complex infrastructure
- Costs (secret manager pricing)
- Network calls to fetch secrets (latency)
- Cluster needs IAM permissions

**Supported backends:**
- AWS Secrets Manager / Parameter Store
- GCP Secret Manager
- Azure Key Vault
- HashiCorp Vault
- 1Password
- Doppler
- Many more...

**Use when:**
- Already using Vault or cloud secret manager
- Need centralized secret management across multiple clusters
- Want automatic secret rotation
- Enterprise with strict secret policies
- Multi-cloud or hybrid cloud

---

### Comparison Summary

| Aspect | Sealed Secrets | SOPS | External Secrets Operator |
|--------|----------------|------|---------------------------|
| **Secret location** | Git (encrypted) | Git (encrypted) | External system |
| **Encryption** | Asymmetric (RSA) | KMS or PGP | N/A (managed externally) |
| **Decryption** | In-cluster controller | Flux with KMS | ESO fetches from external |
| **Key management** | Cluster holds private key | Cloud KMS or PGP | External system IAM |
| **Secret rotation** | Manual (re-seal) | Manual (re-encrypt) | Automatic (when external updates) |
| **Audit trail** | No | Yes (via KMS) | Yes (via secret manager) |
| **Multi-cluster** | Re-encrypt per cluster | Same file, grant KMS access | Same reference, grant IAM access |
| **External dependency** | None | KMS API | Secret manager API |
| **Complexity** | Low | Medium | Medium-High |
| **Cost** | Free | KMS costs | Secret manager costs |

---

### Best Practices for Secrets in GitOps

1. **Never commit plaintext secrets**: Not even in initial commits. Git history is forever.

2. **Use .gitignore for local secret files:**
   ```
   # .gitignore
   secret.yaml
   *.unsealed.yaml
   *.dec.yaml
   ```

3. **Separate secret encryption from secret values:**
   - Developers encrypt secrets with public key (Sealed Secrets) or KMS (SOPS)
   - Developers don't need access to decryption keys or production secret values

4. **Rotation strategy:**
   - **Sealed Secrets**: Re-seal with new public key after controller restart
   - **SOPS**: `sops --rotate` to re-encrypt with new KMS key
   - **ESO**: Rotate in external system, ESO syncs automatically

5. **Least privilege:**
   - Flux ServiceAccount: read-only Git access
   - Secret decryption: only needs KMS decrypt permission (SOPS) or secret manager read (ESO)
   - Developers: encrypt access only, not decrypt

6. **Secret naming conventions:**
   ```
   my-secret.enc.yaml         # SOPS encrypted
   my-secret.sealed.yaml      # Sealed Secret
   my-secret-external.yaml    # ExternalSecret reference
   ```

7. **Don't encrypt entire files with SOPS:**
   ```yaml
   # Bad: metadata encrypted (hard to review PRs)
   apiVersion: ENC[...]

   # Good: only secret data encrypted
   apiVersion: v1
   kind: Secret
   data:
     password: ENC[AES256_GCM,data:xyz,type:str]
   ```

8. **Use different encryption keys per environment:**
   ```yaml
   # .sops.yaml
   creation_rules:
     - path_regex: kubernetes/production/.*
       gcp_kms: projects/prod-project/locations/global/keyRings/sops/cryptoKeys/prod-key
     - path_regex: kubernetes/staging/.*
       gcp_kms: projects/staging-project/locations/global/keyRings/sops/cryptoKeys/staging-key
   ```

9. **Emergency access pattern:**
   - Store sealed secrets controller private key in secure vault
   - Document procedure to restore from backup
   - Test disaster recovery periodically

10. **Secret validation:**
    - Use pre-commit hooks to prevent plaintext secrets
    - Tools: `gitleaks`, `trufflehog`, `detect-secrets`
    ```bash
    # Install pre-commit hook
    pip install pre-commit
    pre-commit install

    # .pre-commit-config.yaml
    repos:
      - repo: https://github.com/trufflesecurity/trufflehog
        rev: v3.63.2
        hooks:
          - id: trufflehog
    ```

---

### Migration Path: From One Solution to Another

**Sealed Secrets → SOPS:**
1. Install SOPS, configure KMS
2. Add `decryption` to Flux Kustomization
3. Create SOPS-encrypted versions of secrets
4. Update Git references
5. Delete SealedSecrets after validation
6. Remove Sealed Secrets controller

**SOPS → External Secrets:**
1. Install ESO, configure SecretStore
2. Migrate secrets to external secret manager
3. Create ExternalSecrets referencing external secrets
4. Remove SOPS-encrypted files after validation
5. Remove `decryption` from Kustomization

**Dual-run during migration:** Both old and new secrets can coexist temporarily (different names) for safe testing.

---

### Your Setup: Adding Secrets Management

**Recommendation for your showcase:** Start with Sealed Secrets (simplicity) or SOPS with GCP KMS (since you're on GCP).

**Quick start with Sealed Secrets:**

```bash
# 1. Add Sealed Secrets via Flux
mkdir -p kubernetes/apps/sealed-secrets

flux create source helm sealed-secrets \
  --url=https://bitnami-labs.github.io/sealed-secrets \
  --namespace=flux-system \
  --export > kubernetes/apps/sealed-secrets/helmrepository.yaml

flux create helmrelease sealed-secrets \
  --source=HelmRepository/sealed-secrets \
  --chart=sealed-secrets \
  --namespace=kube-system \
  --export > kubernetes/apps/sealed-secrets/helmrelease.yaml

# 2. Create kustomization.yaml
cat > kubernetes/apps/sealed-secrets/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrepository.yaml
  - helmrelease.yaml
EOF

# 3. Add to apps kustomization
cd kubernetes/apps && kustomize edit add resource sealed-secrets && cd ../..

# 4. Commit and push
git add kubernetes/apps/sealed-secrets/ kubernetes/apps/kustomization.yaml
git commit -m "Add Sealed Secrets for secret management"
git push

# 5. Wait for deployment, then seal a secret
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=sealed-secrets -n kube-system --timeout=300s

# 6. Create and seal a test secret
echo -n supersecret | kubectl create secret generic test-secret \
  --from-file=password=/dev/stdin \
  --dry-run=client -o yaml | kubeseal -o yaml > test-sealed.yaml

# 7. Commit sealed secret to Git
git add test-sealed.yaml && git commit -m "Add test sealed secret" && git push
```

---

### Old Interview Questions (From Original Section 5)

#### GitHub Actions

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

**Important:** The `sourceRef` in HelmRelease must explicitly specify `namespace: flux-system` to find the HelmRepository in a different namespace. If omitted, Flux looks in the same namespace as the HelmRelease.

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

### Helm Deep Dive

**Q: Explain the structure of a Helm chart.**

A: A Helm chart has this structure:
```
mychart/
├── Chart.yaml        # Metadata: name, version, appVersion, description
├── values.yaml       # Default configuration values
├── templates/        # Kubernetes manifest templates
│   ├── _helpers.tpl  # Reusable template snippets (define/include)
│   ├── deployment.yaml
│   ├── service.yaml
│   └── NOTES.txt     # Post-install instructions
└── charts/           # Dependencies (sub-charts)
```

Key files:
- `Chart.yaml`: Identity of the chart (name, version)
- `values.yaml`: Defaults that users override
- `_helpers.tpl`: DRY - define templates once, include everywhere
- `NOTES.txt`: Shown after install (how to access the app)

---

**Q: Explain this Helm template syntax: `{{ include "myapp.fullname" . | nindent 4 }}`**

A: Breaking it down:
- `include "myapp.fullname" .` - Call the template named "myapp.fullname", passing current context (`.`)
- `|` - Pipe the result to next function
- `nindent 4` - Add newline + 4 spaces indentation

This is used to insert multi-line content (like labels) with proper YAML indentation:
```yaml
metadata:
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
```

Result:
```yaml
metadata:
  labels:
    app.kubernetes.io/name: myapp
    app.kubernetes.io/instance: myrelease
```

---

**Q: What's the difference between `{{ }}` and `{{- }}`?**

A: Whitespace control:
- `{{ }}` - Preserves whitespace
- `{{- }}` - Removes whitespace **before** the tag
- `{{ -}}` - Removes whitespace **after** the tag
- `{{- -}}` - Removes whitespace on both sides

Example:
```yaml
labels:
  {{- include "myapp.labels" . | nindent 2 }}
```

Without `{{-`, you'd get an extra blank line before the labels.

---

**Q: How do you deploy a local chart (from Git) vs a remote chart (from HelmRepository)?**

A: Different `sourceRef` in HelmRelease:

**Remote chart** (Prometheus):
```yaml
chart:
  spec:
    chart: prometheus           # Chart NAME
    sourceRef:
      kind: HelmRepository      # From Helm repo
      name: prometheus-community
```

**Local chart** (hello-gitops):
```yaml
chart:
  spec:
    chart: ./charts/hello-gitops  # Chart PATH
    sourceRef:
      kind: GitRepository         # From Git repo
      name: flux-system
```

Local charts don't need a separate HelmRepository - they use the existing GitRepository that Flux already watches.

---

**Q: What are Helm hooks and when would you use them?**

A: Hooks run at specific lifecycle points:
- `pre-install` / `post-install` - Before/after first install
- `pre-upgrade` / `post-upgrade` - Before/after upgrades
- `pre-delete` / `post-delete` - Before/after uninstall

Common use cases:
- **pre-upgrade**: Database migration, backup
- **post-install**: Seed data, cache warming
- **pre-delete**: Backup before removal

Example:
```yaml
metadata:
  annotations:
    "helm.sh/hook": pre-upgrade
    "helm.sh/hook-delete-policy": hook-succeeded
```

---

**Q: How do you override values when using Flux HelmRelease?**

A: In the `values:` section of HelmRelease:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
spec:
  chart:
    spec:
      chart: prometheus
  values:
    # These override the chart's values.yaml
    server:
      replicaCount: 2
      resources:
        limits:
          memory: 1Gi
```

This is equivalent to:
```bash
helm install prometheus prometheus-community/prometheus \
  --set server.replicaCount=2 \
  --set server.resources.limits.memory=1Gi
```

But declarative and GitOps-managed.

---

**Q: What's `_helpers.tpl` and why use it?**

A: A file containing reusable template definitions. The `_` prefix means Helm won't try to render it as a manifest.

Purpose:
1. **DRY**: Define once, use everywhere
2. **Consistency**: Same names/labels across all resources
3. **Kubernetes compliance**: Handle 63-char name limits

Example:
```yaml
{{- define "myapp.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
```

Usage in templates:
```yaml
name: {{ include "myapp.fullname" . }}
```

---

### Deployment Strategies

**Q: What's the difference between Rolling Update and Blue-Green deployment?**

A:
| Aspect | Rolling Update | Blue-Green |
|--------|----------------|------------|
| **Downtime** | Zero | Zero |
| **Resource cost** | 1x + small surge | 2x (full duplicate) |
| **Version mixing** | Yes (gradual) | No (instant switch) |
| **Rollback speed** | Medium (gradual) | Instant (switch back) |
| **Traffic control** | Pod-based (indirect) | Service selector (direct) |

Rolling Update is Kubernetes default—good for standard apps. Blue-Green is for high-risk deployments needing instant rollback but costs double resources.

---

**Q: When would you use Canary over Blue-Green?**

A:
- **Canary**: When you want to test with a small percentage of real users first, have good metrics/monitoring, and want to minimize blast radius. Common in high-traffic production apps.
- **Blue-Green**: When you need instant switchover, can afford 2x resources, and want full testing before any user exposure. Common in regulated industries.

Canary is gradual risk reduction with metrics-based decisions. Blue-Green is binary switch with instant rollback.

---

**Q: How would you implement Blue-Green deployments in your GitOps setup?**

A: Two approaches:

**Approach 1: Two HelmReleases**
```yaml
# Create myapp-blue and myapp-green HelmReleases
# Use different image tags and version labels
# Service selector points to blue or green
# To switch: edit Service selector in Git, push
```

**Approach 2: Flagger (automated)**
```yaml
# Install Flagger via Flux
# Create Flagger Canary resource with analysis.type: BlueGreen
# Flagger automates traffic switch based on metrics
```

Manual approach gives full control. Flagger automates based on health checks.

---

**Q: Explain how Canary deployments work with Flagger.**

A: Flagger automates progressive delivery:
1. Detects Deployment image change
2. Creates canary deployment with new version
3. Gradually shifts traffic: 0% → 10% → 20% → ... → 50%
4. At each step, queries Prometheus for metrics (error rate, latency)
5. If metrics good: continue progression
6. If metrics bad: automatic rollback
7. On success: promotes canary to primary, deletes canary

This removes manual intervention and ensures metrics-based rollout.

---

### Secrets Management

**Q: How do you handle secrets in GitOps? You can't commit them to Git.**

A: Three main approaches:

**1. Sealed Secrets** (simplest):
- Encrypt secrets with public key (kubeseal)
- Commit encrypted SealedSecret to Git
- Controller in cluster decrypts with private key
- Good for: Single cluster, getting started

**2. SOPS** (enterprise):
- Encrypt YAML values with cloud KMS (AWS/GCP/Azure) or PGP
- Commit encrypted YAML to Git
- Flux decrypts during reconciliation using KMS
- Good for: Multi-cloud, audit requirements, key rotation

**3. External Secrets Operator** (centralized):
- Store secrets in external system (Vault, AWS Secrets Manager, GCP Secret Manager)
- Commit reference (not secret) to Git
- ESO fetches and syncs to Kubernetes Secret
- Good for: Centralized secret management, automatic rotation

**Rule:** Never commit plaintext secrets. Always encrypt or externalize before committing.

---

**Q: What's the difference between Sealed Secrets and SOPS?**

A:
| Aspect | Sealed Secrets | SOPS |
|--------|----------------|------|
| **Encryption** | Asymmetric (RSA) in-cluster | KMS (AWS/GCP/Azure) or PGP |
| **Decryption** | Sealed Secrets controller | Flux with KMS credentials |
| **Key location** | Private key in cluster | Cloud KMS or PGP key |
| **Audit trail** | No | Yes (via KMS logs) |
| **Key rotation** | Manual (complex) | Built-in (`sops --rotate`) |
| **Multi-cluster** | Re-encrypt per cluster | Same file, grant KMS access |

Sealed Secrets: simpler, no external deps, good for single cluster.
SOPS: enterprise-grade, audit trail, better for multi-cluster and compliance.

---

**Q: How would you migrate from plaintext secrets to Sealed Secrets in your setup?**

A:
1. Install Sealed Secrets via Flux HelmRelease
2. For each plaintext secret:
   ```bash
   # Create secret YAML (don't commit)
   kubectl create secret generic my-secret --from-literal=key=value \
     --dry-run=client -o yaml > secret.yaml

   # Seal it
   kubeseal < secret.yaml > sealed-secret.yaml

   # Commit sealed version
   git add sealed-secret.yaml
   ```
3. Delete plaintext secrets from Git (and history: `git filter-branch`)
4. Push changes
5. Flux applies SealedSecrets, controller decrypts to normal Secrets

**Important:** Clean Git history of old plaintext secrets—they're cached forever otherwise.

---

**Q: What are the security benefits of External Secrets Operator vs storing encrypted secrets in Git?**

A:
**External Secrets Operator advantages:**
1. **Secrets never in Git**: Even encrypted secrets aren't in Git. Git compromise doesn't expose secret metadata.
2. **Centralized rotation**: Rotate in secret manager, all clusters sync automatically
3. **Granular IAM**: Fine-grained access control via cloud IAM
4. **Audit trail**: Secret manager logs all access attempts
5. **Compliance**: Meets requirements for storing secrets in certified systems (Vault, AWS Secrets Manager)

**Trade-off:** External dependency. Secret manager outage means secrets don't sync.

---

### Troubleshooting

**Q: A HelmRelease is stuck in "Installing" state. How do you troubleshoot?**

A: Systematic approach:
```bash
# 1. Check HelmRelease status
kubectl describe helmrelease <name> -n <namespace>

# 2. Check intermediate HelmChart
kubectl get helmcharts -n flux-system
kubectl describe helmchart <namespace>-<name> -n flux-system

# 3. Check HelmRepository is ready
flux get sources helm -A

# 4. Check underlying Helm status
helm list -n <namespace>
helm status <name> -n <namespace>

# 5. Check pod status (if Helm installed but pods failing)
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>

# 6. Check controller logs
kubectl logs -n flux-system deploy/helm-controller
```

**Common causes:** HelmRepository URL wrong, chart version doesn't exist, invalid values, resource conflicts, RBAC issues.

---

**Q: How do you prevent unauthorized changes to the cluster in a GitOps setup?**

A: Multiple layers:

**1. Pull-based model:**
- Nothing pushes to cluster from outside
- Only Flux (in-cluster) applies changes
- Attackers can't inject via CI/CD

**2. RBAC on Flux ServiceAccount:**
- Limit what Flux can deploy
- Namespace-scoped permissions
- Use separate ServiceAccounts per Kustomization

**3. Git-based controls:**
- Branch protection: require PR reviews
- CODEOWNERS: require approval from specific teams
- Signed commits: verify commit author

**4. Policy enforcement:**
- Kyverno/OPA Gatekeeper: validate resources before apply
- Example: block privileged pods, require resource limits

**5. Audit logging:**
- Kubernetes audit logs: track all API calls
- Git history: track all changes with author attribution

**Result:** All changes flow through Git with review + approval. Direct kubectl changes are reverted by Flux.

---

**Q: What are the performance implications of Flux reconciliation intervals?**

A: Trade-off between responsiveness and API load:

**Short intervals (1m GitRepository, 5m HelmRelease):**
- **Pros:** Changes applied faster, drift corrected quickly
- **Cons:** More API calls (Git, Kubernetes), higher CPU usage

**Long intervals (10m GitRepository, 30m HelmRelease):**
- **Pros:** Lower resource usage, less API load
- **Cons:** Slower change propagation, drift persists longer

**Your setup:**
- GitRepository: 1m (Git polling - cheap operation)
- Kustomization: 10m (good balance)
- HelmRelease: 5m (good balance)

**Best practices:**
- GitRepository: 1-5m (cheap to poll)
- Kustomization: 5-10m (moderate cost)
- HelmRelease: 5-15m (Helm operations expensive)
- Use `flux reconcile` for immediate deployment (don't wait)

**At scale:** 1000 HelmReleases reconciling every 5m = 200 reconciliations/min. Monitor controller resource usage.

---

**Q: Explain Flux's dependency management with dependsOn.**

A: `dependsOn` ensures resources are applied in order.

**Example:**
```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
spec:
  interval: 10m
  path: ./infrastructure
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: applications
spec:
  interval: 10m
  path: ./applications
  dependsOn:
    - name: infrastructure  # Wait for infrastructure first
```

**Flow:**
1. Flux applies `infrastructure` Kustomization
2. Waits for `infrastructure` to be Ready
3. Then applies `applications` Kustomization

**Use cases:**
- CRDs before CRs (install operator before custom resources)
- Namespaces before resources (create namespace before deploying to it)
- Secrets before apps (ensure secrets exist before app references them)
- Infrastructure before apps (networking, storage, then applications)

**Your setup:** Currently flat (no dependsOn). Could add:
```yaml
# prometheus depends on monitoring namespace existing
dependsOn:
  - name: namespaces
```

---

**Q: How do you monitor GitOps health? What metrics matter?**

A: Key areas to monitor:

**1. Reconciliation health:**
```promql
# Resources not Ready
gotk_reconcile_condition{status="False",type="Ready"}

# Reconciliation duration (detect slowness)
gotk_reconcile_duration_seconds_bucket

# Suspended resources (should be 0)
gotk_suspend_status == 1
```

**2. Git connectivity:**
```promql
# GitRepository fetch failures
sum(rate(gotk_reconcile_condition{kind="GitRepository",status="False"}[5m]))
```

**3. HelmRelease failures:**
```promql
# Failed HelmReleases
count(gotk_reconcile_condition{kind="HelmRelease",status="False"})
```

**4. Controller health:**
```bash
# Controller pod restarts (should be 0)
kubectl get pods -n flux-system
```

**Grafana dashboards:**
- Import 15798 (Flux Cluster Stats)
- Import 15800 (Flux Control Plane)

**Alerts:**
```yaml
- alert: FluxReconciliationFailed
  expr: gotk_reconcile_condition{status="False"} == 1
  for: 10m
  annotations:
    summary: "Flux {{ $labels.kind }}/{{ $labels.name }} failing"
```

**Your setup:** Prometheus already installed. Add these metrics to monitoring!

---

**Q: What happens if Git is unavailable (GitHub outage)?**

A: Designed for this scenario:

**What keeps working:**
- All applications keep running (no impact on uptime)
- Flux reconciles from cached artifacts (Git content, Helm charts)
- Self-healing still works (Flux corrects drift using last known state)

**What stops working:**
- New Git commits can't be fetched
- Can't deploy new versions
- Can't see latest changes

**How long can it last?**
- Indefinitely for existing resources
- Until Git returns for new deployments

**When Git returns:**
```bash
flux reconcile source git flux-system
# Fetches all missed commits, applies changes
```

**Mitigation:**
- **Git mirrors**: Use multiple Git servers (GitHub, GitLab mirror)
- **OCI registries**: Store Flux artifacts in OCI as backup
- **Emergency kubectl**: Direct cluster access (breaks GitOps but restores service)

**Your setup:** If GitHub down for 1 hour, your cluster keeps running fine. When GitHub returns, Flux auto-catches up.

---

**Q: How do you handle HelmRelease rollbacks?**

A: The GitOps way: rollback in Git.

**Preferred method (GitOps):**
```bash
# Find the bad commit
git log --oneline kubernetes/apps/myapp/

# Revert it
git revert <bad-commit-sha>
git push

# Flux automatically rolls back (within reconciliation interval)
# Or force immediate:
flux reconcile helmrelease myapp -n production
```

**Emergency method (imperative):**
```bash
# Helm rollback (bypasses GitOps)
helm history myapp -n production
helm rollback myapp <revision> -n production

# Then update Git to match (restore GitOps)
# Edit helmrelease.yaml to match rolled-back state
git commit -am "Emergency rollback of myapp"
git push
```

**Best practice:** Always prefer Git revert. Emergency Helm rollback is for "production is on fire" scenarios only.

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

## Exposing Applications

### LoadBalancer vs Ingress Trade-offs

When exposing applications in Kubernetes, you have two primary options:

#### LoadBalancer Service

**How it works:**
- Creates a cloud provider LoadBalancer (e.g., Network Load Balancer in GCP)
- Direct L4 (TCP/UDP) load balancing
- Each service gets its own external IP

**Pros:**
- Simple configuration
- Works with any protocol (HTTP, TCP, UDP, gRPC)
- No additional components required
- Direct connection to pods (lower latency)
- SSL/TLS termination at application level

**Cons:**
- Cost scales linearly with services (~$18-20/month per LoadBalancer in GCP)
- No path-based routing
- No hostname-based routing
- Separate IP for each service
- Limited traffic management features

**Example from your repo:**
```yaml
# kubernetes/apps/hello-gitops/helmrelease.yaml
service:
  type: LoadBalancer  # Creates external LB
```

**Best for:**
- Small number of services
- Non-HTTP protocols
- Simple deployments
- Development/testing environments

---

#### Ingress

**How it works:**
- Single LoadBalancer + Ingress Controller (nginx, traefik, etc.)
- L7 (HTTP/HTTPS) routing
- Routes traffic based on hostname/path to backend services

**Pros:**
- Single external IP for multiple services
- Cost-effective at scale (one LoadBalancer for all apps)
- SSL/TLS termination at ingress
- Advanced routing (path-based, header-based)
- Centralized certificate management
- Built-in rate limiting, auth, rewrite rules

**Cons:**
- Requires ingress controller installation
- HTTP/HTTPS only (unless TCP/UDP ingress configured)
- Additional complexity
- Single point of failure (mitigated by HA setup)
- Slight latency overhead from routing layer

**Example:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-gitops
spec:
  type: ClusterIP  # Internal only
  ports:
    - port: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-gitops
spec:
  rules:
    - host: hello.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: hello-gitops
                port:
                  number: 80
```

**Best for:**
- Multiple HTTP/HTTPS services
- Production environments with many apps
- Need for advanced routing
- Centralized SSL management
- Cost optimization

---

#### Decision Matrix

| Scenario | Recommendation |
|----------|----------------|
| 1-3 services, any protocol | LoadBalancer |
| 4+ HTTP services | Ingress |
| Non-HTTP protocol (gRPC, database) | LoadBalancer |
| Need path-based routing | Ingress |
| Budget-conscious | Ingress (for multiple apps) |
| Simplicity > features | LoadBalancer |
| Need centralized SSL | Ingress |

---

### Your Setup

In this GitOps showcase:
- **Grafana**: LoadBalancer (easy access to monitoring UI)
- **hello-gitops**: LoadBalancer (demonstration simplicity)
- **Prometheus**: ClusterIP (internal metrics collection only)

**Cost impact:** 2 LoadBalancers = ~$36-40/month + nodes (~$49/month) = ~$85-89/month total

**Production alternative:** Use 1 Ingress Controller with LoadBalancer + 2 Ingress resources = ~$18-20/month savings

---

## Grafana Dashboard Provisioning

### Overview

Grafana supports automatic dashboard provisioning via:
1. **Dashboard Providers**: Configure where/how to load dashboards
2. **Dashboards**: Specify which dashboards to import

When using Helm, this is configured in the `values` section of the HelmRelease.

---

### How It Works

**Step 1: Define Dashboard Provider**

Tells Grafana where to find dashboard JSON files:

```yaml
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: 'default'
        orgId: 1
        folder: ''  # Root folder, or specify folder name
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default
```

**Step 2: Define Dashboards**

Specify which dashboards to download from Grafana.com:

```yaml
dashboards:
  default:  # Matches provider name
    my-dashboard:
      gnetId: 7249          # Dashboard ID from grafana.com
      revision: 1            # Dashboard version
      datasource: Prometheus # Default datasource to use
```

---

### Your Actual Configuration

**File:** `kubernetes/apps/grafana/helmrelease.yaml`

```yaml
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default

dashboards:
  default:
    kubernetes-cluster-monitoring:
      gnetId: 7249   # Kubernetes Cluster Monitoring
      revision: 1
      datasource: Prometheus
    node-exporter-full:
      gnetId: 1860   # Node Exporter Full
      revision: 36
      datasource: Prometheus
    kubernetes-pods:
      gnetId: 6417   # Kubernetes Pods
      revision: 1
      datasource: Prometheus
    kubernetes-cluster-overview:
      gnetId: 315    # Kubernetes Cluster Overview
      revision: 3
      datasource: Prometheus
```

---

### Community Dashboards Included

| Dashboard ID | Name | What It Shows |
|--------------|------|---------------|
| 7249 | Kubernetes Cluster Monitoring | Cluster-level metrics: CPU, memory, network usage across nodes |
| 1860 | Node Exporter Full | Detailed node metrics: CPU, memory, disk I/O, network, filesystem |
| 6417 | Kubernetes Pods | Pod-level metrics: container CPU/memory, restarts, status |
| 315 | Kubernetes Cluster Overview | High-level cluster health: pods, deployments, resource quotas |

---

### How to Find Dashboard IDs

1. Browse [grafana.com/dashboards](https://grafana.com/grafana/dashboards/)
2. Search for your tech stack (e.g., "Kubernetes", "PostgreSQL", "nginx")
3. Copy the dashboard ID from the URL: `grafana.com/grafana/dashboards/7249` → ID: `7249`
4. Note the latest revision number (or omit for latest)

---

### Adding More Dashboards

To add a dashboard:

1. Find the dashboard ID on grafana.com
2. Edit `kubernetes/apps/grafana/helmrelease.yaml`
3. Add entry under `dashboards.default`:

```yaml
dashboards:
  default:
    # ... existing dashboards ...
    nginx-ingress:
      gnetId: 9614
      revision: 1
      datasource: Prometheus
```

4. Commit and push - Flux reconciles automatically
5. Dashboards appear in Grafana within ~1 minute

---

### Troubleshooting

**Dashboard not appearing?**
```bash
# Check Grafana logs
kubectl logs -n monitoring deployment/grafana

# Check ConfigMap (dashboards stored here)
kubectl get cm -n monitoring | grep dashboard

# Force Flux reconciliation
flux reconcile helmrelease grafana -n monitoring
```

**Wrong datasource?**
- Ensure `datasource: Prometheus` matches your datasource name
- Check datasource config in `datasources.yaml` section

---

## Troubleshooting

### Overview

Troubleshooting Flux and GitOps deployments requires understanding the reconciliation loop and knowing where to look when things go wrong.

**The Flux reconciliation flow:**
```
GitRepository → Kustomization → HelmRelease → Kubernetes Resources
     ↓              ↓                ↓                ↓
  Source        Kustomize        Helm            Actual
Controller     Controller      Controller         Pods
```

Each component can fail independently. Troubleshooting means identifying which layer is broken.

---

### Diagnostic Commands Quick Reference

```bash
# Overview of all Flux resources
flux get all -A

# Check specific resource types
flux get sources git -A          # GitRepository status
flux get sources helm -A         # HelmRepository status
flux get kustomizations -A       # Kustomization status
flux get helmreleases -A         # HelmRelease status

# Detailed status of specific resource
flux get helmrelease prometheus -n monitoring
kubectl describe helmrelease prometheus -n monitoring

# Reconcile immediately (don't wait for interval)
flux reconcile source git flux-system
flux reconcile kustomization flux-system --with-source
flux reconcile helmrelease prometheus -n monitoring

# View logs
flux logs --level=error                           # All errors
flux logs --kind=HelmRelease --name=prometheus    # Specific resource
kubectl logs -n flux-system deploy/helm-controller -f
kubectl logs -n flux-system deploy/source-controller -f
kubectl logs -n flux-system deploy/kustomize-controller -f

# Events
kubectl get events -n flux-system --sort-by='.lastTimestamp'
kubectl get events -n monitoring --sort-by='.lastTimestamp'

# Suspend/resume (for maintenance)
flux suspend helmrelease prometheus -n monitoring
flux resume helmrelease prometheus -n monitoring
```

---

### Common Flux Issues and Solutions

#### Issue 1: GitRepository Not Fetching

**Symptoms:**
```bash
$ flux get sources git
NAME        READY   MESSAGE
flux-system False   failed to checkout and determine revision: unable to clone: authentication required
```

**Diagnosis:**
```bash
# Check GitRepository details
kubectl describe gitrepository flux-system -n flux-system

# Look for authentication errors in events
kubectl get events -n flux-system | grep flux-system

# Check if secret exists
kubectl get secret flux-system -n flux-system

# View secret (check if token is present)
kubectl get secret flux-system -n flux-system -o yaml
```

**Common causes:**
1. **Invalid GitHub token**: Token expired or lacks permissions
2. **Wrong repository URL**: Typo in URL or repo doesn't exist
3. **Network issues**: Cluster can't reach GitHub (firewall, DNS)
4. **Branch doesn't exist**: Tracking non-existent branch

**Solutions:**
```bash
# 1. Regenerate GitHub token
# Go to GitHub → Settings → Developer settings → Personal access tokens
# Create new token with "repo" scope
# Update secret:
kubectl create secret generic flux-system \
  --from-literal=username=git \
  --from-literal=password=<new-token> \
  -n flux-system \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. Fix repository URL
kubectl edit gitrepository flux-system -n flux-system
# Update spec.url to correct value

# 3. Check branch
kubectl edit gitrepository flux-system -n flux-system
# Ensure spec.ref.branch matches your default branch (main/master)

# 4. Force reconcile
flux reconcile source git flux-system
```

**Note for your setup:** Terraform bootstrap creates the flux-system secret. If recreating manually, ensure token has same permissions.

---

#### Issue 2: Kustomization Build Failures

**Symptoms:**
```bash
$ flux get kustomizations
NAME        READY   MESSAGE
flux-system False   kustomization build failed: accumulating resources: accumulation err='accumulating resources from 'apps': ...
```

**Diagnosis:**
```bash
# Get detailed error
kubectl describe kustomization flux-system -n flux-system

# Build locally to see exact error
cd /path/to/gitops
kustomize build kubernetes/

# Check for common kustomize issues
kubectl kustomize kubernetes/
```

**Common causes:**
1. **Invalid YAML**: Syntax errors, incorrect indentation
2. **Missing files**: kustomization.yaml references non-existent files
3. **Invalid kustomization.yaml**: Wrong resources list, typos
4. **Duplicate resources**: Same resource defined multiple times

**Solutions:**
```bash
# 1. Validate YAML syntax
yamllint kubernetes/

# 2. Test kustomize build locally
kustomize build kubernetes/ > /tmp/output.yaml
# Review /tmp/output.yaml for issues

# 3. Check file paths in kustomization.yaml
cat kubernetes/apps/kustomization.yaml
# Ensure all resources exist:
ls -la kubernetes/apps/prometheus/
ls -la kubernetes/apps/grafana/

# 4. Fix and commit
vim kubernetes/apps/kustomization.yaml
git commit -am "Fix kustomization.yaml"
git push
flux reconcile kustomization flux-system --with-source
```

**Prevention:**
- Use `kustomize build` locally before committing
- CI/CD validation: `kustomize build kubernetes/ > /dev/null` in GitHub Actions
- IDE plugins for YAML validation

---

#### Issue 3: HelmRelease Stuck in "Installing" State

**Symptoms:**
```bash
$ flux get helmreleases -n monitoring
NAME       READY   MESSAGE
prometheus False   HelmChart 'flux-system/monitoring-prometheus' is not ready
```

**Diagnosis:**
```bash
# Check HelmRelease
kubectl describe helmrelease prometheus -n monitoring

# Check HelmChart (intermediate resource)
kubectl get helmcharts -n flux-system
kubectl describe helmchart monitoring-prometheus -n flux-system

# Check if chart exists in HelmRepository
flux get sources helm -A
kubectl describe helmrepository prometheus-community -n flux-system

# Check underlying Helm release
helm list -n monitoring
helm status prometheus -n monitoring
```

**Common causes:**
1. **HelmRepository not ready**: Chart repo URL wrong or unreachable
2. **Chart version doesn't exist**: Specified version not in repo
3. **Invalid values**: Chart fails to render with provided values
4. **Resource conflicts**: Trying to create resource that already exists
5. **Insufficient permissions**: ServiceAccount lacks RBAC permissions

**Solutions:**
```bash
# 1. Fix HelmRepository
kubectl edit helmrepository prometheus-community -n flux-system
# Verify URL: https://prometheus-community.github.io/helm-charts
flux reconcile source helm prometheus-community -n flux-system

# 2. Check chart version exists
helm search repo prometheus-community/prometheus --versions
# Update HelmRelease with valid version

# 3. Test values locally
helm template prometheus prometheus-community/prometheus \
  -f /tmp/values.yaml \
  --dry-run
# Fix values if errors

# 4. Delete conflicting resources
kubectl delete deployment prometheus-server -n monitoring
# Then reconcile HelmRelease

# 5. Check RBAC (if using restricted ServiceAccount)
kubectl auth can-i create deployments -n monitoring --as=system:serviceaccount:flux-system:helm-controller
```

**Force clean restart:**
```bash
# Suspend HelmRelease
flux suspend helmrelease prometheus -n monitoring

# Delete Helm release
helm uninstall prometheus -n monitoring

# Resume HelmRelease (Flux reinstalls)
flux resume helmrelease prometheus -n monitoring
```

---

#### Issue 4: HelmRelease Stuck in "Upgrading" State

**Symptoms:**
```bash
$ flux get helmreleases -n monitoring
NAME       READY   MESSAGE
prometheus False   Helm upgrade failed: timed out waiting for the condition
```

**Diagnosis:**
```bash
# Check HelmRelease
kubectl describe helmrelease prometheus -n monitoring

# Check Helm status
helm status prometheus -n monitoring

# Check if pods are failing
kubectl get pods -n monitoring
kubectl describe pod prometheus-server-xxx -n monitoring
kubectl logs -n monitoring prometheus-server-xxx

# Check events
kubectl get events -n monitoring --sort-by='.lastTimestamp'
```

**Common causes:**
1. **Pods failing readiness/liveness probes**: New version unhealthy
2. **Resource limits too low**: Pods OOMKilled or CPU throttled
3. **Image pull failures**: Wrong image tag or registry auth issues
4. **PVC mount issues**: Persistent volume problems
5. **Init containers failing**: Pre-start tasks not completing

**Solutions:**
```bash
# 1. Check pod status
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
kubectl describe pod <pod-name> -n monitoring

# 2. Check logs
kubectl logs -n monitoring <pod-name>
kubectl logs -n monitoring <pod-name> --previous  # Previous crashed pod

# 3. Check image pull
kubectl get events -n monitoring | grep -i pull
# If ImagePullBackOff, verify image exists:
docker pull <image:tag>

# 4. Increase resources in HelmRelease values
# Edit kubernetes/apps/prometheus/helmrelease.yaml
spec:
  values:
    server:
      resources:
        limits:
          memory: 1Gi  # Increase from 512Mi
        requests:
          memory: 512Mi

# 5. Rollback via Git
git log --oneline kubernetes/apps/prometheus/
git revert <bad-commit>
git push
```

**Emergency rollback:**
```bash
# Helm rollback (bypasses GitOps - use only in emergency)
helm history prometheus -n monitoring
helm rollback prometheus <revision-number> -n monitoring

# Then fix Git to match
# And reconcile to restore GitOps control
flux reconcile helmrelease prometheus -n monitoring
```

---

#### Issue 5: HelmRelease in "Failed" State

**Symptoms:**
```bash
$ flux get helmreleases -n monitoring
NAME       READY   MESSAGE
grafana    False   Helm install failed: rendered manifests contain a resource that already exists
```

**Diagnosis:**
```bash
# Full error details
kubectl describe helmrelease grafana -n monitoring

# Check if resources already exist
kubectl get all -n monitoring -l app.kubernetes.io/name=grafana

# Check Helm release
helm list -n monitoring
helm status grafana -n monitoring
```

**Common causes:**
1. **Resource already exists**: Previous install didn't clean up
2. **Helm release in bad state**: Partial install left artifacts
3. **CRD conflicts**: CRDs from other sources conflict
4. **Namespace issues**: Wrong namespace or namespace doesn't exist

**Solutions:**
```bash
# 1. Clean up existing resources
kubectl delete all -n monitoring -l app.kubernetes.io/name=grafana
# Be careful: this deletes everything with that label

# 2. Delete Helm release metadata
helm uninstall grafana -n monitoring

# 3. Reconcile HelmRelease (fresh install)
flux reconcile helmrelease grafana -n monitoring

# 4. If namespace missing, create it
kubectl create namespace monitoring

# 5. Nuclear option: suspend, clean, resume
flux suspend helmrelease grafana -n monitoring
kubectl delete helmrelease grafana -n monitoring
# Remove from Git temporarily, push, re-add, push
flux resume helmrelease grafana -n monitoring
```

---

#### Issue 6: Reconciliation Not Happening

**Symptoms:**
- Made Git changes but cluster not updating
- `flux get all` shows Ready but old revision

**Diagnosis:**
```bash
# Check if Flux controllers are running
kubectl get pods -n flux-system

# Check controller logs
kubectl logs -n flux-system deploy/source-controller
kubectl logs -n flux-system deploy/kustomize-controller
kubectl logs -n flux-system deploy/helm-controller

# Check resource intervals
flux get sources git flux-system
# Shows: next reconciliation in 30s, etc.

# Check if suspended
flux get kustomizations -A
flux get helmreleases -A
# Look for "Suspended: True"
```

**Common causes:**
1. **Controllers crashed**: Flux pods not running
2. **Resource suspended**: Manual suspension active
3. **Interval too long**: Not patient enough (wait for interval)
4. **Webhook not configured**: Using webhooks but misconfigured

**Solutions:**
```bash
# 1. Restart Flux controllers
kubectl rollout restart -n flux-system deployment/source-controller
kubectl rollout restart -n flux-system deployment/kustomize-controller
kubectl rollout restart -n flux-system deployment/helm-controller

# 2. Resume suspended resources
flux resume kustomization flux-system
flux resume helmrelease <name> -n <namespace>

# 3. Force immediate reconciliation
flux reconcile source git flux-system
flux reconcile kustomization flux-system --with-source
flux reconcile helmrelease <name> -n <namespace>

# 4. Check Flux health
flux check
# Should show: ✔ all checks passed
```

---

#### Issue 7: Authentication Errors (Git)

**Symptoms:**
```
authentication required
unable to clone: remote: Repository not found
```

**Diagnosis:**
```bash
# Check GitRepository
flux get sources git -A

# Check secret
kubectl get secret flux-system -n flux-system -o yaml

# Decode token (check if valid)
kubectl get secret flux-system -n flux-system -o jsonpath='{.data.password}' | base64 -d
# Copy token, test manually:
# curl -H "Authorization: token <TOKEN>" https://api.github.com/repos/<owner>/<repo>
```

**Solutions:**
```bash
# 1. Verify token has correct permissions
# GitHub → Settings → Developer settings → Personal access tokens
# Needs: repo (full repo access)

# 2. Recreate secret with new token
kubectl delete secret flux-system -n flux-system
kubectl create secret generic flux-system \
  --from-literal=username=git \
  --from-literal=password=<new-token> \
  -n flux-system

# 3. Reconcile
flux reconcile source git flux-system
```

---

#### Issue 8: Authentication Errors (Helm Repo)

**Symptoms:**
```
failed to fetch Helm repository index: Get "https://...": dial tcp: lookup ... no such host
failed to fetch Helm repository index: 401 Unauthorized
```

**Diagnosis:**
```bash
# Check HelmRepository
flux get sources helm -A
kubectl describe helmrepository <name> -n flux-system

# Test URL manually
curl -I https://prometheus-community.github.io/helm-charts/index.yaml

# For private repos, check secret
kubectl get secret <helm-secret> -n flux-system -o yaml
```

**Solutions:**
```bash
# 1. Fix HelmRepository URL
kubectl edit helmrepository <name> -n flux-system
# Ensure URL is correct (usually ends in /helm-charts or /)

# 2. For private repos, add secret
kubectl create secret generic helm-auth \
  --from-literal=username=<user> \
  --from-literal=password=<password> \
  -n flux-system

# Update HelmRepository
kubectl edit helmrepository <name> -n flux-system
# Add:
spec:
  secretRef:
    name: helm-auth

# 3. Check network connectivity
kubectl run curl --image=curlimages/curl -it --rm -- \
  curl -I https://prometheus-community.github.io/helm-charts/index.yaml
```

---

### How to Read Flux Logs

**Log levels:**
```bash
# Error only (recommended for troubleshooting)
flux logs --level=error

# Info (includes reconciliation events)
flux logs --level=info

# Debug (verbose, shows all operations)
flux logs --level=debug
```

**Filter by resource type:**
```bash
# GitRepository logs
flux logs --kind=GitRepository --name=flux-system

# HelmRelease logs
flux logs --kind=HelmRelease --name=prometheus

# All HelmReleases
flux logs --kind=HelmRelease
```

**Directly from controllers:**
```bash
# Source controller (GitRepository, HelmRepository)
kubectl logs -n flux-system deploy/source-controller -f

# Kustomize controller (Kustomization)
kubectl logs -n flux-system deploy/kustomize-controller -f

# Helm controller (HelmRelease)
kubectl logs -n flux-system deploy/helm-controller -f

# Follow logs in real-time
kubectl logs -n flux-system deploy/helm-controller -f --tail=50
```

**Log analysis patterns:**

**Success pattern:**
```
{"level":"info","ts":"2024-01-15T10:30:00.123Z","msg":"Reconciliation finished","reconciler kind":"HelmRelease","name":"prometheus","namespace":"monitoring","revision":"1.0.0"}
```

**Error pattern:**
```
{"level":"error","ts":"2024-01-15T10:30:00.123Z","msg":"Reconciliation failed","reconciler kind":"HelmRelease","name":"prometheus","namespace":"monitoring","error":"Helm install failed: rendered manifests contain a resource that already exists"}
```

---

### Common Mistakes and How to Avoid Them

#### Mistake 1: Wrong Namespace References

**Problem:**
```yaml
# HelmRelease in monitoring namespace
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: prometheus
  namespace: monitoring
spec:
  chart:
    spec:
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        # MISSING: namespace: flux-system
```

**Error:** HelmRelease looks for HelmRepository in monitoring namespace, doesn't find it.

**Fix:**
```yaml
spec:
  chart:
    spec:
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: flux-system  # ← Add this!
```

**Rule:** When `sourceRef` points to a resource in a different namespace, always specify `namespace`.

---

#### Mistake 2: Forgetting to Add Resources to Kustomization

**Problem:**
```bash
# Created new app directory
mkdir -p kubernetes/apps/myapp
# Created HelmRelease
vim kubernetes/apps/myapp/helmrelease.yaml
# Committed and pushed
git add kubernetes/apps/myapp/ && git commit && git push
# Nothing happens!
```

**Why:** Parent `kubernetes/apps/kustomization.yaml` doesn't include `myapp`.

**Fix:**
```bash
# Add to parent kustomization
cd kubernetes/apps
kustomize edit add resource myapp
git commit -am "Add myapp to kustomization" && git push
```

**Prevention:** Always update parent kustomization.yaml when adding new directories.

---

#### Mistake 3: Using Relative Paths in Git

**Problem:**
```yaml
# In kubernetes/apps/prometheus/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base/prometheus  # Relative path to non-existent directory
```

**Error:** `accumulating resources: accumulation err='accumulating resources from '../../base/prometheus': evalsymlink failure`

**Fix:** Use correct relative paths or keep structure flat.

**Best practice:** Keep structure simple as in your setup—each app is self-contained.

---

#### Mistake 4: Modifying Resources Directly with kubectl

**Problem:**
```bash
# "Quick fix" directly on cluster
kubectl edit deployment prometheus-server -n monitoring
# Change replicas from 1 to 2
# Works temporarily!
```

**What happens:** Next reconciliation (within 10 minutes), Flux reverts to Git state (replicas: 1).

**Right way:**
```bash
# Edit in Git
vim kubernetes/apps/prometheus/helmrelease.yaml
# Change replicaCount in values
git commit -am "Scale Prometheus to 2 replicas"
git push
# Flux applies within 1 minute
```

**Exception:** Emergency fixes are okay, but **immediately follow up with Git commit** to match.

---

#### Mistake 5: Not Checking HelmChart Intermediate Resource

**Problem:** HelmRelease shows cryptic error, hard to debug.

**What to check:**
```bash
# HelmRelease creates a HelmChart
kubectl get helmcharts -n flux-system
kubectl describe helmchart <namespace>-<helmrelease-name> -n flux-system

# HelmChart errors are often more detailed
```

**Example:**
```bash
# HelmRelease error
Error: Helm install failed

# HelmChart error (more specific)
Error: chart requires kubeVersion: >=1.25.0 which is incompatible with Kubernetes v1.24.0
```

---

#### Mistake 6: Ignoring Resource Limits

**Problem:** Helm chart deployed without resource limits specified.

**What happens:**
- Development: Works fine (small cluster)
- Production: OOMKilled, CPU throttling, cluster instability

**Best practice:** Always specify in HelmRelease values:
```yaml
values:
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 256Mi
```

**Your setup:** Already does this for Prometheus and Grafana. Good!

---

#### Mistake 7: Not Testing Locally Before Committing

**Problem:** Push broken YAML, Flux fails, have to debug in cluster.

**Better workflow:**
```bash
# Before committing
kustomize build kubernetes/ > /dev/null && echo "OK" || echo "FAILED"

# Validate specific HelmRelease
helm template test ./charts/myapp --values /tmp/test-values.yaml

# Lint Helm chart
helm lint ./charts/myapp

# Validate YAML syntax
yamllint kubernetes/
```

**Add to GitHub Actions:**
```yaml
# .github/workflows/validate.yml
name: Validate
on: [pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: azure/setup-kubectl@v3
      - run: kubectl kustomize kubernetes/ > /dev/null
```

---

### Emergency Debugging Checklist

When everything is broken and you don't know where to start:

```bash
# 1. Check Flux controllers are running
kubectl get pods -n flux-system
# All should be Running

# 2. Check Flux can reach Git
flux get sources git -A
# Should show Ready: True

# 3. Check Kustomizations
flux get kustomizations -A
# Should show Ready: True

# 4. Check HelmRepositories
flux get sources helm -A
# Should show Ready: True

# 5. Check HelmReleases
flux get helmreleases -A
# Identify which are False

# 6. Describe the failed HelmRelease
kubectl describe helmrelease <name> -n <namespace>
# Read the Events and Conditions

# 7. Check underlying pods
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>

# 8. Check recent events
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20

# 9. Force reconciliation
flux reconcile kustomization flux-system --with-source
flux reconcile helmrelease <name> -n <namespace>

# 10. If still stuck, check controller logs
kubectl logs -n flux-system deploy/helm-controller --tail=100
```

---

### Monitoring Flux Health (Proactive)

**Set up alerts:**

Install Prometheus + Alertmanager (you have Prometheus):

```yaml
# Alert when Flux reconciliation fails
- alert: FluxReconciliationFailure
  expr: |
    gotk_reconcile_condition{status="False",type="Ready"} == 1
  for: 10m
  annotations:
    summary: "Flux reconciliation failed for {{ $labels.kind }}/{{ $labels.name }}"
```

**Metrics to watch:**
```promql
# Reconciliation duration
gotk_reconcile_duration_seconds_bucket

# Reconciliation failures
gotk_reconcile_condition{status="False"}

# Suspended resources
gotk_suspend_status == 1
```

**Grafana dashboard:** Import dashboard ID 15798 (Flux Cluster Stats) or 15800 (Flux Control Plane).

---

### What Happens If Git Is Unavailable?

**Scenario:** GitHub down, or network partition between cluster and Git.

**What happens:**
1. **GitRepository polls fail**: source-controller can't fetch updates
2. **Last known state persists**: Cluster keeps running with last synced revision
3. **No new deployments**: Can't apply changes from Git
4. **Self-healing still works**: Flux reconciles from cached artifacts

**How long can it survive?**
- **Indefinitely for existing apps**: They keep running
- **No new changes applied**: Until Git is reachable again

**Cached artifacts:** Flux caches Git content and Helm charts locally. Reconciliation uses cache if Git unreachable.

**Recovery:**
```bash
# When Git back online
flux reconcile source git flux-system
# Fetches any missed commits, applies changes
```

**Mitigation strategies:**
1. **GitRepository mirrors**: Use Git mirrors for high availability
2. **OCI registries**: Store Flux artifacts in OCI registry as backup
3. **Terraform fallback**: Keep Terraform configs for infrastructure recovery

**Your setup:** If GitHub is down temporarily, your cluster keeps running fine. When GitHub returns, Flux catches up automatically.

---

### Useful Debugging Scripts

**Check all Flux resources at once:**
```bash
#!/bin/bash
echo "=== GitRepositories ==="
flux get sources git -A
echo ""
echo "=== HelmRepositories ==="
flux get sources helm -A
echo ""
echo "=== Kustomizations ==="
flux get kustomizations -A
echo ""
echo "=== HelmReleases ==="
flux get helmreleases -A
echo ""
echo "=== Recent Errors ==="
flux logs --level=error --since=10m
```

**Find all failing resources:**
```bash
flux get all -A | grep False
```

**Watch reconciliation in real-time:**
```bash
watch -n 5 'flux get helmreleases -A'
```

---

## Interview Questions

### GitOps Fundamentals

**Q: What is GitOps and how does it differ from traditional CI/CD?**

GitOps is a set of practices where Git serves as the single source of truth for declarative infrastructure and applications. Key differences:

| Aspect | Traditional CI/CD | GitOps |
|--------|------------------|--------|
| **Model** | Push-based (CI pushes to cluster) | Pull-based (cluster pulls from Git) |
| **Source of truth** | CI/CD pipeline state | Git repository |
| **Credentials** | CI needs cluster access | Cluster needs Git read access |
| **Drift detection** | Manual or none | Continuous and automatic |
| **Rollback** | Re-run pipeline or manual | `git revert` |

**Q: What are the four principles of GitOps?**

1. **Declarative**: System state is described declaratively (YAML, not scripts)
2. **Versioned and Immutable**: Git stores the desired state with full history
3. **Pulled Automatically**: Agents pull desired state and apply it
4. **Continuously Reconciled**: Agents continuously ensure actual state matches desired state

**Q: What is drift detection and why is it important?**

Drift detection identifies differences between the desired state (Git) and actual state (cluster). It's important because:
- Manual `kubectl` changes are detected and can be reverted
- Ensures consistency across environments
- Provides audit trail of who changed what
- Prevents configuration sprawl

---

### Flux CD Questions

**Q: Explain the Flux reconciliation loop.**

```
1. Source Controller polls Git (every 1m by default)
2. Detects new commits by comparing SHA
3. Downloads manifests from specified path
4. Kustomize Controller builds manifests (follows kustomization.yaml hierarchy)
5. Helm Controller processes HelmReleases (fetches charts, renders templates)
6. Resources applied to cluster via Kubernetes API
7. Loop repeats at configured interval (reconciles even without Git changes)
```

**Q: What are the main Flux CRDs and their purposes?**

| CRD | Purpose | Controller |
|-----|---------|------------|
| `GitRepository` | Defines Git source to watch | source-controller |
| `HelmRepository` | Defines Helm chart repository | source-controller |
| `Kustomization` | Defines what path to apply from source | kustomize-controller |
| `HelmRelease` | Defines Helm chart to install with values | helm-controller |

**Q: What's the difference between Flux Kustomization and Kustomize kustomization.yaml?**

| Flux Kustomization (CRD) | Kustomize kustomization.yaml |
|--------------------------|------------------------------|
| `kustomize.toolkit.fluxcd.io/v1` | `kustomize.config.k8s.io/v1beta1` |
| Tells Flux what to apply | Tells Kustomize how to build |
| Has `sourceRef`, `interval`, `prune` | Has `resources`, `patches`, `commonLabels` |
| Kubernetes resource (applied to cluster) | File processed by kustomize CLI |

**Q: How does Flux handle secrets?**

Flux itself doesn't encrypt secrets. Options:
1. **Sealed Secrets**: Encrypt with cluster public key, commit encrypted version
2. **SOPS**: Encrypt with age/GPG/KMS, Flux decrypts at apply time
3. **External Secrets Operator**: Fetch from Vault/AWS Secrets Manager at runtime

**Q: A HelmRelease is stuck in "False" ready state. How do you debug it?**

```bash
# 1. Check HelmRelease status
flux get helmrelease <name> -n <namespace>

# 2. Describe for detailed error
kubectl describe helmrelease <name> -n <namespace>

# 3. Check Helm Controller logs
flux logs --kind=HelmRelease --name=<name> -n <namespace>

# 4. Check if HelmRepository is ready
flux get sources helm -A

# 5. Try manual Helm template to see rendering errors
helm template <release> <chart> --values values.yaml
```

**Q: How do you temporarily stop Flux from reconciling a resource?**

```bash
# Suspend a HelmRelease
flux suspend helmrelease <name> -n <namespace>

# Resume when ready
flux resume helmrelease <name> -n <namespace>
```

Use cases: debugging, manual testing, preventing rollback during incident response.

---

### Helm Questions

**Q: Explain the Helm chart structure.**

```
mychart/
├── Chart.yaml          # Metadata (name, version, dependencies)
├── values.yaml         # Default configuration values
├── charts/             # Subcharts (dependencies)
├── templates/          # Kubernetes manifest templates
│   ├── _helpers.tpl    # Reusable template functions
│   ├── deployment.yaml
│   ├── service.yaml
│   └── NOTES.txt       # Post-install instructions
└── .helmignore         # Files to exclude from packaging
```

**Q: What is the values precedence in Helm?**

From lowest to highest priority:
1. `values.yaml` in parent chart
2. `values.yaml` in subchart
3. `-f custom-values.yaml` (in order specified)
4. `--set key=value` (highest priority)

In Flux HelmRelease:
```yaml
spec:
  values:        # Equivalent to -f values.yaml
    key: value
  valuesFrom:    # Load from ConfigMap/Secret
    - kind: ConfigMap
      name: my-values
```

**Q: What are Helm hooks and when would you use them?**

Hooks run at specific lifecycle points:
- `pre-install`: Before any resources installed (e.g., create namespace)
- `post-install`: After all resources installed (e.g., run migrations)
- `pre-upgrade`: Before upgrade (e.g., backup database)
- `post-upgrade`: After upgrade (e.g., clear cache)
- `pre-delete`: Before deletion (e.g., backup data)

Example use case: Database migration Job that runs before deploying new app version.

**Q: How do you debug a Helm template rendering issue?**

```bash
# Render templates locally without installing
helm template myrelease ./mychart

# With debug output
helm template myrelease ./mychart --debug

# Dry-run against cluster (validates against API)
helm install myrelease ./mychart --dry-run

# Lint for common issues
helm lint ./mychart
```

---

### Kubernetes Questions

**Q: What's the difference between Deployment, StatefulSet, and DaemonSet?**

| Type | Use Case | Characteristics |
|------|----------|-----------------|
| **Deployment** | Stateless apps | Interchangeable pods, rolling updates |
| **StatefulSet** | Stateful apps | Stable network IDs, ordered deployment, persistent storage |
| **DaemonSet** | Node agents | One pod per node (logging, monitoring agents) |

**Q: Explain Kubernetes service types.**

| Type | Accessibility | Use Case |
|------|---------------|----------|
| `ClusterIP` | Internal only | Service-to-service communication |
| `NodePort` | External via node IP:port | Development, on-prem without LB |
| `LoadBalancer` | External via cloud LB | Production external access |
| `ExternalName` | DNS alias | Accessing external services |

**Q: What is a ConfigMap vs Secret?**

| ConfigMap | Secret |
|-----------|--------|
| Non-sensitive configuration | Sensitive data (passwords, tokens) |
| Stored as plain text | Base64 encoded (not encrypted by default!) |
| No size limit (practical: 1MB) | Size limit: 1MB |
| Can be mounted as files or env vars | Same, but with restricted access |

---

### Scenario-Based Questions

**Q: Your team pushed a bad config that broke production. How do you rollback with GitOps?**

```bash
# Option 1: Git revert (preferred - maintains history)
git revert HEAD
git push
# Flux detects new commit, applies previous state

# Option 2: Helm rollback via Flux (if using HelmRelease)
flux suspend helmrelease <name> -n <namespace>
helm rollback <release> <revision> -n <namespace>
# Then fix Git and resume Flux

# Option 3: Check Flux revision history
kubectl get helmrelease <name> -n <namespace> -o yaml
# Look at status.history for previous versions
```

**Q: How would you implement a canary deployment with Flux?**

Option 1: **Flagger** (Flux's progressive delivery tool)
```yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: my-app
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  progressDeadlineSeconds: 60
  service:
    port: 80
  analysis:
    interval: 30s
    threshold: 5
    maxWeight: 50
    stepWeight: 10
```

Option 2: **Manual with two HelmReleases**
- `my-app-stable` (90% traffic)
- `my-app-canary` (10% traffic)
- Adjust traffic split via Ingress weights

**Q: How do you handle secrets in a GitOps workflow where everything is in Git?**

Never commit plain secrets. Options:

1. **Sealed Secrets**:
   ```bash
   kubeseal --format yaml < secret.yaml > sealed-secret.yaml
   # Commit sealed-secret.yaml (encrypted)
   ```

2. **SOPS with Flux**:
   ```yaml
   # HelmRelease
   spec:
     valuesFrom:
       - kind: Secret
         name: my-secret
         valuesKey: values.yaml
     decryption:
       provider: sops
       secretRef:
         name: sops-age
   ```

3. **External Secrets Operator**:
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   spec:
     refreshInterval: 1h
     secretStoreRef:
       name: vault-backend
     target:
       name: my-secret
     data:
       - secretKey: password
         remoteRef:
           key: secret/myapp
           property: password
   ```

**Q: Your HelmRelease keeps failing with "upgrade retries exhausted". What do you do?**

```bash
# 1. Check the error
kubectl describe helmrelease <name> -n <namespace>

# 2. Check Helm history
helm history <release> -n <namespace>

# 3. If stuck in pending state, uninstall and let Flux reinstall
flux suspend helmrelease <name> -n <namespace>
helm uninstall <release> -n <namespace>
flux resume helmrelease <name> -n <namespace>

# 4. Or reset the failure count
kubectl patch helmrelease <name> -n <namespace> \
  --type='json' -p='[{"op": "remove", "path": "/status"}]'
flux reconcile helmrelease <name> -n <namespace>
```

**Q: How do you promote changes from dev to staging to production in GitOps?**

Common patterns:

1. **Branch-per-environment**:
   - `dev` branch → dev cluster
   - `staging` branch → staging cluster
   - `main` branch → production cluster
   - Promotion via PR merge

2. **Directory-per-environment** (recommended):
   ```
   environments/
   ├── dev/
   │   └── kustomization.yaml
   ├── staging/
   │   └── kustomization.yaml
   └── production/
       └── kustomization.yaml
   ```
   Each cluster watches its own path.

3. **Image promotion**:
   - All environments use same manifests
   - Only image tag differs
   - Flux ImagePolicy auto-updates tags

---

### Architecture Questions

**Q: How would you set up Flux for multiple clusters?**

Option 1: **Single repo, multiple paths**
```
clusters/
├── dev/
│   └── flux-system/
├── staging/
│   └── flux-system/
└── production/
    └── flux-system/
```
Each cluster's Flux watches its own path.

Option 2: **Repo per cluster**
- Separate repos for each environment
- Shared base repo as Git submodule or Flux dependency

Option 3: **Fleet management** (for many clusters)
- Use Flux's `Kustomization` dependencies
- Central management repo with cluster-specific overlays

**Q: What's your approach to disaster recovery with GitOps?**

1. **Git is the backup**: All desired state is in Git
2. **Recreate cluster**: `terraform apply` (or equivalent)
3. **Bootstrap Flux**: `flux bootstrap` or Terraform flux provider
4. **Automatic recovery**: Flux pulls from Git, recreates all resources

Key considerations:
- Persistent data needs separate backup (Velero, cloud snapshots)
- Secrets need to be recoverable (backup encryption keys)
- Document bootstrap process

**Q: How do you handle CRDs in GitOps?**

CRDs must exist before resources that use them. Options:

1. **Flux dependency ordering**:
   ```yaml
   # cert-manager-crds Kustomization
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: cert-manager-crds
   ---
   # cert-manager Kustomization depends on CRDs
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: cert-manager
   spec:
     dependsOn:
       - name: cert-manager-crds
   ```

2. **Helm chart includes CRDs**: Most charts install their own CRDs

3. **installCRDs value**: Many charts have `installCRDs: true` option

---

## Quick Reference

### Flux CLI Cheat Sheet

#### Status Commands

```bash
# Check Flux installation health
flux check

# View all Flux resources across namespaces
flux get all -A

# Check specific resource types
flux get sources git -A          # GitRepositories
flux get sources helm -A         # HelmRepositories
flux get kustomizations -A       # Kustomizations
flux get helmreleases -A         # HelmReleases

# View Flux logs
flux logs                        # All controllers
flux logs --level=error          # Errors only
flux logs --kind=HelmRelease --name=prometheus -n monitoring
```

#### Reconciliation Commands

```bash
# Force immediate reconciliation
flux reconcile source git flux-system           # Git source
flux reconcile kustomization flux-system        # Kustomization
flux reconcile helmrelease prometheus -n monitoring

# Reconcile with source (fetch + apply)
flux reconcile kustomization flux-system --with-source
```

#### Suspend/Resume Commands

```bash
# Suspend (stop reconciling)
flux suspend kustomization flux-system
flux suspend helmrelease grafana -n monitoring
flux suspend source git flux-system

# Resume
flux resume kustomization flux-system
flux resume helmrelease grafana -n monitoring
flux resume source git flux-system
```

#### Resource Generation (No YAML Memorization!)

```bash
# Generate HelmRelease for remote chart
flux create helmrelease prometheus \
  --source=HelmRepository/prometheus-community \
  --chart=prometheus \
  --chart-version="25.x" \
  --namespace=monitoring \
  --target-namespace=monitoring \
  --export > helmrelease.yaml

# Generate HelmRelease for local chart (in Git repo)
flux create helmrelease hello-gitops \
  --source=GitRepository/flux-system \
  --chart=./charts/hello-gitops \
  --namespace=default \
  --export > helmrelease.yaml

# Generate HelmRepository
flux create source helm prometheus-community \
  --url=https://prometheus-community.github.io/helm-charts \
  --interval=1h \
  --namespace=flux-system \
  --export > helmrepository.yaml

# Generate GitRepository
flux create source git my-repo \
  --url=https://github.com/org/repo \
  --branch=main \
  --interval=1m \
  --export > gitrepository.yaml

# Generate Kustomization
flux create kustomization apps \
  --source=GitRepository/flux-system \
  --path=./kubernetes/apps \
  --prune=true \
  --interval=10m \
  --export > kustomization.yaml
```

---

### Helm CLI Cheat Sheet

#### Chart Development

```bash
# Create new chart scaffold
helm create mychart

# Validate chart
helm lint mychart/

# Render templates locally (see output without installing)
helm template myrelease mychart/
helm template myrelease mychart/ --values custom-values.yaml
helm template myrelease mychart/ --set key=value --debug

# Package chart
helm package mychart/
```

#### Chart Installation (Manual, not GitOps)

```bash
# Add repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Search for charts
helm search repo prometheus

# Show chart values
helm show values prometheus-community/prometheus

# Install
helm install myrelease prometheus-community/prometheus -n monitoring
helm install myrelease ./local-chart -f values.yaml

# Upgrade
helm upgrade myrelease prometheus-community/prometheus -n monitoring

# Rollback
helm rollback myrelease 1 -n monitoring

# Uninstall
helm uninstall myrelease -n monitoring

# List releases
helm list -A
helm history myrelease -n monitoring
```

---

### Kubectl Commands for GitOps

#### Resource Inspection

```bash
# View Flux CRDs
kubectl get gitrepositories -A
kubectl get helmrepositories -A
kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A
kubectl get helmreleases -A

# Detailed status
kubectl describe helmrelease prometheus -n monitoring
kubectl describe kustomization flux-system -n flux-system

# View YAML
kubectl get helmrelease prometheus -n monitoring -o yaml
```

#### Debugging

```bash
# Pod logs
kubectl logs -n flux-system deploy/source-controller
kubectl logs -n flux-system deploy/kustomize-controller
kubectl logs -n flux-system deploy/helm-controller

# Events (recent activity)
kubectl get events -n monitoring --sort-by='.lastTimestamp'

# Check pods
kubectl get pods -n monitoring
kubectl describe pod <pod-name> -n monitoring

# Resource status
kubectl get deploy,svc,pods -n monitoring
```

#### Port Forwarding

```bash
# Access Grafana locally
kubectl port-forward svc/grafana 3000:80 -n monitoring

# Access Prometheus locally
kubectl port-forward svc/prometheus-server 9090:80 -n monitoring

# Access your app
kubectl port-forward svc/hello-gitops 8080:80
```

---

### Kustomize CLI Cheat Sheet

```bash
# Initialize kustomization.yaml in current directory
kustomize init

# Add resources
kustomize edit add resource deployment.yaml
kustomize edit add resource ./subdir/

# Build (render) kustomization
kustomize build .
kustomize build kubernetes/apps/

# Apply directly (without Flux)
kubectl apply -k .
kubectl apply -k kubernetes/apps/

# Dry-run
kubectl apply -k . --dry-run=client -o yaml
```

---

### Common YAML Templates

#### HelmRelease (Remote Chart)

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <release-name>
  namespace: <deploy-to-namespace>
spec:
  interval: 5m
  chart:
    spec:
      chart: <chart-name>
      version: "<semver-range>"  # e.g., "25.x" or ">=1.0.0"
      sourceRef:
        kind: HelmRepository
        name: <repo-name>
        namespace: flux-system   # Required if different namespace
  values:
    key: value
```

#### HelmRelease (Local Chart from Git)

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <release-name>
  namespace: <deploy-to-namespace>
spec:
  interval: 5m
  chart:
    spec:
      chart: ./path/to/chart    # Relative to Git repo root
      sourceRef:
        kind: GitRepository
        name: flux-system
        namespace: flux-system
  values:
    key: value
```

#### HelmRepository

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: <repo-name>
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.example.com
```

#### Kustomization (Flux)

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <name>
  namespace: flux-system
spec:
  interval: 10m
  path: ./kubernetes/apps
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
```

#### kustomization.yaml (Kustomize)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - ./subdirectory/
```

---

### Troubleshooting Decision Tree

```
Resource not deploying?
│
├─ Is GitRepository ready?
│  └─ flux get sources git -A
│     ├─ False → Check Git URL, branch, credentials
│     └─ True → Continue
│
├─ Is HelmRepository ready? (if using remote chart)
│  └─ flux get sources helm -A
│     ├─ False → Check repository URL, network access
│     └─ True → Continue
│
├─ Is Kustomization ready?
│  └─ flux get kustomizations -A
│     ├─ False → Check path exists, YAML syntax valid
│     └─ True → Continue
│
├─ Is HelmRelease ready?
│  └─ flux get helmreleases -A
│     ├─ False → kubectl describe helmrelease <name> -n <ns>
│     │         Check: chart exists, values valid, resources available
│     └─ True → Continue
│
└─ Are pods running?
   └─ kubectl get pods -n <namespace>
      ├─ Pending → kubectl describe pod <name> - check resources, node selector
      ├─ CrashLoopBackOff → kubectl logs <pod> - check app errors
      └─ Running → Check service, ingress, network policies
```

---

### Common Error Messages and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `chart not found` | Wrong chart name or repo | Check HelmRepository URL, chart name spelling |
| `upgrade retries exhausted` | Helm upgrade failed multiple times | Suspend, `helm uninstall`, resume |
| `source not found` | Missing sourceRef namespace | Add `namespace: flux-system` to sourceRef |
| `kustomize build failed` | Invalid YAML or missing resource | Run `kustomize build` locally to debug |
| `authentication required` | Git/Helm repo needs credentials | Create Secret with credentials |
| `target namespace not found` | Namespace doesn't exist | Create namespace or add to Kustomization |
| `context deadline exceeded` | Network timeout | Check DNS, firewall, increase timeout |
| `CRD not found` | CRD not installed | Install CRDs first, use dependsOn |

---

### Useful One-Liners

```bash
# Watch all Flux resources
watch -n 5 'flux get all -A'

# Find all failing resources
flux get all -A | grep -i false

# Get all Flux errors from last 10 minutes
flux logs --level=error --since=10m

# Force full reconciliation
flux reconcile kustomization flux-system --with-source

# Check what Flux would apply (dry-run)
kustomize build kubernetes/ | kubectl apply --dry-run=client -f -

# Export all HelmReleases to files
for hr in $(kubectl get helmreleases -A -o name); do
  kubectl get $hr -o yaml > $(basename $hr).yaml
done

# Restart all pods in a namespace (force re-pull)
kubectl rollout restart deployment -n <namespace>

# View Flux component versions
flux version

# Check resource events
kubectl get events -A --sort-by='.lastTimestamp' | head -20
```

---

### Environment Variables Reference

```bash
# GitHub Actions → Terraform
TF_VAR_project_id         # GCP project ID
TF_VAR_region             # GCP region
TF_VAR_github_owner       # Repository owner
TF_VAR_github_repository  # Repository name
TF_VAR_github_token       # PAT for Flux

# Flux environment
KUBECONFIG               # Path to kubeconfig
FLUX_SYSTEM_NAMESPACE    # Default: flux-system
```

---

### File Structure Reference (Your Repo)

```
gitops/
├── .github/workflows/
│   ├── terraform-deploy.yml    # Bootstrap + deploy
│   └── terraform-destroy.yml   # Teardown (manual)
│
├── terraform/
│   ├── bootstrap/              # GCS bucket for state
│   ├── main.tf                 # GKE + Flux bootstrap
│   ├── variables.tf
│   └── outputs.tf
│
├── kubernetes/
│   ├── kustomization.yaml      # Root: includes flux-system + apps
│   ├── flux-system/            # Flux manages itself
│   │   ├── gotk-components.yaml
│   │   ├── gotk-sync.yaml
│   │   └── kustomization.yaml
│   └── apps/
│       ├── kustomization.yaml  # Includes all apps
│       ├── prometheus/
│       │   ├── kustomization.yaml
│       │   ├── helmrepository.yaml
│       │   └── helmrelease.yaml
│       ├── grafana/
│       │   ├── kustomization.yaml
│       │   ├── helmrepository.yaml
│       │   └── helmrelease.yaml
│       └── hello-gitops/
│           ├── kustomization.yaml
│           └── helmrelease.yaml
│
└── charts/
    └── hello-gitops/           # Local Helm chart
        ├── Chart.yaml
        ├── values.yaml
        └── templates/
            ├── _helpers.tpl
            ├── deployment.yaml
            ├── service.yaml
            └── configmap.yaml
```

---

Good luck with your preparation!
