# GitOps Learning Guide - Hands-On Learning Plan

**Timeline**: 2 days focused, hands-on learning
**Goal**: Refresh knowledge through experimentation, not theory
**Focus**: Terraform, GCP, Kubernetes, Flux, Helm, GitHub Actions

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Day 1: Infrastructure Layer](#day-1-infrastructure-layer-terraform--gcp--kubernetes-basics)
   - Terraform
   - GCP & GKE
   - Kubernetes Basics
3. [Day 2: GitOps Layer](#day-2-gitops-layer-flux--helm)
   - Flux CD
   - Helm
   - GitHub Actions
4. [Troubleshooting Scenarios](#troubleshooting-scenarios)
5. [Quick Command Reference](#quick-command-reference)
6. [Final Checklist](#final-checklist)

---

## Prerequisites

Before starting this learning plan, ensure you have all required tools installed and properly configured.

### Required Tools

```bash
# Check all required tools are installed
command -v terraform && echo "✓ Terraform" || echo "✗ Terraform MISSING"
command -v gcloud && echo "✓ gcloud" || echo "✗ gcloud MISSING"
command -v kubectl && echo "✓ kubectl" || echo "✗ kubectl MISSING"
command -v flux && echo "✓ Flux CLI" || echo "✗ Flux CLI MISSING"
command -v helm && echo "✓ Helm" || echo "✗ Helm MISSING"
command -v jq && echo "✓ jq" || echo "✗ jq MISSING"
command -v yq && echo "✓ yq" || echo "✗ yq MISSING (optional)"
```

### Tool Versions

```bash
# Verify tool versions
terraform version
gcloud version
kubectl version --client
flux version --client
helm version
jq --version
yq --version 2>/dev/null || echo "yq not installed (optional)"
```

### Context Verification

```bash
# Verify working directory
cd /Users/geoagriogiannis/Documents/GitHub/gitops
pwd

# Verify GCP authentication
gcloud config get-value project
gcloud config get-value account

# Verify cluster access
kubectl cluster-info
kubectl get nodes

# Verify Flux is operational
flux check
```

**Note**: All commands in this guide assume you're running them from the repository root unless otherwise specified. If a command requires a specific directory, it will be explicitly stated.

---
## Day 1: Infrastructure Layer (Terraform + GCP + Kubernetes Basics)

### TERRAFORM - 3 hours

#### Explore Your Repo (45 mins)

**Files to dissect line-by-line:**
```bash
# Read these files and explain EVERY line to yourself
cat /Users/geoagriogiannis/Documents/GitHub/gitops/terraform/main.tf
cat /Users/geoagriogiannis/Documents/GitHub/gitops/terraform/flux.tf
cat /Users/geoagriogiannis/Documents/GitHub/gitops/terraform/bootstrap/main.tf
cat /Users/geoagriogiannis/Documents/GitHub/gitops/terraform/versions.tf
```

**Commands to run:**
```bash
cd /Users/geoagriogiannis/Documents/GitHub/gitops/terraform

# See current state
terraform show

# See what resources Terraform manages
terraform state list

# Inspect specific resources
terraform state show google_container_cluster.main
terraform state show google_container_node_pool.primary
terraform state show kubernetes_namespace.monitoring
terraform state show flux_bootstrap_git.this

# See dependencies
terraform graph | dot -Tpng > /tmp/terraform-graph.png && open /tmp/terraform-graph.png

# Check what would change if you re-applied
terraform plan
```

**Questions to answer by exploring:**
1. Why is `remove_default_node_pool = true` set? What happens without it?
2. Why does `flux_bootstrap_git.this` depend on `time_sleep.wait_for_namespaces`?
3. What OAuth scope is granted to nodes and why is it `cloud-platform` (full access)?
4. Why are image-reflector and image-automation controllers commented out?
5. Where is the Terraform state stored? (Check backend config)
6. What happens if you remove the `depends_on` from the flux bootstrap?

#### Hands-On Exercises (1.5 hours)

**Exercise 1: State Manipulation**
```bash
cd /Users/geoagriogiannis/Documents/GitHub/gitops/terraform

# List all resources in state
terraform state list

# Move a resource (dry run first)
terraform state show kubernetes_namespace.monitoring

# Taint a resource to force recreation next apply
terraform taint time_sleep.wait_for_namespaces
terraform plan
# Then untaint it
terraform untaint time_sleep.wait_for_namespaces
```

**Exercise 2: Add a Development Namespace**
```bash
# Edit main.tf and add after the monitoring namespace:
cat >> /Users/geoagriogiannis/Documents/GitHub/gitops/terraform/main.tf << 'EOF'

resource "kubernetes_namespace" "development" {
  metadata {
    name = "development"
    labels = {
      environment = "dev"
    }
  }

  depends_on = [google_container_node_pool.primary]
}
EOF

# Plan and apply
terraform plan
terraform apply

# Verify in cluster
kubectl get namespace development -o yaml

# Now remove it
git restore /Users/geoagriogiannis/Documents/GitHub/gitops/terraform/main.tf
terraform plan
terraform apply
```

**Exercise 3: Understand Provider Configuration**
```bash
# Check what providers are in use
terraform providers

# See the lock file
cat /Users/geoagriogiannis/Documents/GitHub/gitops/terraform/.terraform.lock.hcl

# Check provider versions
terraform version
```

**Exercise 4: Output Experimentation**
```bash
# Check existing outputs
terraform output

# Add a new output to outputs.tf
cat >> /Users/geoagriogiannis/Documents/GitHub/gitops/terraform/outputs.tf << 'EOF'

output "node_pool_instance_group" {
  value = google_container_node_pool.primary.instance_group_urls
}
EOF

terraform apply
terraform output node_pool_instance_group

# Clean up
git restore /Users/geoagriogiannis/Documents/GitHub/gitops/terraform/outputs.tf
```

**Exercise 5: Break and Fix**
```bash
# Change node_count to trigger an update
# Edit variables.tf or create terraform.tfvars
echo 'node_count = 2' > /Users/geoagriogiannis/Documents/GitHub/gitops/terraform/testing.tfvars

terraform plan -var-file=testing.tfvars

# Don't apply, just see the plan
rm /Users/geoagriogiannis/Documents/GitHub/gitops/terraform/testing.tfvars
```

#### Knowledge Checklist

Test yourself by running these commands and explaining the output:

- [ ] **State management**: What's the difference between `terraform state list` vs `terraform show`?
- [ ] **Resource addressing**: Run `terraform state show google_container_cluster.main` - explain each attribute
- [ ] **Lifecycle**: Why use `time_sleep` resource? Test: `terraform state show time_sleep.wait_for_namespaces`
- [ ] **Dependencies**: Run `terraform graph` - can you identify implicit vs explicit dependencies?
- [ ] **Provider versions**: Check `.terraform.lock.hcl` - why lock provider versions?
- [ ] **Workspaces**: Run `terraform workspace list` - are you using workspaces?
- [ ] **Remote state**: Where is state stored? Check `bootstrap/main.tf` for GCS backend config
- [ ] **Count vs for_each**: Where do you use `for_each`? Check `bootstrap/main.tf`

#### Practice Questions

**Q: How do you handle Terraform state in a team environment?**
- Check: `/Users/geoagriogiannis/Documents/GitHub/gitops/terraform/bootstrap/main.tf`
- Your answer should mention GCS backend, state locking, etc.

**Q: How do you manage dependencies between resources?**
- Check: `flux.tf` line 3, `main.tf` line 68, 73
- Explain `depends_on` vs implicit dependencies via attributes

**Q: How would you import existing GCP resources into Terraform?**
```bash
# Example command structure
terraform import google_container_cluster.main projects/PROJECT/locations/ZONE/clusters/NAME
```

**Q: How do you handle sensitive values in Terraform?**
- Check: Are there any `sensitive = true` outputs?
- Where are credentials stored? (Check how GCP provider authenticates)

**Q: What's the difference between `terraform taint` and `terraform apply -replace`?**
```bash
# Test it
terraform taint time_sleep.wait_for_namespaces
terraform plan
terraform untaint time_sleep.wait_for_namespaces

# vs
terraform plan -replace=time_sleep.wait_for_namespaces
```

---

### GCP - 1.5 hours

#### Explore Your Repo (30 mins)

**Commands to run:**
```bash
# See what GCP project you're using
gcloud config get-value project

# List enabled APIs (matches bootstrap/main.tf)
gcloud services list --enabled

# Inspect the GKE cluster
# Note: Run these from the terraform directory
cd /Users/geoagriogiannis/Documents/GitHub/gitops/terraform
gcloud container clusters describe $(terraform output -raw cluster_name) --zone=$(terraform output -raw zone)

# List node pools
gcloud container node-pools list --cluster=$(terraform output -raw cluster_name) --zone=$(terraform output -raw zone)

# Get cluster credentials
gcloud container clusters get-credentials $(terraform output -raw cluster_name) --zone=$(terraform output -raw zone)

# Check IAM for the project
gcloud projects get-iam-policy $(gcloud config get-value project)

# List GCS buckets (Terraform state backend)
gcloud storage ls
```

**Questions to answer:**
1. What GCP APIs are enabled and why? (Check `bootstrap/main.tf`)
2. What's the difference between zonal vs regional GKE clusters? (Your cluster is zonal)
3. What's the VPC network being used? (Check cluster networking)
4. What service account do the GKE nodes use?
5. What's the release channel for GKE and why does it matter?

#### Hands-On Exercises (45 mins)

**Exercise 1: Explore GKE Cluster Details**
```bash
# Get full cluster info
gcloud container clusters describe $(terraform output -raw cluster_name) --zone=$(terraform output -raw zone) --format=yaml > /tmp/cluster-info.yaml
cat /tmp/cluster-info.yaml

# Check node pool details
gcloud container node-pools describe primary-pool \
  --cluster=$(terraform output -raw cluster_name) \
  --zone=$(terraform output -raw zone)

# Check what K8s version is running
kubectl version --short

# Check node configuration
kubectl get nodes -o wide
kubectl describe node $(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
```

**Exercise 2: Examine GCP Logging and Monitoring**
```bash
# Check what's being logged (matches main.tf logging_config)
gcloud container clusters describe $(terraform output -raw cluster_name) \
  --zone=$(terraform output -raw zone) \
  --format="value(loggingConfig.componentConfig.enableComponents)"

# Check monitoring config
gcloud container clusters describe $(terraform output -raw cluster_name) \
  --zone=$(terraform output -raw zone) \
  --format="value(monitoringConfig.componentConfig.enableComponents)"

# View logs in Cloud Logging
gcloud logging read "resource.type=k8s_cluster" --limit=10 --format=json
```

**Exercise 3: IAM Deep Dive**
```bash
# What service account do nodes use?
gcloud container node-pools describe primary-pool \
  --cluster=$(terraform output -raw cluster_name) \
  --zone=$(terraform output -raw zone) \
  --format="value(config.serviceAccount)"

# Check IAM roles for that service account
SA=$(gcloud container node-pools describe primary-pool \
  --cluster=$(terraform output -raw cluster_name) \
  --zone=$(terraform output -raw zone) \
  --format="value(config.serviceAccount)")

gcloud projects get-iam-policy $(gcloud config get-value project) \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:$SA"
```

**Exercise 4: Simulate Node Pool Upgrade**
```bash
# Check available K8s versions
gcloud container get-server-config --zone=$(terraform output -raw zone)

# See current version
gcloud container node-pools describe primary-pool \
  --cluster=$(terraform output -raw cluster_name) \
  --zone=$(terraform output -raw zone) \
  --format="value(version)"

# DON'T actually upgrade, but understand the command
echo "To upgrade: gcloud container clusters upgrade CLUSTER --node-pool=primary-pool --zone=ZONE"
```

#### Knowledge Checklist

- [ ] **GKE Architecture**: What's the difference between control plane and nodes? Who manages what?
- [ ] **OAuth Scopes**: Check `main.tf` line 42-44 - why `cloud-platform`? What are alternatives?
- [ ] **VPC-Native**: What does `networking_mode = "VPC_NATIVE"` mean? Test: describe cluster networking
- [ ] **Release Channels**: What's REGULAR vs RAPID vs STABLE? Check with gcloud describe
- [ ] **Node Pool Management**: Why separate node pool from cluster? Check `main.tf` lines 7-8
- [ ] **Auto-repair/upgrade**: Check node pool config - what do these do?
- [ ] **Deletion Protection**: Why is it `false` in your cluster? When should it be `true`?

#### Practice Questions

**Q: How does GKE authentication work with kubectl?**
```bash
# Check your kubeconfig
kubectl config view
# Notice the gcloud commands for token generation
```

**Q: What's the difference between GKE Standard and Autopilot?**
- Your cluster is Standard - explain node management, control, pricing differences

**Q: How do you troubleshoot a node that won't join the cluster?**
```bash
# Check node status
kubectl get nodes
kubectl describe node NODE_NAME

# Check GCP console for node pool health
gcloud container operations list --filter="targetLink:primary-pool"
```

**Q: How do you secure a GKE cluster?**
- Check: Workload Identity (not enabled in your setup), Network Policies, Binary Authorization
- Command: `gcloud container clusters describe` - look for security settings

---

### KUBERNETES BASICS - 2 hours

#### Explore Your Repo (40 mins)

**Commands to run:**
```bash
# Make sure you're connected
kubectl cluster-info

# List all namespaces
kubectl get namespaces

# Check monitoring namespace (created by Terraform)
kubectl get namespace monitoring -o yaml

# List all resources across namespaces
kubectl get all -A

# Check Flux system namespace
kubectl get all -n flux-system

# Check monitoring namespace
kubectl get all -n monitoring

# Get pods with more details
kubectl get pods -A -o wide

# Check resource usage
kubectl top nodes
kubectl top pods -A
```

**Questions to answer by exploring:**
1. What namespaces exist and who created them? (Terraform vs Flux)
2. What controllers are running in flux-system?
3. What's running in the monitoring namespace?
4. How many replicas of prometheus-server are running?
5. What services are exposed and how? (ClusterIP, NodePort, LoadBalancer?)

#### Hands-On Exercises (1 hour)

**Exercise 1: Explore Resource Hierarchy**
```bash
# Pick a pod in monitoring namespace
POD=$(kubectl get pods -n monitoring -o jsonpath='{.items[0].metadata.name}')

# Check its ownerReferences
kubectl get pod $POD -n monitoring -o jsonpath='{.metadata.ownerReferences}' | jq

# Trace up the hierarchy
kubectl get replicaset -n monitoring
kubectl get deployment -n monitoring

# See how Helm resources look
kubectl get helmrelease -n monitoring
kubectl describe helmrelease prometheus -n monitoring
```

**Exercise 2: Deep Dive into a Pod**
```bash
# Pick prometheus server pod
POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}')

# Get full spec
kubectl get pod $POD -n monitoring -o yaml > /tmp/pod-spec.yaml
cat /tmp/pod-spec.yaml

# Check container details
kubectl describe pod $POD -n monitoring

# Check logs
kubectl logs $POD -n monitoring --tail=50

# Exec into the pod
kubectl exec -it $POD -n monitoring -- /bin/sh
# Then exit

# Check resource requests/limits
kubectl get pod $POD -n monitoring -o jsonpath='{.spec.containers[*].resources}' | jq
```

**Exercise 3: ConfigMaps and Secrets**
```bash
# List configmaps in monitoring
kubectl get configmaps -n monitoring

# Examine prometheus configmap
kubectl get configmap prometheus-server -n monitoring -o yaml

# List secrets
kubectl get secrets -n monitoring

# Check a secret (base64 encoded)
kubectl get secret -n flux-system flux-system -o yaml
```

**Exercise 4: Services and Networking**
```bash
# List services
kubectl get svc -A

# Describe prometheus service
kubectl get svc -n monitoring prometheus-server -o yaml

# Port-forward to access prometheus locally
kubectl port-forward -n monitoring svc/prometheus-server 9090:80 &
PF_PROMETHEUS_PID=$!
# Visit http://localhost:9090
# Kill the port-forward when done
kill $PF_PROMETHEUS_PID

# Do the same for grafana
kubectl port-forward -n monitoring svc/grafana 3000:80 &
PF_GRAFANA_PID=$!
# Visit http://localhost:3000
# Kill it when done
kill $PF_GRAFANA_PID

# Note: If you lose the PID, you can find and kill the process manually:
# ps aux | grep port-forward
# kill <PID>
```

**Exercise 5: Create a Test Deployment**
```bash
# Create a simple deployment
kubectl create deployment test-nginx --image=nginx --replicas=2 -n monitoring

# Watch it come up
kubectl get pods -n monitoring -l app=test-nginx -w
# Ctrl+C to stop watching

# Expose it
kubectl expose deployment test-nginx --port=80 -n monitoring

# Test connectivity from another pod
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n monitoring -- curl http://test-nginx

# Clean up
kubectl delete deployment test-nginx -n monitoring
kubectl delete service test-nginx -n monitoring
```

**Exercise 6: Labels and Selectors**
```bash
# Show all labels
kubectl get pods -n monitoring --show-labels

# Filter by label
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

# Use field selectors
kubectl get pods -n monitoring --field-selector status.phase=Running

# Check deployment selectors
kubectl get deployment -n monitoring prometheus-server -o jsonpath='{.spec.selector}'
```

#### Knowledge Checklist

- [ ] **Resource Hierarchy**: Pod -> ReplicaSet -> Deployment - explain each. Test: trace a pod's ownership
- [ ] **Labels vs Annotations**: Check pods - explain difference. Command: `kubectl get pods --show-labels`
- [ ] **Namespaces**: Why use them? Check: `kubectl get ns` and describe each purpose
- [ ] **Services**: ClusterIP vs NodePort vs LoadBalancer. Check: `kubectl get svc -A`
- [ ] **Resource Requests/Limits**: Check prometheus HelmRelease values (lines 22-28). Why set both?
- [ ] **ConfigMaps vs Secrets**: When to use which? Check: `kubectl get cm,secret -n monitoring`
- [ ] **Probes**: Readiness vs Liveness vs Startup. Check: `kubectl describe pod` in monitoring
- [ ] **Init Containers**: Do any pods use them? Check: `kubectl get pods -A -o jsonpath='{.items[*].spec.initContainers}' | jq`

#### Practice Questions

**Q: How do you troubleshoot a pod that won't start?**
```bash
# Simulate by creating a broken pod
kubectl run broken --image=nginx:nonexistent -n monitoring
kubectl get pods -n monitoring -l run=broken
kubectl describe pod broken -n monitoring
kubectl logs broken -n monitoring
kubectl delete pod broken -n monitoring
```

**Q: Explain the difference between a Deployment and a StatefulSet**
- Check: Do you have any StatefulSets? `kubectl get statefulset -A`
- When would you use one vs the other?

**Q: How do you perform a rolling update?**
```bash
# Check rollout status
kubectl rollout status deployment/prometheus-server -n monitoring

# See rollout history
kubectl rollout history deployment/prometheus-server -n monitoring

# See what a rollback would look like (DON'T actually do it)
echo "kubectl rollout undo deployment/prometheus-server -n monitoring"
```

**Q: How does DNS work in Kubernetes?**
```bash
# Check DNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test DNS from a pod
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup prometheus-server.monitoring.svc.cluster.local
```

---

## Day 2: GitOps Layer (Flux + Helm)
## Day 2: GitOps Layer (Flux + Helm)

### FLUX - 2.5 hours

#### Explore Your Repo (45 mins)

**Files to dissect:**
```bash
# Flux bootstrap files
cat /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/flux-system/gotk-sync.yaml
cat /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/flux-system/gotk-components.yaml

# Kustomization hierarchy
cat /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/kustomization.yaml
cat /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/kustomization.yaml

# App definitions
cat /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/prometheus/helmrepository.yaml
cat /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/prometheus/helmrelease.yaml
cat /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/prometheus/kustomization.yaml
```

**Commands to run:**
```bash
# Check Flux installation
flux check

# List all Flux resources
flux get all

# Check GitRepository source
flux get sources git
kubectl get gitrepository -n flux-system flux-system -o yaml

# Check Kustomizations
flux get kustomizations
kubectl get kustomization -n flux-system -o yaml

# Check HelmRepositories
flux get sources helm
kubectl get helmrepository -A -o yaml

# Check HelmReleases
flux get helmreleases -A
kubectl get helmrelease -n monitoring -o yaml

# Check Flux logs
flux logs --level=info --all-namespaces

# Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization flux-system
```

**Questions to answer:**
1. How does Flux know which Git repo to watch? (Check gotk-sync.yaml)
2. What's the reconciliation interval for GitRepository vs Kustomization?
3. Why are HelmRepositories in flux-system namespace but HelmReleases in monitoring?
4. What happens when you push a change to the Git repo?
5. Which Flux controllers are running? (Check flux.tf - only 3 enabled)
6. What's the path that Flux monitors? (Check gotk-sync.yaml line 23)

#### Hands-On Exercises (1.5 hours)

**Exercise 1: Trace Flux Reconciliation**

**IMPORTANT**: This exercise modifies files and pushes to Git. Consider working on a feature branch:
```bash
git checkout -b test-flux-reconciliation
```

```bash
# Watch Flux reconcile
flux get kustomizations --watch &
WATCH_PID=$!

# Make a change to trigger reconciliation
# Edit a helmrelease
cat /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/prometheus/helmrelease.yaml

# Change the interval from 5m to 1m temporarily
# Note: sed -i behavior differs between macOS and Linux
# macOS requires -i '' or -i.bak, Linux uses -i directly
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i.bak 's/interval: 5m/interval: 1m/' /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/prometheus/helmrelease.yaml
else
  sed -i 's/interval: 5m/interval: 1m/' /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/prometheus/helmrelease.yaml
fi

# Commit and push
cd /Users/geoagriogiannis/Documents/GitHub/gitops
git add kubernetes/apps/prometheus/helmrelease.yaml
git commit -m "Test: change prometheus interval to 1m"
git push

# Watch Flux pick it up (takes up to 1 minute for git poll)
flux logs -f --level=info

# Restore
git revert HEAD
git push

kill $WATCH_PID

# Return to master if you used a feature branch
git checkout master
git branch -D test-flux-reconciliation
```

**Exercise 2: Suspend and Resume Resources**
```bash
# Suspend a HelmRelease
flux suspend helmrelease prometheus -n monitoring

# Check status
flux get helmreleases -A

# Try to reconcile (it won't work while suspended)
flux reconcile helmrelease prometheus -n monitoring

# Resume
flux resume helmrelease prometheus -n monitoring

# Force reconcile
flux reconcile helmrelease prometheus -n monitoring
```

**Exercise 3: Examine HelmRelease Lifecycle**
```bash
# Check HelmRelease status
kubectl get helmrelease prometheus -n monitoring -o yaml

# Check what Helm sees
helm list -n monitoring

# Check Helm release details
helm get values prometheus -n monitoring
helm get manifest prometheus -n monitoring | head -50

# Check Helm history
helm history prometheus -n monitoring

# Compare HelmRelease values to what's deployed
# Using yq (if installed)
kubectl get helmrelease prometheus -n monitoring -o jsonpath='{.spec.values}' | yq
# Alternative using jq (always available per prerequisites)
kubectl get helmrelease prometheus -n monitoring -o json | jq '.spec.values'
```

**Exercise 4: Add a New App via Flux**

**IMPORTANT**: This exercise pushes changes to Git. Consider using a feature branch:
```bash
cd /Users/geoagriogiannis/Documents/GitHub/gitops
git checkout -b test-add-nginx-app
```

```bash
# Create nginx directory
mkdir -p /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/nginx

# Create HelmRepository
cat > /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/nginx/helmrepository.yaml << 'EOF'
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: bitnami
  namespace: flux-system
spec:
  interval: 60m
  url: https://charts.bitnami.com/bitnami
EOF

# Create HelmRelease
cat > /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/nginx/helmrelease.yaml << 'EOF'
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nginx
  namespace: monitoring
spec:
  interval: 5m
  chart:
    spec:
      chart: nginx
      version: "18.x"
      sourceRef:
        kind: HelmRepository
        name: bitnami
        namespace: flux-system
  values:
    replicaCount: 1
EOF

# Create Kustomization
cat > /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/nginx/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrepository.yaml
  - helmrelease.yaml
EOF

# Add to apps kustomization
cat > /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - prometheus
  - grafana
  - nginx
EOF

# Commit and push
cd /Users/geoagriogiannis/Documents/GitHub/gitops
git add kubernetes/apps/nginx kubernetes/apps/kustomization.yaml
git commit -m "Add nginx test app"
git push

# Watch Flux deploy it
flux logs -f --level=info
kubectl get helmrelease nginx -n monitoring -w

# Clean up
rm -rf /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/nginx
git restore /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/kustomization.yaml
git add -A
git commit -m "Remove nginx test app"
git push

# Return to master if you used a feature branch
git checkout master
git branch -D test-add-nginx-app
```

**Exercise 5: Break and Fix - Simulate Failures**
```bash
# Create an invalid HelmRelease
cat > /tmp/broken-helmrelease.yaml << 'EOF'
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: broken
  namespace: monitoring
spec:
  interval: 1m
  chart:
    spec:
      chart: nonexistent-chart
      version: "1.0.0"
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: flux-system
EOF

kubectl apply -f /tmp/broken-helmrelease.yaml

# Watch it fail
flux get helmreleases -A
kubectl describe helmrelease broken -n monitoring

# Check events
kubectl get events -n monitoring --sort-by='.lastTimestamp' | grep broken

# Clean up
kubectl delete helmrelease broken -n monitoring
```

#### Knowledge Checklist

- [ ] **Flux Architecture**: What's the purpose of each controller? Check: `kubectl get pods -n flux-system`
- [ ] **Source Controller**: How does GitRepository work? Check: `flux get sources git`
- [ ] **Kustomize Controller**: What does it do? Check: `flux get kustomizations`
- [ ] **Helm Controller**: How does HelmRelease work? Check: `flux get hr -A`
- [ ] **Reconciliation**: What's the difference between interval and retryInterval?
- [ ] **Dependencies**: Can Kustomizations depend on each other? Check: `kubectl get kustomization -A -o yaml | grep -A5 dependsOn`
- [ ] **Health Checks**: How does Flux determine if a HelmRelease is healthy? Check: `kubectl describe hr -n monitoring`
- [ ] **Pruning**: What happens to resources when you remove them from Git? Check: gotk-sync.yaml line 24

#### Practice Questions

**Q: How does Flux differ from ArgoCD?**
- Your answer should mention: Kubernetes-native CRDs, pull vs push, multi-tenancy, image automation

**Q: How do you debug a failing HelmRelease?**
```bash
# Show the process
flux get helmreleases -A
kubectl describe helmrelease prometheus -n monitoring
flux logs --kind=HelmRelease --name=prometheus --namespace=monitoring
helm list -n monitoring
helm history prometheus -n monitoring
```

**Q: How do you handle secrets in Flux?**
- Mention: Sealed Secrets, SOPS, External Secrets Operator
- Your repo uses a GitHub PAT stored as a secret: `kubectl get secret flux-system -n flux-system`

**Q: What's the difference between Flux Kustomization and kubectl kustomize?**
- Flux Kustomization is a CRD that watches sources and applies kustomizations
- kubectl kustomize is a CLI tool
- Show: `kubectl get kustomization -n flux-system` vs kustomization.yaml files

**Q: How do you do progressive delivery with Flux?**
- Mention: Flagger (not in your setup), canary deployments, A/B testing
- Your setup is basic reconciliation

---

### HELM - 2 hours

#### Explore Your Repo (40 mins)

**Files to examine:**
```bash
# Your HelmRelease definitions
cat /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/prometheus/helmrelease.yaml
cat /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/grafana/helmrelease.yaml

# HelmRepository definitions
cat /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/prometheus/helmrepository.yaml
cat /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/grafana/helmrepository.yaml
```

**Commands to run:**
```bash
# List Helm releases
helm list -A

# Get release details
helm get values prometheus -n monitoring
helm get values grafana -n monitoring

# Get all manifests rendered by Helm
helm get manifest prometheus -n monitoring > /tmp/prometheus-manifests.yaml
cat /tmp/prometheus-manifests.yaml

# Check Helm chart info
helm show chart prometheus-community/prometheus
helm show values prometheus-community/prometheus | head -100
helm show readme prometheus-community/prometheus | head -50

# Check Helm history
helm history prometheus -n monitoring
helm history grafana -n monitoring

# Search for charts
helm search repo prometheus
helm search repo grafana

# Update repo cache
helm repo list
helm repo update
```

**Questions to answer:**
1. What values are overridden in the prometheus HelmRelease?
2. Why is persistentVolume disabled for prometheus?
3. What's the version constraint "25.x" - what does it mean?
4. Where are the HelmRepositories defined and why in flux-system namespace?
5. How does Helm track release state? (Check secrets in monitoring namespace)

#### Hands-On Exercises (1 hour)

**Exercise 1: Inspect Rendered Templates**
```bash
# Get the prometheus chart
helm pull prometheus-community/prometheus --version 25.0.0 --untar --untardir /tmp

# Look at the templates
ls /tmp/prometheus/templates/

# Look at a specific template
cat /tmp/prometheus/templates/server/deployment.yaml

# See how values are used
grep -n "{{ .Values" /tmp/prometheus/templates/server/deployment.yaml | head -20

# Render templates locally with your values
cat > /tmp/my-values.yaml << 'EOF'
server:
  replicaCount: 1
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
EOF

helm template my-prometheus /tmp/prometheus -f /tmp/my-values.yaml > /tmp/rendered.yaml
cat /tmp/rendered.yaml | head -100
```

**Exercise 2: Compare HelmRelease Values to Chart Defaults**
```bash
# Get default values from chart
helm show values prometheus-community/prometheus > /tmp/prometheus-defaults.yaml

# Get your deployed values
helm get values prometheus -n monitoring > /tmp/prometheus-deployed.yaml

# Compare
diff /tmp/prometheus-defaults.yaml /tmp/prometheus-deployed.yaml

# What's different?
grep -A10 "server:" /tmp/prometheus-deployed.yaml
grep -A10 "alertmanager:" /tmp/prometheus-deployed.yaml
```

**Exercise 3: Modify HelmRelease Values**

**IMPORTANT**: This exercise pushes changes to Git. Consider using a feature branch:
```bash
cd /Users/geoagriogiannis/Documents/GitHub/gitops
git checkout -b test-scale-prometheus
```

```bash
# Current prometheus replicas is 1. Let's change to 2
cat /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/prometheus/helmrelease.yaml

# Edit the file
cat > /Users/geoagriogiannis/Documents/GitHub/gitops/kubernetes/apps/prometheus/helmrelease.yaml << 'EOF'
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
      replicaCount: 2
      persistentVolume:
        enabled: false
      resources:
        limits:
          cpu: 500m
          memory: 512Mi
        requests:
          cpu: 100m
          memory: 256Mi
    alertmanager:
      enabled: false
    kube-state-metrics:
      enabled: true
    prometheus-node-exporter:
      enabled: true
    prometheus-pushgateway:
      enabled: false
EOF

# Commit and push
cd /Users/geoagriogiannis/Documents/GitHub/gitops
git add kubernetes/apps/prometheus/helmrelease.yaml
git commit -m "Scale prometheus to 2 replicas"
git push

# Watch Helm upgrade
watch helm list -n monitoring
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -w

# Verify
kubectl get deployment prometheus-server -n monitoring -o jsonpath='{.spec.replicas}'

# Restore
git revert HEAD
git push

# Return to master if you used a feature branch
git checkout master
git branch -D test-scale-prometheus
```

**Exercise 4: Understand Helm Release Secrets**
```bash
# Helm stores release info as secrets
kubectl get secrets -n monitoring

# Decode a Helm release secret
kubectl get secret -n monitoring -l owner=helm -o yaml

# See the release metadata
# Note: The secret name includes version number (v1, v2, etc.) which increments with each release
# Check available versions first
kubectl get secrets -n monitoring -l name=prometheus,owner=helm --sort-by=.metadata.creationTimestamp

# Decode the latest release (adjust version number as needed)
LATEST_VERSION=$(kubectl get secrets -n monitoring -l name=prometheus,owner=helm -o jsonpath='{.items[-1].metadata.name}')
kubectl get secret $LATEST_VERSION -n monitoring -o jsonpath='{.data.release}' | base64 -d | base64 -d | gunzip | jq .

# Check how many releases exist
kubectl get secrets -n monitoring -l name=prometheus,owner=helm
```

**Exercise 5: Install a Chart Directly (Outside Flux)**
```bash
# Install a test chart with Helm CLI
helm install my-nginx bitnami/nginx \
  --namespace monitoring \
  --set replicaCount=1 \
  --create-namespace

# List releases
helm list -n monitoring

# Check what was created
kubectl get all -n monitoring -l app.kubernetes.io/instance=my-nginx

# Upgrade it
helm upgrade my-nginx bitnami/nginx \
  --namespace monitoring \
  --set replicaCount=2

# Check history
helm history my-nginx -n monitoring

# Rollback
helm rollback my-nginx 1 -n monitoring

# Uninstall
helm uninstall my-nginx -n monitoring
```

**Exercise 6: Chart Development Basics**
```bash
# Create a simple chart
helm create /tmp/mychart

# Look at the structure
tree /tmp/mychart

# Examine files
cat /tmp/mychart/Chart.yaml
cat /tmp/mychart/values.yaml
cat /tmp/mychart/templates/deployment.yaml

# Lint the chart
helm lint /tmp/mychart

# Render templates without installing
helm template test /tmp/mychart

# Modify a value and see the difference
helm template test /tmp/mychart --set replicaCount=3
```

#### Knowledge Checklist

- [ ] **Chart Structure**: What are the required files in a Helm chart? Check: `/tmp/prometheus/`
- [ ] **Values Hierarchy**: How do default values, values files, and --set interact? Test with helm template
- [ ] **Template Functions**: What's the difference between `{{ .Values.foo }}` and `{{ .Values.foo | quote }}`?
- [ ] **Helm Hooks**: What are pre-install, post-install hooks? Check: `grep -r "helm.sh/hook" /tmp/prometheus/templates/`
- [ ] **Dependencies**: How do charts specify dependencies? Check: `cat /tmp/prometheus/Chart.yaml | grep -A10 dependencies`
- [ ] **Version Constraints**: What does "25.x" mean? What about "~25.0.0" or ">=25.0.0 <26.0.0"?
- [ ] **Release State**: Where does Helm store release info? Check: `kubectl get secrets -n monitoring -l owner=helm`
- [ ] **Helm vs Kubectl**: When would you use one over the other?

#### Practice Questions

**Q: How does Helm handle upgrades and rollbacks?**
```bash
# Show the process
helm history prometheus -n monitoring
helm get manifest prometheus -n monitoring
# Explain: Helm compares current state with desired state, applies diff
# Rollback: helm rollback RELEASE REVISION
```

**Q: What are Helm hooks and when would you use them?**
```bash
# Check if your charts use hooks
helm get manifest prometheus -n monitoring | grep -A5 "helm.sh/hook"
# Explain: pre-install, post-install, pre-delete, etc.
```

**Q: How do you debug a failed Helm release?**
```bash
# Show the debugging process
helm list -n monitoring
helm status prometheus -n monitoring
helm get values prometheus -n monitoring
helm get manifest prometheus -n monitoring
kubectl get events -n monitoring --sort-by='.lastTimestamp'
```

**Q: What's the difference between Helm 2 and Helm 3?**
- Your answer: Tiller removed, 3-way merge, secrets for storage, library charts, OCI support

**Q: How do you handle secrets in Helm charts?**
- External Secrets, Sealed Secrets, SOPS, Kubernetes secrets with encryption at rest
- Check: `helm get manifest prometheus -n monitoring | grep -i secret`

---

### CI/CD - GITHUB ACTIONS - 2 hours

#### GitHub Actions Structure Overview (30 mins)

**Core Concepts to Understand:**

```yaml
# Workflow file structure (.github/workflows/*.yml)

name: Workflow Name              # Display name in GitHub UI

run-name: "Dynamic name"         # Dynamic run name with expressions

on:                              # TRIGGERS - when does this run?
  push:                          # On git push
    branches: [master]           # Only these branches
    paths: ['terraform/**']      # Only when these paths change
  pull_request:                  # On PR events
  workflow_dispatch:             # Manual trigger with inputs
    inputs:
      action:
        type: choice
        options: [plan, apply]
  schedule:                      # Cron-based triggers
    - cron: '0 0 * * *'

env:                             # ENVIRONMENT VARIABLES - workflow level
  MY_VAR: value
  SECRET_VAR: ${{ secrets.NAME }}

jobs:                            # JOBS - units of work
  job-name:
    runs-on: ubuntu-latest       # Runner type
    needs: [other-job]           # Job dependencies
    if: condition                # Conditional execution
    defaults:
      run:
        working-directory: dir   # Default working directory

    steps:                       # STEPS - sequential tasks
      - name: Step name
        uses: action@version     # Use a pre-built action
        with:                    # Action inputs
          input-name: value

      - name: Run command
        run: |                   # Run shell commands
          echo "Hello"
        env:                     # Step-level env vars
          STEP_VAR: value
        if: condition            # Conditional step
        continue-on-error: true  # Don't fail job if step fails
```

**Key Expressions:**
```yaml
${{ github.event_name }}         # Event that triggered workflow
${{ github.actor }}              # User who triggered
${{ github.ref }}                # Branch/tag ref
${{ github.sha }}                # Commit SHA
${{ secrets.SECRET_NAME }}       # Repository secret
${{ env.VAR_NAME }}              # Environment variable
${{ needs.job.outputs.var }}     # Output from previous job
${{ github.event.inputs.name }}  # Manual trigger input
```

#### Explore Your Repo (30 mins)

**Files to study line-by-line:**
```bash
cat /Users/geoagriogiannis/Documents/GitHub/gitops/.github/workflows/terraform-deploy.yml
cat /Users/geoagriogiannis/Documents/GitHub/gitops/.github/workflows/terraform-destroy.yml
```

**Your terraform-deploy.yml Analysis:**

| Line | What It Does | Why It Matters |
|------|--------------|----------------|
| 3 | Dynamic `run-name` with ternary | Shows PLAN vs APPLY in UI, includes actor name for audit |
| 5-20 | Dual triggers: push + workflow_dispatch | Auto-plan on push, manual apply for safety |
| 9-10 | Path filter `terraform/**` | Only runs when Terraform files change |
| 22-27 | Environment variables from secrets | Injects Terraform variables securely |
| 30 | Job `bootstrap` | Enables GCP APIs before main Terraform |
| 58-60 | `needs: bootstrap` | Ensures bootstrap runs first |
| 78-88 | Idempotent GCS bucket creation | Safe to re-run, checks before creating |
| 98-100 | `continue-on-error: true` on fmt | Warns but doesn't fail on formatting |
| 105-110 | Plan always, apply only on dispatch | Safety gate for infrastructure changes |

**Your terraform-destroy.yml Analysis:**

| Line | What It Does | Why It Matters |
|------|--------------|----------------|
| 4-9 | Manual trigger only with confirmation | Prevents accidental destruction |
| 27-31 | Validation step that fails if wrong input | Double-safety for destructive action |

**Questions to answer by reading the workflows:**
1. What triggers a plan vs an apply?
2. Why is bootstrap a separate job?
3. How are secrets passed to Terraform?
4. What's the purpose of `continue-on-error` on fmt check?
5. Why use `terraform plan -out=tfplan` then `terraform apply tfplan`?
6. How does the destroy workflow prevent accidents?

#### Hands-On Exercises (45 mins)

**Exercise 1: Trace a Workflow Run**
```bash
# Go to GitHub Actions tab in your repo
# Find a recent workflow run
# Click into it and examine:
# - Which trigger started it (push vs dispatch)?
# - Did bootstrap run? Did deploy run?
# - How long did each job take?
# - Check the logs for each step
```

**Exercise 2: Understand Job Dependencies**
```bash
# In terraform-deploy.yml:
# - bootstrap job has no 'needs'
# - deploy job has 'needs: bootstrap'
#
# What happens if bootstrap fails?
# Answer: deploy job is skipped
#
# Visualize in GitHub UI: Actions -> Select run -> See job graph
```

**Exercise 3: Manually Trigger a Plan**
```bash
# Go to Actions tab
# Select "Terraform Infrastructure" workflow
# Click "Run workflow"
# Select branch: master
# Select action: plan
# Click "Run workflow"
# Watch the run execute
```

**Exercise 4: Examine Secrets Usage**
```bash
# List secrets used in your workflows:
grep -h "secrets\." /Users/geoagriogiannis/Documents/GitHub/gitops/.github/workflows/*.yml | sort -u

# You should see:
# - secrets.GCP_PROJECT_ID
# - secrets.GCP_REGION
# - secrets.GCP_SA_KEY
# - secrets.FLUX_GITHUB_TOKEN

# These are set in: Repo Settings -> Secrets and variables -> Actions
```

**Exercise 5: Add a New Workflow Step (Don't Commit)**
```bash
# Create a test workflow to understand structure
cat > /tmp/test-workflow.yml << 'EOF'
name: Test Workflow

on:
  workflow_dispatch:
    inputs:
      message:
        description: 'Message to echo'
        required: true
        default: 'Hello World'

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Echo message
        run: echo "${{ github.event.inputs.message }}"

      - name: Show context
        run: |
          echo "Event: ${{ github.event_name }}"
          echo "Actor: ${{ github.actor }}"
          echo "Ref: ${{ github.ref }}"
          echo "SHA: ${{ github.sha }}"
EOF

# Read it and understand each part
cat /tmp/test-workflow.yml
```

**Exercise 6: Simulate Adding Validation**
```bash
# Your workflow has terraform fmt and validate
# Study what they do:

cd /Users/geoagriogiannis/Documents/GitHub/gitops/terraform

# Format check (what the workflow does)
terraform fmt -check
# Returns 0 if formatted, non-zero if not

# Validate (what the workflow does)
terraform validate
# Returns 0 if valid, non-zero if errors

# Try breaking formatting
echo "   " >> main.tf
terraform fmt -check
# Should fail

# Fix it
terraform fmt
git checkout main.tf
```

**Exercise 7: Understand Conditional Execution**
```bash
# Your workflow uses conditionals:

# Line 55: if: github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'apply'
# This means: only run terraform apply if manually triggered AND action is 'apply'

# Line 109: Same condition for main apply

# What this achieves:
# - Push to master = plan only (safe)
# - Manual dispatch with 'plan' = plan only
# - Manual dispatch with 'apply' = plan AND apply

# Test understanding: What would happen with this condition?
# if: github.ref == 'refs/heads/master'
# Answer: Only run on master branch, any trigger
```

#### Knowledge Checklist

Test yourself on these concepts:

- [ ] **Triggers**: Explain `push`, `pull_request`, `workflow_dispatch`, `schedule`. Check: lines 5-20 in deploy workflow
- [ ] **Job Dependencies**: What does `needs: bootstrap` do? What if bootstrap fails?
- [ ] **Secrets**: How are secrets different from env vars? Check: lines 22-27
- [ ] **Conditionals**: Explain `if:` at job level vs step level. Check: lines 55, 109
- [ ] **Working Directory**: What does `defaults.run.working-directory` do? Check: lines 34-36
- [ ] **Continue on Error**: When would you use `continue-on-error: true`? Check: line 100
- [ ] **Expressions**: What's the difference between `${{ secrets.X }}` and `${{ env.X }}`?
- [ ] **Plan vs Apply**: Why separate them? Why require manual trigger for apply?

#### Common GitHub Actions Patterns

**Pattern 1: Plan on PR, Apply on Merge**
```yaml
on:
  pull_request:
    branches: [master]
  push:
    branches: [master]

jobs:
  terraform:
    steps:
      - run: terraform plan
      - run: terraform apply -auto-approve
        if: github.event_name == 'push'  # Only on merge to master
```

**Pattern 2: Matrix Strategy**
```yaml
jobs:
  test:
    strategy:
      matrix:
        environment: [dev, staging, prod]
    steps:
      - run: terraform plan -var-file=${{ matrix.environment }}.tfvars
```

**Pattern 3: Reusable Workflows**
```yaml
# .github/workflows/terraform-reusable.yml
on:
  workflow_call:
    inputs:
      environment:
        required: true
        type: string

# .github/workflows/deploy-dev.yml
jobs:
  deploy:
    uses: ./.github/workflows/terraform-reusable.yml
    with:
      environment: dev
```

**Pattern 4: Environment Protection Rules**
```yaml
jobs:
  deploy-prod:
    environment: production  # Requires approval in GitHub settings
    steps:
      - run: terraform apply
```

**Pattern 5: Artifacts Between Jobs**
```yaml
jobs:
  plan:
    steps:
      - run: terraform plan -out=tfplan
      - uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: tfplan

  apply:
    needs: plan
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: tfplan
      - run: terraform apply tfplan
```

#### Practice Questions

**Q: Walk me through your CI/CD pipeline for infrastructure changes.**
```
Answer using YOUR workflow:
1. Developer pushes to master OR manually triggers
2. Bootstrap job enables GCP APIs (idempotent)
3. Deploy job runs: init → fmt check → validate → plan
4. Apply only runs if manually triggered with 'apply' action
5. Destroy is separate workflow with confirmation gate
```

**Q: How do you handle secrets in GitHub Actions?**
```
Answer:
- Secrets stored in repo Settings -> Secrets
- Accessed via ${{ secrets.NAME }}
- Never logged (GitHub masks them)
- Passed as env vars to Terraform via TF_VAR_*
- For more security: use OIDC with cloud providers instead of static keys
```

**Q: How would you implement pull request-based infrastructure review?**
```
Answer:
- Trigger on pull_request
- Run terraform plan
- Post plan output as PR comment (using actions)
- Require approval before merge
- Apply only on merge to master
```

**Q: What's the difference between `env` at workflow level vs job level vs step level?**
```
Answer:
- Workflow level: Available to all jobs
- Job level: Available to all steps in that job
- Step level: Only available to that step
- More specific overrides more general
```

**Q: How do you debug a failing GitHub Actions workflow?**
```
Answer:
1. Check workflow run logs in Actions tab
2. Look for red X on failed step
3. Expand step logs for error details
4. Add debug logging: echo statements, set -x
5. Use actions/upload-artifact to capture files
6. For secrets issues: check Settings -> Secrets
7. Use act (https://github.com/nektos/act) to run locally
```

**Q: How would you add linting/security scanning to this pipeline?**
```
Answer (for your Terraform workflow):
- Add tflint for Terraform best practices
- Add checkov or tfsec for security scanning
- Add infracost for cost estimation
- Run before plan, fail on critical issues

Example step:
- name: Security scan
  uses: aquasecurity/tfsec-action@v1
  with:
    soft_fail: true  # or false to block
```

**Q: When would you use workflow_dispatch vs push trigger?**
```
Answer:
- push: Automatic on code changes (CI)
- workflow_dispatch: Manual control (CD for production)
- Your workflow uses both: auto-plan on push, manual apply
- This is a safety pattern for infrastructure
```

---

## Troubleshooting Scenarios

These are common real-world problems you'll encounter. Practice diagnosing and fixing them.

### Scenario 1: Pod CrashLoopBackOff

**Symptoms**: Pod keeps restarting, never reaches Running state

**Diagnosis Steps**:
```bash
# Identify the crashing pod
kubectl get pods -A | grep -i crash

# Check pod status and recent events
kubectl describe pod <POD_NAME> -n <NAMESPACE>

# Check logs from current container
kubectl logs <POD_NAME> -n <NAMESPACE>

# Check logs from previous crashed container
kubectl logs <POD_NAME> -n <NAMESPACE> --previous

# Check if it's a resource issue
kubectl top pod <POD_NAME> -n <NAMESPACE>

# Check container exit code
kubectl get pod <POD_NAME> -n <NAMESPACE> -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'
```

**Common Causes and Fixes**:

1. **Missing ConfigMap or Secret**:
   ```bash
   # Check what the pod is trying to mount
   kubectl get pod <POD_NAME> -n <NAMESPACE> -o yaml | grep -A5 "volumes:"

   # Verify the ConfigMap/Secret exists
   kubectl get configmap,secret -n <NAMESPACE>
   ```

2. **Application Error**:
   ```bash
   # Check logs for stack trace or error message
   kubectl logs <POD_NAME> -n <NAMESPACE> --previous | tail -50

   # If it's a liveness probe failure, check probe config
   kubectl get pod <POD_NAME> -n <NAMESPACE> -o jsonpath='{.spec.containers[0].livenessProbe}'
   ```

3. **Resource Limits**:
   ```bash
   # Check if OOMKilled
   kubectl describe pod <POD_NAME> -n <NAMESPACE> | grep -A5 "Last State"

   # Increase memory limits in deployment/helmrelease
   kubectl get deployment <DEPLOYMENT> -n <NAMESPACE> -o yaml | grep -A10 resources
   ```

4. **Permission Issues**:
   ```bash
   # Check security context
   kubectl get pod <POD_NAME> -n <NAMESPACE> -o jsonpath='{.spec.securityContext}'

   # Check service account
   kubectl get pod <POD_NAME> -n <NAMESPACE> -o jsonpath='{.spec.serviceAccountName}'
   kubectl get serviceaccount <SA_NAME> -n <NAMESPACE> -o yaml
   ```

### Scenario 2: Flux Reconciliation Stuck

**Symptoms**: HelmRelease shows "Reconciling" for extended period, changes in Git not applied

**Diagnosis Steps**:
```bash
# Check Flux system health
flux check

# Check all Flux resources status
flux get all

# Check specific HelmRelease
flux get helmrelease <RELEASE_NAME> -n <NAMESPACE>

# Check detailed status and events
kubectl describe helmrelease <RELEASE_NAME> -n <NAMESPACE>

# Check Flux logs
flux logs --kind=HelmRelease --name=<RELEASE_NAME> --namespace=<NAMESPACE>

# Check helm-controller logs
kubectl logs -n flux-system deploy/helm-controller -f

# Check source-controller logs (for Git fetch issues)
kubectl logs -n flux-system deploy/source-controller -f
```

**Common Causes and Fixes**:

1. **Git Authentication Failure**:
   ```bash
   # Check GitRepository status
   flux get sources git
   kubectl describe gitrepository flux-system -n flux-system

   # Verify GitHub PAT secret is valid
   kubectl get secret flux-system -n flux-system -o yaml

   # Test Git access manually
   git ls-remote https://github.com/<USER>/<REPO>.git
   ```

2. **Helm Chart Not Found**:
   ```bash
   # Check HelmRepository status
   flux get sources helm
   kubectl describe helmrepository <REPO_NAME> -n flux-system

   # Verify chart exists
   helm search repo <REPO_NAME>/<CHART_NAME>

   # Force HelmRepository update
   flux reconcile source helm <REPO_NAME> -n flux-system
   ```

3. **Invalid HelmRelease Values**:
   ```bash
   # Get current values
   kubectl get helmrelease <RELEASE_NAME> -n <NAMESPACE> -o yaml

   # Test rendering locally
   helm template <RELEASE_NAME> <REPO>/<CHART> -f values.yaml --dry-run

   # Check for validation errors in events
   kubectl get events -n <NAMESPACE> --sort-by='.lastTimestamp' | grep <RELEASE_NAME>
   ```

4. **Resource in Suspended State**:
   ```bash
   # Check if suspended
   flux get helmreleases -A | grep -i suspend

   # Resume if needed
   flux resume helmrelease <RELEASE_NAME> -n <NAMESPACE>

   # Force reconciliation
   flux reconcile helmrelease <RELEASE_NAME> -n <NAMESPACE>
   ```

5. **Kustomization Dependency Not Met**:
   ```bash
   # Check kustomization dependencies
   kubectl get kustomization -n flux-system -o yaml | grep -A5 dependsOn

   # Check if dependency is healthy
   flux get kustomizations

   # Force reconcile the dependency first
   flux reconcile kustomization <DEPENDENCY_NAME> -n flux-system
   ```

### Scenario 3: Terraform State Lock

**Symptoms**: Terraform commands hang or fail with "Error acquiring the state lock"

**Diagnosis Steps**:
```bash
cd /Users/geoagriogiannis/Documents/GitHub/gitops/terraform

# Try to run terraform plan
terraform plan
# Will show lock info including Lock ID and who owns it

# Check state backend configuration
cat backend.tf  # or wherever backend is configured

# For GCS backend, check lock info
gsutil ls gs://<BUCKET_NAME>/<STATE_FILE>.lock
```

**Common Causes and Fixes**:

1. **Previous Operation Interrupted**:
   ```bash
   # Check if any terraform process is still running
   ps aux | grep terraform

   # If stale lock, force unlock (USE WITH CAUTION)
   # Get the Lock ID from the error message
   terraform force-unlock <LOCK_ID>

   # Confirm no one else is actually running terraform
   # Then try your operation again
   terraform plan
   ```

2. **CI/CD Pipeline Still Running**:
   ```bash
   # Check GitHub Actions
   gh run list --workflow=terraform-deploy.yml --limit=5

   # Check if any runs are in progress
   gh run list --workflow=terraform-deploy.yml --status=in_progress

   # If needed, cancel the run
   gh run cancel <RUN_ID>

   # Wait for lock to release, then proceed
   ```

3. **Multiple Users/Sessions**:
   ```bash
   # Error message shows who has the lock and when
   # Contact that person or wait for their operation to complete

   # If you KNOW it's safe (e.g., your own stale lock)
   terraform force-unlock <LOCK_ID>
   ```

4. **Backend Credentials Issue**:
   ```bash
   # Verify GCP authentication
   gcloud auth list
   gcloud config get-value project

   # Test access to state bucket
   gsutil ls gs://<BUCKET_NAME>/

   # If auth expired, re-authenticate
   gcloud auth application-default login
   ```

**Prevention Best Practices**:
```bash
# Always let terraform complete (don't Ctrl+C unless necessary)
# If you must interrupt, use:
# - Ctrl+C once (terraform will try to cleanup)
# - Wait for "Interrupt received" message
# - Only Ctrl+C again if terraform truly hangs

# Use state locking in backend configuration (already done in your repo)
# Use CI/CD for team environments to serialize operations
# Consider using Terraform Cloud/Enterprise for better collaboration
```

**Emergency State Recovery**:
```bash
# If state is corrupted or lost
# Pull a backup from GCS versioning
gsutil ls -a gs://<BUCKET_NAME>/terraform.tfstate

# Download a previous version
gsutil cp gs://<BUCKET_NAME>/terraform.tfstate#<VERSION> ./terraform.tfstate.backup

# Restore if needed (after backing up current state)
terraform state pull > current-state.json
terraform state push terraform.tfstate.backup
```

---

## Quick Command Reference

### Terraform
```bash
cd /Users/geoagriogiannis/Documents/GitHub/gitops/terraform
terraform state list
terraform state show RESOURCE
terraform plan
terraform output
terraform graph
```

### GCP
```bash
gcloud container clusters describe CLUSTER --zone=ZONE
gcloud container node-pools list --cluster=CLUSTER --zone=ZONE
gcloud services list --enabled
gcloud projects get-iam-policy PROJECT
```

### Kubernetes
```bash
kubectl get all -A
kubectl describe pod POD -n NAMESPACE
kubectl logs POD -n NAMESPACE
kubectl get events -n NAMESPACE --sort-by='.lastTimestamp'
kubectl top nodes
kubectl top pods -A
```

### Flux
```bash
flux check
flux get all
flux get sources git
flux get kustomizations
flux get helmreleases -A
flux reconcile source git flux-system
flux logs --level=info
```

### Helm
```bash
helm list -A
helm get values RELEASE -n NAMESPACE
helm get manifest RELEASE -n NAMESPACE
helm history RELEASE -n NAMESPACE
helm show values CHART
```

### GitHub Actions
```bash
# View workflow files
ls -la .github/workflows/
cat .github/workflows/terraform-deploy.yml

# Check workflow syntax locally (requires act)
act -l                              # List workflows
act -n                              # Dry run
act workflow_dispatch               # Run locally

# GitHub CLI for workflows
gh workflow list
gh workflow view terraform-deploy.yml
gh run list --workflow=terraform-deploy.yml
gh run view RUN_ID
gh run watch RUN_ID
```

---
## Final Checklist

**Day Before Practice:**
- [ ] Run `terraform plan` - make sure you understand every resource
- [ ] Run `flux get all` - explain what each resource does
- [ ] Run `helm list -A` - explain each release
- [ ] Read `.github/workflows/*.yml` - explain each step's purpose
- [ ] Check cluster health: `kubectl get nodes; kubectl get pods -A`
- [ ] Review this doc and mark anything you couldn't explain

**Practice Day:**
- [ ] Have kubeconfig connected to cluster
- [ ] Have GCP credentials active
- [ ] Have repo cloned and ready
- [ ] Have terminal with proper PATH for all tools
- [ ] Test all tools work: `terraform version; gcloud version; kubectl version; flux version; helm version`

**If Asked to Demonstrate:**
- "Let me show you in my local setup" (keep it brief)
- Show a specific file or command output
- Don't walk through everything unless asked
- Focus on explaining concepts, not touring the repo
