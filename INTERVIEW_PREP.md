# GitOps Repo Interview Prep - Hands-On Learning Plan

**Timeline**: 2 days focused, hands-on learning
**Goal**: Refresh knowledge through experimentation, not theory

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

#### Interview Questions to Practice

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

#### Interview Questions to Practice

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

#### Interview Questions to Practice

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

#### Interview Questions to Practice

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

#### Interview Questions to Practice

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

#### Interview Questions to Practice

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

**Q: How would you implement PR-based infrastructure review?**
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

## Quick Command Reference for Interview Day

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

## Day 3: RKE Deep Dive + Kubernetes Internals

This section focuses on Rancher Kubernetes Engine (RKE), Kubernetes control plane internals, and advanced topics for supporting production RKE clusters.

### RKE ARCHITECTURE & FUNDAMENTALS - 2.5 hours

#### RKE1 vs RKE2 Architecture (45 mins)

**Understanding the Differences:**

| Aspect | RKE1 | RKE2 |
|--------|------|------|
| **Architecture** | Docker-based, components in containers | containerd-native, some as static pods |
| **Installation** | CLI tool (rke binary) generates config | systemd service, more like a distro |
| **Security** | CIS hardening manual | CIS 1.6 compliant by default |
| **Configuration** | cluster.yml (single file) | config.yaml + server/agent model |
| **Upgrades** | Manual rke up with new version | systemd service upgrade or helm |
| **etcd** | etcd in Docker container | etcd as part of rke2-server process |
| **Network Policies** | Optional, manual | Enabled by default |
| **PSPs/PSS** | Manual configuration | Pod Security Standards by default |
| **Use Case** | Legacy, simpler setups | Production, compliance-focused |

**RKE1 Architecture Deep Dive:**

```
┌─────────────────────────────────────────────────────────────┐
│                        Control Plane                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   etcd       │  │  API Server  │  │  Scheduler   │      │
│  │  (Docker)    │  │   (Docker)   │  │   (Docker)   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│  ┌──────────────────────────────────┐                       │
│  │   Controller Manager (Docker)    │                       │
│  └──────────────────────────────────┘                       │
│  ┌──────────────────────────────────┐                       │
│  │    kubelet + kube-proxy + CNI    │                       │
│  └──────────────────────────────────┘                       │
└─────────────────────────────────────────────────────────────┘
                            │
                    Docker Engine
                            │
                      Host OS
```

**RKE2 Architecture Deep Dive:**

```
┌─────────────────────────────────────────────────────────────┐
│                        rke2-server                          │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Embedded etcd + API Server + Scheduler + Controller│    │
│  │  Manager (all in rke2-server systemd service)       │    │
│  └─────────────────────────────────────────────────────┘    │
│  ┌──────────────────────────────────────┐                   │
│  │    kubelet (part of rke2-server)     │                   │
│  └──────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
                            │
                      containerd
                            │
                      Host OS (systemd)
```

**Key Architectural Differences:**

1. **Process Model**:
   - RKE1: Each component in separate Docker container
   - RKE2: Single rke2-server/rke2-agent binary as systemd service

2. **Container Runtime**:
   - RKE1: Docker required
   - RKE2: containerd only (Docker not needed)

3. **Security Posture**:
   - RKE1: Open by default, harden manually
   - RKE2: Hardened by default (CIS 1.6 compliant)

4. **Management**:
   - RKE1: rke CLI tool manages cluster lifecycle
   - RKE2: systemd manages service, kubectl for cluster

#### RKE1 cluster.yml Deep Dive (30 mins)

**Complete cluster.yml Anatomy:**

```yaml
# Basic cluster identity
cluster_name: production-cluster

# Node definitions - SSH-based provisioning
nodes:
  - address: 10.0.1.10
    user: ubuntu
    role: [controlplane, etcd]
    ssh_key_path: ~/.ssh/id_rsa
    port: 22
    labels:
      node-role: control
    taints:
      - key: node-role
        value: control
        effect: NoSchedule

  - address: 10.0.1.11
    user: ubuntu
    role: [worker]
    ssh_key_path: ~/.ssh/id_rsa
    labels:
      node-role: worker

  - address: 10.0.1.12
    user: ubuntu
    role: [worker]
    ssh_key_path: ~/.ssh/id_rsa

# Kubernetes version
kubernetes_version: v1.28.5-rancher1-1

# Services configuration
services:
  # etcd service
  etcd:
    # Snapshot configuration
    snapshot: true
    creation: 6h
    retention: 24h
    # Backup to S3
    backup_config:
      enabled: true
      interval_hours: 12
      retention: 6
      s3_backup_config:
        access_key: ""
        secret_key: ""
        bucket_name: rke-etcd-backup
        endpoint: s3.amazonaws.com
        region: us-west-2
    # etcd resource limits
    extra_args:
      election-timeout: "5000"
      heartbeat-interval: "500"
    # TLS cipher suites
    extra_binds:
      - "/var/lib/etcd:/var/lib/etcd"

  # kube-api configuration
  kube-api:
    service_cluster_ip_range: 10.43.0.0/16
    service_node_port_range: 30000-32767
    pod_security_policy: true
    always_pull_images: false
    # Audit log configuration
    audit_log:
      enabled: true
      configuration:
        max_age: 30
        max_backup: 10
        max_size: 100
        path: /var/log/kube-audit/audit-log.json
        format: json
        policy:
          apiVersion: audit.k8s.io/v1
          kind: Policy
          rules:
            - level: Metadata
    # API server flags
    extra_args:
      anonymous-auth: "false"
      profiling: "false"
      service-account-lookup: "true"
      enable-admission-plugins: "NodeRestriction,PodSecurityPolicy"
      encryption-provider-config: "/etc/kubernetes/encryption.yaml"
    # Extra volumes for encryption config
    extra_binds:
      - "/opt/kubernetes/encryption.yaml:/etc/kubernetes/encryption.yaml"

  # kube-controller configuration
  kube-controller:
    cluster_cidr: 10.42.0.0/16
    service_cluster_ip_range: 10.43.0.0/16
    extra_args:
      profiling: "false"
      terminated-pod-gc-threshold: "1000"
      feature-gates: "RotateKubeletServerCertificate=true"

  # scheduler configuration
  scheduler:
    extra_args:
      profiling: "false"

  # kubelet configuration
  kubelet:
    cluster_domain: cluster.local
    cluster_dns_server: 10.43.0.10
    fail_swap_on: false
    generate_serving_certificate: true
    extra_args:
      max-pods: "110"
      feature-gates: "RotateKubeletServerCertificate=true"
      protect-kernel-defaults: "true"
      tls-cipher-suites: "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"

  # kubeproxy configuration
  kubeproxy:
    extra_args:
      proxy-mode: "iptables"

# Network plugin configuration
network:
  plugin: canal
  options:
    canal_flannel_backend_type: vxlan
    canal_autoscaler_priority_class_name: system-cluster-critical
    canal_priority_class_name: system-cluster-critical

# Authentication
authentication:
  strategy: x509
  sans:
    - "rancher.example.com"
    - "10.0.1.10"
    - "10.0.1.11"

# Authorization
authorization:
  mode: rbac

# Addons (deployed after cluster up)
addons: |-
  ---
  apiVersion: v1
  kind: Namespace
  metadata:
    name: cattle-system
  ---
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: cattle
    namespace: cattle-system

# System images (custom registry)
system_images:
  kubernetes: rancher/hyperkube:v1.28.5-rancher1
  etcd: rancher/coreos-etcd:v3.5.9-rancher1
  alpine: rancher/rke-tools:v0.1.90
  nginx_proxy: rancher/rke-tools:v0.1.90

# Private registry configuration
private_registries:
  - url: registry.example.com
    user: admin
    password: password
    is_default: true

# Ingress controller
ingress:
  provider: nginx
  options:
    use-forwarded-headers: "true"
  node_selector:
    node-role: worker
  extra_args:
    default-ssl-certificate: "ingress-nginx/tls-cert"

# Cluster-level options
# Enable monitoring
monitoring:
  provider: metrics-server

# Restore from backup
restore:
  restore: false
  snapshot_name: ""

# Rotate certificates
rotate_certificates:
  ca_certificates: false
  services:
    - etcd
    - kubelet
    - kube-apiserver

# Upgrade strategy
upgrade_strategy:
  max_unavailable_worker: "10%"
  max_unavailable_controlplane: "1"
  drain: true
  drain_input:
    delete_local_data: true
    force: true
    grace_period: 60
    ignore_daemon_sets: true
    timeout: 120
```

**Key Sections Explained:**

1. **nodes**: SSH-based node inventory, RKE connects and provisions
2. **services**: Fine-grained control plane component configuration
3. **network**: CNI plugin selection and configuration
4. **system_images**: Override default images (air-gap scenarios)
5. **restore**: Disaster recovery from etcd snapshot
6. **upgrade_strategy**: Controls rolling upgrade behavior

**Questions to Answer:**

1. Why separate controlplane, etcd, and worker roles?
2. What's the minimum etcd cluster size for HA?
3. How does RKE use SSH keys?
4. What's the purpose of `sans` in authentication?
5. How do you add a node after initial cluster creation?

#### RKE CLI Commands - Hands-On (45 mins)

**Installation and Setup:**

```bash
# Install RKE CLI
curl -LO https://github.com/rancher/rke/releases/download/v1.5.5/rke_linux-amd64
mv rke_linux-amd64 /usr/local/bin/rke
chmod +x /usr/local/bin/rke

# Verify installation
rke --version

# Generate cluster template
rke config --name cluster.yml

# Validate cluster configuration
rke config validate --file cluster.yml
```

**Cluster Provisioning:**

```bash
# Initial cluster creation
rke up --config cluster.yml

# What happens during 'rke up':
# 1. SSH to each node
# 2. Install Docker (if not present)
# 3. Pull system images
# 4. Start etcd containers on etcd nodes
# 5. Start control plane components
# 6. Generate kubeconfig
# 7. Deploy network plugin
# 8. Deploy DNS
# 9. Deploy ingress controller
# 10. Mark cluster as ready

# Output files created:
# - kube_config_cluster.yml (kubectl config)
# - cluster.rkestate (cluster state, CRITICAL - backup this!)

# Use the cluster
export KUBECONFIG=$PWD/kube_config_cluster.yml
kubectl get nodes
```

**Cluster Operations:**

```bash
# Update cluster (apply config changes)
rke up --config cluster.yml --update-only

# Upgrade Kubernetes version
# Edit cluster.yml: kubernetes_version: v1.29.0-rancher1-1
rke up --config cluster.yml

# Add a node
# Edit cluster.yml: add new node entry
rke up --config cluster.yml
# RKE detects new node and provisions it

# Remove a node
# Edit cluster.yml: remove node entry
rke remove --config cluster.yml --force
# Then run rke up

# Check cluster health
rke util get-state-file --config cluster.yml

# View running containers on a node (SSH to node)
docker ps --filter name=kube --format "table {{.Names}}\t{{.Status}}"

# View logs from control plane component
docker logs kube-apiserver
docker logs kube-controller-manager
docker logs kube-scheduler
docker logs etcd
```

**etcd Backup and Restore:**

```bash
# Manual etcd snapshot
rke etcd snapshot-save \
  --config cluster.yml \
  --name manual-backup-$(date +%Y%m%d-%H%M%S)

# List snapshots
rke etcd snapshot-list --config cluster.yml

# Restore from snapshot
# CRITICAL: This is destructive, cluster will be recreated
rke etcd snapshot-restore \
  --config cluster.yml \
  --name manual-backup-20240215-120000

# Restore process:
# 1. Stops all cluster components
# 2. Restores etcd data from snapshot
# 3. Restarts etcd cluster
# 4. Restarts control plane
# 5. Cluster recovers with data from snapshot time

# Download snapshot from S3 (if configured)
# Snapshots are in /opt/rke/etcd-snapshots/ on etcd nodes
ssh ubuntu@10.0.1.10 "ls -la /opt/rke/etcd-snapshots/"
```

**Certificate Management:**

```bash
# Rotate all certificates (before expiry)
rke cert rotate --config cluster.yml

# Rotate specific service certificates
rke cert rotate --config cluster.yml \
  --service kubelet \
  --service kube-apiserver

# Rotate CA certificates (MAJOR operation)
# This requires cluster recreation
rke cert rotate --config cluster.yml --rotate-ca

# Check certificate expiry
# On control plane node
docker exec kube-apiserver \
  openssl x509 -in /etc/kubernetes/ssl/kube-apiserver.pem -noout -dates
```

**Troubleshooting Commands:**

```bash
# Remove cluster (cleanup)
rke remove --config cluster.yml --force
# This stops all containers and removes cluster state

# Check RKE state file
cat cluster.rkestate | jq .

# Verify node connectivity
rke util ping --config cluster.yml

# Get cluster certificates info
rke cert list --config cluster.yml

# Validate Docker installation on nodes
# RKE requires specific Docker versions
docker version
# Should be Docker CE 19.03.x or 20.10.x

# Check RKE system containers on a node
ssh ubuntu@10.0.1.10 '
  docker ps --filter name=kube --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
'

# View etcd member list
ssh ubuntu@10.0.1.10 '
  docker exec etcd etcdctl \
    --cacert=/etc/kubernetes/ssl/kube-ca.pem \
    --cert=/etc/kubernetes/ssl/kube-etcd-*.pem \
    --key=/etc/kubernetes/ssl/kube-etcd-*-key.pem \
    --endpoints=https://127.0.0.1:2379 \
    member list -w table
'
```

**Advanced Operations:**

```bash
# Upgrade strategy testing
# Dry run upgrade (see what would change)
rke up --config cluster.yml --update-only --dry-run

# Upgrade with custom drain settings
# Edit cluster.yml upgrade_strategy section
rke up --config cluster.yml

# Air-gap installation (offline)
# 1. Save required images to tarball
rke config --system-images | grep -v '^INFO' > system-images.txt
while read image; do
  docker pull $image
  docker save $image -o $(echo $image | tr '/:' '_').tar
done < system-images.txt

# 2. Load images on air-gap nodes
# 3. Configure private_registries in cluster.yml
# 4. Run rke up

# Customize addon deployments
# Use addons section in cluster.yml for day-1 configs
# Or use addons_include to reference external files
cat >> cluster.yml << 'EOF'
addons_include:
  - https://raw.githubusercontent.com/example/monitoring.yaml
  - /path/to/local/addon.yaml
EOF

# Enable cluster monitoring
# Edit cluster.yml
monitoring:
  provider: metrics-server
  options:
    nodeSelector:
      node-role: controlplane

# Test node drain during upgrade
kubectl drain node-1 \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60
# This is what RKE does during upgrades
```

#### RKE vs Other Distributions (30 mins)

**Comparison Matrix:**

| Feature | RKE1 | RKE2 | kubeadm | GKE | EKS |
|---------|------|------|---------|-----|-----|
| **Deployment** | SSH-based | Binary install | Binary install | Managed | Managed |
| **Control Plane** | User-managed | User-managed | User-managed | Google-managed | AWS-managed |
| **Node OS** | Any Linux | Any Linux | Any Linux | COS/Ubuntu | Amazon Linux |
| **Networking** | Canal/Calico/Flannel | Canal/Calico/Cilium | Manual | GKE-native | VPC-CNI |
| **Storage** | Manual | Longhorn option | Manual | GCE PD | EBS CSI |
| **Upgrades** | rke up | systemd upgrade | kubeadm upgrade | Auto/Manual | Auto/Manual |
| **HA etcd** | Manual setup | Built-in | Manual setup | Managed | Managed |
| **CIS Compliance** | Manual | Default | Manual | Partial | Partial |
| **Air-gap Support** | Yes | Yes | Yes | No | No |
| **Cost** | Free | Free | Free | Paid | Paid |

**When to Use Each:**

1. **RKE1**:
   - Legacy environments
   - Simple deployments
   - Migrating to RKE2

2. **RKE2**:
   - Production workloads
   - Compliance requirements (CIS, FIPS)
   - Edge/air-gap deployments
   - Government/regulated industries

3. **kubeadm**:
   - Learning Kubernetes
   - Custom distributions
   - Full control over every component

4. **GKE/EKS**:
   - Cloud-native workloads
   - Don't want to manage control plane
   - Need cloud integration (IAM, LB, etc)

**Key Differences:**

```bash
# RKE1: Components in Docker
ssh node-1 'docker ps | grep kube-apiserver'

# RKE2: Components as systemd service
ssh node-1 'systemctl status rke2-server'
ssh node-1 'crictl ps | grep kube-apiserver'

# kubeadm: Components as static pods
ssh node-1 'crictl ps | grep kube-apiserver'
ls /etc/kubernetes/manifests/

# GKE/EKS: Control plane not accessible
# You only interact via kubectl
```

**Migration Paths:**

```bash
# RKE1 to RKE2 migration (no in-place upgrade)
# 1. Backup RKE1 cluster (etcd + workloads)
# 2. Provision new RKE2 cluster
# 3. Migrate workloads
# 4. Switch traffic to RKE2
# 5. Decommission RKE1

# Example backup script
#!/bin/bash
# Backup RKE1 cluster
rke etcd snapshot-save --config cluster.yml --name pre-migration
kubectl get all --all-namespaces -o yaml > all-resources.yaml
kubectl get pv -o yaml > persistent-volumes.yaml
kubectl get secrets --all-namespaces -o yaml > secrets.yaml
```

#### Knowledge Checklist

- [ ] **RKE1 Architecture**: Can you diagram where each component runs?
- [ ] **cluster.yml**: Explain each major section and when you'd customize it
- [ ] **RKE CLI**: What's the difference between `rke up` and `rke up --update-only`?
- [ ] **etcd Backup**: How do you take a backup? How do you restore?
- [ ] **Certificate Rotation**: When would you rotate certs? What's the process?
- [ ] **Node Operations**: How do you add/remove nodes safely?
- [ ] **Upgrade Strategy**: What does `max_unavailable_worker: "10%"` mean?
- [ ] **RKE2 Benefits**: Why migrate from RKE1 to RKE2?
- [ ] **Troubleshooting**: What do you check if `rke up` fails halfway?

#### Interview Questions to Practice

**Q: Walk me through the RKE1 cluster provisioning process.**

Answer:
1. Create cluster.yml with node inventory and configuration
2. RKE connects to each node via SSH using provided keys
3. Validates Docker installation and version
4. Pulls required system images (etcd, hyperkube, etc)
5. Deploys etcd containers on etcd role nodes
6. Deploys control plane components (API server, scheduler, controller)
7. Generates kubeconfig and certificates
8. Deploys network plugin (Canal/Calico)
9. Deploys kube-dns/CoreDNS
10. Deploys ingress controller if configured
11. Saves cluster state to cluster.rkestate file
12. Outputs kube_config_cluster.yml for kubectl access

**Q: How do you perform a zero-downtime Kubernetes upgrade in RKE?**

Answer:
1. Edit cluster.yml to update kubernetes_version
2. Configure upgrade_strategy in cluster.yml:
   ```yaml
   upgrade_strategy:
     max_unavailable_worker: "10%"
     max_unavailable_controlplane: "1"
     drain: true
     drain_input:
       grace_period: 60
       ignore_daemon_sets: true
   ```
3. Run `rke up --config cluster.yml`
4. RKE upgrades control plane nodes one at a time
5. Then upgrades worker nodes in batches (10% at a time)
6. For each node: drain pods, upgrade components, uncordon
7. Verify cluster health between each node
8. Total cluster stays operational throughout

**Q: How do you recover from a complete cluster failure?**

Answer:
1. Identify the most recent etcd snapshot
2. Ensure you have cluster.yml and cluster.rkestate files
3. If nodes are lost, provision new nodes matching cluster.yml
4. Run `rke etcd snapshot-restore --config cluster.yml --name <snapshot>`
5. RKE will:
   - Stop all cluster services
   - Restore etcd data directory from snapshot
   - Restart cluster with restored state
6. Verify cluster comes up: `kubectl get nodes`
7. Check workload status: `kubectl get pods -A`
8. Cluster should match state from snapshot time

**Q: What's the difference between RKE1 and RKE2, and when would you choose each?**

Answer:

RKE1:
- Docker-based, components in containers
- Simpler, easier to understand
- Good for dev/test or legacy migrations
- Manual CIS hardening required
- SSH-based provisioning

RKE2:
- containerd-native, systemd services
- CIS 1.6 compliant by default
- Better for production and compliance
- FIPS 140-2 validated crypto
- More secure default configuration

Choose RKE2 for:
- Production workloads
- Compliance requirements (CIS, FIPS, NIST)
- Government/regulated industries
- Edge deployments
- New greenfield clusters

Choose RKE1 for:
- Legacy environments already on RKE1
- Simpler understanding needed
- Temporary/dev clusters
- Migration path to RKE2

---

### KUBERNETES INTERNALS - 3 hours

#### API Server Architecture (45 mins)

**Request Flow Through API Server:**

```
Client (kubectl)
       │
       ▼
[Authentication]
   │   └─> X.509 Client Certs
   │   └─> Bearer Tokens
   │   └─> Service Account Tokens
   │   └─> Bootstrap Tokens
   │
   ▼
[Authorization]
   │   └─> RBAC (Role-Based Access Control)
   │   └─> ABAC (Attribute-Based Access Control)
   │   └─> Node Authorization
   │   └─> Webhook
   │
   ▼
[Admission Controllers]
   │   └─> Mutating Webhooks (modify request)
   │   └─> Validating Webhooks (accept/reject)
   │   └─> Built-in: LimitRanger, ResourceQuota, PodSecurity
   │
   ▼
[Schema Validation]
   │   └─> OpenAPI schema check
   │
   ▼
[etcd Write]
   │   └─> Store to etcd
   │
   ▼
[Watchers Notified]
   │   └─> Controller Manager
   │   └─> Scheduler
   │   └─> kubelet
   └─> Response to Client
```

**Hands-On Exploration:**

```bash
# View API server configuration
# On RKE1 node
docker inspect kube-apiserver | jq '.[0].Args'

# On RKE2/kubeadm node
ps aux | grep kube-apiserver

# Check API server flags
kubectl -n kube-system get pod kube-apiserver-node1 -o yaml | grep -A100 command:

# Test API server directly (bypass kubectl)
APISERVER=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')
TOKEN=$(kubectl get secret -n kube-system \
  $(kubectl get serviceaccount default -n kube-system -o jsonpath='{.secrets[0].name}') \
  -o jsonpath='{.data.token}' | base64 -d)

curl -k -H "Authorization: Bearer $TOKEN" $APISERVER/api/v1/namespaces

# Enable API server audit logging
# Check if enabled in cluster.yml (RKE1)
grep -A10 audit_log cluster.yml

# View audit logs
# On control plane node
tail -f /var/log/kube-audit/audit-log.json | jq .

# See what API groups are available
kubectl api-resources

# See API versions
kubectl api-versions

# Explain how a resource reaches API server
kubectl create deployment test --image=nginx --dry-run=client -o yaml
# This shows the payload that would be sent to API server
```

**Watch API in Action:**

```bash
# Open two terminals

# Terminal 1: Watch API server logs
# RKE1
docker logs -f kube-apiserver 2>&1 | grep -i "pods"

# Terminal 2: Create a pod
kubectl run test-pod --image=nginx

# Observe in Terminal 1:
# 1. POST /api/v1/namespaces/default/pods
# 2. Authentication check
# 3. Authorization check
# 4. Admission controller execution
# 5. etcd write
# 6. Response 201 Created

# Watch changes with kubectl
kubectl get pods -w
# This uses the watch API: GET /api/v1/pods?watch=true
```

**Key API Server Flags:**

```bash
# Security-critical flags
--anonymous-auth=false                # Disable anonymous access
--authorization-mode=Node,RBAC        # Enable RBAC
--enable-admission-plugins=...        # Admission controllers
--encryption-provider-config=...      # Encrypt secrets at rest
--audit-log-path=...                  # Enable audit logging
--tls-cert-file=...                   # TLS certificate
--client-ca-file=...                  # Client cert verification

# Performance flags
--max-requests-inflight=400           # Concurrent requests
--max-mutating-requests-inflight=200  # Concurrent mutating requests
--watch-cache-sizes=...               # Watch cache per resource

# etcd flags
--etcd-servers=https://...            # etcd endpoints
--etcd-cafile=...                     # etcd CA cert
--etcd-certfile=...                   # etcd client cert
```

#### etcd Operations (45 mins)

**etcd Architecture in Kubernetes:**

```
┌─────────────────────────────────────────┐
│            API Server                   │
│  (reads/writes through etcd client)     │
└────────────────┬────────────────────────┘
                 │
      ┌──────────┴──────────┐
      │                     │
┌─────▼─────┐      ┌────────▼────┐
│  etcd-1   │◄────►│   etcd-2    │
│  (leader) │      │  (follower) │
└─────┬─────┘      └────────┬────┘
      │                     │
      └──────────┬──────────┘
                 │
         ┌───────▼────────┐
         │    etcd-3      │
         │   (follower)   │
         └────────────────┘

 Raft Consensus (quorum: 2 out of 3)
```

**Direct etcd Interaction:**

```bash
# Set up etcdctl (on RKE1 etcd node)
ETCDCTL_API=3
ETCD_ENDPOINTS=https://127.0.0.1:2379
ETCD_CACERT=/etc/kubernetes/ssl/kube-ca.pem
ETCD_CERT=/etc/kubernetes/ssl/kube-etcd-*.pem
ETCD_KEY=/etc/kubernetes/ssl/kube-etcd-*-key.pem

# Check etcd health
docker exec etcd etcdctl \
  --cacert=$ETCD_CACERT \
  --cert=$ETCD_CERT \
  --key=$ETCD_KEY \
  --endpoints=$ETCD_ENDPOINTS \
  endpoint health

# Check etcd member list
docker exec etcd etcdctl \
  --cacert=$ETCD_CACERT \
  --cert=$ETCD_CERT \
  --key=$ETCD_KEY \
  --endpoints=$ETCD_ENDPOINTS \
  member list -w table

# Check etcd status
docker exec etcd etcdctl \
  --cacert=$ETCD_CACERT \
  --cert=$ETCD_CERT \
  --key=$ETCD_KEY \
  --endpoints=$ETCD_ENDPOINTS \
  endpoint status -w table

# List all Kubernetes keys in etcd
docker exec etcd etcdctl \
  --cacert=$ETCD_CACERT \
  --cert=$ETCD_CERT \
  --key=$ETCD_KEY \
  --endpoints=$ETCD_ENDPOINTS \
  get / --prefix --keys-only | head -20

# Get a specific resource from etcd
# Example: Get default namespace
docker exec etcd etcdctl \
  --cacert=$ETCD_CACERT \
  --cert=$ETCD_CERT \
  --key=$ETCD_KEY \
  --endpoints=$ETCD_ENDPOINTS \
  get /registry/namespaces/default

# Check etcd metrics
curl -k --cert $ETCD_CERT --key $ETCD_KEY --cacert $ETCD_CACERT \
  https://127.0.0.1:2379/metrics | grep etcd_server

# Monitor etcd performance
watch -n 1 'docker exec etcd etcdctl \
  --cacert=$ETCD_CACERT \
  --cert=$ETCD_CERT \
  --key=$ETCD_KEY \
  --endpoints=$ETCD_ENDPOINTS \
  endpoint status -w table'
```

**etcd Backup and Restore:**

```bash
# Manual snapshot (RKE1)
docker exec etcd etcdctl \
  --cacert=$ETCD_CACERT \
  --cert=$ETCD_CERT \
  --key=$ETCD_KEY \
  --endpoints=$ETCD_ENDPOINTS \
  snapshot save /backup/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db

# Verify snapshot
docker exec etcd etcdctl \
  --cacert=$ETCD_CACERT \
  snapshot status /backup/etcd-snapshot-20240215.db -w table

# Automated backup (RKE handles this)
# Check cluster.yml snapshot configuration
services:
  etcd:
    snapshot: true
    creation: 6h
    retention: 24h

# Restore from snapshot (DANGEROUS)
# This is handled by 'rke etcd snapshot-restore'
# Manual restore process:
# 1. Stop API server
# 2. Stop etcd
# 3. Remove old etcd data
# 4. Restore snapshot to data directory
# 5. Start etcd
# 6. Start API server

# Example manual restore (educational only)
docker stop kube-apiserver
docker stop etcd
docker exec etcd etcdctl \
  snapshot restore /backup/etcd-snapshot.db \
  --name=etcd-1 \
  --initial-cluster=etcd-1=https://10.0.1.10:2380 \
  --initial-advertise-peer-urls=https://10.0.1.10:2380 \
  --data-dir=/var/lib/etcd-restore
# Then move restored data to /var/lib/etcd
# Then restart etcd and API server
```

**etcd Health Checks:**

```bash
# Check if etcd is responding
docker exec etcd etcdctl \
  --cacert=$ETCD_CACERT \
  --cert=$ETCD_CERT \
  --key=$ETCD_KEY \
  --endpoints=$ETCD_ENDPOINTS \
  endpoint health

# Check etcd alarms (disk space, corruption)
docker exec etcd etcdctl \
  --cacert=$ETCD_CACERT \
  --cert=$ETCD_CERT \
  --key=$ETCD_KEY \
  --endpoints=$ETCD_ENDPOINTS \
  alarm list

# Check etcd database size
docker exec etcd etcdctl \
  --cacert=$ETCD_CACERT \
  --cert=$ETCD_CERT \
  --key=$ETCD_KEY \
  --endpoints=$ETCD_ENDPOINTS \
  endpoint status -w table | grep "DB SIZE"

# Defragment etcd (if database growing)
docker exec etcd etcdctl \
  --cacert=$ETCD_CACERT \
  --cert=$ETCD_CERT \
  --key=$ETCD_KEY \
  --endpoints=$ETCD_ENDPOINTS \
  defrag

# Compact etcd history (reclaim space)
# Get current revision
REV=$(docker exec etcd etcdctl \
  --cacert=$ETCD_CACERT \
  --cert=$ETCD_CERT \
  --key=$ETCD_KEY \
  --endpoints=$ETCD_ENDPOINTS \
  endpoint status -w json | jq -r '.[0].Status.header.revision')

# Compact up to current revision
docker exec etcd etcdctl \
  --cacert=$ETCD_CACERT \
  --cert=$ETCD_CERT \
  --key=$ETCD_KEY \
  --endpoints=$ETCD_ENDPOINTS \
  compact $REV
```

**etcd Troubleshooting Scenarios:**

```bash
# Scenario 1: etcd member not healthy
# Check member status
docker exec etcd etcdctl member list -w table
# Look for "unhealthy" members

# Check network connectivity between members
# On etcd-1, test connection to etcd-2
curl -k --cert $ETCD_CERT --key $ETCD_KEY \
  https://etcd-2:2379/health

# Check etcd logs
docker logs etcd --tail=100 | grep -i error

# Scenario 2: etcd out of space
# Check alarm
docker exec etcd etcdctl alarm list
# If "memberID:xxx alarm:NOSPACE"

# Check disk space
df -h /var/lib/etcd

# Disarm alarm after freeing space
docker exec etcd etcdctl alarm disarm

# Scenario 3: etcd slow
# Check etcd metrics for slow operations
docker exec etcd etcdctl \
  --endpoints=$ETCD_ENDPOINTS \
  --cacert=$ETCD_CACERT \
  --cert=$ETCD_CERT \
  --key=$ETCD_KEY \
  check perf

# Look for disk latency issues
# etcd is very sensitive to disk I/O
```

#### Scheduler Internals (30 mins)

**Scheduler Decision Process:**

```
New Pod Created (no node assigned)
       │
       ▼
[Filtering Phase]
   │   Checks:
   │   - Node has enough CPU/memory?
   │   - Pod tolerates node taints?
   │   - Node selector matches?
   │   - Ports available?
   │   - Volume can be mounted?
   │   - Pod affinity/anti-affinity satisfied?
   │
   ▼
[Feasible Nodes: node-1, node-3, node-5]
       │
       ▼
[Scoring Phase]
   │   Scores each feasible node:
   │   - LeastRequestedPriority (prefers less loaded)
   │   - BalancedResourceAllocation (balance CPU/mem)
   │   - NodeAffinityPriority (affinity preferences)
   │   - ImageLocalityPriority (image already on node)
   │   - TaintTolerationPriority
   │
   ▼
[Highest Score: node-3 (score: 95)]
       │
       ▼
[Binding Phase]
   │   API Server: Bind pod to node-3
   │   kubelet on node-3: Start pod
   │
   ▼
[Pod Running on node-3]
```

**Hands-On Scheduler Exploration:**

```bash
# Watch scheduler make decisions
kubectl -n kube-system logs -f kube-scheduler-node1 | grep -i "successfully assigned"

# Create pod and watch scheduling
kubectl run test-sched --image=nginx
kubectl get events --sort-by='.lastTimestamp' | grep test-sched

# Check why a pod is not scheduling
kubectl describe pod test-sched | grep -A10 Events

# View scheduler configuration
kubectl -n kube-system get pod kube-scheduler-node1 -o yaml

# Check scheduler leader election
kubectl -n kube-system get lease kube-scheduler -o yaml
# Shows which scheduler instance is leader (in HA control plane)

# Simulate scheduler filtering
# Create pod with impossible requirements
kubectl run impossible --image=nginx \
  --requests="cpu=1000,memory=1000Gi"

kubectl get pods impossible
# Status: Pending

kubectl describe pod impossible
# Events: "0/3 nodes available: insufficient cpu, insufficient memory"
```

**Custom Scheduling Scenarios:**

```bash
# Node selector scheduling
kubectl run nginx-worker --image=nginx \
  --overrides='{"spec":{"nodeSelector":{"node-role":"worker"}}}'

# Verify placement
kubectl get pod nginx-worker -o wide

# Node affinity (preferred)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx-affinity
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: disk-type
            operator: In
            values:
            - ssd
  containers:
  - name: nginx
    image: nginx
EOF

# Pod affinity (schedule near other pods)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx-near-redis
spec:
  affinity:
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - redis
        topologyKey: kubernetes.io/hostname
  containers:
  - name: nginx
    image: nginx
EOF

# Pod anti-affinity (spread pods across nodes)
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-spread
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: web
            topologyKey: kubernetes.io/hostname
      containers:
      - name: nginx
        image: nginx
EOF

# Verify spread across nodes
kubectl get pods -l app=web -o wide

# Taints and tolerations
# Taint a node
kubectl taint nodes node-1 dedicated=gpu:NoSchedule

# Create pod that tolerates taint
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-pod
spec:
  tolerations:
  - key: dedicated
    operator: Equal
    value: gpu
    effect: NoSchedule
  containers:
  - name: nvidia
    image: nvidia/cuda:11.0-base
EOF

# Remove taint
kubectl taint nodes node-1 dedicated=gpu:NoSchedule-
```

#### Control Plane Components (30 mins)

**Controller Manager Internals:**

```bash
# View running controllers
kubectl -n kube-system logs kube-controller-manager-node1 | grep "Starting controller"

# Key controllers:
# - ReplicaSet controller: ensures desired replicas
# - Deployment controller: manages ReplicaSets
# - Job controller: creates pods for jobs
# - CronJob controller: creates jobs on schedule
# - Node controller: monitors node health
# - Service controller: creates cloud load balancers
# - Endpoint controller: populates endpoints
# - PV controller: binds PVs to PVCs
# - Namespace controller: cleans up deleted namespaces

# Watch ReplicaSet controller in action
# Terminal 1
kubectl scale deployment nginx --replicas=5
kubectl get rs -w

# Terminal 2
kubectl -n kube-system logs -f kube-controller-manager-node1 | grep replica

# Test Node controller
# Simulate node failure by stopping kubelet
# On a worker node
systemctl stop kubelet

# Watch from control plane
kubectl get nodes -w
# After ~40 seconds: NotReady
# After ~5 minutes: Pods evicted

# Restart kubelet
systemctl start kubelet

# Watch node rejoin
kubectl get nodes -w
```

**Kubelet Deep Dive:**

```bash
# View kubelet configuration
# On worker node
systemctl status kubelet
ps aux | grep kubelet

# Check kubelet config file
cat /var/lib/kubelet/config.yaml

# Kubelet API (runs on each node)
# From control plane or node itself
curl -k https://localhost:10250/pods | jq .

# Requires authentication
# Get node kubelet client cert
kubectl get csr

# Check kubelet logs
journalctl -u kubelet -f

# Kubelet responsibilities:
# 1. Pod lifecycle management
# 2. Container runtime interaction (containerd/docker)
# 3. Volume mounting
# 4. Resource reporting
# 5. Health checking (probes)
# 6. cAdvisor integration (metrics)

# Watch kubelet create a pod
# Terminal 1: Watch kubelet logs
journalctl -u kubelet -f

# Terminal 2: Create pod on this node
kubectl run test --image=nginx \
  --overrides='{"spec":{"nodeName":"node-1"}}'

# Observe in Terminal 1:
# - Pull image
# - Create container
# - Start container
# - Report status to API server
```

**Container Runtime Interface (CRI):**

```bash
# RKE1 uses Docker
# Check Docker
docker ps --filter name=k8s

# Each Kubernetes pod has:
# 1. Pause container (holds network namespace)
# 2. Application containers

# RKE2/kubeadm use containerd
# Use crictl to interact
crictl ps
crictl pods
crictl images

# Inspect a pod
POD_ID=$(crictl pods --name nginx -q)
crictl inspectp $POD_ID

# Check pod network namespace
CONTAINER_ID=$(crictl ps --pod $POD_ID -q | head -1)
crictl inspect $CONTAINER_ID | jq '.info.pid'
# Network namespace is shared among pod containers

# View container logs
crictl logs $CONTAINER_ID

# Execute in container
crictl exec -it $CONTAINER_ID /bin/sh
```

#### Knowledge Checklist

- [ ] **API Server Flow**: Can you diagram the authentication -> authorization -> admission flow?
- [ ] **etcd Quorum**: How many etcd nodes do you need? What happens if you lose quorum?
- [ ] **etcd Backup**: How do you take a backup? How long does restore take?
- [ ] **Scheduler Filtering**: Name 5 filtering predicates the scheduler uses
- [ ] **Scheduler Scoring**: What factors influence node score?
- [ ] **Node Affinity**: Difference between required vs preferred?
- [ ] **Controllers**: Name 5 controllers in controller-manager and their purpose
- [ ] **Kubelet**: What happens if kubelet crashes? What about pods?
- [ ] **CRI**: Difference between Docker and containerd in Kubernetes?

#### Interview Questions to Practice

**Q: Explain how a kubectl create deployment command becomes running pods.**

Answer:
1. kubectl sends POST to API server /apis/apps/v1/deployments
2. API server: authentication (client cert), authorization (RBAC), admission (validation)
3. API server writes Deployment object to etcd
4. Deployment controller (in controller-manager) watches Deployments
5. Controller creates ReplicaSet object via API server
6. ReplicaSet controller watches ReplicaSets
7. Controller creates Pod objects (3 if replicas=3)
8. Scheduler watches unscheduled Pods
9. Scheduler assigns each Pod to a node, updates Pod.spec.nodeName
10. kubelet on assigned node watches Pods for its node
11. kubelet pulls image, creates containers via CRI
12. kubelet reports Pod status back to API server
13. Pod enters Running state

**Q: An etcd node fails in a 3-node cluster. What happens?**

Answer:
- 3-node etcd cluster has quorum of 2
- Losing 1 node: cluster still has quorum (2/3)
- Cluster continues operating normally
- Writes still succeed (replicated to 2 nodes)
- Performance may degrade slightly
- Should replace failed node ASAP:
  - Remove old member: `etcdctl member remove`
  - Add new member: `etcdctl member add`
  - Start etcd on new node
  - It will sync data from other members

If you lose 2 nodes (only 1 remains):
- Cluster loses quorum
- Cluster becomes read-only
- API server can read but not write
- No new pods, updates, or deletes work
- Must restore from backup or recover members

**Q: Why is a pod stuck in Pending state?**

Common causes:
1. **Insufficient resources**: No node has enough CPU/memory
   ```bash
   kubectl describe pod <pod> | grep -i "insufficient"
   ```

2. **Node selector mismatch**: No nodes match selector
   ```bash
   kubectl describe pod <pod> | grep -i "node selector"
   ```

3. **Taints without tolerations**: All nodes tainted
   ```bash
   kubectl describe nodes | grep -i taint
   ```

4. **PVC not bound**: Pod waiting for volume
   ```bash
   kubectl get pvc
   ```

5. **Image pull issues**: Can't download image
   ```bash
   kubectl describe pod <pod> | grep -i "pull"
   ```

Diagnosis process:
```bash
kubectl describe pod <pod>
kubectl get events --sort-by='.lastTimestamp'
kubectl logs kube-scheduler -n kube-system
```

---

### CRDs, CONTROLLERS & OPERATORS - 2 hours

#### Custom Resource Definitions (45 mins)

**What Are CRDs?**

CRDs extend Kubernetes API with custom resource types. Instead of just Pods, Services, Deployments, you can create `Backups`, `Databases`, `Applications`, etc.

**CRD Structure:**

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: databases.example.com
spec:
  group: example.com
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                engine:
                  type: string
                  enum: [postgres, mysql]
                version:
                  type: string
                replicas:
                  type: integer
                  minimum: 1
                  maximum: 5
                storage:
                  type: string
                  pattern: '^[0-9]+Gi$'
              required:
                - engine
                - version
            status:
              type: object
              properties:
                phase:
                  type: string
                  enum: [Pending, Running, Failed]
                endpoint:
                  type: string
  scope: Namespaced
  names:
    plural: databases
    singular: database
    kind: Database
    shortNames:
      - db
```

**Hands-On CRD Creation:**

```bash
# Create a simple CRD
cat <<EOF | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.example.com
spec:
  group: example.com
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                source:
                  type: string
                schedule:
                  type: string
                retention:
                  type: integer
            status:
              type: object
              properties:
                lastBackup:
                  type: string
                status:
                  type: string
  scope: Namespaced
  names:
    plural: backups
    singular: backup
    kind: Backup
    shortNames:
      - bkp
EOF

# Verify CRD created
kubectl get crd backups.example.com
kubectl describe crd backups.example.com

# CRD is now part of API
kubectl api-resources | grep backup

# Create a custom resource
cat <<EOF | kubectl apply -f -
apiVersion: example.com/v1
kind: Backup
metadata:
  name: daily-backup
spec:
  source: postgresql-prod
  schedule: "0 2 * * *"
  retention: 30
EOF

# Query custom resources
kubectl get backups
kubectl get bkp  # short name works
kubectl describe backup daily-backup

# Get as YAML
kubectl get backup daily-backup -o yaml

# Note: CRD alone doesn't DO anything
# You need a controller to watch and act on these resources
```

**CRD with Validation:**

```bash
# Create CRD with comprehensive validation
cat <<EOF | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: applications.platform.example.com
spec:
  group: platform.example.com
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          required: ["spec"]
          properties:
            spec:
              type: object
              required: ["image", "replicas"]
              properties:
                image:
                  type: string
                  pattern: '^[a-z0-9./:-]+$'
                replicas:
                  type: integer
                  minimum: 1
                  maximum: 100
                resources:
                  type: object
                  properties:
                    cpu:
                      type: string
                      pattern: '^[0-9]+m?$'
                    memory:
                      type: string
                      pattern: '^[0-9]+[MGT]i$'
                env:
                  type: array
                  items:
                    type: object
                    required: ["name", "value"]
                    properties:
                      name:
                        type: string
                      value:
                        type: string
            status:
              type: object
              properties:
                phase:
                  type: string
                  enum: [Pending, Running, Failed, Succeeded]
                deploymentName:
                  type: string
                serviceName:
                  type: string
      additionalPrinterColumns:
        - name: Phase
          type: string
          jsonPath: .status.phase
        - name: Replicas
          type: integer
          jsonPath: .spec.replicas
        - name: Age
          type: date
          jsonPath: .metadata.creationTimestamp
  scope: Namespaced
  names:
    plural: applications
    singular: application
    kind: Application
    shortNames:
      - app
EOF

# Test validation
# This should succeed
cat <<EOF | kubectl apply -f -
apiVersion: platform.example.com/v1
kind: Application
metadata:
  name: my-app
spec:
  image: nginx:1.21
  replicas: 3
  resources:
    cpu: 500m
    memory: 512Mi
  env:
    - name: ENV
      value: production
EOF

# This should fail (invalid replicas)
cat <<EOF | kubectl apply -f -
apiVersion: platform.example.com/v1
kind: Application
metadata:
  name: bad-app
spec:
  image: nginx:1.21
  replicas: 150  # exceeds maximum: 100
EOF
# Error: replicas in body should be less than or equal to 100

# View custom columns
kubectl get applications
# Shows: NAME, PHASE, REPLICAS, AGE
```

**CRD Versioning:**

```bash
# CRD supporting multiple versions
cat <<EOF | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.com
spec:
  group: example.com
  versions:
    - name: v1alpha1
      served: true
      storage: false  # Old version
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                size:
                  type: string  # v1alpha1 uses string
    - name: v1
      served: true
      storage: true  # Current version
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                replicas:
                  type: integer  # v1 uses integer
  conversion:
    strategy: None  # Or Webhook for auto-conversion
  scope: Namespaced
  names:
    plural: widgets
    singular: widget
    kind: Widget
EOF

# Create v1alpha1 resource
kubectl apply -f - <<EOF
apiVersion: example.com/v1alpha1
kind: Widget
metadata:
  name: old-widget
spec:
  size: "3"
EOF

# Create v1 resource
kubectl apply -f - <<EOF
apiVersion: example.com/v1
kind: Widget
metadata:
  name: new-widget
spec:
  replicas: 3
EOF

# Both versions work
kubectl get widgets
```

#### Controller Pattern (45 mins)

**Controller Reconciliation Loop:**

```
┌──────────────────────────────────────┐
│     Watch API Server (Informer)      │
│   for changes to watched resources   │
└─────────────┬────────────────────────┘
              │
              ▼
      ┌───────────────┐
      │  Work Queue   │
      │  (add event)  │
      └───────┬───────┘
              │
              ▼
    ┌─────────────────────┐
    │  Reconcile Function │
    │                     │
    │  1. Get desired     │
    │  2. Get actual      │
    │  3. Compare         │
    │  4. Take action     │
    └─────────┬───────────┘
              │
              ▼
       ┌──────────────┐
       │  Update API  │
       │  (if needed) │
       └──────────────┘
              │
              └──────> Back to Watch
```

**Simple Controller Example (Pseudo-code):**

```go
// This is conceptual - shows controller pattern
package main

import (
    "context"
    "fmt"
    corev1 "k8s.io/api/core/v1"
    "k8s.io/client-go/informers"
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/tools/cache"
)

func main() {
    // Create Kubernetes client
    clientset := getKubernetesClient()

    // Create informer factory
    factory := informers.NewSharedInformerFactory(clientset, 0)

    // Watch Backups (our CRD)
    backupInformer := factory.Example().V1().Backups().Informer()

    // Add event handlers
    backupInformer.AddEventHandler(cache.ResourceEventHandlerFuncs{
        AddFunc: func(obj interface{}) {
            backup := obj.(*Backup)
            reconcile(backup)
        },
        UpdateFunc: func(oldObj, newObj interface{}) {
            backup := newObj.(*Backup)
            reconcile(backup)
        },
        DeleteFunc: func(obj interface{}) {
            backup := obj.(*Backup)
            cleanup(backup)
        },
    })

    // Start informer
    stopCh := make(chan struct{})
    factory.Start(stopCh)

    // Wait forever
    <-stopCh
}

func reconcile(backup *Backup) {
    // Reconciliation logic
    fmt.Printf("Reconciling backup: %s\n", backup.Name)

    // 1. Get desired state from backup.Spec
    desiredSchedule := backup.Spec.Schedule
    desiredRetention := backup.Spec.Retention

    // 2. Get actual state (check if CronJob exists)
    cronJob := getCronJob(backup.Name)

    // 3. Compare desired vs actual
    if cronJob == nil {
        // CronJob doesn't exist, create it
        createCronJob(backup)
    } else if cronJob.Spec.Schedule != desiredSchedule {
        // CronJob exists but schedule differs, update it
        updateCronJob(cronJob, backup)
    }

    // 4. Update status
    backup.Status.LastReconcile = time.Now()
    updateBackupStatus(backup)
}

func cleanup(backup *Backup) {
    // Cleanup logic when Backup is deleted
    deleteCronJob(backup.Name)
    deleteBackupData(backup.Name)
}
```

**Real Controller Example - Deploy and Examine:**

```bash
# Let's examine an actual controller: Flux HelmRelease controller

# Check Flux helm-controller
kubectl -n flux-system get deployment helm-controller

# View controller logs
kubectl -n flux-system logs -f deployment/helm-controller

# Create a HelmRelease and watch controller react
cat <<EOF | kubectl apply -f -
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: test-release
  namespace: default
spec:
  interval: 5m
  chart:
    spec:
      chart: nginx
      sourceRef:
        kind: HelmRepository
        name: bitnami
        namespace: flux-system
      version: "18.x"
  values:
    replicaCount: 1
EOF

# Watch controller logs
# You'll see:
# 1. Watch event: HelmRelease created
# 2. Reconcile starts
# 3. Check if HelmChart exists
# 4. Check if Helm release exists
# 5. Install Helm release
# 6. Update HelmRelease status
# 7. Schedule next reconciliation

# Check HelmRelease status
kubectl describe helmrelease test-release

# Controller updates status regularly
kubectl get helmrelease test-release -o yaml | grep -A10 status:

# Clean up
kubectl delete helmrelease test-release
```

**Writing a Simple Controller:**

```bash
# We'll use kubebuilder to scaffold a controller
# Install kubebuilder
curl -L -o kubebuilder https://go.kubebuilder.io/dl/latest/$(go env GOOS)/$(go env GOARCH)
chmod +x kubebuilder
mv kubebuilder /usr/local/bin/

# Create controller project
mkdir backup-controller
cd backup-controller
kubebuilder init --domain example.com --repo example.com/backup-controller

# Create API and controller
kubebuilder create api --group batch --version v1 --kind Backup

# This generates:
# - api/v1/backup_types.go (CRD definition)
# - controllers/backup_controller.go (controller logic)

# Edit api/v1/backup_types.go
# Define BackupSpec and BackupStatus

# Edit controllers/backup_controller.go
# Implement Reconcile() function

# Install CRD into cluster
make install

# Run controller locally
make run

# Build and deploy controller
make docker-build docker-push IMG=example.com/backup-controller:v1
make deploy IMG=example.com/backup-controller:v1
```

#### Operator Pattern (30 mins)

**Operator = CRD + Controller + Domain Logic**

Operators encode operational knowledge:
- How to install software
- How to upgrade
- How to backup and restore
- How to scale
- How to heal failures

**Famous Operators:**

1. **Prometheus Operator**: Manages Prometheus, Alertmanager, ServiceMonitors
2. **etcd Operator**: Manages etcd clusters
3. **PostgreSQL Operator**: Manages PostgreSQL databases
4. **Longhorn**: Manages distributed block storage

**Installing an Operator:**

```bash
# Install Prometheus Operator (if not already installed)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus-operator prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace

# Check CRDs installed by operator
kubectl get crd | grep monitoring.coreos.com
# prometheus.monitoring.coreos.com
# servicemonitor.monitoring.coreos.com
# alertmanager.monitoring.coreos.com
# prometheusrule.monitoring.coreos.com

# Check operator pod
kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus-operator

# Create a ServiceMonitor (operator watches this)
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-metrics
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      interval: 30s
EOF

# Operator detects ServiceMonitor and updates Prometheus config
kubectl -n monitoring logs -f prometheus-operator-xxx | grep ServiceMonitor

# Create PrometheusRule (alert rules)
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: my-alerts
  namespace: monitoring
spec:
  groups:
    - name: my-app
      interval: 30s
      rules:
        - alert: HighErrorRate
          expr: rate(http_requests_total{status="500"}[5m]) > 0.05
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High error rate detected"
EOF

# Operator updates Prometheus with new rules
```

**Operator Capability Levels:**

```
Level 5: Auto Pilot
  └─> Full auto-healing, tuning, scaling

Level 4: Deep Insights
  └─> Metrics, alerts, log processing

Level 3: Full Lifecycle
  └─> Backup, restore, upgrade, scaling

Level 2: Seamless Upgrades
  └─> Version upgrades, patching

Level 1: Basic Install
  └─> Automated install and config
```

#### Knowledge Checklist

- [ ] **CRD Structure**: Can you write a CRD with validation from scratch?
- [ ] **CRD Versioning**: How do you add a new version while supporting old one?
- [ ] **Controller Pattern**: Explain the watch -> reconcile -> update loop
- [ ] **Reconciliation**: What's the difference between level-triggered vs edge-triggered?
- [ ] **Operators**: Name 3 operators and what they manage
- [ ] **Informers**: How do informers reduce API server load?
- [ ] **Work Queues**: Why use a queue instead of processing events immediately?
- [ ] **Status Updates**: Why separate spec from status in CRs?

#### Interview Questions to Practice

**Q: Design a CRD and controller for managing Redis clusters.**

Answer:
```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: redisclusters.cache.example.com
spec:
  group: cache.example.com
  names:
    kind: RedisCluster
    plural: redisclusters
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                replicas:
                  type: integer
                  minimum: 3
                version:
                  type: string
                persistence:
                  type: boolean
                resources:
                  type: object
            status:
              type: object
              properties:
                phase:
                  type: string
                masterNode:
                  type: string
                replicas:
                  type: integer
```

Controller would:
1. Watch RedisCluster resources
2. Create StatefulSet with Redis pods
3. Configure Redis replication
4. Create Service for access
5. Monitor cluster health
6. Handle failover (promote replica if master fails)
7. Update status with current state

**Q: How do you handle backward compatibility when updating a CRD?**

Answer:
1. **Add new version, keep old version served**:
   ```yaml
   versions:
     - name: v1alpha1
       served: true
       storage: false
     - name: v1
       served: true
       storage: true  # New storage version
   ```

2. **Use conversion webhooks** to translate between versions
3. **Never remove required fields** from old versions
4. **Add fields as optional** with defaults
5. **Deprecation process**:
   - v1alpha1: Mark as deprecated, still served
   - Next release: v1alpha1 served=false (but schema remains)
   - Two releases later: Remove v1alpha1 completely

6. **Migration strategy**:
   ```bash
   # Convert all existing resources to new version
   kubectl get resourcetype.v1alpha1 -A -o json | \
     jq '.items[] | .apiVersion = "group/v1"' | \
     kubectl apply -f -
   ```

---

### CNI NETWORKING - 1.5 hours

#### CNI Fundamentals (30 mins)

**What is CNI?**

CNI (Container Network Interface) is a specification for configuring network interfaces in Linux containers. When kubelet starts a pod, it calls the CNI plugin to set up networking.

**CNI Workflow:**

```
kubelet starts pod
       │
       ▼
[Create pause container]
       │
       ▼
[Call CNI plugin]
   │   CNI plugin creates:
   │   - veth pair (one end in pod, one in host)
   │   - Assign IP to pod
   │   - Set up routes
   │   - Configure iptables rules
   │
   ▼
[Pod has network connectivity]
       │
       ▼
[Start application containers]
   (they share pause container's network namespace)
```

**RKE CNI Options:**

1. **Canal (Default in RKE)**: Flannel + Calico
   - Flannel: Handles pod networking (VXLAN overlay)
   - Calico: Handles network policies

2. **Calico**: Full-featured networking + policy
   - BGP routing or VXLAN overlay
   - Network policy enforcement
   - More complex but powerful

3. **Flannel**: Simple overlay network
   - VXLAN, host-gw, or UDP backend
   - No network policy support
   - Easy to understand and debug

**Hands-On CNI Exploration:**

```bash
# Check CNI plugin configuration (on any node)
ls /etc/cni/net.d/
cat /etc/cni/net.d/10-canal.conflist

# Check CNI binary plugins
ls /opt/cni/bin/
# You'll see: bridge, host-local, loopback, portmap, bandwidth, etc.

# Check Canal/Calico components
kubectl -n kube-system get pods | grep -E 'canal|calico'

# View Canal pod logs
kubectl -n kube-system logs canal-xxxxx -c calico-node
kubectl -n kube-system logs canal-xxxxx -c flannel

# Check pod IP allocation
kubectl get pods -A -o wide | head -20
# Notice IPs are from pod CIDR (e.g., 10.42.0.0/16)

# On a node, check network interfaces
ip addr show
# You'll see caliXXXXX interfaces (one per pod on this node)

# Examine a pod's network namespace
docker inspect <container-id> | jq '.[0].NetworkSettings'
# Or for containerd
crictl inspect <container-id> | jq '.info.runtimeSpec.linux.namespaces'

# Check routing table on node
ip route show
# Shows routes to pod CIDRs on other nodes

# Check iptables rules created by kube-proxy and CNI
iptables -t nat -L KUBE-SERVICES -n | head -20
iptables -t filter -L KUBE-FORWARD -n
```

#### Canal (Calico + Flannel) Deep Dive (30 mins)

**Canal Architecture:**

```
┌─────────────────────────────────────────────────┐
│                   Node 1                        │
│  ┌──────────────┐       ┌──────────────┐       │
│  │  Pod A       │       │  Pod B       │       │
│  │  10.42.0.10  │       │  10.42.0.11  │       │
│  └──────┬───────┘       └──────┬───────┘       │
│         │                      │                │
│     caliXXX                caliYYY              │
│         │                      │                │
│         └──────────┬───────────┘                │
│                    │                            │
│          ┌─────────▼─────────┐                  │
│          │  Flannel VXLAN    │                  │
│          │  (overlay network)│                  │
│          └─────────┬─────────┘                  │
│                    │                            │
│               eth0 (10.0.1.10)                  │
└────────────────────┼───────────────────────────┘
                     │
          ┌──────────┴──────────┐
          │                     │
┌─────────▼─────────┐  ┌────────▼────────┐
│     Node 2        │  │     Node 3      │
│  10.0.1.11        │  │  10.0.1.12      │
│  Pods: 10.42.1.x  │  │  Pods: 10.42.2.x│
└───────────────────┘  └─────────────────┘
```

**Flannel Component:**
- Creates VXLAN tunnel between nodes
- Encapsulates pod traffic
- Maintains routing table for pod CIDRs

**Calico Component:**
- Enforces NetworkPolicy rules
- Uses iptables/eBPF for policy enforcement
- Monitors policy changes via Kubernetes API

**Hands-On Canal Configuration:**

```bash
# Check Flannel configuration
kubectl -n kube-system get configmap canal-config -o yaml

# Key settings:
# - net-conf.json: Flannel network config
# - Network: 10.42.0.0/16 (pod CIDR)
# - Backend: { "Type": "vxlan" }

# Check Calico configuration
kubectl get installation.operator.tigera.io default -o yaml

# View Calico IP pools
kubectl get ippools -A

# Check Flannel routes
# On each node
ip route show | grep flannel

# Check VXLAN interface
ip -d link show flannel.1
# Shows VXLAN tunnel interface

# Test pod-to-pod communication
kubectl run test-1 --image=nicolaka/netshoot -- sleep 3600
kubectl run test-2 --image=nicolaka/netshoot -- sleep 3600

# Get IPs
POD1_IP=$(kubectl get pod test-1 -o jsonpath='{.status.podIP}')
POD2_IP=$(kubectl get pod test-2 -o jsonpath='{.status.podIP}')

# Ping between pods
kubectl exec test-1 -- ping -c 3 $POD2_IP

# Trace route
kubectl exec test-1 -- traceroute $POD2_IP

# Check which node each pod is on
kubectl get pods -o wide | grep test-

# Clean up
kubectl delete pod test-1 test-2
```

#### Network Policies (30 mins)

**NetworkPolicy Types:**

1. **Ingress**: Controls incoming traffic to pods
2. **Egress**: Controls outgoing traffic from pods

**Hands-On Network Policies:**

```bash
# Create test namespace and pods
kubectl create namespace netpol-test

# Deploy frontend and backend
kubectl -n netpol-test run frontend --image=nginx --labels=app=frontend
kubectl -n netpol-test run backend --image=nginx --labels=app=backend

# Expose backend
kubectl -n netpol-test expose pod backend --port=80

# Test connectivity (should work)
kubectl -n netpol-test exec frontend -- curl -s backend:80

# Apply default deny ingress policy
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: netpol-test
spec:
  podSelector: {}
  policyTypes:
    - Ingress
EOF

# Test again (should fail)
kubectl -n netpol-test exec frontend -- curl -s --connect-timeout 2 backend:80
# Times out

# Allow frontend to backend
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: netpol-test
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 80
EOF

# Test again (should work)
kubectl -n netpol-test exec frontend -- curl -s backend:80

# Egress policy example - restrict outbound
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-egress
  namespace: netpol-test
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: backend
      ports:
        - protocol: TCP
          port: 80
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
        - podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
EOF

# Test: frontend can reach backend and DNS
kubectl -n netpol-test exec frontend -- curl -s backend:80
kubectl -n netpol-test exec frontend -- nslookup google.com

# But cannot reach external internet (no route out)
kubectl -n netpol-test exec frontend -- curl -s --connect-timeout 2 google.com
# Times out

# Namespace selector example
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-prod-namespace
  namespace: netpol-test
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              environment: production
EOF

# Visualize network policies
kubectl -n netpol-test describe networkpolicy

# Check Calico enforcement (on node)
# Calico translates NetworkPolicies to iptables rules
iptables -t filter -L -n | grep -A10 cali
```

**Network Policy Best Practices:**

```bash
# 1. Start with default deny
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
EOF

# 2. Explicitly allow required traffic
# 3. Use namespace selectors for multi-tenancy
# 4. Test policies in dev before production
# 5. Monitor blocked traffic (Calico logs)
```

#### Troubleshooting Networking (30 mins)

**Common Networking Issues:**

**1. Pod cannot reach other pods:**

```bash
# Check pod IPs
kubectl get pods -A -o wide

# Check CNI plugin status
kubectl -n kube-system get pods | grep -E 'canal|calico|flannel'

# Check CNI logs
kubectl -n kube-system logs -l k8s-app=canal -c calico-node
kubectl -n kube-system logs -l k8s-app=canal -c flannel

# On node, check routes
ip route show

# Check if VXLAN tunnel is up
ip -d link show flannel.1

# Test direct pod ping
kubectl exec <pod> -- ping <other-pod-ip>

# Check for network policy blocking
kubectl describe networkpolicy -n <namespace>
```

**2. Pod cannot reach services:**

```bash
# Check service exists
kubectl get svc

# Check endpoints are populated
kubectl get endpoints <service-name>

# If no endpoints, pods might not match service selector
kubectl get svc <service-name> -o yaml | grep -A5 selector
kubectl get pods -l <selector> -n <namespace>

# Check kube-proxy is running
kubectl -n kube-system get pods -l k8s-app=kube-proxy

# Check kube-proxy logs
kubectl -n kube-system logs -l k8s-app=kube-proxy

# Check iptables rules for service
iptables -t nat -L KUBE-SERVICES -n | grep <service-name>

# Test service from a pod
kubectl run test --image=nicolaka/netshoot -it --rm -- curl <service-name>:<port>
```

**3. External traffic cannot reach cluster:**

```bash
# Check ingress controller
kubectl -n ingress-nginx get pods

# Check ingress resource
kubectl get ingress -A
kubectl describe ingress <ingress-name>

# Check ingress controller service
kubectl -n ingress-nginx get svc

# If LoadBalancer, check external IP assigned
kubectl -n ingress-nginx get svc ingress-nginx-controller

# Check ingress logs
kubectl -n ingress-nginx logs -f deployment/ingress-nginx-controller

# Test from outside cluster
curl -v http://<ingress-ip> -H "Host: myapp.example.com"
```

**4. DNS not working:**

```bash
# Check CoreDNS pods
kubectl -n kube-system get pods -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl -n kube-system logs -l k8s-app=kube-dns

# Check CoreDNS service
kubectl -n kube-system get svc kube-dns

# Test DNS from pod
kubectl run test --image=busybox -it --rm -- nslookup kubernetes.default

# Check /etc/resolv.conf in pod
kubectl run test --image=busybox -it --rm -- cat /etc/resolv.conf

# Should point to kube-dns service IP (usually 10.43.0.10)
```

**5. Network performance issues:**

```bash
# Check MTU settings (VXLAN overhead)
# Pod MTU should be 1450 (1500 - 50 for VXLAN)
kubectl exec <pod> -- ip link show eth0

# Test bandwidth between pods
kubectl run iperf-server --image=networkstatic/iperf3 -- iperf3 -s
kubectl run iperf-client --image=networkstatic/iperf3 -it --rm -- \
  iperf3 -c <iperf-server-ip>

# Check for packet loss
kubectl exec <pod> -- ping -c 100 <target-ip>

# Check CNI plugin CPU usage
kubectl top pods -n kube-system | grep -E 'canal|calico'
```

---

### CSI STORAGE (LONGHORN) - 1.5 hours

#### CSI Architecture (30 mins)

**CSI Components:**

```
┌────────────────────────────────────────────────┐
│             Kubernetes Control Plane           │
│  ┌──────────────────────────────────────────┐  │
│  │     CSI Controller Plugin (StatefulSet)  │  │
│  │  - Provisioner (creates volumes)         │  │
│  │  - Attacher (attaches to nodes)          │  │
│  │  - Resizer (resizes volumes)             │  │
│  │  - Snapshotter (creates snapshots)       │  │
│  └──────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
┌───────▼────────┐      ┌─────────▼────────┐
│    Node 1      │      │     Node 2       │
│  ┌──────────┐  │      │   ┌──────────┐   │
│  │   CSI    │  │      │   │   CSI    │   │
│  │ Node     │  │      │   │ Node     │   │
│  │ Plugin   │  │      │   │ Plugin   │   │
│  └─────┬────┘  │      │   └─────┬────┘   │
│        │       │      │         │        │
│   ┌────▼────┐  │      │    ┌────▼────┐   │
│   │ Volume  │  │      │    │ Volume  │   │
│   │ Mounted │  │      │    │ Mounted │   │
│   │ to Pod  │  │      │    │ to Pod  │   │
│   └─────────┘  │      │    └─────────┘   │
└────────────────┘      └──────────────────┘
```

**CSI Volume Lifecycle:**

```
1. PVC Created by user
       │
       ▼
2. CSI Provisioner creates PV
   (calls CSI plugin CreateVolume)
       │
       ▼
3. PV bound to PVC
       │
       ▼
4. Pod scheduled to node
       │
       ▼
5. CSI Attacher attaches volume to node
   (calls CSI plugin ControllerPublishVolume)
       │
       ▼
6. CSI Node Plugin mounts volume
   (calls CSI plugin NodeStageVolume, NodePublishVolume)
       │
       ▼
7. Pod can use volume
       │
       ▼
8. Pod deleted
       │
       ▼
9. CSI Node Plugin unmounts volume
       │
       ▼
10. CSI Attacher detaches from node
       │
       ▼
11. PVC deleted (if reclaim policy is Delete)
       │
       ▼
12. CSI Provisioner deletes volume
```

#### Longhorn Deep Dive (45 mins)

**Longhorn Architecture:**

```
┌─────────────────────────────────────────────────────┐
│               Longhorn Manager (DaemonSet)          │
│   Runs on every node - orchestrates volumes         │
└──────────────────┬──────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
┌───────▼────────┐   ┌────────▼───────┐
│  Longhorn      │   │   Longhorn     │
│  Engine        │   │   Replica      │
│  (Frontend)    │   │   (Backend)    │
│                │   │                │
│  - iSCSI       │◄─►│  - Stores data │
│  - Serves I/O  │   │  - Replication │
└───────┬────────┘   └────────────────┘
        │
   ┌────▼─────┐
   │   Pod    │
   │  Volume  │
   └──────────┘
```

**Installing Longhorn:**

```bash
# Install Longhorn using kubectl
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml

# Or via Helm
helm repo add longhorn https://charts.longhorn.io
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace

# Check Longhorn installation
kubectl -n longhorn-system get pods

# You'll see:
# - longhorn-manager (DaemonSet on every node)
# - longhorn-driver-deployer
# - longhorn-ui
# - CSI plugin pods

# Check CSI driver registration
kubectl get csidrivers
# Should show: driver.longhorn.io

# Check storage classes
kubectl get storageclass
# Should show: longhorn (default)

# Access Longhorn UI
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80
# Visit http://localhost:8080
```

**Longhorn Storage Classes:**

```bash
# View default Longhorn StorageClass
kubectl get storageclass longhorn -o yaml

# Key parameters:
# - numberOfReplicas: "3" (data replicated to 3 nodes)
# - staleReplicaTimeout: "30" (minutes before replica marked stale)
# - fromBackup: "" (restore from backup)

# Create custom StorageClass
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-fast
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "2"
  staleReplicaTimeout: "20"
  diskSelector: "ssd"
  nodeSelector: "storage-node"
EOF
```

**Using Longhorn Volumes:**

```bash
# Create PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 5Gi
EOF

# Check PVC status
kubectl get pvc longhorn-pvc
# STATUS: Bound

# Check PV created
kubectl get pv

# View Longhorn volume details
# In Longhorn UI or via kubectl
kubectl -n longhorn-system get volumes
kubectl -n longhorn-system describe volume pvc-xxxxx

# Use PVC in pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-longhorn
spec:
  containers:
    - name: app
      image: nginx
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: longhorn-pvc
EOF

# Verify pod is running
kubectl get pod test-longhorn

# Write data to volume
kubectl exec test-longhorn -- sh -c 'echo "Hello Longhorn" > /data/test.txt'

# Delete pod
kubectl delete pod test-longhorn

# Recreate pod (same PVC)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-longhorn-2
spec:
  containers:
    - name: app
      image: nginx
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: longhorn-pvc
EOF

# Data persists
kubectl exec test-longhorn-2 -- cat /data/test.txt
# Output: Hello Longhorn
```

**Longhorn Replicas:**

```bash
# Check volume replicas in UI or:
kubectl -n longhorn-system get replicas

# Each volume has 3 replicas (by default) on different nodes
# Check replica distribution for a volume
kubectl -n longhorn-system get replicas -o wide | grep pvc-xxxxx

# Simulate node failure
# Longhorn will detect and rebuild replica on another node

# Check volume health
kubectl -n longhorn-system get volumes -o yaml | grep state
# State should be: healthy, degraded, or faulted
```

#### Longhorn Backup and Restore (30 mins)

**Configure Backup Target:**

```bash
# Longhorn supports S3-compatible storage for backups
# Configure in Longhorn UI: Settings -> Backup Target

# Or via kubectl
kubectl -n longhorn-system edit settings backup-target

# Set to S3 endpoint:
# s3://bucket-name@region/path

# Configure backup credentials
kubectl -n longhorn-system create secret generic aws-secret \
  --from-literal=AWS_ACCESS_KEY_ID=<key> \
  --from-literal=AWS_SECRET_ACCESS_KEY=<secret>
```

**Create Backups:**

```bash
# One-time snapshot
# In Longhorn UI: Select volume -> Create Snapshot

# Or via kubectl (create VolumeSnapshot)
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: longhorn-snapshot-1
spec:
  volumeSnapshotClassName: longhorn
  source:
    persistentVolumeClaimName: longhorn-pvc
EOF

# Check snapshot
kubectl get volumesnapshot

# Create backup from snapshot (Longhorn UI)
# Or configure recurring backup job

# Recurring backup
# In Longhorn UI: Volume -> Schedule Recurring Backup
# Or create RecurringJob CR

cat <<EOF | kubectl apply -f -
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: backup-daily
  namespace: longhorn-system
spec:
  cron: "0 2 * * *"
  task: "backup"
  retain: 7
  concurrency: 1
  labels:
    interval: daily
EOF

# Apply job to volume
# Longhorn UI: Volume -> Attach label "interval=daily"
```

**Restore from Backup:**

```bash
# List available backups
# Longhorn UI: Backup -> List backups

# Restore to new PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restored-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  dataSource:
    name: longhorn-backup-xxxxx
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  resources:
    requests:
      storage: 5Gi
EOF

# Or restore via Longhorn UI:
# Backup -> Select backup -> Restore

# Mount restored PVC to pod
kubectl run test-restore --image=nginx \
  --overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"restored-pvc"}}],"containers":[{"name":"nginx","image":"nginx","volumeMounts":[{"name":"data","mountPath":"/data"}]}]}}'

# Verify data
kubectl exec test-restore -- ls /data
```

**Disaster Recovery:**

```bash
# Scenario: Complete cluster loss, need to restore

# 1. Deploy new cluster with Longhorn
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace

# 2. Configure same backup target
kubectl -n longhorn-system edit settings backup-target
# Set to same S3 bucket

# 3. List available backups
# Longhorn UI: Backup tab shows all backups from S3

# 4. Restore volumes
# For each volume backup:
# - Create PVC from backup
# - Longhorn downloads data from S3
# - Recreate workload pods with restored PVCs

# 5. Verify applications
kubectl get pods
kubectl logs <pod>
```

#### Knowledge Checklist

- [ ] **CSI Components**: What's the difference between controller and node plugin?
- [ ] **Volume Lifecycle**: Walk through PVC -> PV -> Mount -> Unmount
- [ ] **Longhorn Architecture**: How does replication work?
- [ ] **Storage Classes**: What parameters can you configure?
- [ ] **Snapshots**: Difference between snapshot and backup?
- [ ] **Backup Target**: What storage backends does Longhorn support?
- [ ] **Restore**: Can you restore to a different cluster?
- [ ] **Performance**: What affects Longhorn volume performance?

---

### CLUSTER LIFECYCLE & TROUBLESHOOTING - 1.5 hours

#### Upgrade Strategies (30 mins)

**Kubernetes Version Compatibility:**

```
Version skew policy:
- kube-apiserver: N (e.g., 1.28)
- controller-manager, scheduler: N or N-1
- kubelet: N, N-1, or N-2
- kubectl: N+1, N, or N-1

Example compatible versions:
- API Server: 1.28
- Controller Manager: 1.28 or 1.27
- Kubelet: 1.28, 1.27, or 1.26
- kubectl: 1.29, 1.28, or 1.27
```

**RKE1 Upgrade Process:**

```bash
# Check current version
kubectl version --short
rke version

# Plan upgrade
# 1. Review release notes
# 2. Test in dev/staging first
# 3. Backup etcd
rke etcd snapshot-save --config cluster.yml --name pre-upgrade

# Update cluster.yml
# Change: kubernetes_version: v1.29.0-rancher1-1
vi cluster.yml

# Configure upgrade strategy
# Already in cluster.yml:
upgrade_strategy:
  max_unavailable_worker: "10%"
  max_unavailable_controlplane: "1"
  drain: true
  drain_input:
    delete_local_data: true
    force: true
    grace_period: 60
    ignore_daemon_sets: true
    timeout: 120

# Perform upgrade
rke up --config cluster.yml

# Upgrade process:
# 1. Control plane node 1: drain, upgrade, uncordon
# 2. Wait for healthy
# 3. Control plane node 2: same
# 4. Control plane node 3: same
# 5. Worker nodes in batches (10% at a time)

# Monitor upgrade
kubectl get nodes -w

# Verify upgrade
kubectl version
kubectl get nodes

# Check workload health
kubectl get pods -A
```

**Manual Node Drain:**

```bash
# Drain node (evict pods gracefully)
kubectl drain node-1 \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60 \
  --timeout=5m

# Upgrade node
# (RKE does this automatically)

# Uncordon node
kubectl uncordon node-1

# Pods will be rescheduled back
```

#### Common RKE Issues (30 mins)

**Issue 1: RKE Up Fails on SSH Connection:**

```bash
# Symptom
rke up --config cluster.yml
# Error: Failed to dial ssh: handshake failed

# Diagnosis
# 1. Test SSH manually
ssh -i ~/.ssh/id_rsa ubuntu@10.0.1.10

# 2. Check SSH key permissions
ls -la ~/.ssh/id_rsa
# Should be 600

chmod 600 ~/.ssh/id_rsa

# 3. Check node SSH config
# On node:
cat /etc/ssh/sshd_config | grep -E 'PubkeyAuthentication|PasswordAuthentication'

# 4. Check firewall
# Ensure port 22 is open

# Fix
# Update cluster.yml with correct SSH key path and user
nodes:
  - address: 10.0.1.10
    user: ubuntu
    ssh_key_path: ~/.ssh/id_rsa
    port: 22
```

**Issue 2: etcd Cluster Unhealthy:**

```bash
# Symptom
kubectl get nodes
# Error: Unable to connect to the server

# Diagnosis
# SSH to etcd node
ssh ubuntu@10.0.1.10

# Check etcd container
docker ps | grep etcd

# Check etcd health
docker exec etcd etcdctl \
  --cacert=/etc/kubernetes/ssl/kube-ca.pem \
  --cert=/etc/kubernetes/ssl/kube-etcd-*.pem \
  --key=/etc/kubernetes/ssl/kube-etcd-*-key.pem \
  --endpoints=https://127.0.0.1:2379 \
  endpoint health

# Check etcd logs
docker logs etcd --tail=100

# Common causes:
# - etcd out of space (check df -h /var/lib/etcd)
# - Clock skew between members
# - Network partition
# - Certificate expired

# Fix: Restore from backup if corrupted
rke etcd snapshot-restore \
  --config cluster.yml \
  --name snapshot-name
```

**Issue 3: Node Won't Join Cluster:**

```bash
# Symptom
# New node added to cluster.yml
# rke up succeeds but node is NotReady

# Diagnosis
kubectl get nodes
# Node shows NotReady

kubectl describe node new-node

# Check kubelet on node
ssh ubuntu@new-node
docker ps | grep kubelet
docker logs kubelet

# Common causes:
# - CNI plugin not running
# - Docker not running
# - Insufficient resources
# - Firewall blocking communication

# Check CNI
docker ps | grep canal

# Check connectivity to other nodes
ping 10.0.1.10

# Fix: Ensure Docker and networking are healthy
systemctl status docker
docker network ls
```

**Issue 4: Pods Can't Pull Images:**

```bash
# Symptom
kubectl get pods
# Status: ImagePullBackOff

kubectl describe pod <pod>
# Error: Failed to pull image

# Causes:
# 1. Image doesn't exist
# 2. Private registry authentication
# 3. Network issue
# 4. Disk space on node

# Fix 1: Check image exists
docker pull <image>

# Fix 2: Create image pull secret
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass \
  --docker-email=email@example.com

# Use in pod
spec:
  imagePullSecrets:
    - name: regcred

# Fix 3: Check node disk space
ssh node
df -h /var/lib/docker
```

#### Node Troubleshooting (30 mins)

**Node Not Ready:**

```bash
# Check node status
kubectl get nodes
kubectl describe node <node>

# Check kubelet logs
ssh <node>
journalctl -u kubelet -f

# Common causes and fixes:

# 1. Disk pressure
df -h
# Clean up: docker system prune -a

# 2. Memory pressure
free -h
# Check for memory leaks: top

# 3. Network issues
# Test connectivity to API server
curl -k https://<api-server>:6443

# 4. Certificate issues
# Check kubelet cert
openssl x509 -in /var/lib/kubelet/pki/kubelet.crt -text -noout

# Rotate if expired
rke cert rotate --config cluster.yml --service kubelet
```

**High Node Load:**

```bash
# Check resource usage
kubectl top node <node>

# Check which pods are using resources
kubectl top pods -A --sort-by=memory
kubectl top pods -A --sort-by=cpu

# SSH to node and investigate
ssh <node>

# Check process list
top
# Or: htop

# Check disk I/O
iostat -x 1
# Or: iotop

# Check network
iftop

# Common fixes:
# 1. Scale down resource-heavy pods
# 2. Add resource limits
# 3. Add more nodes
# 4. Investigate application issues
```

**Pod Eviction:**

```bash
# Symptom: Pods being evicted

kubectl get pods -A | grep Evicted

# Check events
kubectl get events -A --sort-by='.lastTimestamp' | grep -i evict

# Causes:
# - Node disk pressure
# - Node memory pressure
# - Node PID pressure

# Check node conditions
kubectl describe node <node> | grep -A5 Conditions

# Fix disk pressure
ssh <node>
docker system prune -a
# Or add more disk

# Fix memory pressure
# Add resource limits to pods
# Or add more memory to nodes

# Clean up evicted pods
kubectl get pods -A | grep Evicted | awk '{print $2 " -n " $1}' | xargs -L1 kubectl delete pod
```

#### Final Knowledge Checklist

- [ ] **RKE Upgrade**: Can you perform a zero-downtime upgrade?
- [ ] **etcd Troubleshooting**: How do you diagnose etcd issues?
- [ ] **Node Troubleshooting**: What are the top 5 causes of NotReady nodes?
- [ ] **Network Debugging**: How do you troubleshoot pod-to-pod communication?
- [ ] **Storage Issues**: How do you diagnose PVC not binding?
- [ ] **Resource Pressure**: How do you handle node disk/memory pressure?
- [ ] **Certificate Rotation**: When and how do you rotate certificates?
- [ ] **Backup/Restore**: Can you restore a cluster from etcd backup?

---

## Day 3 - Final Prep Checklist

**Night Before Second Interview:**
- [ ] Review RKE1 vs RKE2 differences - explain architecture
- [ ] Practice explaining API server request flow
- [ ] Walk through etcd backup and restore process
- [ ] Explain scheduler filtering and scoring
- [ ] Design a simple CRD + controller
- [ ] Explain Canal (Calico + Flannel) architecture
- [ ] Demonstrate network policy creation
- [ ] Explain Longhorn replication and backup
- [ ] Practice troubleshooting scenarios
- [ ] Review common RKE issues and fixes

**Interview Day:**
- [ ] Be ready to whiteboard architectures
- [ ] Have examples of issues you've debugged
- [ ] Prepare questions about their RKE environment
- [ ] Be ready for scenario-based questions
- [ ] Focus on "how you would troubleshoot" approach

**Key Talking Points:**
- Emphasize hands-on experience with Kubernetes internals
- Discuss production troubleshooting methodology
- Show understanding of RKE vs cloud-managed differences
- Demonstrate systematic debugging approach
- Mention monitoring and observability practices
- Discuss high availability and disaster recovery

---

## Final Prep Checklist

**Day Before Interview:**
- [ ] Run `terraform plan` - make sure you understand every resource
- [ ] Run `flux get all` - explain what each resource does
- [ ] Run `helm list -A` - explain each release
- [ ] Read `.github/workflows/*.yml` - explain each step's purpose
- [ ] Check cluster health: `kubectl get nodes; kubectl get pods -A`
- [ ] Review this doc and mark anything you couldn't explain

**Interview Day:**
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
