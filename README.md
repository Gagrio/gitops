# 🚀 GitOps Showcase

*Because clicking buttons in a UI is so 2015* 😎

A demonstration of GitOps principles using GitHub Actions, Terraform, GKE, and Flux. Push code, grab coffee ☕, watch magic happen!

## 🏗️ Architecture

```
GitHub Actions (Terraform)
         │
         ▼ 🔨 "Let there be cluster!"
    GKE Cluster
    (e2-standard-2)
         │
         ├── 📦 default namespace (Terraform)
         ├── 📦 monitoring namespace (Terraform)
         │
         ▼
       Flux 🤖 ──────► kubernetes/apps/
         │              "I got this, fam"
         ▼
  ┌──────────────────────────┐
  │ Prometheus + Grafana 📊  │
  │ hello-gitops 👋          │
  └──────────────────────────┘
```

## 🧠 Architecture Principles

*a.k.a. "Who does what around here?"*

| Layer | Managed By | Resources |
|-------|------------|-----------|
| ☁️ Cloud Infrastructure | Terraform | GKE cluster, node pools, IAM |
| 🏠 Kubernetes Infrastructure | Terraform | Namespaces (default, monitoring) |
| 📱 Applications | Flux | HelmReleases, HelmRepositories |

**TL;DR:** Terraform builds the house 🏠, Flux decorates it 🎨

## 🛠️ Manual Setup (one-time, ~10 minutes)

*The only manual work you'll ever do. We promise!* 🤞

Everything below is done in the browser - no local tools needed. Your laptop can stay closed! 💻😴

### 1. 🌍 Create GCP Project

1. Go to [GCP Console](https://console.cloud.google.com)
2. Create a new project (or use existing)
3. Note your **Project ID** (you'll need this, don't forget! 🧠)

### 2. 💳 Enable Billing

1. Go to [Billing](https://console.cloud.google.com/billing)
2. Link a billing account to your project
3. *Yes, it costs money. No, we can't mine Bitcoin to pay for it.* 😅

### 3. 🤖 Create Service Account

1. Go to [IAM & Admin → Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts)
2. Click **Create Service Account**
3. Name: `github-actions` *(or `skynet`, we don't judge)*
4. Click **Create and Continue**
5. Add these roles:
   - `Editor` (or for the security-conscious: Storage Admin, Kubernetes Engine Admin, Compute Admin, Service Account User)
6. Click **Done**
7. Click on the created service account
8. Go to **Keys** tab → **Add Key** → **Create new key** → **JSON**
9. Save the downloaded JSON file *(guard it with your life! 🔐)*

### 4. 🎫 Create GitHub PAT

1. Go to [GitHub Settings → Tokens](https://github.com/settings/tokens)
2. **Generate new token (classic)**
3. Select scope: `repo`
4. Copy the token *(another secret to guard! 🤫)*

### 5. 🔐 Add GitHub Secrets

In your repository → **Settings** → **Secrets and variables** → **Actions**, add:

| Secret | Value |
|--------|-------|
| `GCP_PROJECT_ID` | Your GCP project ID |
| `GCP_REGION` | `europe-west1` |
| `GCP_SA_KEY` | Contents of the JSON key file |
| `FLUX_GITHUB_TOKEN` | GitHub PAT from step 4 |

### 6. 🎬 Deploy

1. Go to **Actions** tab
2. Select **Terraform Deploy**
3. Click **Run workflow**
4. Select `apply`
5. Click **Run workflow**
6. *Go make that coffee* ☕

**🎉 Done!** The workflow will:
- ✅ Enable GCP APIs
- ✅ Create GCS bucket for state
- ✅ Create GKE cluster with managed node pool
- ✅ Create monitoring namespace
- ✅ Install Flux
- ✅ Deploy Prometheus + Grafana

## 📦 What Gets Created

| Component | Created By | Details |
|-----------|------------|---------|
| 🔌 GCP APIs | Terraform (bootstrap job) | compute, container, storage, iam |
| 🪣 GCS Bucket | gcloud (deploy job) | Terraform state backend |
| ☸️ GKE Cluster | Terraform | Managed node pool, e2-standard-2 |
| 📦 Namespaces | Terraform | default, monitoring |
| 🤖 Flux | Terraform | source, kustomize, helm controllers |
| 📈 Prometheus | Flux (GitOps) | HelmRelease in monitoring namespace |
| 📊 Grafana | Flux (GitOps) | HelmRelease in monitoring namespace, with pre-configured dashboards |
| 👋 hello-gitops | Flux (GitOps) | Custom Helm chart in default namespace |

## 🎮 Usage

### 📊 Access Grafana

```bash
# Get kubeconfig (run in Cloud Shell or locally)
gcloud container clusters get-credentials gitops-showcase \
  --zone europe-west1-b \
  --project YOUR_PROJECT_ID

# Get Grafana external IP
kubectl get svc -n monitoring grafana
```

🔑 Login: `admin` / `gitops-showcase` *(yes, it's in the repo. no, this isn't production 😅)*

**Pre-configured dashboards:**
- Kubernetes Cluster Monitoring (7249) - Cluster-wide CPU, memory, network
- Node Exporter Full (1860) - Detailed node metrics
- Kubernetes Pods (6417) - Pod-level resource usage
- Kubernetes Cluster Overview (315) - High-level cluster health

### 👋 Access hello-gitops App

```bash
# Get hello-gitops external IP
kubectl get svc -n default hello-gitops

# Visit in browser
curl http://<EXTERNAL-IP>
```

Expected response: `Hello from GitOps! Deployed by Flux.`

### 🎪 Demonstrate GitOps

*This is the fun part! Show your friends!* 🎉

**Example 1: Scale Prometheus**
1. Edit `kubernetes/apps/prometheus/helmrelease.yaml`
2. Change `server.replicaCount` from `1` to `2`
3. Commit and push to main
4. Watch Flux apply the change (~1 minute)
5. 🎤 *Drop mic* - "That's GitOps, baby!"

**Example 2: Update hello-gitops Message**
1. Edit `kubernetes/apps/hello-gitops/helmrelease.yaml`
2. Change `message: "Hello from GitOps! Deployed by Flux."`
3. Commit and push to main
4. Flux reconciles, pod restarts with new message
5. Visit the external IP to see the change

### 💥 Teardown

*All good things must come to an end* 😢

1. Go to **Actions** → **Terraform Destroy**
2. Click **Run workflow**
3. Type `yes-destroy` *(we need to know you're serious)*
4. Click **Run workflow**
5. 👋 Goodbye, cluster!

## 💰 Cost

| Resource | Cost |
|----------|------|
| GKE cluster (1 zonal) | Free tier 🎁 |
| 1x e2-standard-2 node | ~$49/month |
| 2x LoadBalancer (Grafana + hello-gitops) | ~$36-40/month |
| GCS bucket | ~$0.02/month |
| **Total** | **~$85-89/month** |

**⚠️ Remember to destroy when done!** *Your wallet will thank you* 💸

## 📁 Repository Structure

```
.
├── .github/workflows/
│   ├── terraform-deploy.yml    # 🚀 Bootstrap + Deploy
│   └── terraform-destroy.yml   # 💥 Destroy
├── terraform/
│   ├── bootstrap/              # 🔌 APIs only
│   ├── main.tf                 # ☸️ GKE cluster, node pool, namespaces
│   ├── flux.tf                 # 🤖 Flux bootstrap
│   └── versions.tf             # 📦 Providers
├── kubernetes/
│   ├── kustomization.yaml      # 🎯 Root: flux-system + apps
│   ├── flux-system/            # 🤖 Auto-generated by Flux
│   └── apps/
│       ├── kustomization.yaml  # 📋 Aggregates all apps
│       ├── prometheus/         # 📈 Metrics go brrr
│       ├── grafana/            # 📊 Pretty dashboards with community dashboards
│       └── hello-gitops/       # 👋 Demo app
├── charts/
│   └── hello-gitops/           # 📦 Custom Helm chart
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
└── README.md                   # 👋 You are here!
```

## 🤝 Contributing

Found a bug? Want to add a feature? PRs welcome!

*Just remember: with great GitOps comes great responsibility* 🕷️

## 📜 License

MIT - *Do whatever you want, just don't blame us!* 😄

---

*Made with ❤️ and mass of ☕ by someone who got tired of clicking buttons*
