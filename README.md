# GitOps Showcase

A demonstration of GitOps principles using GitHub Actions, Terraform, GKE, and Flux.

## Architecture

```
GitHub Actions (Terraform)
         │
         ▼
    GKE Cluster
         │
         ▼
       Flux ──────► kubernetes/apps/
         │
         ▼
  Prometheus + Grafana
```

## Manual Setup (one-time, ~10 minutes)

Everything below is done in the browser - no local tools needed.

### 1. Create GCP Project

1. Go to [GCP Console](https://console.cloud.google.com)
2. Create a new project (or use existing)
3. Note your **Project ID**

### 2. Enable Billing

1. Go to [Billing](https://console.cloud.google.com/billing)
2. Link a billing account to your project

### 3. Create Service Account

1. Go to [IAM & Admin → Service Accounts](https://console.cloud.google.com/iam-admin/serviceaccounts)
2. Click **Create Service Account**
3. Name: `github-actions`
4. Click **Create and Continue**
5. Add these roles:
   - `Editor` (or for least privilege: Storage Admin, Kubernetes Engine Admin, Compute Admin, Service Account User)
6. Click **Done**
7. Click on the created service account
8. Go to **Keys** tab → **Add Key** → **Create new key** → **JSON**
9. Save the downloaded JSON file

### 4. Create GitHub PAT

1. Go to [GitHub Settings → Tokens](https://github.com/settings/tokens)
2. **Generate new token (classic)**
3. Select scope: `repo`
4. Copy the token

### 5. Add GitHub Secrets

In your repository → **Settings** → **Secrets and variables** → **Actions**, add:

| Secret | Value |
|--------|-------|
| `GCP_PROJECT_ID` | Your GCP project ID |
| `GCP_REGION` | `europe-west1` |
| `GCP_SA_KEY` | Contents of the JSON key file |
| `FLUX_GITHUB_TOKEN` | GitHub PAT from step 4 |

### 6. Deploy

1. Go to **Actions** tab
2. Select **Terraform Deploy**
3. Click **Run workflow**
4. Select `apply`
5. Click **Run workflow**

**Done!** The workflow will:
- Enable GCP APIs
- Create GCS bucket for state
- Create GKE cluster
- Install Flux
- Deploy Prometheus + Grafana

## What Gets Created

| Component | Created By |
|-----------|------------|
| GCP APIs | Terraform (bootstrap job) |
| GCS Bucket | gcloud (deploy job) |
| GKE Cluster | Terraform (deploy job) |
| Flux | Terraform (deploy job) |
| Prometheus | Flux (GitOps) |
| Grafana | Flux (GitOps) |

## Usage

### Access Grafana

```bash
# Get kubeconfig (run in Cloud Shell or locally)
gcloud container clusters get-credentials gitops-showcase \
  --zone europe-west1-b \
  --project YOUR_PROJECT_ID

# Get Grafana external IP
kubectl get svc -n monitoring grafana
```

Login: `admin` / `gitops-showcase`

### Demonstrate GitOps

1. Edit `kubernetes/apps/prometheus/helmrelease.yaml`
2. Change `server.replicaCount` from `1` to `2`
3. Commit and push to main
4. Watch Flux apply the change (~1 minute)

### Teardown

1. Go to **Actions** → **Terraform Destroy**
2. Click **Run workflow**
3. Type `yes-destroy`
4. Click **Run workflow**

## Cost

| Resource | Cost |
|----------|------|
| GKE cluster (1 zonal) | Free tier |
| 1x e2-medium node | ~$25/month |
| GCS bucket | ~$0.02/month |

**Remember to destroy when done!**

## Repository Structure

```
.
├── .github/workflows/
│   ├── terraform-deploy.yml    # Bootstrap + Deploy
│   └── terraform-destroy.yml   # Destroy
├── terraform/
│   ├── bootstrap/              # APIs only
│   └── *.tf                    # GKE, Flux
├── kubernetes/apps/
│   ├── prometheus/
│   └── grafana/
└── README.md
```

## License

MIT
