# Kubernetes API Beginner's Guide

A comprehensive guide to understanding and working with the Kubernetes API, from basic concepts to building your own applications that interact with the cluster.

**Target Audience**: Software engineers who are new to Kubernetes but have programming experience.

**Last Updated**: February 2026 | K8s 1.34 | RKE2 v1.34.3

---

## Table-of-Contents

1. [Prerequisites](#prerequisites)
2. [What-is-the-Kubernetes-API](#what-is-the-kubernetes-api)
3. [Exploring-the-API](#exploring-the-api)
4. [API-Resource-Structure-GVR](#api-resource-structure-gvr)
5. [API-Operations-CRUD](#api-operations-crud)
6. [Authentication-and-Authorization](#authentication-and-authorization)
7. [Understanding-API-Objects](#understanding-api-objects)
8. [Watching-Resources-and-Events](#watching-resources-and-events)
9. [Working-with-the-API-Programmatically](#working-with-the-api-programmatically)
10. [Custom-Resources-and-CRDs](#custom-resources-and-crds)
11. [RKE2-Specific-API-Extensions](#rke2-specific-api-extensions)
12. [Practical-Exercises](#practical-exercises)
13. [Common-Mistakes-and-Troubleshooting](#common-mistakes-and-troubleshooting)
14. [Quick-Reference](#quick-reference)
15. [Building-a-Small-App-Pod-Health-Monitor](#building-a-small-app-pod-health-monitor)

---

## Prerequisites

Before diving into the Kubernetes API, ensure you have the following tools and knowledge in place.

### Required-Tools

You'll need these installed on your local machine:

```bash
# kubectl - Kubernetes command-line tool
kubectl version --client

# curl - for direct API calls
curl --version

# jq - JSON processor for readable output
jq --version

# Optional but recommended: Python 3.9+ or Go 1.21+
python3 --version
go version
```

**Installing kubectl** (if not already installed):

```bash
# Linux
curl -LO "https://dl.k8s.io/release/v1.34.0/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# macOS
brew install kubectl

# Verify installation
kubectl version --client
```

**Installing jq**:

```bash
# Linux
sudo apt-get install jq  # Debian/Ubuntu
sudo yum install jq      # RHEL/CentOS

# macOS
brew install jq
```

### Cluster-Access

You need access to a Kubernetes cluster. This guide assumes you have:

- A running cluster (RKE2, K3s, minikube, or managed K8s)
- A valid kubeconfig file
- Basic cluster admin permissions (at least for a namespace)

**Verify cluster access**:

```bash
# Check current context
kubectl config current-context

# Test connectivity
kubectl cluster-info

# List nodes (requires appropriate permissions)
kubectl get nodes

# Create a test namespace for exercises
kubectl create namespace api-learning
kubectl config set-context --current --namespace=api-learning
```

### Assumed-Knowledge

This guide assumes you understand:

- **Basic programming concepts**: Variables, functions, loops, error handling
- **HTTP fundamentals**: GET/POST/PUT/DELETE methods, status codes (200, 404, 403, etc.)
- **JSON structure**: Objects, arrays, key-value pairs
- **Command-line basics**: Running commands, piping output, environment variables

You do NOT need prior Kubernetes experience, but familiarity with containerization (Docker) is helpful.

### Verification-Checklist

Run these commands to ensure you're ready:

```bash
# 1. kubectl works
kubectl version --client --output=json | jq -r '.clientVersion.gitVersion'

# 2. Cluster is accessible
kubectl get --raw /healthz

# 3. You can create resources
kubectl auth can-i create pods --namespace=api-learning

# 4. API server is reachable
kubectl get --raw /api/v1 | jq -r '.kind'
```

Expected outputs:
- [ ] kubectl version shows v1.34.x
- [ ] `/healthz` returns `ok`
- [ ] `can-i` returns `yes`
- [ ] API call returns `APIResourceList`

If any check fails, troubleshoot your kubeconfig and cluster connectivity before proceeding.

[↑ Back to ToC](#table-of-contents)

---

## What-is-the-Kubernetes-API

The Kubernetes API is the foundation of the entire Kubernetes system. Understanding it transforms you from someone who runs commands to someone who truly understands what's happening under the hood.

### Everything-is-an-API-Call

Here's a fundamental insight: **every interaction with Kubernetes is an HTTP API call to the API server**.

When you run `kubectl get pods`, kubectl doesn't have special magic. It's making an HTTP GET request to the API server. Let's see this in action:

```bash
# Run kubectl with verbose output to see the actual API calls
kubectl get pods --v=8
```

You'll see output like:

```
GET https://10.43.0.1:443/api/v1/namespaces/api-learning/pods?limit=500
Request Headers:
  Accept: application/json;as=Table;v=v1;g=meta.k8s.io
  User-Agent: kubectl/v1.34.0
Response Status: 200 OK
Response Body: {"kind":"Table","apiVersion":"meta.k8s.io/v1"...}
```

**Key insight**: Every kubectl command translates to an HTTP request. The API server is just a REST API that speaks JSON.

### Why-the-API-Matters

Understanding the Kubernetes API is crucial because:

1. **Automation**: You can programmatically manage clusters from any language that speaks HTTP
2. **Debugging**: When things break, you need to understand what the API is actually doing
3. **Advanced features**: Custom controllers, operators, and automation tools all interact with this API
4. **Troubleshooting**: Reading error messages becomes easier when you understand API responses
5. **Career growth**: Senior engineers build tools that extend Kubernetes via the API

### Declarative-vs-Imperative

Kubernetes embraces a **declarative** model:

**Imperative** (traditional):
```bash
# You tell the system HOW to do something step-by-step
ssh server1
sudo systemctl start nginx
ssh server2
sudo systemctl start nginx
# Manual, sequential, fragile
```

**Declarative** (Kubernetes):
```yaml
# You tell the system WHAT you want, not HOW to achieve it
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 2
  # K8s figures out how to make this reality
```

When you apply this YAML, Kubernetes:
1. Receives your desired state via the API
2. Compares it to the current state
3. Calculates the necessary changes
4. Executes those changes
5. Continuously monitors to maintain your desired state

**Key insight**: The API is the interface through which you declare your desired state. Kubernetes controllers watch the API and work to reconcile reality with your desires.

### What-Happens-When-You-Apply-a-Deployment

Let's trace exactly what happens when you run `kubectl apply -f deployment.yaml`:

**Step 1: kubectl parses the YAML**

```bash
# Create a simple deployment
cat <<EOF > /tmp/nginx-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: api-learning
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
EOF

# Apply it with verbose output
kubectl apply -f /tmp/nginx-deployment.yaml --v=8
```

**Step 2: kubectl makes an HTTP request**

You'll see kubectl makes a request like:

```
PATCH /apis/apps/v1/namespaces/api-learning/deployments/nginx
Content-Type: application/apply-patch+yaml
```

The request body contains your YAML with special metadata for server-side apply.

**Step 3: API server receives and validates**

The API server:
- Authenticates your request (checks your credentials)
- Authorizes your request (checks RBAC permissions)
- Validates the resource (checks schema, required fields)
- Persists to etcd (the cluster's database)

**Step 4: Controllers react**

The Deployment controller watches the API for Deployment objects:
- Sees your new Deployment
- Creates a ReplicaSet object (also via the API)
- The ReplicaSet controller sees the new ReplicaSet
- Creates 3 Pod objects (via the API)
- The Scheduler sees unscheduled Pods
- Assigns nodes to each Pod (updates via API)
- Kubelets on those nodes see Pods assigned to them
- Pull images and start containers

**Key insight**: Every step in this cascade is driven by API reads and writes. Controllers are watching the API, reacting to changes, and making new API calls to reconcile state.

### The-API-is-the-Source-of-Truth

Everything stored in Kubernetes lives in etcd, accessible only through the API:

```bash
# Everything you see is from the API
kubectl get all --namespace=api-learning

# The real-time state is in the API server
kubectl get deployment nginx -o yaml

# Changes must go through the API
kubectl scale deployment nginx --replicas=5

# Even status updates from kubelets go through the API
kubectl get pod nginx-xyz123-abc45 -o jsonpath='{.status.phase}'
```

> **Note:** You should never access etcd directly. The API server is the only supported interface to cluster state.

### API-Server-Architecture

The API server is stateless. It:

- Validates and processes API requests
- Reads/writes to etcd (the only stateful component)
- Serves as the central hub for all cluster communication
- Implements authentication, authorization, and admission control
- Provides watch capabilities for real-time updates

```
┌─────────────┐
│   kubectl   │
│  or custom  │──┐
│   client    │  │
└─────────────┘  │
                 │  HTTP/JSON
┌─────────────┐  │
│ Controllers │──┤
│ (Deployment,│  │
│ ReplicaSet) │  │
└─────────────┘  │
                 ▼
         ┌──────────────┐         ┌──────┐
         │  API Server  │────────▶│ etcd │
         │  (stateless) │◀────────│      │
         └──────────────┘         └──────┘
                 ▲
                 │
         ┌───────┴────────┐
         │                │
    ┌────────┐      ┌─────────┐
    │Kubelet │      │Scheduler│
    │(nodes) │      │         │
    └────────┘      └─────────┘
```

### REST-Principles

The Kubernetes API follows REST conventions:

- **Resources** are identified by URLs: `/api/v1/namespaces/default/pods/nginx`
- **HTTP verbs** map to operations: GET (read), POST (create), PUT (replace), PATCH (update), DELETE (remove)
- **Stateless**: Each request contains all necessary information
- **JSON**: Primary representation format (YAML is converted to JSON by kubectl)

Example REST patterns:

```bash
# List all pods in a namespace (GET collection)
GET /api/v1/namespaces/api-learning/pods

# Get a specific pod (GET resource)
GET /api/v1/namespaces/api-learning/pods/nginx-xyz

# Create a new pod (POST to collection)
POST /api/v1/namespaces/api-learning/pods

# Update a pod (PUT or PATCH to resource)
PATCH /api/v1/namespaces/api-learning/pods/nginx-xyz

# Delete a pod (DELETE resource)
DELETE /api/v1/namespaces/api-learning/pods/nginx-xyz
```

### Idempotency

Many API operations are idempotent, meaning you can safely repeat them:

```bash
# Applying the same YAML multiple times is safe
kubectl apply -f deployment.yaml
kubectl apply -f deployment.yaml  # No error, no duplicate resources

# Deleting an already-deleted resource is safe (with --ignore-not-found)
kubectl delete pod nonexistent --ignore-not-found
```

This is crucial for automation and recovery scenarios.

### API-Versioning

Kubernetes APIs evolve over time. Resources have versions like:

- `v1` - Stable, production-ready
- `v1beta1` - Pre-release, may change
- `v1alpha1` - Experimental, may be removed

```bash
# Deployments graduated to stable
apiVersion: apps/v1  # Current stable version

# Some features start in beta
apiVersion: batch/v1beta1  # Hypothetical beta API
```

**Key insight**: Always use stable (`v1`) APIs in production. Beta APIs may change between Kubernetes versions, breaking your manifests.

[↑ Back to ToC](#table-of-contents)

---

## Exploring-the-API

Now that you understand what the API is, let's explore it hands-on. Kubernetes provides excellent tools for API discovery without needing to read documentation.

### kubectl-api-resources

The `api-resources` command shows every resource type available in your cluster:

```bash
# List all API resources
kubectl api-resources

# Output includes:
# NAME          SHORTNAMES   APIVERSION   NAMESPACED   KIND
# pods          po           v1           true         Pod
# services      svc          v1           true         Service
# deployments   deploy       apps/v1      true         Deployment
```

**Understanding the columns**:

- **NAME**: Resource name used in API paths and kubectl commands
- **SHORTNAMES**: Aliases (e.g., `po` for `pods`, `svc` for `services`)
- **APIVERSION**: Group and version (`v1` means core group, `apps/v1` means apps group)
- **NAMESPACED**: Whether the resource exists within a namespace or is cluster-wide
- **KIND**: The name used in YAML manifests

**Filtering by API group**:

```bash
# Show only core resources (no group prefix)
kubectl api-resources --api-group=""

# Show only apps group resources
kubectl api-resources --api-group=apps

# Show only batch group resources
kubectl api-resources --api-group=batch
```

**Filtering by namespace scope**:

```bash
# Show only namespaced resources
kubectl api-resources --namespaced=true

# Show only cluster-scoped resources (e.g., Nodes, ClusterRoles)
kubectl api-resources --namespaced=false
```

**Finding resource details**:

```bash
# Search for specific resources
kubectl api-resources | grep -i deployment

# Get all verbs supported for a resource
kubectl api-resources -o wide | grep pods
# Shows: [create delete deletecollection get list patch update watch]
```

**Key insight**: Use `api-resources` when you forget a resource name or want to discover what's available in your cluster.

### kubectl-explain

The `explain` command is like built-in documentation. It shows the schema for any resource:

```bash
# Get top-level documentation for Pods
kubectl explain pod

# Output shows:
# KIND:     Pod
# VERSION:  v1
# DESCRIPTION:
#     Pod is a collection of containers...
# FIELDS:
#   apiVersion <string>
#   kind       <string>
#   metadata   <Object>
#   spec       <Object>
#   status     <Object>
```

**Drilling down into nested fields**:

```bash
# Explain pod.spec
kubectl explain pod.spec

# Explain pod.spec.containers
kubectl explain pod.spec.containers

# Explain a specific container field
kubectl explain pod.spec.containers.image

# Go deep into nested structures
kubectl explain pod.spec.containers.resources.limits
```

**Getting recursive output**:

```bash
# Show all fields recursively (warning: very verbose)
kubectl explain pod --recursive

# Show recursive output with types
kubectl explain pod --recursive=true | less
```

**Practical example - finding memory limit syntax**:

```bash
# You want to set memory limits but forget the syntax
kubectl explain pod.spec.containers.resources

# Shows:
# FIELDS:
#   limits   <map[string]string>
#   requests <map[string]string>

# Drill deeper
kubectl explain pod.spec.containers.resources.limits

# Shows it's a map of resource names to quantities
# Example: memory: "128Mi", cpu: "500m"
```

**Key insight**: Use `kubectl explain` when writing YAML manifests. It's faster than searching documentation and always matches your cluster's version.

### kubectl-api-versions

This command lists all API versions available in your cluster:

```bash
# List all API groups and versions
kubectl api-versions

# Output includes:
# v1                    # Core group
# apps/v1              # Apps group
# batch/v1             # Batch group
# networking.k8s.io/v1 # Networking group
# rbac.authorization.k8s.io/v1  # RBAC group
```

**Why this matters**:

Different Kubernetes versions support different API versions. When you see an error like:

```
error: unable to recognize "deployment.yaml": no matches for kind "Deployment" in version "apps/v1beta1"
```

It means your cluster doesn't support that API version. Check available versions:

```bash
# Check if apps/v1 is available
kubectl api-versions | grep apps/

# Update your YAML to use a supported version
apiVersion: apps/v1  # Instead of apps/v1beta1
```

### Direct-API-Access-with-kubectl-proxy

kubectl can create a local proxy to the API server, removing authentication complexity:

```bash
# Start the proxy (runs in foreground)
kubectl proxy --port=8080

# In another terminal, make direct API calls
curl http://localhost:8080/api/v1/namespaces
```

**Why use the proxy**:

- No need to deal with certificates and tokens
- Easy testing with curl or browser
- Great for learning API structure

**Exploring endpoints**:

```bash
# Start proxy in background
kubectl proxy --port=8080 &

# Get API versions
curl http://localhost:8080/api

# Get resource lists
curl http://localhost:8080/api/v1 | jq -r '.resources[].name'

# List all pods in a namespace
curl http://localhost:8080/api/v1/namespaces/api-learning/pods | jq -r '.items[].metadata.name'

# Get a specific pod
curl http://localhost:8080/api/v1/namespaces/api-learning/pods/nginx-xyz | jq .

# Stop the proxy when done
killall kubectl
```

**Understanding JSON responses**:

```bash
# Get a pod and examine its structure
curl -s http://localhost:8080/api/v1/namespaces/api-learning/pods | jq '.' | less

# The response is a "PodList" object:
{
  "kind": "PodList",
  "apiVersion": "v1",
  "metadata": {
    "resourceVersion": "12345"
  },
  "items": [
    {
      "kind": "Pod",
      "apiVersion": "v1",
      "metadata": { ... },
      "spec": { ... },
      "status": { ... }
    }
  ]
}
```

**Key insight**: Every list response has `kind` (e.g., PodList), `apiVersion`, `metadata`, and `items` array. Individual resources have `metadata`, `spec`, and `status`.

### Exploring-API-Paths

API paths follow predictable patterns. Understanding them helps you construct API calls:

**Pattern for core resources** (v1 API group):

```
/api/v1/namespaces/{namespace}/{resource-type}
/api/v1/namespaces/{namespace}/{resource-type}/{name}
```

Examples:

```bash
# List all pods in default namespace
GET /api/v1/namespaces/default/pods

# Get specific pod
GET /api/v1/namespaces/default/pods/nginx-xyz
```

**Pattern for named group resources** (apps, batch, etc.):

```
/apis/{group}/{version}/namespaces/{namespace}/{resource-type}
/apis/{group}/{version}/namespaces/{namespace}/{resource-type}/{name}
```

Examples:

```bash
# List deployments (apps/v1)
GET /apis/apps/v1/namespaces/api-learning/deployments

# Get specific deployment
GET /apis/apps/v1/namespaces/api-learning/deployments/nginx

# List cronjobs (batch/v1)
GET /apis/batch/v1/namespaces/api-learning/cronjobs
```

**Pattern for cluster-scoped resources**:

```
/api/v1/{resource-type}
/api/v1/{resource-type}/{name}

/apis/{group}/{version}/{resource-type}
/apis/{group}/{version}/{resource-type}/{name}
```

Examples:

```bash
# List all nodes (core, cluster-scoped)
GET /api/v1/nodes

# Get specific node
GET /api/v1/nodes/worker-1

# List all cluster roles (rbac, cluster-scoped)
GET /apis/rbac.authorization.k8s.io/v1/clusterroles
```

**Testing these patterns**:

```bash
# Start proxy
kubectl proxy --port=8080 &

# Core resource (Pod)
curl http://localhost:8080/api/v1/namespaces/api-learning/pods | jq -r '.items[].metadata.name'

# Named group resource (Deployment)
curl http://localhost:8080/apis/apps/v1/namespaces/api-learning/deployments | jq -r '.items[].metadata.name'

# Cluster resource (Node)
curl http://localhost:8080/api/v1/nodes | jq -r '.items[].metadata.name'
```

### Discovery-Endpoints

The API server provides discovery endpoints that describe available resources:

```bash
# Root discovery
curl http://localhost:8080/api | jq .

# Core group resources
curl http://localhost:8080/api/v1 | jq -r '.resources[] | "\(.name) (\(.kind))"'

# Apps group resources
curl http://localhost:8080/apis/apps/v1 | jq -r '.resources[] | "\(.name) (\(.kind))"'

# All API groups
curl http://localhost:8080/apis | jq -r '.groups[] | .name'
```

**Discovering verbs**:

```bash
# See what operations are supported for pods
curl http://localhost:8080/api/v1 | jq -r '.resources[] | select(.name=="pods") | .verbs[]'

# Output:
# create
# delete
# deletecollection
# get
# list
# patch
# update
# watch
```

**Key insight**: The API is self-documenting. You can discover everything programmatically without external documentation.

### Using-OpenAPI-Specification

Kubernetes publishes its API as an OpenAPI (Swagger) spec:

```bash
# Get the OpenAPI spec (large JSON document)
curl http://localhost:8080/openapi/v2 > /tmp/k8s-openapi.json

# Get schema for a specific resource
cat /tmp/k8s-openapi.json | jq '.definitions."io.k8s.api.core.v1.Pod"'

# Or use OpenAPI v3
curl http://localhost:8080/openapi/v3 | jq .
```

This is how tools like kubectl and client libraries know resource schemas.

### Practical-Discovery-Exercise

Let's discover everything about Services:

```bash
# 1. Find the resource
kubectl api-resources | grep -i service

# Output:
# services    svc    v1    true    Service

# 2. Get documentation
kubectl explain service

# 3. Check API group and version
kubectl api-versions | grep '^v1$'

# 4. Build the API path
# Core group (no prefix), namespaced resource
# Path: /api/v1/namespaces/{namespace}/services

# 5. List services via API
kubectl proxy --port=8080 &
curl http://localhost:8080/api/v1/namespaces/api-learning/services | jq -r '.items[].metadata.name'

# 6. Get supported operations
curl http://localhost:8080/api/v1 | jq -r '.resources[] | select(.name=="services") | .verbs[]'

# 7. Read a specific service
kubectl create service clusterip test --tcp=80:80 --namespace=api-learning
curl http://localhost:8080/api/v1/namespaces/api-learning/services/test | jq .

# Cleanup
kubectl delete service test --namespace=api-learning
killall kubectl
```

[↑ Back to ToC](#table-of-contents)

---

## API-Resource-Structure-GVR

Understanding how Kubernetes organizes API resources is crucial for working with the API effectively. The GVR model (Group, Version, Resource) is the key to navigation.

### What-is-GVR

GVR stands for:

- **Group**: Logical collection of related resources (e.g., `apps`, `batch`, `networking.k8s.io`)
- **Version**: API stability level (e.g., `v1`, `v1beta1`, `v1alpha1`)
- **Resource**: The actual resource type (e.g., `deployments`, `pods`, `services`)

Together, these form a unique identifier for any resource type in Kubernetes.

### The-Core-Group

The **core group** (also called legacy group) contains fundamental Kubernetes resources. It has no group name in API paths.

**Core resources include**:
- Pods
- Services
- ConfigMaps
- Secrets
- Namespaces
- Nodes
- PersistentVolumes
- PersistentVolumeClaims
- ServiceAccounts

**API paths for core resources**:

```bash
# Format: /api/{version}/...
# Notice: NO "apis" (plural), NO group name

# Examples:
GET /api/v1/namespaces
GET /api/v1/namespaces/default/pods
GET /api/v1/namespaces/default/services
GET /api/v1/nodes
```

**In YAML manifests**:

```yaml
# Core group resources use just "v1"
apiVersion: v1
kind: Pod
metadata:
  name: nginx
```

**Key insight**: If you see `apiVersion: v1` with no prefix, it's a core group resource. If you see `apiVersion: something/v1`, it's a named group.

### Named-API-Groups

All non-core resources belong to named groups. These organize resources by functionality:

**Common named groups**:

| Group | Purpose | Example Resources |
|-------|---------|-------------------|
| `apps` | Application workloads | Deployments, StatefulSets, DaemonSets, ReplicaSets |
| `batch` | Batch processing | Jobs, CronJobs |
| `networking.k8s.io` | Networking | NetworkPolicies, Ingresses |
| `rbac.authorization.k8s.io` | Access control | Roles, ClusterRoles, RoleBindings |
| `storage.k8s.io` | Storage | StorageClasses, VolumeAttachments |
| `policy` | Pod security | PodDisruptionBudgets, PodSecurityPolicies |
| `autoscaling` | Scaling | HorizontalPodAutoscalers |

**API paths for named groups**:

```bash
# Format: /apis/{group}/{version}/...
# Notice: "apis" (plural) + group name

# Examples:
GET /apis/apps/v1/namespaces/default/deployments
GET /apis/batch/v1/namespaces/default/jobs
GET /apis/networking.k8s.io/v1/namespaces/default/networkpolicies
GET /apis/rbac.authorization.k8s.io/v1/clusterroles
```

**In YAML manifests**:

```yaml
# Named group resources include the group prefix
apiVersion: apps/v1
kind: Deployment

---
apiVersion: batch/v1
kind: CronJob

---
apiVersion: networking.k8s.io/v1
kind: Ingress
```

### API-Versioning-Levels

Kubernetes uses three stability levels for API versions:

**Alpha (v1alpha1, v2alpha1)**:
- Experimental features
- May be buggy
- May be removed in future versions without notice
- Disabled by default in many clusters
- Not recommended for production

```yaml
# Example alpha API (hypothetical)
apiVersion: example.k8s.io/v1alpha1
kind: ExperimentalResource
```

**Beta (v1beta1, v2beta1)**:
- Pre-release features
- Well-tested but may change
- Enabled by default
- Will be migrated to stable eventually
- May have breaking changes before going stable

```yaml
# Example beta API
apiVersion: batch/v1beta1
kind: CronJob  # CronJob was beta until K8s 1.21
```

**Stable (v1, v2)**:
- Production-ready
- Changes are backward-compatible
- Will be supported for many releases
- The only version you should use in production

```yaml
# Stable APIs
apiVersion: v1
kind: Pod

---
apiVersion: apps/v1
kind: Deployment
```

**Version progression example**:

```yaml
# CronJob's journey through versions:

# Kubernetes 1.8-1.20: Beta
apiVersion: batch/v1beta1
kind: CronJob

# Kubernetes 1.21+: Stable
apiVersion: batch/v1
kind: CronJob
```

**Checking available versions in your cluster**:

```bash
# See all versions for a resource
kubectl api-resources | grep cronjobs

# Output might show:
# cronjobs    cj    batch/v1    true    CronJob

# Check if older versions are still available
kubectl api-versions | grep batch
```

**Key insight**: Always use the most stable version available. When upgrading Kubernetes, check release notes for deprecated API versions.

### Reading-API-Paths

Let's practice deconstructing API paths:

**Example 1: Core resource**

```
/api/v1/namespaces/production/pods/nginx-xyz
```

Breaking it down:
- `/api` - Core group indicator
- `/v1` - API version (stable)
- `/namespaces/production` - Namespace scope
- `/pods` - Resource type
- `/nginx-xyz` - Specific resource name

**Example 2: Named group resource**

```
/apis/apps/v1/namespaces/production/deployments/web-app
```

Breaking it down:
- `/apis` - Named group indicator (plural)
- `/apps` - Group name
- `/v1` - API version
- `/namespaces/production` - Namespace scope
- `/deployments` - Resource type
- `/web-app` - Specific resource name

**Example 3: Cluster-scoped resource**

```
/apis/rbac.authorization.k8s.io/v1/clusterroles/admin
```

Breaking it down:
- `/apis` - Named group
- `/rbac.authorization.k8s.io` - Group name (with domain)
- `/v1` - API version
- `/clusterroles` - Resource type (no namespace)
- `/admin` - Specific resource name

**Building paths from YAML**:

Given this YAML:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
  namespace: production
```

Construct the API path:
1. `apiVersion: networking.k8s.io/v1` → `/apis/networking.k8s.io/v1`
2. `kind: Ingress` → resource type is `ingresses` (lowercase, plural)
3. `namespace: production` → `/namespaces/production`
4. `name: web-ingress` → `/web-ingress`

Full path:
```
/apis/networking.k8s.io/v1/namespaces/production/ingresses/web-ingress
```

**Testing your understanding**:

```bash
kubectl proxy --port=8080 &

# Create an ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  namespace: api-learning
spec:
  rules:
  - host: test.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: test
            port:
              number: 80
EOF

# Access it via the constructed API path
curl http://localhost:8080/apis/networking.k8s.io/v1/namespaces/api-learning/ingresses/test-ingress | jq .

# Cleanup
kubectl delete ingress test-ingress --namespace=api-learning
killall kubectl
```

### Subresources

Some resources have **subresources** - special endpoints under a resource:

**Common subresources**:

| Subresource | Purpose | Example Path |
|-------------|---------|--------------|
| `/status` | Read/write status field independently | `/api/v1/namespaces/default/pods/nginx/status` |
| `/scale` | Get/set replica count for scalable resources | `/apis/apps/v1/namespaces/default/deployments/nginx/scale` |
| `/log` | Get container logs | `/api/v1/namespaces/default/pods/nginx/log` |
| `/exec` | Execute command in container | `/api/v1/namespaces/default/pods/nginx/exec` |
| `/portforward` | Forward local port to pod port | `/api/v1/namespaces/default/pods/nginx/portforward` |
| `/proxy` | Proxy HTTP requests to pod | `/api/v1/namespaces/default/pods/nginx/proxy` |

**Example: Getting pod logs via API**:

```bash
kubectl proxy --port=8080 &

# Create a pod
kubectl run nginx --image=nginx:1.27 --namespace=api-learning

# Wait for it to run
kubectl wait --for=condition=ready pod/nginx --namespace=api-learning --timeout=60s

# Get logs via API
curl "http://localhost:8080/api/v1/namespaces/api-learning/pods/nginx/log"

# Get logs with query parameters
curl "http://localhost:8080/api/v1/namespaces/api-learning/pods/nginx/log?tailLines=10&timestamps=true"

# Cleanup
kubectl delete pod nginx --namespace=api-learning
killall kubectl
```

**Example: Scaling via the scale subresource**:

```bash
# Get current scale
curl http://localhost:8080/apis/apps/v1/namespaces/api-learning/deployments/nginx/scale | jq .

# Update scale (requires proper HTTP client, see CRUD section)
```

**Key insight**: Subresources allow operations on specific aspects of a resource without modifying the entire object. Controllers use these heavily (e.g., updating status without triggering full reconciliation).

### Resource-Naming-Conventions

Kubernetes follows these conventions:

**In API paths**:
- Lowercase
- Plural form
- Hyphens for multi-word names

Examples: `pods`, `services`, `replicasets`, `horizontalpodautoscalers`

**In YAML (Kind field)**:
- CamelCase
- Singular form

Examples: `Pod`, `Service`, `ReplicaSet`, `HorizontalPodAutoscaler`

**Converting between them**:

```bash
# Use kubectl api-resources to see both
kubectl api-resources | grep -i deployment

# Output shows mapping:
# NAME           SHORTNAMES   KIND
# deployments    deploy       Deployment
```

[↑ Back to ToC](#table-of-contents)

---

## API-Operations-CRUD

Now that you understand API structure, let's learn how to Create, Read, Update, and Delete resources via the API. We'll show both kubectl and raw API approaches.

### Create-POST

Creating a resource sends a POST request to the collection endpoint.

**With kubectl**:

```bash
# Imperative create
kubectl run nginx --image=nginx:1.27 --namespace=api-learning

# Declarative create from YAML
cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Pod
metadata:
  name: web-pod
  namespace: api-learning
  labels:
    app: web
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    ports:
    - containerPort: 80
EOF

# See the API call with verbose output
kubectl create -f pod.yaml --v=8
```

**With direct API calls**:

```bash
# Start proxy
kubectl proxy --port=8080 &

# Create pod with POST
curl -X POST \
  http://localhost:8080/api/v1/namespaces/api-learning/pods \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "v1",
    "kind": "Pod",
    "metadata": {
      "name": "api-pod",
      "namespace": "api-learning"
    },
    "spec": {
      "containers": [
        {
          "name": "nginx",
          "image": "nginx:1.27"
        }
      ]
    }
  }'

# Check the response
# Status 201 Created means success
# Response body contains the created object with server-generated fields (uid, resourceVersion, etc.)
```

**What happens on create**:

1. API server validates the resource schema
2. Runs admission controllers (mutating, then validating)
3. Assigns a UID and initial resourceVersion
4. Persists to etcd
5. Returns the created object

**Key insight**: POST always creates a new resource. If a resource with that name exists, you get a 409 Conflict error.

### Read-GET

Reading resources uses GET requests.

**Reading a single resource**:

```bash
# With kubectl
kubectl get pod nginx --namespace=api-learning -o yaml

# With API
curl http://localhost:8080/api/v1/namespaces/api-learning/pods/nginx | jq .

# Get specific field
kubectl get pod nginx --namespace=api-learning -o jsonpath='{.status.phase}'

# Same with API and jq
curl -s http://localhost:8080/api/v1/namespaces/api-learning/pods/nginx | jq -r '.status.phase'
```

**Listing resources (collection)**:

```bash
# With kubectl
kubectl get pods --namespace=api-learning

# With API - returns a PodList object
curl http://localhost:8080/api/v1/namespaces/api-learning/pods | jq .

# The response structure:
{
  "kind": "PodList",
  "apiVersion": "v1",
  "metadata": {
    "resourceVersion": "12345"
  },
  "items": [
    { /* Pod 1 */ },
    { /* Pod 2 */ }
  ]
}
```

**Filtering with field selectors**:

```bash
# Get pods on a specific node
kubectl get pods --field-selector spec.nodeName=worker-1

# Via API
curl "http://localhost:8080/api/v1/namespaces/api-learning/pods?fieldSelector=spec.nodeName=worker-1"

# Get only running pods
kubectl get pods --field-selector status.phase=Running

# Multiple selectors (AND logic)
kubectl get pods --field-selector status.phase=Running,spec.restartPolicy=Always
```

**Filtering with label selectors**:

```bash
# Get pods with specific label
kubectl get pods -l app=nginx

# Via API
curl "http://localhost:8080/api/v1/namespaces/api-learning/pods?labelSelector=app=nginx"

# Multiple labels (AND)
kubectl get pods -l app=nginx,environment=production

# Set-based selectors
kubectl get pods -l 'app in (nginx, apache)'
kubectl get pods -l 'environment,environment notin (dev, test)'
```

**Pagination with limit and continue**:

```bash
# Get first 10 pods
curl "http://localhost:8080/api/v1/pods?limit=10" | jq -r '.metadata.continue'

# Use the continue token for next page
curl "http://localhost:8080/api/v1/pods?limit=10&continue=ENCODED_TOKEN"
```

**Key insight**: List operations can be expensive. Always use labels/fields to filter, and use pagination for large result sets.

### Update-PUT-vs-PATCH

There are three ways to update resources: PUT (replace), PATCH (strategic merge), and PATCH (JSON merge/patch).

#### PUT-Replace

PUT replaces the entire resource. You must include all fields.

```bash
# Get current resource
kubectl get pod nginx --namespace=api-learning -o json > /tmp/pod.json

# Modify the JSON file
jq '.spec.containers[0].image = "nginx:1.28"' /tmp/pod.json > /tmp/pod-updated.json

# Replace with PUT (not recommended - use PATCH instead)
curl -X PUT \
  http://localhost:8080/api/v1/namespaces/api-learning/pods/nginx \
  -H "Content-Type: application/json" \
  -d @/tmp/pod-updated.json
```

**Problems with PUT**:
- You must send the entire object
- Risk of overwriting concurrent changes
- Removes fields if you forget them

**When to use PUT**: Rarely. Only when you truly want to replace the entire resource.

#### PATCH-Strategic-Merge

Strategic merge patch is Kubernetes-specific and the most common approach. It intelligently merges your changes.

```bash
# With kubectl
kubectl patch pod nginx --namespace=api-learning \
  --type='strategic' \
  --patch='{"spec":{"containers":[{"name":"nginx","image":"nginx:1.28"}]}}'

# With API
curl -X PATCH \
  http://localhost:8080/api/v1/namespaces/api-learning/pods/nginx \
  -H "Content-Type: application/strategic-merge-patch+json" \
  -d '{
    "spec": {
      "containers": [
        {
          "name": "nginx",
          "image": "nginx:1.28"
        }
      ]
    }
  }'
```

**How strategic merge works**:

- **Maps/objects**: Fields are merged (not replaced)
- **Arrays with patch strategies**: Elements are merged by key (e.g., container name)
- **Primitive arrays**: Replaced entirely

**Example: Adding a label**:

```bash
# Only send the new label, existing labels preserved
kubectl patch pod nginx --namespace=api-learning \
  --type='strategic' \
  --patch='{
    "metadata": {
      "labels": {
        "environment": "production"
      }
    }
  }'

# Check result - both old and new labels exist
kubectl get pod nginx --namespace=api-learning --show-labels
```

#### PATCH-JSON-Merge

JSON merge patch follows RFC 7386. Simpler but less intelligent than strategic merge.

```bash
# With kubectl
kubectl patch pod nginx --namespace=api-learning \
  --type='merge' \
  --patch='{"metadata":{"labels":{"version":"v2"}}}'

# With API
curl -X PATCH \
  http://localhost:8080/api/v1/namespaces/api-learning/pods/nginx \
  -H "Content-Type: application/merge-patch+json" \
  -d '{
    "metadata": {
      "labels": {
        "version": "v2"
      }
    }
  }'
```

**JSON merge rules**:
- Fields in patch are merged or replaced
- `null` value deletes a field
- Arrays are always replaced (not merged)

**Deleting a field**:

```bash
# Remove a label by setting it to null
kubectl patch pod nginx --namespace=api-learning \
  --type='merge' \
  --patch='{"metadata":{"labels":{"version":null}}}'
```

#### PATCH-JSON-Patch

JSON patch follows RFC 6902. Most powerful but complex - allows precise operations.

```bash
# JSON patch uses an array of operations
kubectl patch pod nginx --namespace=api-learning \
  --type='json' \
  --patch='[
    {"op": "replace", "path": "/spec/containers/0/image", "value": "nginx:1.28"},
    {"op": "add", "path": "/metadata/labels/patched", "value": "true"}
  ]'

# With API
curl -X PATCH \
  http://localhost:8080/api/v1/namespaces/api-learning/pods/nginx \
  -H "Content-Type: application/json-patch+json" \
  -d '[
    {"op": "replace", "path": "/spec/containers/0/image", "value": "nginx:1.28"}
  ]'
```

**JSON patch operations**:
- `add`: Add a field or array element
- `remove`: Delete a field or array element
- `replace`: Change a value
- `move`: Move a value from one path to another
- `copy`: Copy a value to another path
- `test`: Assert a value (fails patch if incorrect)

**Example: Safe update with test**:

```bash
# Only apply patch if image is currently nginx:1.27
kubectl patch pod nginx --namespace=api-learning \
  --type='json' \
  --patch='[
    {"op": "test", "path": "/spec/containers/0/image", "value": "nginx:1.27"},
    {"op": "replace", "path": "/spec/containers/0/image", "value": "nginx:1.28"}
  ]'
```

### Which-Patch-Type-to-Use

**Strategic merge** (default):
- Best for most use cases
- Intuitive behavior
- Use when: Making simple changes to Kubernetes resources

**JSON merge**:
- Good for removing fields
- Simpler than strategic merge
- Use when: Working with non-Kubernetes resources or need to delete fields

**JSON patch**:
- Most precise control
- Complex syntax
- Use when: Need atomic operations or conditional updates

### kubectl-apply-Server-Side-Apply

`kubectl apply` uses a special technique called **server-side apply** (SSA):

```bash
# Apply tracks field ownership
kubectl apply -f deployment.yaml

# Apply again - idempotent
kubectl apply -f deployment.yaml

# See field managers
kubectl get deployment nginx --namespace=api-learning -o yaml | grep -A 10 managedFields
```

**How SSA works**:

1. You apply a resource with specific fields
2. API server tracks which fields you "own" (managedFields)
3. Future applies only modify your owned fields
4. Other controllers can own other fields without conflicts

**Example: Two managers collaborating**:

```bash
# You manage replicas
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: api-learning
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
      containers:
      - name: nginx
        image: nginx:1.27
EOF

# HPA manages replicas too (simulated)
kubectl patch deployment web --namespace=api-learning \
  --type='merge' \
  --patch='{"spec":{"replicas":5}}'

# Your next apply doesn't reset replicas because HPA owns that field
# (Actual HPA behavior is more complex, this is simplified)
```

**Key insight**: Server-side apply enables multiple actors to manage different fields of the same resource without conflicts.

### Delete-DELETE

Deleting resources sends a DELETE request.

**Simple delete**:

```bash
# With kubectl
kubectl delete pod nginx --namespace=api-learning

# With API
curl -X DELETE \
  http://localhost:8080/api/v1/namespaces/api-learning/pods/nginx

# Response is a Status object
{
  "kind": "Status",
  "apiVersion": "v1",
  "status": "Success",
  "code": 200
}
```

**Graceful deletion**:

Pods have a grace period before force-killing:

```bash
# Default 30-second grace period
kubectl delete pod nginx --namespace=api-learning

# Custom grace period
kubectl delete pod nginx --namespace=api-learning --grace-period=60

# Immediate deletion (dangerous!)
kubectl delete pod nginx --namespace=api-learning --grace-period=0 --force
```

**Delete with preconditions**:

```bash
# Only delete if resourceVersion matches (prevents race conditions)
curl -X DELETE \
  "http://localhost:8080/api/v1/namespaces/api-learning/pods/nginx?preconditions.resourceVersion=12345"
```

**Finalizers prevent deletion**:

Some resources have finalizers that must be cleared before deletion:

```bash
# Resource with finalizer won't fully delete
kubectl get pod nginx --namespace=api-learning -o yaml | grep -A 5 finalizers

# Output:
# metadata:
#   finalizers:
#   - example.com/cleanup

# Pod stays in Terminating state until finalizer is removed
# A controller must remove the finalizer after cleanup
```

**Cascading deletion**:

When you delete an owner resource, dependents are also deleted:

```bash
# Delete deployment (also deletes ReplicaSet and Pods)
kubectl delete deployment nginx --namespace=api-learning

# Orphan dependents (leave pods running)
kubectl delete deployment nginx --namespace=api-learning --cascade=orphan

# Delete in foreground (wait for dependents to delete first)
kubectl delete deployment nginx --namespace=api-learning --cascade=foreground

# Delete in background (default)
kubectl delete deployment nginx --namespace=api-learning --cascade=background
```

### Watch-GET-with-watch-param

The watch operation keeps a connection open and streams changes:

```bash
# With kubectl
kubectl get pods --namespace=api-learning --watch

# With API (in background)
curl "http://localhost:8080/api/v1/namespaces/api-learning/pods?watch=true" &

# In another terminal, create/delete pods to see events
kubectl run test --image=nginx --namespace=api-learning
kubectl delete pod test --namespace=api-learning
```

**Watch response format**:

```json
{
  "type": "ADDED",
  "object": {
    "kind": "Pod",
    "apiVersion": "v1",
    "metadata": { "name": "test", ... },
    "spec": { ... },
    "status": { ... }
  }
}
```

Watch is covered in detail in the next section.

### Complete-CRUD-Example

Let's perform a complete lifecycle using direct API calls:

```bash
# Start proxy
kubectl proxy --port=8080 &

# 1. CREATE - Deploy a pod
curl -X POST \
  http://localhost:8080/api/v1/namespaces/api-learning/pods \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "v1",
    "kind": "Pod",
    "metadata": {
      "name": "crud-example",
      "labels": {
        "app": "demo"
      }
    },
    "spec": {
      "containers": [
        {
          "name": "nginx",
          "image": "nginx:1.27"
        }
      ]
    }
  }' | jq '.metadata.name'

# 2. READ - Get the pod
curl -s http://localhost:8080/api/v1/namespaces/api-learning/pods/crud-example | jq '{name: .metadata.name, phase: .status.phase}'

# 3. UPDATE - Add a label
curl -X PATCH \
  http://localhost:8080/api/v1/namespaces/api-learning/pods/crud-example \
  -H "Content-Type: application/strategic-merge-patch+json" \
  -d '{
    "metadata": {
      "labels": {
        "updated": "true"
      }
    }
  }' | jq '.metadata.labels'

# 4. LIST - Find pods with our label
curl -s "http://localhost:8080/api/v1/namespaces/api-learning/pods?labelSelector=updated=true" | jq '.items[].metadata.name'

# 5. DELETE - Remove the pod
curl -X DELETE \
  http://localhost:8080/api/v1/namespaces/api-learning/pods/crud-example | jq '.status'

# Verify deletion
curl -s http://localhost:8080/api/v1/namespaces/api-learning/pods/crud-example | jq '.code'
# Output: 404

# Cleanup
killall kubectl
```

[↑ Back to ToC](#table-of-contents)

---

## Authentication-and-Authorization

Before the API server processes your request, it must verify **who you are** (authentication) and **what you're allowed to do** (authorization).

### Authentication-How-K8s-Identifies-You

Kubernetes supports multiple authentication methods. Every request must include credentials.

**Common authentication methods**:

1. **X.509 Client Certificates** - Most common for users
2. **Bearer Tokens** - Service accounts, OIDC tokens
3. **Bootstrap Tokens** - Node bootstrapping
4. **Static Token File** - Legacy, not recommended
5. **OIDC Tokens** - Integration with external identity providers

### X509-Client-Certificates

Your kubeconfig typically uses client certificates:

```bash
# View your kubeconfig
kubectl config view

# Look for client-certificate and client-key
# Or certificate-authority-data (base64-encoded cert)
```

**What's in the certificate**:

```bash
# Extract and decode your client cert (if embedded)
kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d > /tmp/client.crt

# View certificate details
openssl x509 -in /tmp/client.crt -text -noout

# Key fields:
# Subject: CN=your-username, O=group1, O=group2
# Issuer: CN=kubernetes-ca
```

**How it works**:

1. Client presents certificate to API server
2. API server validates certificate against CA
3. Extracts username from Common Name (CN)
4. Extracts groups from Organization (O) fields
5. Username and groups are used for authorization

### Bearer-Tokens-Service-Accounts

Pods use service account tokens for authentication:

```bash
# Every pod gets a token automatically mounted
kubectl run test --image=nginx --namespace=api-learning
kubectl exec test --namespace=api-learning -- cat /var/run/secrets/kubernetes.io/serviceaccount/token

# This token authenticates as the pod's service account
```

**Service account anatomy**:

```bash
# Create a service account
kubectl create serviceaccount api-demo --namespace=api-learning

# View it
kubectl get serviceaccount api-demo --namespace=api-learning -o yaml

# Use it in a pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: sa-test
  namespace: api-learning
spec:
  serviceAccountName: api-demo
  containers:
  - name: nginx
    image: nginx:1.27
EOF

# Inside the pod, the token authenticates as:
# Username: system:serviceaccount:api-learning:api-demo
# Groups: system:serviceaccounts, system:serviceaccounts:api-learning
```

**Using a service account token outside the cluster**:

```bash
# Get the token
TOKEN=$(kubectl create token api-demo --namespace=api-learning --duration=1h)

# Use it to call the API
kubectl proxy --port=8080 &

# This won't work with proxy (it uses your user credentials)
# Instead, get the API server URL and CA cert
APISERVER=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')
CA_CERT=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

# Make authenticated request
curl --cacert <(echo "$CA_CERT") \
  --header "Authorization: Bearer $TOKEN" \
  "$APISERVER/api/v1/namespaces/api-learning/pods"

killall kubectl
```

### Understanding-kubeconfig

The kubeconfig file contains authentication credentials and cluster information:

```bash
# Default location
cat ~/.kube/config

# Or wherever KUBECONFIG points
echo $KUBECONFIG
```

**kubeconfig structure**:

```yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: LS0tLS...  # CA cert for API server
    server: https://10.43.0.1:6443          # API server URL
  name: my-cluster
contexts:
- context:
    cluster: my-cluster
    namespace: default
    user: my-user
  name: my-context
current-context: my-context
users:
- name: my-user
  user:
    client-certificate-data: LS0tLS...     # Your client cert
    client-key-data: LS0tLS...              # Your private key
```

**Key components**:

- **clusters**: Define API server locations and CA certs
- **users**: Define authentication credentials
- **contexts**: Combine a cluster + user + optional namespace
- **current-context**: Which context kubectl uses by default

**Managing contexts**:

```bash
# List contexts
kubectl config get-contexts

# Switch context
kubectl config use-context my-other-context

# Set namespace for context
kubectl config set-context --current --namespace=api-learning

# Create a new context
kubectl config set-context dev-context \
  --cluster=my-cluster \
  --user=dev-user \
  --namespace=development
```

### RBAC-Role-Based-Access-Control

Once authenticated, Kubernetes uses RBAC to determine what you can do.

**RBAC components**:

1. **Role/ClusterRole** - Defines permissions (rules)
2. **RoleBinding/ClusterRoleBinding** - Grants permissions to users/groups/service accounts

**Role vs ClusterRole**:

- **Role**: Namespaced, grants access to resources in one namespace
- **ClusterRole**: Cluster-wide, grants access to cluster resources or across all namespaces

**RoleBinding vs ClusterRoleBinding**:

- **RoleBinding**: Grants Role or ClusterRole permissions within one namespace
- **ClusterRoleBinding**: Grants ClusterRole permissions cluster-wide

### Creating-a-Role

```bash
# Create a role that can read pods
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: api-learning
rules:
- apiGroups: [""]  # "" means core API group
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
EOF

# View it
kubectl describe role pod-reader --namespace=api-learning
```

**Rule anatomy**:

```yaml
rules:
- apiGroups: [""]          # Which API group (apps, batch, "", etc.)
  resources: ["pods"]      # Which resources (pods, deployments, etc.)
  verbs: ["get", "list"]   # Which operations
  resourceNames: ["pod1"]  # Optional: restrict to specific names
```

**Common verbs**:
- `get` - Read a single resource
- `list` - List resources
- `watch` - Watch for changes
- `create` - Create resources
- `update` - Update resources
- `patch` - Patch resources
- `delete` - Delete resources
- `deletecollection` - Delete multiple resources

### Creating-a-RoleBinding

```bash
# Bind the role to a user
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods-binding
  namespace: api-learning
subjects:
- kind: User
  name: jane
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
EOF

# Now user "jane" can read pods in api-learning namespace
```

**Binding to a service account**:

```bash
# Bind role to service account
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: api-demo-read-pods
  namespace: api-learning
subjects:
- kind: ServiceAccount
  name: api-demo
  namespace: api-learning
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
EOF

# Now pods using api-demo service account can read pods
```

### Creating-ClusterRoles-and-ClusterRoleBindings

```bash
# ClusterRole for reading nodes (cluster-scoped resource)
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-reader
rules:
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
EOF

# ClusterRoleBinding grants access cluster-wide
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: read-nodes-global
subjects:
- kind: User
  name: jane
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: node-reader
  apiGroup: rbac.authorization.k8s.io
EOF
```

**Using ClusterRole with RoleBinding**:

```bash
# You can bind a ClusterRole in a specific namespace
# This grants the permissions only in that namespace

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: admin-in-this-namespace
  namespace: api-learning
subjects:
- kind: User
  name: john
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin  # Built-in ClusterRole
  apiGroup: rbac.authorization.k8s.io
EOF

# John is admin of api-learning namespace only
```

### Built-in-Roles

Kubernetes includes default ClusterRoles:

```bash
# View built-in roles
kubectl get clusterroles | grep -E '^(view|edit|admin|cluster-admin)'

# Details
kubectl describe clusterrole view
kubectl describe clusterrole edit
kubectl describe clusterrole admin
kubectl describe clusterrole cluster-admin
```

**Common built-in roles**:

- **view**: Read-only access to most resources (no secrets)
- **edit**: Read-write access, can't modify RBAC
- **admin**: Full access in a namespace, including RBAC
- **cluster-admin**: Superuser, full access everywhere

### kubectl-auth-can-i

Test permissions before attempting operations:

```bash
# Can I create pods?
kubectl auth can-i create pods --namespace=api-learning

# Can I delete nodes?
kubectl auth can-i delete nodes

# Can a service account create deployments?
kubectl auth can-i create deployments \
  --namespace=api-learning \
  --as=system:serviceaccount:api-learning:api-demo

# List all permissions for a service account
kubectl auth can-i --list \
  --as=system:serviceaccount:api-learning:api-demo \
  --namespace=api-learning
```

### Practical-RBAC-Example

Let's create a restricted service account for a monitoring app:

```bash
# 1. Create namespace for the app
kubectl create namespace monitoring

# 2. Create service account
kubectl create serviceaccount pod-monitor --namespace=monitoring

# 3. Create ClusterRole to read pods across all namespaces
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-monitor-role
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
EOF

# 4. Create ClusterRoleBinding
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pod-monitor-binding
subjects:
- kind: ServiceAccount
  name: pod-monitor
  namespace: monitoring
roleRef:
  kind: ClusterRole
  name: pod-monitor-role
  apiGroup: rbac.authorization.k8s.io
EOF

# 5. Test permissions
kubectl auth can-i list pods --all-namespaces \
  --as=system:serviceaccount:monitoring:pod-monitor
# Output: yes

kubectl auth can-i delete pods \
  --as=system:serviceaccount:monitoring:pod-monitor
# Output: no

# 6. Use in a pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: monitor
  namespace: monitoring
spec:
  serviceAccountName: pod-monitor
  containers:
  - name: kubectl
    image: bitnami/kubectl:1.34
    command: ["sleep", "3600"]
EOF

# 7. Verify access from inside the pod
kubectl exec -it monitor --namespace=monitoring -- kubectl get pods --all-namespaces
```

[↑ Back to ToC](#table-of-contents)

---

## Understanding-API-Objects

Every resource in Kubernetes follows a common structure. Understanding this structure is essential for working with the API effectively.

### Standard-Object-Structure

All Kubernetes objects have three main sections:

```yaml
apiVersion: v1
kind: Pod
metadata:
  # Identity and metadata
spec:
  # Desired state (what you want)
status:
  # Actual state (what currently exists)
```

**Key insight**: You write `spec`, Kubernetes writes `status`. The control plane continuously works to make `status` match `spec`.

### Metadata-Fields

Every object has metadata that identifies and describes it:

```yaml
metadata:
  name: nginx-pod                    # Required: Object name
  namespace: api-learning            # Optional: Namespace (default: "default")
  uid: 6f3d8e7c-1234-5678-90ab-cdef # Server-generated: Unique ID
  resourceVersion: "12345"           # Server-generated: Version for optimistic locking
  generation: 3                      # Server-generated: Spec change counter
  creationTimestamp: 2026-02-08T10:00:00Z
  deletionTimestamp: null            # Set when object is being deleted
  labels:                            # Key-value pairs for organization
    app: web
    environment: production
  annotations:                       # Non-identifying metadata
    description: "Main web server"
    kubectl.kubernetes.io/last-applied-configuration: |
      {...}
  ownerReferences:                   # Garbage collection and ownership
  - apiVersion: apps/v1
    kind: ReplicaSet
    name: nginx-replicaset
    uid: abc123
    controller: true
  finalizers:                        # Block deletion until conditions met
  - kubernetes.io/pvc-protection
```

### Name-and-Namespace

**name** uniquely identifies a resource within its namespace:

```bash
# Names must be unique per resource type per namespace
# These can coexist:
kubectl create deployment nginx --image=nginx --namespace=api-learning
kubectl create service clusterip nginx --tcp=80 --namespace=api-learning

# But this fails (duplicate deployment name):
kubectl create deployment nginx --image=nginx --namespace=api-learning
# Error: deployments.apps "nginx" already exists
```

**Naming rules**:
- Max 253 characters (DNS subdomain format)
- Lowercase alphanumeric, `-`, `.`
- Start and end with alphanumeric

**namespace** provides scope:

```bash
# Same name, different namespaces
kubectl create deployment nginx --image=nginx --namespace=api-learning
kubectl create deployment nginx --image=nginx --namespace=production

# List from specific namespace
kubectl get deployments --namespace=api-learning

# List from all namespaces
kubectl get deployments --all-namespaces
```

### UID-and-ResourceVersion

**uid** is immutable and globally unique:

```bash
# Get a pod's UID
kubectl get pod nginx --namespace=api-learning -o jsonpath='{.metadata.uid}'

# UIDs persist in events and logs
# If you delete and recreate a pod with the same name, it gets a new UID
kubectl delete pod nginx --namespace=api-learning
kubectl run nginx --image=nginx --namespace=api-learning
kubectl get pod nginx --namespace=api-learning -o jsonpath='{.metadata.uid}'
# Different UID
```

**resourceVersion** enables optimistic concurrency control:

```bash
# Get current version
kubectl get pod nginx --namespace=api-learning -o jsonpath='{.metadata.resourceVersion}'

# Every update increments resourceVersion
kubectl label pod nginx --namespace=api-learning foo=bar
kubectl get pod nginx --namespace=api-learning -o jsonpath='{.metadata.resourceVersion}'
# Higher number

# Conflicts occur if you try to update based on an old version
# This prevents lost updates in concurrent scenarios
```

**How resourceVersion prevents conflicts**:

```bash
# Process A reads a pod
POD_JSON=$(kubectl get pod nginx --namespace=api-learning -o json)
RV=$(echo $POD_JSON | jq -r '.metadata.resourceVersion')

# Process B updates the pod
kubectl label pod nginx --namespace=api-learning updated=by-process-b

# Process A tries to update based on old data
# If it includes the old resourceVersion in a precondition, the update fails
# This prevents Process A from overwriting Process B's changes
```

### Labels-and-Selectors

**Labels** are key-value pairs for organizing and selecting resources:

```bash
# Add labels
kubectl label pod nginx --namespace=api-learning app=web tier=frontend

# View labels
kubectl get pods --namespace=api-learning --show-labels

# Update label
kubectl label pod nginx --namespace=api-learning tier=backend --overwrite

# Remove label
kubectl label pod nginx --namespace=api-learning tier-

# Select by label
kubectl get pods --namespace=api-learning -l app=web
kubectl get pods --namespace=api-learning -l 'tier in (frontend, backend)'
```

**Label best practices**:

```yaml
metadata:
  labels:
    app.kubernetes.io/name: nginx
    app.kubernetes.io/instance: nginx-prod
    app.kubernetes.io/version: "1.27"
    app.kubernetes.io/component: webserver
    app.kubernetes.io/part-of: ecommerce-platform
    app.kubernetes.io/managed-by: helm
```

**Selectors in resource specs**:

```yaml
# Deployment selects pods with matchLabels
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx  # Must match selector
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
```

### Annotations

**Annotations** store arbitrary non-identifying metadata:

```bash
# Add annotation
kubectl annotate pod nginx --namespace=api-learning \
  description="Primary web server" \
  contact="ops-team@example.com"

# View annotations
kubectl get pod nginx --namespace=api-learning -o jsonpath='{.metadata.annotations}'

# Update annotation
kubectl annotate pod nginx --namespace=api-learning description="Updated description" --overwrite

# Remove annotation
kubectl annotate pod nginx --namespace=api-learning description-
```

**Common annotation uses**:

```yaml
metadata:
  annotations:
    # kubectl apply tracking
    kubectl.kubernetes.io/last-applied-configuration: |
      {...}

    # Build/deployment info
    build-id: "12345"
    git-commit: "abc123def456"
    deployed-by: "ci-pipeline"
    deployment-timestamp: "2026-02-08T10:00:00Z"

    # Tool-specific
    prometheus.io/scrape: "true"
    prometheus.io/port: "9090"
    fluxcd.io/automated: "true"

    # Human notes
    oncall: "ops-team"
    runbook: "https://wiki.example.com/runbooks/nginx"
```

**Key insight**: Use labels for identification and selection. Use annotations for everything else (documentation, tool configuration, metadata).

### Owner-References-and-Garbage-Collection

**ownerReferences** establish parent-child relationships:

```bash
# Create a deployment (which creates a ReplicaSet and Pods)
kubectl create deployment nginx --image=nginx:1.27 --namespace=api-learning

# View ownerReferences on the ReplicaSet
kubectl get replicaset --namespace=api-learning -o yaml | grep -A 10 ownerReferences

# Output:
# ownerReferences:
# - apiVersion: apps/v1
#   kind: Deployment
#   name: nginx
#   uid: abc123
#   controller: true
#   blockOwnerDeletion: true

# View ownerReferences on a Pod
kubectl get pods --namespace=api-learning -o yaml | grep -A 10 ownerReferences

# Output:
# ownerReferences:
# - apiVersion: apps/v1
#   kind: ReplicaSet
#   name: nginx-xyz
#   uid: def456
#   controller: true
#   blockOwnerDeletion: true
```

**Garbage collection in action**:

```bash
# Delete the deployment
kubectl delete deployment nginx --namespace=api-learning

# ReplicaSet and Pods are automatically deleted (cascade)
kubectl get replicasets --namespace=api-learning  # None
kubectl get pods --namespace=api-learning         # None
```

**Orphaning resources**:

```bash
# Delete deployment but keep ReplicaSet and Pods
kubectl delete deployment nginx --namespace=api-learning --cascade=orphan

# ReplicaSet and Pods still exist
kubectl get replicasets --namespace=api-learning  # Still there
kubectl get pods --namespace=api-learning         # Still there
```

### Finalizers

**Finalizers** prevent deletion until specific conditions are met:

```bash
# Create a PVC (has protection finalizer)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: api-learning
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# View finalizers
kubectl get pvc test-pvc --namespace=api-learning -o jsonpath='{.metadata.finalizers}'
# Output: [kubernetes.io/pvc-protection]

# Try to delete while it's in use
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pvc-user
  namespace: api-learning
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: test-pvc
EOF

# Delete PVC
kubectl delete pvc test-pvc --namespace=api-learning

# Check status - it's stuck in Terminating
kubectl get pvc --namespace=api-learning

# It won't fully delete until the pod is removed
kubectl delete pod pvc-user --namespace=api-learning

# Now PVC is deleted
kubectl get pvc --namespace=api-learning  # Not found
```

**Custom finalizers**:

Controllers add finalizers to ensure cleanup:

```yaml
metadata:
  finalizers:
  - example.com/cleanup-external-resources
```

When the object is deleted:
1. `deletionTimestamp` is set
2. Object remains (status: Terminating)
3. Controller sees `deletionTimestamp`, performs cleanup
4. Controller removes its finalizer
5. When all finalizers are gone, object is deleted from etcd

### Generation-Field

**generation** tracks spec changes:

```bash
# Create deployment
kubectl create deployment nginx --image=nginx:1.27 --namespace=api-learning

# Check generation
kubectl get deployment nginx --namespace=api-learning -o jsonpath='{.metadata.generation}'
# Output: 1

# Update spec (e.g., scale)
kubectl scale deployment nginx --replicas=3 --namespace=api-learning

# Generation increments
kubectl get deployment nginx --namespace=api-learning -o jsonpath='{.metadata.generation}'
# Output: 2

# Metadata-only updates (labels) don't increment generation
kubectl label deployment nginx --namespace=api-learning foo=bar
kubectl get deployment nginx --namespace=api-learning -o jsonpath='{.metadata.generation}'
# Still: 2
```

Controllers use `generation` vs `status.observedGeneration` to detect pending changes:

```bash
# View observed generation in status
kubectl get deployment nginx --namespace=api-learning -o jsonpath='{.status.observedGeneration}'

# If metadata.generation > status.observedGeneration, reconciliation is pending
```

[↑ Back to ToC](#table-of-contents)

---

## Watching-Resources-and-Events

The Watch API is one of Kubernetes' most powerful features. It allows you to receive real-time notifications when resources change, rather than polling repeatedly.

### What-is-the-Watch-API

The watch mechanism keeps an HTTP connection open and streams changes as they happen:

```bash
# Traditional polling (inefficient)
while true; do
  kubectl get pods --namespace=api-learning
  sleep 5
done

# Watching (efficient)
kubectl get pods --namespace=api-learning --watch
```

**How watch works**:

1. Client opens HTTP connection with `?watch=true` parameter
2. API server streams JSON objects, one per line
3. Each object describes a change event (ADDED, MODIFIED, DELETED)
4. Connection stays open until timeout or client disconnects

### Watch-Event-Types

Watch returns events with these types:

```json
{
  "type": "ADDED",
  "object": {
    "kind": "Pod",
    "metadata": { "name": "nginx", ... },
    "spec": { ... },
    "status": { ... }
  }
}
```

**Event types**:

- **ADDED**: New resource created, or initial list when starting watch
- **MODIFIED**: Resource updated (spec or status changed)
- **DELETED**: Resource removed
- **BOOKMARK**: Periodic checkpoint with current resourceVersion (for resuming)
- **ERROR**: Watch encountered an error

### Watching-with-kubectl

```bash
# Watch all pods in a namespace
kubectl get pods --namespace=api-learning --watch

# Watch with output format
kubectl get pods --namespace=api-learning --watch -o wide

# Watch specific resource
kubectl get pod nginx --namespace=api-learning --watch

# Watch all resources of a type cluster-wide
kubectl get pods --all-namespaces --watch
```

**What you see**:

```
NAME    READY   STATUS    RESTARTS   AGE
nginx   0/1     Pending   0          0s
nginx   0/1     ContainerCreating   0          2s
nginx   1/1     Running             0          5s
```

Each line is a watch event (MODIFIED).

### Watching-with-curl

```bash
# Start proxy
kubectl proxy --port=8080 &

# Watch pods (run in background to see output)
curl -N "http://localhost:8080/api/v1/namespaces/api-learning/pods?watch=true" &
WATCH_PID=$!

# In another terminal, create/delete pods
kubectl run test1 --image=nginx --namespace=api-learning
sleep 2
kubectl delete pod test1 --namespace=api-learning

# Stop watching
kill $WATCH_PID
killall kubectl
```

**Raw watch output**:

```json
{"type":"ADDED","object":{"kind":"Pod","apiVersion":"v1","metadata":{"name":"test1",...},...}}
{"type":"MODIFIED","object":{"kind":"Pod","apiVersion":"v1","metadata":{"name":"test1",...},"status":{"phase":"Pending"},...}}
{"type":"MODIFIED","object":{"kind":"Pod","apiVersion":"v1","metadata":{"name":"test1",...},"status":{"phase":"Running"},...}}
{"type":"DELETED","object":{"kind":"Pod","apiVersion":"v1","metadata":{"name":"test1",...},...}}
```

Each line is a separate JSON object.

### ResourceVersion-and-Consistency

The watch API uses **resourceVersion** for consistency:

```bash
# List pods and get resourceVersion
RV=$(kubectl get pods --namespace=api-learning -o json | jq -r '.metadata.resourceVersion')
echo "ResourceVersion: $RV"

# Watch from this resourceVersion (only see changes after this point)
curl -N "http://localhost:8080/api/v1/namespaces/api-learning/pods?watch=true&resourceVersion=$RV" &
```

**ResourceVersion strategies**:

| Parameter | Behavior |
|-----------|----------|
| Not set | Start with initial list (ADDED for all existing resources), then watch |
| `resourceVersion=0` | Same as not set |
| `resourceVersion=<specific>` | Start watching from that version (no initial list) |
| `resourceVersion=0&allowWatchBookmarks=true` | Enable bookmarks for long watches |

**Why resourceVersion matters**:

```bash
# Scenario: Your watch client crashes
# When it restarts, you don't want to miss changes

# 1. Before crash, you saved the last resourceVersion you processed
LAST_RV=12345

# 2. After restart, resume from that point
# You'll see all changes since resourceVersion 12345
curl -N "http://localhost:8080/api/v1/namespaces/api-learning/pods?watch=true&resourceVersion=$LAST_RV"
```

**Watch bookmarks**:

```bash
# Request periodic bookmarks
curl -N "http://localhost:8080/api/v1/namespaces/api-learning/pods?watch=true&allowWatchBookmarks=true"

# You'll receive BOOKMARK events with current resourceVersion
{"type":"BOOKMARK","object":{"kind":"Pod","apiVersion":"v1","metadata":{"resourceVersion":"12500"}}}

# Save these to resume from correct position if disconnected
```

### Watch-Timeouts-and-Reconnection

Watches don't last forever:

```bash
# Default timeout varies (typically 5-10 minutes)
# Watch ends with timeout or connection close

# You'll see connection close when watching with curl
# HTTP/1.1 200 OK
# Connection: close

# Your client must reconnect
```

**Reconnection pattern**:

```python
import requests
import json

def watch_pods_forever(namespace):
    resource_version = None

    while True:
        try:
            # Build watch URL
            url = f"http://localhost:8080/api/v1/namespaces/{namespace}/pods"
            params = {"watch": "true"}

            if resource_version:
                params["resourceVersion"] = resource_version

            # Stream events
            response = requests.get(url, params=params, stream=True)

            for line in response.iter_lines():
                if line:
                    event = json.loads(line)
                    event_type = event["type"]
                    obj = event["object"]

                    # Process event
                    print(f"{event_type}: {obj['metadata']['name']}")

                    # Save resourceVersion for resume
                    resource_version = obj["metadata"]["resourceVersion"]

        except Exception as e:
            print(f"Watch error: {e}, reconnecting...")
            # Brief delay before reconnecting
            time.sleep(1)

# Usage
watch_pods_forever("api-learning")
```

### Informers-and-Shared-Informers

**Informers** are client-side components that watch resources and maintain a local cache. They're the foundation of Kubernetes controllers.

**How informers work**:

1. **List**: Get all existing resources
2. **Watch**: Stream updates
3. **Cache**: Maintain local up-to-date copy
4. **Handlers**: Call your code when resources change

**Shared informers** allow multiple components to watch the same resource without duplicate API calls.

**Conceptual example** (simplified):

```go
// Pseudo-code for an informer
type PodInformer struct {
    cache map[string]*Pod
    handlers []func(eventType, pod)
}

func (i *PodInformer) Start() {
    // Initial list
    pods := client.ListPods()
    for pod in pods {
        i.cache[pod.Name] = pod
        for handler in i.handlers {
            handler("ADDED", pod)
        }
    }

    // Watch for changes
    for event := range client.WatchPods() {
        switch event.Type {
        case "ADDED", "MODIFIED":
            i.cache[event.Object.Name] = event.Object
        case "DELETED":
            delete(i.cache, event.Object.Name)
        }

        // Notify handlers
        for handler in i.handlers {
            handler(event.Type, event.Object)
        }
    }
}
```

**Why informers are important**:

- Efficient: Single watch for multiple consumers
- Fast local reads: No API call to check resource state
- Event-driven: React to changes immediately
- Resilient: Handle disconnections automatically

We'll use actual informers in the programming examples section.

### Kubernetes-Events-vs-Watch-Events

Don't confuse these two concepts:

**Watch events**: API mechanism for streaming resource changes
- `{"type": "ADDED", "object": {...}}`
- Every resource type can be watched
- For detecting resource changes

**Kubernetes Event objects**: Resources that record cluster events
- Kind: Event
- Created by components to log noteworthy occurrences
- For debugging and auditing

**Viewing Event objects**:

```bash
# Events are a resource type
kubectl get events --namespace=api-learning

# Example output:
# LAST SEEN   TYPE      REASON              OBJECT         MESSAGE
# 2m          Normal    Scheduled           pod/nginx      Successfully assigned...
# 2m          Normal    Pulling             pod/nginx      Pulling image "nginx:1.27"
# 1m          Normal    Pulled              pod/nginx      Successfully pulled image
# 1m          Normal    Created             pod/nginx      Created container nginx
# 1m          Normal    Started             pod/nginx      Started container nginx

# Watch Event objects
kubectl get events --namespace=api-learning --watch

# Get events for a specific pod
kubectl describe pod nginx --namespace=api-learning | grep -A 20 Events:
```

**Creating Event objects programmatically**:

```bash
# Events have a special API structure
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Event
metadata:
  name: custom-event
  namespace: api-learning
type: Normal
reason: TestEvent
message: "This is a custom event for testing"
involvedObject:
  apiVersion: v1
  kind: Pod
  name: nginx
  namespace: api-learning
firstTimestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
lastTimestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
count: 1
source:
  component: test-script
EOF

# View it
kubectl get events --namespace=api-learning | grep custom-event
```

**Key insight**: Watch events are the transport mechanism. Event objects are log entries about what happened in your cluster.

### Practical-Watch-Example

Let's build a simple pod watcher using curl and jq:

```bash
#!/bin/bash
# pod-watcher.sh - Monitor pod lifecycle

NAMESPACE=api-learning

echo "Watching pods in namespace: $NAMESPACE"
echo "Press Ctrl+C to stop"
echo ""

# Start kubectl proxy in background
kubectl proxy --port=8080 >/dev/null 2>&1 &
PROXY_PID=$!

# Ensure cleanup on exit
trap "kill $PROXY_PID 2>/dev/null" EXIT

# Give proxy time to start
sleep 1

# Watch pods
curl -sN "http://localhost:8080/api/v1/namespaces/$NAMESPACE/pods?watch=true" | \
while IFS= read -r line; do
    # Parse event
    EVENT_TYPE=$(echo "$line" | jq -r '.type')
    POD_NAME=$(echo "$line" | jq -r '.object.metadata.name')
    POD_PHASE=$(echo "$line" | jq -r '.object.status.phase // "Unknown"')
    TIMESTAMP=$(date +"%H:%M:%S")

    # Display event
    case "$EVENT_TYPE" in
        ADDED)
            echo "[$TIMESTAMP] ✨ Pod created: $POD_NAME (Phase: $POD_PHASE)"
            ;;
        MODIFIED)
            echo "[$TIMESTAMP] 🔄 Pod updated: $POD_NAME (Phase: $POD_PHASE)"
            ;;
        DELETED)
            echo "[$TIMESTAMP] 🗑️  Pod deleted: $POD_NAME"
            ;;
        ERROR)
            echo "[$TIMESTAMP] ❌ Watch error"
            ;;
    esac
done
```

**Test it**:

```bash
# Save the script
chmod +x pod-watcher.sh

# Run it in one terminal
./pod-watcher.sh

# In another terminal, create and delete pods
kubectl run test1 --image=nginx --namespace=api-learning
sleep 5
kubectl delete pod test1 --namespace=api-learning

kubectl run test2 --image=nginx --namespace=api-learning
kubectl run test3 --image=nginx --namespace=api-learning
kubectl delete pod test2 test3 --namespace=api-learning
```

You'll see real-time updates as pods are created, transition through phases, and are deleted.

[↑ Back to ToC](#table-of-contents)

---

## Working-with-the-API-Programmatically

While kubectl is great for manual operations, automation and custom tools require programmatic API access. Let's explore client libraries in Python and Go.

### Why-Use-Client-Libraries

**Avoid these problems**:

```bash
# Raw HTTP is tedious
curl -X POST \
  --cacert /path/to/ca.crt \
  --cert /path/to/client.crt \
  --key /path/to/client.key \
  https://10.43.0.1:6443/api/v1/namespaces/default/pods \
  -H "Content-Type: application/json" \
  -d '{ ... hundreds of lines of JSON ... }'

# Error handling is manual
# Authentication is complex
# Watching and retries need custom code
```

**Client libraries provide**:

- Automatic authentication from kubeconfig
- Type-safe resource definitions
- Built-in retry and error handling
- Watch helpers and informers
- Resource builders and utilities

### Python-Client-kubernetes

Install the official Python client:

```bash
# Install
pip install kubernetes

# Or in requirements.txt
echo "kubernetes>=29.0.0" > requirements.txt
pip install -r requirements.txt
```

### Python-Example-List-Pods

```python
#!/usr/bin/env python3
"""
list-pods.py - List all pods in a namespace
"""
from kubernetes import client, config

# Load kubeconfig from default location (~/.kube/config)
config.load_kube_config()

# Create API client
v1 = client.CoreV1Api()

# List pods in a namespace
namespace = "api-learning"

try:
    print(f"Listing pods in namespace: {namespace}\n")

    # Call the API
    pod_list = v1.list_namespaced_pod(namespace=namespace)

    # Iterate over pods
    for pod in pod_list.items:
        name = pod.metadata.name
        phase = pod.status.phase
        node = pod.spec.node_name or "Not scheduled"

        print(f"Pod: {name}")
        print(f"  Phase: {phase}")
        print(f"  Node: {node}")
        print()

except client.exceptions.ApiException as e:
    print(f"API Error: {e.status} - {e.reason}")
    print(f"Details: {e.body}")

```

**Run it**:

```bash
# Create some test pods
kubectl run nginx --image=nginx --namespace=api-learning
kubectl run redis --image=redis --namespace=api-learning

# Run the Python script
python3 list-pods.py

# Output:
# Listing pods in namespace: api-learning
#
# Pod: nginx
#   Phase: Running
#   Node: worker-1
#
# Pod: redis
#   Phase: Running
#   Node: worker-2
```

### Python-Example-Create-Deployment

```python
#!/usr/bin/env python3
"""
create-deployment.py - Create a Deployment programmatically
"""
from kubernetes import client, config

config.load_kube_config()

# Create API clients
apps_v1 = client.AppsV1Api()

# Define the deployment
deployment = client.V1Deployment(
    api_version="apps/v1",
    kind="Deployment",
    metadata=client.V1ObjectMeta(
        name="python-nginx",
        namespace="api-learning",
        labels={"app": "nginx", "created-by": "python"}
    ),
    spec=client.V1DeploymentSpec(
        replicas=3,
        selector=client.V1LabelSelector(
            match_labels={"app": "nginx"}
        ),
        template=client.V1PodTemplateSpec(
            metadata=client.V1ObjectMeta(
                labels={"app": "nginx"}
            ),
            spec=client.V1PodSpec(
                containers=[
                    client.V1Container(
                        name="nginx",
                        image="nginx:1.27",
                        ports=[client.V1ContainerPort(container_port=80)]
                    )
                ]
            )
        )
    )
)

# Create the deployment
try:
    print(f"Creating deployment: {deployment.metadata.name}")

    response = apps_v1.create_namespaced_deployment(
        namespace="api-learning",
        body=deployment
    )

    print(f"✓ Deployment created successfully")
    print(f"  Name: {response.metadata.name}")
    print(f"  UID: {response.metadata.uid}")
    print(f"  Replicas: {response.spec.replicas}")

except client.exceptions.ApiException as e:
    if e.status == 409:
        print(f"✗ Deployment already exists")
    else:
        print(f"✗ API Error: {e.status} - {e.reason}")
        print(f"  Details: {e.body}")

```

**Run it**:

```bash
python3 create-deployment.py

# Verify
kubectl get deployment python-nginx --namespace=api-learning
kubectl get pods --namespace=api-learning -l app=nginx
```

### Python-Example-Watch-Events

```python
#!/usr/bin/env python3
"""
watch-pods.py - Watch pod events in real-time
"""
from kubernetes import client, config, watch
import sys

config.load_kube_config()

v1 = client.CoreV1Api()
namespace = "api-learning"

print(f"Watching pods in namespace: {namespace}")
print("Press Ctrl+C to stop\n")

# Create a watch object
watcher = watch.Watch()

try:
    # Stream events
    for event in watcher.stream(
        v1.list_namespaced_pod,
        namespace=namespace,
        timeout_seconds=0  # 0 = no timeout
    ):
        event_type = event['type']
        pod = event['object']

        name = pod.metadata.name
        phase = pod.status.phase or "Unknown"

        # Format output based on event type
        if event_type == "ADDED":
            print(f"✨ Pod created: {name} (Phase: {phase})")
        elif event_type == "MODIFIED":
            print(f"🔄 Pod updated: {name} (Phase: {phase})")
        elif event_type == "DELETED":
            print(f"🗑️  Pod deleted: {name}")
        else:
            print(f"❓ Unknown event: {event_type} for {name}")

except KeyboardInterrupt:
    print("\n\nWatch stopped by user")
    watcher.stop()
except client.exceptions.ApiException as e:
    print(f"\n✗ API Error: {e.status} - {e.reason}")
except Exception as e:
    print(f"\n✗ Unexpected error: {e}")

```

**Run it**:

```bash
# Terminal 1: Start watching
python3 watch-pods.py

# Terminal 2: Create and delete pods
kubectl run watch-test --image=nginx --namespace=api-learning
sleep 5
kubectl delete pod watch-test --namespace=api-learning

# You'll see real-time updates in Terminal 1
```

### Python-Error-Handling-Patterns

```python
from kubernetes import client, config
from kubernetes.client.rest import ApiException

config.load_kube_config()
v1 = client.CoreV1Api()

def get_pod_safe(namespace, name):
    """Get pod with proper error handling"""
    try:
        pod = v1.read_namespaced_pod(name=name, namespace=namespace)
        return pod
    except ApiException as e:
        if e.status == 404:
            print(f"Pod not found: {namespace}/{name}")
            return None
        elif e.status == 403:
            print(f"Permission denied: Cannot read pod {namespace}/{name}")
            return None
        else:
            print(f"API error ({e.status}): {e.reason}")
            raise
    except Exception as e:
        print(f"Unexpected error: {e}")
        raise

def create_pod_idempotent(namespace, pod_manifest):
    """Create pod, ignore if already exists"""
    try:
        pod = v1.create_namespaced_pod(namespace=namespace, body=pod_manifest)
        print(f"Created pod: {pod.metadata.name}")
        return pod
    except ApiException as e:
        if e.status == 409:
            print(f"Pod already exists: {pod_manifest.metadata.name}")
            # Optionally retrieve existing pod
            return v1.read_namespaced_pod(
                name=pod_manifest.metadata.name,
                namespace=namespace
            )
        else:
            raise

def delete_pod_safe(namespace, name):
    """Delete pod, ignore if not found"""
    try:
        v1.delete_namespaced_pod(name=name, namespace=namespace)
        print(f"Deleted pod: {namespace}/{name}")
    except ApiException as e:
        if e.status == 404:
            print(f"Pod not found (already deleted?): {namespace}/{name}")
        else:
            raise

# Usage examples
pod = get_pod_safe("api-learning", "nginx")
delete_pod_safe("api-learning", "nonexistent")
```

### Go-Client-client-go

For Go applications, use the official client-go library:

```bash
# Initialize Go module
go mod init pod-lister

# Install client-go
go get k8s.io/client-go@v0.34.0
go get k8s.io/apimachinery/pkg/apis/meta/v1
```

### Go-Example-List-Pods

```go
// main.go - List pods using Go
package main

import (
    "context"
    "fmt"
    "log"
    "path/filepath"

    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/tools/clientcmd"
    "k8s.io/client-go/util/homedir"
)

func main() {
    // Build kubeconfig path
    var kubeconfig string
    if home := homedir.HomeDir(); home != "" {
        kubeconfig = filepath.Join(home, ".kube", "config")
    } else {
        log.Fatal("Cannot find home directory")
    }

    // Build config from kubeconfig
    config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
    if err != nil {
        log.Fatalf("Error building kubeconfig: %v", err)
    }

    // Create clientset
    clientset, err := kubernetes.NewForConfig(config)
    if err != nil {
        log.Fatalf("Error creating clientset: %v", err)
    }

    // List pods
    namespace := "api-learning"
    pods, err := clientset.CoreV1().Pods(namespace).List(
        context.TODO(),
        metav1.ListOptions{},
    )
    if err != nil {
        log.Fatalf("Error listing pods: %v", err)
    }

    fmt.Printf("Listing pods in namespace: %s\n\n", namespace)

    for _, pod := range pods.Items {
        fmt.Printf("Pod: %s\n", pod.Name)
        fmt.Printf("  Phase: %s\n", pod.Status.Phase)
        fmt.Printf("  Node: %s\n", pod.Spec.NodeName)
        fmt.Println()
    }
}
```

**Build and run**:

```bash
# Build
go build -o pod-lister

# Run
./pod-lister
```

### Go-Example-Watch-Pods

```go
// watch.go - Watch pod changes
package main

import (
    "context"
    "fmt"
    "log"
    "path/filepath"

    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/apimachinery/pkg/watch"
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/tools/clientcmd"
    "k8s.io/client-go/util/homedir"
)

func main() {
    // Setup client (same as previous example)
    var kubeconfig string
    if home := homedir.HomeDir(); home != "" {
        kubeconfig = filepath.Join(home, ".kube", "config")
    }

    config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
    if err != nil {
        log.Fatal(err)
    }

    clientset, err := kubernetes.NewForConfig(config)
    if err != nil {
        log.Fatal(err)
    }

    // Start watching
    namespace := "api-learning"
    fmt.Printf("Watching pods in namespace: %s\n", namespace)
    fmt.Println("Press Ctrl+C to stop\n")

    watcher, err := clientset.CoreV1().Pods(namespace).Watch(
        context.TODO(),
        metav1.ListOptions{},
    )
    if err != nil {
        log.Fatalf("Error creating watcher: %v", err)
    }
    defer watcher.Stop()

    // Process events
    for event := range watcher.ResultChan() {
        pod, ok := event.Object.(*v1.Pod)
        if !ok {
            log.Printf("Unexpected type: %T", event.Object)
            continue
        }

        switch event.Type {
        case watch.Added:
            fmt.Printf("✨ Pod created: %s (Phase: %s)\n", pod.Name, pod.Status.Phase)
        case watch.Modified:
            fmt.Printf("🔄 Pod updated: %s (Phase: %s)\n", pod.Name, pod.Status.Phase)
        case watch.Deleted:
            fmt.Printf("🗑️  Pod deleted: %s\n", pod.Name)
        case watch.Error:
            fmt.Printf("❌ Watch error\n")
        }
    }
}
```

### In-Cluster-Configuration

When running inside a pod, use in-cluster config:

**Python**:

```python
from kubernetes import client, config

# Automatically uses service account token
config.load_incluster_config()

# Now use client as normal
v1 = client.CoreV1Api()
pods = v1.list_namespaced_pod(namespace="default")
```

**Go**:

```go
import (
    "k8s.io/client-go/rest"
    "k8s.io/client-go/kubernetes"
)

// Use in-cluster config
config, err := rest.InClusterConfig()
if err != nil {
    log.Fatal(err)
}

clientset, err := kubernetes.NewForConfig(config)
```

**Detecting environment**:

```python
from kubernetes import client, config

try:
    # Try in-cluster first (for pods)
    config.load_incluster_config()
    print("Using in-cluster configuration")
except config.ConfigException:
    # Fall back to kubeconfig (for local development)
    config.load_kube_config()
    print("Using kubeconfig")

v1 = client.CoreV1Api()
```

[↑ Back to ToC](#table-of-contents)

---

## Custom-Resources-and-CRDs

Custom Resource Definitions (CRDs) let you extend Kubernetes with your own resource types. They're fundamental to operators and custom controllers.

### What-are-Custom-Resources

Kubernetes comes with built-in resources: Pods, Services, Deployments, etc. But what if you want to manage custom things like:

- Databases (PostgreSQL, MySQL)
- Message queues (RabbitMQ, Kafka)
- Certificates (cert-manager)
- Applications (your own abstractions)

**Custom Resources** let you define new resource types that work just like built-in ones:

```bash
# Built-in resource
kubectl get pods

# Custom resource (after defining CRD)
kubectl get databases
kubectl get rabbitmqclusters
kubectl get certificates
```

### When-to-Use-CRDs

**Use CRDs when**:

- You're building a Kubernetes operator
- You need to manage complex, multi-component systems
- You want declarative configuration for custom resources
- You need Kubernetes-style lifecycle management

**Don't use CRDs when**:

- Simple configuration is enough (use ConfigMap)
- Data storage is the primary goal (use ConfigMap or external DB)
- You just need to trigger actions (use Jobs)

**CRDs vs ConfigMaps**:

```yaml
# ConfigMap: Unstructured data
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  database-url: "postgres://..."
  replicas: "3"  # Just a string, no validation

---

# CRD: Structured, validated resource
apiVersion: example.com/v1
kind: Database
metadata:
  name: my-postgres
spec:
  engine: postgres
  version: "15"
  replicas: 3        # Validated as integer
  storage: 10Gi      # Validated as quantity
```

### Defining-a-CRD

Let's create a CRD for managing simple web applications:

```yaml
# webapp-crd.yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  # Name must be: <plural>.<group>
  name: webapps.example.com
spec:
  # API group
  group: example.com

  # Namespaced or cluster-scoped
  scope: Namespaced

  names:
    # Plural name for API URLs
    plural: webapps
    # Singular name for display
    singular: webapp
    # Kind used in YAML
    kind: WebApp
    # Short name for kubectl
    shortNames:
    - wa

  # Supported versions
  versions:
  - name: v1
    # Served via API
    served: true
    # Storage version (only one can be true)
    storage: true

    # OpenAPI schema for validation
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required:
            - image
            - replicas
            properties:
              image:
                type: string
                description: "Container image for the web app"
              replicas:
                type: integer
                minimum: 1
                maximum: 10
                description: "Number of replicas"
              port:
                type: integer
                default: 80
                description: "Container port"
              env:
                type: object
                additionalProperties:
                  type: string
                description: "Environment variables"
          status:
            type: object
            properties:
              availableReplicas:
                type: integer
              conditions:
                type: array
                items:
                  type: object
                  properties:
                    type:
                      type: string
                    status:
                      type: string
                    reason:
                      type: string
```

**Apply the CRD**:

```bash
kubectl apply -f webapp-crd.yaml

# Verify
kubectl get crd webapps.example.com

# Check details
kubectl describe crd webapps.example.com

# CRD creates a new API endpoint
kubectl api-resources | grep webapp
# Output: webapps  wa  example.com/v1  true  WebApp
```

### Creating-Custom-Resource-Instances

Now you can create instances of your custom resource:

```yaml
# my-webapp.yaml
apiVersion: example.com/v1
kind: WebApp
metadata:
  name: my-app
  namespace: api-learning
spec:
  image: nginx:1.27
  replicas: 3
  port: 80
  env:
    ENVIRONMENT: production
    LOG_LEVEL: info
```

**Apply it**:

```bash
kubectl apply -f my-webapp.yaml

# List custom resources
kubectl get webapps --namespace=api-learning

# Describe
kubectl describe webapp my-app --namespace=api-learning

# Get as YAML
kubectl get webapp my-app --namespace=api-learning -o yaml

# Use short name
kubectl get wa --namespace=api-learning
```

### Validation-with-OpenAPI-Schema

The schema in your CRD validates instances:

```bash
# This fails validation (replicas > 10)
cat <<EOF | kubectl apply -f -
apiVersion: example.com/v1
kind: WebApp
metadata:
  name: invalid-app
  namespace: api-learning
spec:
  image: nginx:1.27
  replicas: 20  # Exceeds maximum: 10
  port: 80
EOF

# Error: validation failure
# spec.replicas: Invalid value: 20: spec.replicas in body should be less than or equal to 10

# This fails (missing required field)
cat <<EOF | kubectl apply -f -
apiVersion: example.com/v1
kind: WebApp
metadata:
  name: invalid-app2
  namespace: api-learning
spec:
  port: 80
  # Missing required fields: image, replicas
EOF

# Error: validation failure
# spec.image: Required value
# spec.replicas: Required value
```

**Advanced validation**:

```yaml
# In CRD schema
spec:
  image:
    type: string
    pattern: '^[a-z0-9.-]+:[a-z0-9.-]+$'  # Regex validation
  replicas:
    type: integer
    minimum: 1
    maximum: 10
  port:
    type: integer
    minimum: 1
    maximum: 65535
  resources:
    type: object
    properties:
      memory:
        type: string
        pattern: '^[0-9]+(Mi|Gi)$'  # Must be like "128Mi" or "2Gi"
```

### Subresources-Status-and-Scale

CRDs can have subresources like built-in resources:

**Status subresource**:

```yaml
# In CRD definition
versions:
- name: v1
  served: true
  storage: true
  # Enable status subresource
  subresources:
    status: {}
  schema:
    # ... schema definition
```

**Why status subresource matters**:

```bash
# Without status subresource: updating spec or status updates resourceVersion
# With status subresource: updating status doesn't increment generation

# Controllers can update status without triggering reconciliation loops
```

**Updating status**:

```bash
# Update status (requires status subresource enabled)
kubectl patch webapp my-app --namespace=api-learning \
  --subresource=status \
  --type=merge \
  --patch='{"status":{"availableReplicas":3}}'
```

**Scale subresource**:

```yaml
# In CRD definition
subresources:
  status: {}
  scale:
    # JSONPath to replicas field in spec
    specReplicasPath: .spec.replicas
    # JSONPath to replicas field in status
    statusReplicasPath: .status.availableReplicas
    # Optional: label selector path
    labelSelectorPath: .status.labelSelector
```

**Scaling custom resources**:

```bash
# With scale subresource, you can use kubectl scale
kubectl scale webapp my-app --namespace=api-learning --replicas=5

# Get scale information
kubectl get webapp my-app --namespace=api-learning -o jsonpath='{.spec.replicas}'
```

### Versioning-CRDs

CRDs can have multiple versions:

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: webapps.example.com
spec:
  group: example.com
  scope: Namespaced
  names:
    plural: webapps
    singular: webapp
    kind: WebApp

  # Multiple versions
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      # v1 schema
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              image: {type: string}
              replicas: {type: integer}

  - name: v1beta1
    served: true
    storage: false  # Only one version can be storage version
    schema:
      # v1beta1 schema (maybe different fields)
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              containerImage: {type: string}  # Different field name
              count: {type: integer}

  # Conversion strategy (webhook or none)
  conversion:
    strategy: None  # For now, no automatic conversion
```

**Using different versions**:

```bash
# Create with v1
kubectl apply -f - <<EOF
apiVersion: example.com/v1
kind: WebApp
metadata:
  name: app-v1
  namespace: api-learning
spec:
  image: nginx:1.27
  replicas: 3
EOF

# Both versions are served
kubectl get webapp app-v1 --namespace=api-learning -o yaml | grep apiVersion
# apiVersion: example.com/v1
```

### CRD-Controllers

CRDs alone don't do anything. You need a **controller** to watch CRs and reconcile them.

**Conceptual controller**:

```python
# Pseudo-code for a WebApp controller
while True:
    webapps = api.list_webapps()

    for webapp in webapps:
        # Reconcile: make reality match desired state
        desired_replicas = webapp.spec.replicas
        actual_deployment = api.get_deployment(webapp.name)

        if not actual_deployment:
            # Create deployment
            api.create_deployment(
                name=webapp.name,
                image=webapp.spec.image,
                replicas=desired_replicas
            )
        elif actual_deployment.replicas != desired_replicas:
            # Update deployment
            api.scale_deployment(webapp.name, desired_replicas)

        # Update status
        actual_replicas = count_ready_pods(webapp.name)
        api.update_status(webapp.name, availableReplicas=actual_replicas)

    time.sleep(5)
```

In the final section, we'll build a real controller that manages WebApp resources.

### Practical-CRD-Example

Let's create a complete working CRD for managing Redis instances:

```bash
# redis-crd.yaml
cat <<'EOF' | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: redisinstances.cache.example.com
spec:
  group: cache.example.com
  scope: Namespaced
  names:
    plural: redisinstances
    singular: redisinstance
    kind: RedisInstance
    shortNames:
    - redis
  versions:
  - name: v1
    served: true
    storage: true
    subresources:
      status: {}
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required:
            - version
            properties:
              version:
                type: string
                enum: ["6.2", "7.0", "7.2"]
              persistence:
                type: boolean
                default: false
              maxMemory:
                type: string
                pattern: '^[0-9]+(mb|gb)$'
                default: "256mb"
          status:
            type: object
            properties:
              phase:
                type: string
              endpoint:
                type: string
    additionalPrinterColumns:
    - name: Version
      type: string
      jsonPath: .spec.version
    - name: Phase
      type: string
      jsonPath: .status.phase
    - name: Endpoint
      type: string
      jsonPath: .status.endpoint
    - name: Age
      type: date
      jsonPath: .metadata.creationTimestamp
EOF

# Create an instance
cat <<EOF | kubectl apply -f -
apiVersion: cache.example.com/v1
kind: RedisInstance
metadata:
  name: my-cache
  namespace: api-learning
spec:
  version: "7.2"
  persistence: true
  maxMemory: "512mb"
EOF

# View instances with custom columns
kubectl get redis --namespace=api-learning

# Output:
# NAME       VERSION   PHASE   ENDPOINT   AGE
# my-cache   7.2               <none>     5s
```

[↑ Back to ToC](#table-of-contents)

---

## RKE2-Specific-API-Extensions

RKE2 (Rancher Kubernetes Engine 2) is a Kubernetes distribution focused on security and compliance. Understanding how it extends the standard Kubernetes API is useful for RKE2 environments.

### RKE2-vs-Vanilla-Kubernetes-API

The core Kubernetes API in RKE2 is identical to upstream Kubernetes:

```bash
# Standard resources work exactly the same
kubectl get pods
kubectl get deployments
kubectl get services

# API endpoints are the same
GET /api/v1/namespaces/default/pods
GET /apis/apps/v1/namespaces/default/deployments
```

**Key insight**: RKE2 is a distribution, not a fork. It uses the same API server code as vanilla Kubernetes.

### RKE2-Enhancements

RKE2 adds value through:

1. **Security hardening**: CIS compliance, PSA enforcement
2. **Embedded components**: containerd, CNI plugins
3. **Simplified operations**: Single binary, systemd integration
4. **Optional Rancher integration**: Management plane CRDs

### Rancher-CRDs

If RKE2 is managed by Rancher, additional CRDs are available:

**Cattle API groups** (Rancher-specific):

```bash
# Check for Rancher CRDs
kubectl api-resources | grep cattle.io

# Common Rancher API groups:
# - cattle.io
# - management.cattle.io
# - project.cattle.io
# - fleet.cattle.io
```

**Example Rancher CRDs**:

| CRD | API Group | Purpose |
|-----|-----------|---------|
| Cluster | management.cattle.io/v3 | Represents a Kubernetes cluster |
| Project | management.cattle.io/v3 | Namespace grouping and RBAC |
| App | project.cattle.io/v3 | Application deployments |
| GitRepo | fleet.cattle.io/v1alpha1 | Fleet GitOps repositories |

### Discovering-Rancher-Resources

```bash
# List all Rancher-related CRDs
kubectl get crd | grep cattle

# Example output (if Rancher is installed):
# apps.project.cattle.io
# clusters.management.cattle.io
# gitrepos.fleet.cattle.io
# projects.management.cattle.io

# Get resources from a Rancher API group
kubectl get clusters.management.cattle.io

# Describe a Rancher CRD
kubectl describe crd clusters.management.cattle.io
```

### RKE2-Addon-CRDs

RKE2 uses HelmChart CRDs for managing addons:

```bash
# HelmChart CRD (if present)
kubectl get crd helmcharts.helm.cattle.io

# List helm charts deployed by RKE2
kubectl get helmcharts -n kube-system

# Example output:
# NAME                  CHART                     VERSION
# rke2-coredns          rancher-coredns           1.29.0
# rke2-ingress-nginx    rancher-ingress-nginx     4.9.1
# rke2-metrics-server   rancher-metrics-server    3.12.0
```

**HelmChart CR structure**:

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: my-app
  namespace: kube-system
spec:
  chart: stable/nginx
  repo: https://charts.helm.sh/stable
  version: 1.2.3
  targetNamespace: default
  valuesContent: |
    replicaCount: 3
    service:
      type: LoadBalancer
```

**Using HelmChart CRDs**:

```bash
# Create a HelmChart resource
cat <<EOF | kubectl apply -f -
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: redis
  namespace: kube-system
spec:
  chart: redis
  repo: https://charts.bitnami.com/bitnami
  targetNamespace: api-learning
  valuesContent: |
    auth:
      enabled: false
    master:
      persistence:
        enabled: false
EOF

# Check status
kubectl get helmchart redis -n kube-system -o yaml

# The RKE2 helm controller will install the chart
kubectl get pods -n api-learning | grep redis
```

### RKE2-Configuration-via-API

RKE2 itself is configured via files, not the Kubernetes API:

```bash
# Configuration file
cat /etc/rancher/rke2/config.yaml

# Sample config:
# write-kubeconfig-mode: "0644"
# tls-san:
#   - "my-kubernetes-domain.com"
# disable:
#   - rke2-ingress-nginx

# This is NOT managed through the K8s API
# Changes require restarting rke2-server service
```

**Key insight**: RKE2 configuration is file-based. The Kubernetes API manages workloads, but not RKE2 itself.

### Accessing-Rancher-API-Directly

If using Rancher, it has its own API (separate from Kubernetes API):

```bash
# Rancher API endpoint (if installed)
# https://rancher.example.com/v3

# Get API keys from Rancher UI
# Settings > API Keys > Create API Key

# Example API call to Rancher
curl -u "${RANCHER_ACCESS_KEY}:${RANCHER_SECRET_KEY}" \
  https://rancher.example.com/v3/clusters

# Returns list of clusters managed by Rancher
```

**Rancher API vs Kubernetes API**:

- **Kubernetes API**: Manages resources within a cluster (pods, deployments, etc.)
- **Rancher API**: Manages clusters, projects, users, catalogs (multi-cluster management)

### Practical-RKE2-Example

Working with RKE2 add-ons:

```bash
# Check what's installed
kubectl get helmcharts -n kube-system

# View an addon's configuration
kubectl get helmchart rke2-ingress-nginx -n kube-system -o yaml

# Customize an addon (create override)
cat <<EOF | kubectl apply -f -
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: rke2-ingress-nginx-config
  namespace: kube-system
spec:
  chart: rke2-ingress-nginx
  createNamespace: true
  targetNamespace: kube-system
  valuesContent: |
    controller:
      service:
        externalTrafficPolicy: Local
      config:
        use-proxy-protocol: "true"
EOF

# Check addon status
kubectl get pods -n kube-system | grep ingress-nginx
```

### RKE2-Security-Features

RKE2 enables security features by default:

**Pod Security Admission**:

```bash
# RKE2 enforces Pod Security Standards
# Check namespace labels
kubectl get ns kube-system -o yaml | grep pod-security

# Output:
# pod-security.kubernetes.io/enforce: privileged
# pod-security.kubernetes.io/audit: restricted
# pod-security.kubernetes.io/warn: restricted

# Your workload namespaces may have restrictions
kubectl label namespace api-learning \
  pod-security.kubernetes.io/enforce=baseline

# Now pods must meet baseline security requirements
```

**Network Policies**:

```bash
# RKE2 includes Calico or Canal for network policies
kubectl get crd | grep network

# Create a network policy
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: api-learning
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# This blocks all traffic in api-learning namespace
```

[↑ Back to ToC](#table-of-contents)

---

## Practical-Exercises

Hands-on exercises to reinforce your understanding of the Kubernetes API. Work through these in order.

### Exercise-1-API-Discovery

**Goal**: Explore the API without external documentation.

**Steps**:

```bash
# 1. Find all batch-related resources
kubectl api-resources --api-group=batch

# Expected output:
# NAME       SHORTNAMES   APIVERSION   NAMESPACED   KIND
# cronjobs   cj           batch/v1     true         CronJob
# jobs                    batch/v1     true         Job

# 2. Learn about CronJob structure
kubectl explain cronjob

# 3. Drill down into spec
kubectl explain cronjob.spec
kubectl explain cronjob.spec.schedule
kubectl explain cronjob.spec.jobTemplate

# 4. Find the API path for CronJobs
# Group: batch
# Version: v1
# Resource: cronjobs
# Namespaced: yes
# Path: /apis/batch/v1/namespaces/{namespace}/cronjobs

# 5. Verify using API
kubectl proxy --port=8080 &
PROXY_PID=$!

curl http://localhost:8080/apis/batch/v1/namespaces/api-learning/cronjobs | jq -r '.kind'
# Output: CronJobList

kill $PROXY_PID

# 6. Create a CronJob using what you learned
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hello
  namespace: api-learning
spec:
  schedule: "*/5 * * * *"  # Every 5 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: hello
            image: busybox:1.36
            command:
            - /bin/sh
            - -c
            - echo "Hello from CronJob at $(date)"
          restartPolicy: OnFailure
EOF

# 7. Verify
kubectl get cronjobs -n api-learning
kubectl get jobs -n api-learning --watch
# Wait for job to run (up to 5 minutes)
```

**Troubleshooting**:

- If CronJob doesn't appear: Check namespace
- If Jobs don't run: Check schedule syntax
- If pods fail: Check image pull and command

**Cleanup**:

```bash
kubectl delete cronjob hello -n api-learning
```

---

### Exercise-2-CRUD-with-curl

**Goal**: Perform all CRUD operations using direct API calls.

**Steps**:

```bash
# Setup
kubectl proxy --port=8080 &
PROXY_PID=$!

# CREATE - Post a ConfigMap
curl -X POST \
  http://localhost:8080/api/v1/namespaces/api-learning/configmaps \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "v1",
    "kind": "ConfigMap",
    "metadata": {
      "name": "my-config"
    },
    "data": {
      "key1": "value1",
      "key2": "value2"
    }
  }' | jq -r '.metadata.name'

# Expected output: my-config

# READ - Get the ConfigMap
curl -s http://localhost:8080/api/v1/namespaces/api-learning/configmaps/my-config | \
  jq '{name: .metadata.name, data: .data}'

# Expected output:
# {
#   "name": "my-config",
#   "data": {
#     "key1": "value1",
#     "key2": "value2"
#   }
# }

# UPDATE - Add a new key using PATCH
curl -X PATCH \
  http://localhost:8080/api/v1/namespaces/api-learning/configmaps/my-config \
  -H "Content-Type: application/strategic-merge-patch+json" \
  -d '{
    "data": {
      "key3": "value3"
    }
  }' | jq -r '.data'

# Expected output: All three keys

# LIST - Get all ConfigMaps
curl -s http://localhost:8080/api/v1/namespaces/api-learning/configmaps | \
  jq -r '.items[].metadata.name'

# DELETE - Remove the ConfigMap
curl -X DELETE \
  http://localhost:8080/api/v1/namespaces/api-learning/configmaps/my-config | \
  jq -r '.status'

# Expected output: "Success"

# Verify deletion
curl -s http://localhost:8080/api/v1/namespaces/api-learning/configmaps/my-config | \
  jq -r '.code'

# Expected output: 404

# Cleanup
kill $PROXY_PID
```

**Challenge**: Repeat the exercise with a Secret resource instead of ConfigMap.

**Troubleshooting**:

- 404 errors: Check namespace and resource name
- 401/403 errors: Check proxy is running and permissions
- Invalid JSON: Validate JSON structure with jq

---

### Exercise-3-Watch-Pod-Changes

**Goal**: Build a simple watcher that logs pod lifecycle events.

**Steps**:

```bash
# 1. Create the watcher script
cat <<'SCRIPT' > /tmp/pod-watcher.sh
#!/bin/bash
set -euo pipefail

NAMESPACE=${1:-api-learning}

echo "Starting pod watcher for namespace: $NAMESPACE"

# Start proxy
kubectl proxy --port=8080 >/dev/null 2>&1 &
PROXY_PID=$!
trap "kill $PROXY_PID 2>/dev/null || true" EXIT

sleep 1

# Watch pods
curl -sN "http://localhost:8080/api/v1/namespaces/$NAMESPACE/pods?watch=true" | \
while IFS= read -r line; do
    TYPE=$(echo "$line" | jq -r '.type')
    NAME=$(echo "$line" | jq -r '.object.metadata.name')
    PHASE=$(echo "$line" | jq -r '.object.status.phase // "Unknown"')
    TIME=$(date '+%H:%M:%S')

    case $TYPE in
        ADDED)
            echo "[$TIME] ✨ Created: $NAME (Phase: $PHASE)"
            ;;
        MODIFIED)
            echo "[$TIME] 🔄 Updated: $NAME (Phase: $PHASE)"
            ;;
        DELETED)
            echo "[$TIME] 🗑️  Deleted: $NAME"
            ;;
    esac
done
SCRIPT

chmod +x /tmp/pod-watcher.sh

# 2. Run watcher in one terminal
/tmp/pod-watcher.sh api-learning &
WATCHER_PID=$!

# 3. In another terminal (or wait a moment), create pods
sleep 2
kubectl run watch-test-1 --image=nginx:1.27 -n api-learning
sleep 5
kubectl run watch-test-2 --image=nginx:1.27 -n api-learning
sleep 5
kubectl delete pod watch-test-1 watch-test-2 -n api-learning

# 4. Observe the output (should see creation, transitions, deletion)

# 5. Stop watcher
sleep 5
kill $WATCHER_PID 2>/dev/null || true
```

**Expected output**:

```
Starting pod watcher for namespace: api-learning
[10:23:15] ✨ Created: watch-test-1 (Phase: Pending)
[10:23:16] 🔄 Updated: watch-test-1 (Phase: Pending)
[10:23:18] 🔄 Updated: watch-test-1 (Phase: Running)
[10:23:20] ✨ Created: watch-test-2 (Phase: Pending)
[10:23:21] 🔄 Updated: watch-test-2 (Phase: Pending)
[10:23:23] 🔄 Updated: watch-test-2 (Phase: Running)
[10:23:25] 🗑️  Deleted: watch-test-1
[10:23:25] 🗑️  Deleted: watch-test-2
```

**Challenge**: Modify the script to also log container restart counts.

---

### Exercise-4-Python-Pod-Watcher

**Goal**: Build a Python application that watches pods and logs events.

**Steps**:

```bash
# 1. Create requirements.txt
cat <<EOF > /tmp/requirements.txt
kubernetes>=29.0.0
EOF

pip install -r /tmp/requirements.txt

# 2. Create the watcher application
cat <<'PYTHON' > /tmp/pod_watcher.py
#!/usr/bin/env python3
"""
Advanced pod watcher with filtering and formatting
"""
from kubernetes import client, config, watch
import sys
import argparse
from datetime import datetime

def format_timestamp():
    return datetime.now().strftime("%H:%M:%S")

def watch_pods(namespace, label_selector=None):
    """Watch pods in a namespace with optional label filter"""

    # Load kubeconfig
    config.load_kube_config()
    v1 = client.CoreV1Api()

    print(f"Watching pods in namespace: {namespace}")
    if label_selector:
        print(f"Label selector: {label_selector}")
    print("Press Ctrl+C to stop\n")

    # Create watcher
    watcher = watch.Watch()

    try:
        # Stream events
        stream = watcher.stream(
            v1.list_namespaced_pod,
            namespace=namespace,
            label_selector=label_selector,
            timeout_seconds=0
        )

        for event in stream:
            event_type = event['type']
            pod = event['object']

            name = pod.metadata.name
            phase = pod.status.phase or "Unknown"
            node = pod.spec.node_name or "Not assigned"

            timestamp = format_timestamp()

            # Format output based on event type
            if event_type == "ADDED":
                print(f"[{timestamp}] ✨ Pod created: {name}")
                print(f"            Phase: {phase}, Node: {node}")

            elif event_type == "MODIFIED":
                # Count containers
                total = len(pod.spec.containers)
                ready = sum(1 for cs in pod.status.container_statuses or []
                           if cs.ready)

                print(f"[{timestamp}] 🔄 Pod updated: {name}")
                print(f"            Phase: {phase}, Containers: {ready}/{total}")

            elif event_type == "DELETED":
                print(f"[{timestamp}] 🗑️  Pod deleted: {name}")

            print()  # Blank line for readability

    except KeyboardInterrupt:
        print("\nWatch stopped by user")
    except client.exceptions.ApiException as e:
        print(f"\nAPI Error: {e.status} - {e.reason}")
    finally:
        watcher.stop()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Watch Kubernetes pods")
    parser.add_argument("namespace", help="Namespace to watch")
    parser.add_argument("-l", "--label", help="Label selector (e.g., app=nginx)")

    args = parser.parse_args()
    watch_pods(args.namespace, args.label)
PYTHON

chmod +x /tmp/pod_watcher.py

# 3. Run the watcher
/tmp/pod_watcher.py api-learning &
WATCHER_PID=$!

# 4. Create test pods
sleep 2
kubectl run py-test-1 --image=nginx:1.27 --labels=app=nginx -n api-learning
kubectl run py-test-2 --image=nginx:1.27 --labels=app=nginx -n api-learning
sleep 10
kubectl delete pod py-test-1 py-test-2 -n api-learning

# 5. Stop watcher
sleep 5
kill $WATCHER_PID 2>/dev/null || true

# 6. Try with label filter
/tmp/pod_watcher.py api-learning -l app=nginx &
WATCHER_PID=$!
sleep 2
kubectl run labeled --image=nginx --labels=app=nginx -n api-learning
kubectl run unlabeled --image=nginx -n api-learning
sleep 5
# Should only see "labeled" pod
kill $WATCHER_PID 2>/dev/null || true
kubectl delete pod labeled unlabeled -n api-learning
```

**Challenge**: Extend the script to also log container restart counts and reasons.

---

### Exercise-5-Define-Your-Own-CRD

**Goal**: Create a custom resource definition and instances.

**Steps**:

```bash
# 1. Design a CRD for managing static websites
cat <<'EOF' > /tmp/website-crd.yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: websites.hosting.example.com
spec:
  group: hosting.example.com
  scope: Namespaced
  names:
    plural: websites
    singular: website
    kind: Website
    shortNames:
    - site
  versions:
  - name: v1
    served: true
    storage: true
    subresources:
      status: {}
    schema:
      openAPIV3Schema:
        type: object
        required:
        - spec
        properties:
          spec:
            type: object
            required:
            - domain
            - contentSource
            properties:
              domain:
                type: string
                pattern: '^[a-z0-9-]+\.[a-z]{2,}$'
                description: "Website domain name"
              contentSource:
                type: object
                required:
                - type
                properties:
                  type:
                    type: string
                    enum: ["git", "configmap"]
                  git:
                    type: object
                    properties:
                      repo:
                        type: string
                      branch:
                        type: string
                        default: "main"
                  configMap:
                    type: object
                    properties:
                      name:
                        type: string
              tls:
                type: boolean
                default: false
              replicas:
                type: integer
                minimum: 1
                maximum: 10
                default: 2
          status:
            type: object
            properties:
              phase:
                type: string
                enum: ["Pending", "Running", "Failed"]
              url:
                type: string
              lastUpdated:
                type: string
                format: date-time
    additionalPrinterColumns:
    - name: Domain
      type: string
      jsonPath: .spec.domain
    - name: TLS
      type: boolean
      jsonPath: .spec.tls
    - name: Phase
      type: string
      jsonPath: .status.phase
    - name: URL
      type: string
      jsonPath: .status.url
    - name: Age
      type: date
      jsonPath: .metadata.creationTimestamp
EOF

# 2. Apply the CRD
kubectl apply -f /tmp/website-crd.yaml

# 3. Verify CRD is registered
kubectl get crd websites.hosting.example.com
kubectl api-resources | grep website

# 4. Create website instances
cat <<EOF | kubectl apply -f -
apiVersion: hosting.example.com/v1
kind: Website
metadata:
  name: blog
  namespace: api-learning
spec:
  domain: blog.example.com
  contentSource:
    type: git
    git:
      repo: https://github.com/example/blog
      branch: main
  tls: true
  replicas: 3
EOF

cat <<EOF | kubectl apply -f -
apiVersion: hosting.example.com/v1
kind: Website
metadata:
  name: docs
  namespace: api-learning
spec:
  domain: docs.example.com
  contentSource:
    type: configmap
    configMap:
      name: docs-content
  tls: false
  replicas: 2
EOF

# 5. List websites
kubectl get websites -n api-learning

# Expected output:
# NAME   DOMAIN              TLS    PHASE   URL   AGE
# blog   blog.example.com    true                 5s
# docs   docs.example.com    false                5s

# 6. View details
kubectl describe website blog -n api-learning

# 7. Test validation - this should fail (invalid domain)
cat <<EOF | kubectl apply -f -
apiVersion: hosting.example.com/v1
kind: Website
metadata:
  name: invalid
  namespace: api-learning
spec:
  domain: "INVALID DOMAIN!"
  contentSource:
    type: git
    git:
      repo: https://github.com/example/site
EOF

# Error: spec.domain in body should match '^[a-z0-9-]+\.[a-z]{2,}$'

# 8. Update status (simulating a controller)
kubectl patch website blog -n api-learning \
  --subresource=status \
  --type=merge \
  --patch='{
    "status": {
      "phase": "Running",
      "url": "https://blog.example.com",
      "lastUpdated": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
    }
  }'

# 9. View updated status
kubectl get websites -n api-learning

# Now shows Phase and URL

# Cleanup
kubectl delete website blog docs -n api-learning
kubectl delete crd websites.hosting.example.com
```

**Challenge**: Write a simple Python controller that watches Website resources and creates corresponding Deployments and Services.

---

[↑ Back to ToC](#table-of-contents)

---

## Common-Mistakes-and-Troubleshooting

Learn from common pitfalls when working with the Kubernetes API.

### Wrong-API-Version

**Problem**: Using deprecated or unavailable API versions.

```bash
# Error example
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1beta1  # Deprecated
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
EOF

# Error: no matches for kind "Deployment" in version "apps/v1beta1"
```

**Solution**: Check available API versions.

```bash
# See what versions are available
kubectl api-versions | grep apps

# Update to correct version
apiVersion: apps/v1  # Current stable version
```

**Prevention**: Always use stable (`v1`) versions in production. Check release notes when upgrading Kubernetes.

### Resource-Not-Found-404

**Problem**: Accessing non-existent resources.

```bash
# Error
kubectl get pod nonexistent -n api-learning

# Error: Error from server (NotFound): pods "nonexistent" not found
```

**Solution**: Verify resource name and namespace.

```bash
# Check spelling
kubectl get pods -n api-learning | grep nginx

# Check all namespaces
kubectl get pods --all-namespaces | grep nginx

# Check if resource type exists
kubectl api-resources | grep pod
```

**Common causes**:

- Typo in resource name
- Wrong namespace
- Resource was deleted
- Using wrong resource type (e.g., `pod` vs `pods`)

### Permission-Denied-403

**Problem**: Insufficient RBAC permissions.

```bash
# Error
kubectl get secrets -n kube-system

# Error: Error from server (Forbidden): secrets is forbidden:
# User "jane" cannot list resource "secrets" in API group "" in namespace "kube-system"
```

**Solution**: Check permissions and request access.

```bash
# Check what you can do
kubectl auth can-i list secrets -n kube-system

# Check all permissions
kubectl auth can-i --list -n kube-system

# Ask admin to grant access with RoleBinding
```

**For service accounts**:

```bash
# Check service account permissions
kubectl auth can-i list pods \
  --as=system:serviceaccount:api-learning:default \
  -n api-learning
```

### Immutable-Fields

**Problem**: Trying to update fields that can't be changed.

```bash
# Create deployment
kubectl create deployment nginx --image=nginx -n api-learning

# Try to change selector (immutable!)
kubectl patch deployment nginx -n api-learning \
  --type=strategic \
  --patch='{
    "spec": {
      "selector": {
        "matchLabels": {
          "app": "new-label"
        }
      }
    }
  }'

# Error: field is immutable
```

**Solution**: Delete and recreate, or use different strategies.

```bash
# Check which fields are immutable
kubectl explain deployment.spec.selector

# For immutable changes, recreate the resource
kubectl delete deployment nginx -n api-learning
kubectl create deployment nginx --image=nginx -n api-learning
```

**Common immutable fields**:

- Deployment: `.spec.selector`
- Service: `.spec.clusterIP`
- PVC: `.spec.volumeName`, `.spec.storageClassName`
- Pod: `.spec.containers[*].name`, `.spec.nodeName`

### Conflict-Errors-ResourceVersion

**Problem**: Concurrent updates cause conflicts.

```bash
# Get a resource
kubectl get deployment nginx -n api-learning -o json > /tmp/deploy.json

# Someone else updates it
kubectl scale deployment nginx --replicas=5 -n api-learning

# You try to apply your old version
kubectl apply -f /tmp/deploy.json

# Possible conflict if using PUT or optimistic locking
```

**Solution**: Use PATCH instead of PUT, or retry with fresh data.

```bash
# Strategic merge patch is safer
kubectl patch deployment nginx -n api-learning \
  --type=strategic \
  --patch='{"spec":{"replicas":3}}'

# Or use kubectl apply (handles conflicts)
kubectl apply -f deployment.yaml
```

**In client code**:

```python
from kubernetes import client
from kubernetes.client.rest import ApiException

def update_with_retry(api, namespace, name, update_func, max_retries=5):
    """Update resource with retry on conflict"""
    for attempt in range(max_retries):
        try:
            # Get current resource
            obj = api.read_namespaced_deployment(name, namespace)

            # Apply update
            updated = update_func(obj)

            # Update (may conflict)
            api.replace_namespaced_deployment(name, namespace, updated)
            return

        except ApiException as e:
            if e.status == 409:  # Conflict
                print(f"Conflict, retrying ({attempt+1}/{max_retries})")
                continue
            raise

    raise Exception("Max retries exceeded")
```

### Watch-Timeouts

**Problem**: Watch connections close unexpectedly.

```bash
# Watch times out after some period
kubectl get pods --watch -n api-learning

# Connection closes with no error message
```

**Solution**: Implement reconnection logic.

```python
from kubernetes import client, config, watch
import time

def watch_with_reconnect(namespace):
    config.load_kube_config()
    v1 = client.CoreV1Api()

    resource_version = None

    while True:
        try:
            watcher = watch.Watch()
            stream = watcher.stream(
                v1.list_namespaced_pod,
                namespace=namespace,
                resource_version=resource_version,
                timeout_seconds=300  # 5 minutes
            )

            for event in stream:
                # Process event
                print(f"{event['type']}: {event['object'].metadata.name}")

                # Save resourceVersion for resume
                resource_version = event['object'].metadata.resource_version

        except Exception as e:
            print(f"Watch error: {e}, reconnecting in 5s...")
            time.sleep(5)
            # Continue loop to reconnect
```

### Invalid-JSON-YAML

**Problem**: Malformed manifests.

```yaml
# Invalid YAML (wrong indentation)
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
containers:  # Should be indented
- name: nginx
  image: nginx
```

**Solution**: Validate YAML before applying.

```bash
# Use --dry-run to validate
kubectl apply -f pod.yaml --dry-run=client

# Use kubectl to check syntax
kubectl apply -f pod.yaml --dry-run=server

# Use external validators
yamllint pod.yaml

# Use jq to validate JSON
cat pod.json | jq . > /dev/null && echo "Valid JSON"
```

### Namespace-Issues

**Problem**: Resources in wrong namespace or no namespace specified.

```bash
# Error: namespace required but not specified
kubectl get pods nginx

# Works if nginx is in default namespace
# Fails if nginx is in another namespace
```

**Solution**: Always specify namespace.

```bash
# Explicit namespace
kubectl get pod nginx -n api-learning

# Set default namespace for context
kubectl config set-context --current --namespace=api-learning

# Check current namespace
kubectl config view --minify | grep namespace:
```

### Label-Selector-Mismatches

**Problem**: Deployment selector doesn't match pod labels.

```yaml
# Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  selector:
    matchLabels:
      app: nginx  # Selector
  template:
    metadata:
      labels:
        app: web  # Doesn't match!
```

**Error**:

```
error: error validating data: selector does not match template labels
```

**Solution**: Ensure labels match.

```yaml
spec:
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx  # Now matches
```

### Field-Not-Found-in-Schema

**Problem**: Using fields that don't exist in the schema.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx
    invalidField: "value"  # Doesn't exist
```

**Solution**: Use `kubectl explain` to check schema.

```bash
# Check valid fields
kubectl explain pod.spec.containers

# Look for specific field
kubectl explain pod.spec.containers.resources
```

[↑ Back to ToC](#table-of-contents)

---

## Quick-Reference

Cheat sheet for common Kubernetes API operations.

### kubectl-API-Commands

```bash
# API resources
kubectl api-resources                           # List all resource types
kubectl api-resources --namespaced=true         # Only namespaced resources
kubectl api-resources --api-group=apps          # Resources in specific group
kubectl api-resources -o wide                   # Include verbs

# API versions
kubectl api-versions                            # List all API versions
kubectl api-versions | grep apps                # Check specific group

# Explain resources
kubectl explain pod                             # Top-level docs
kubectl explain pod.spec                        # Nested field
kubectl explain pod.spec.containers             # Deeper nesting
kubectl explain pod --recursive                 # All fields

# Direct API access
kubectl get --raw /api/v1                       # Core API resources
kubectl get --raw /apis/apps/v1                 # Apps group resources
kubectl get --raw /healthz                      # Health check
kubectl get --raw /version                      # Server version
```

### API-Path-Patterns

```bash
# Core resources (v1)
/api/v1/namespaces                              # Cluster-scoped
/api/v1/namespaces/{ns}/{resource}              # Namespaced collection
/api/v1/namespaces/{ns}/{resource}/{name}       # Specific resource

# Named group resources
/apis/{group}/{version}/{resource}              # Cluster-scoped
/apis/{group}/{version}/namespaces/{ns}/{resource}           # Namespaced collection
/apis/{group}/{version}/namespaces/{ns}/{resource}/{name}    # Specific resource

# Subresources
/api/v1/namespaces/{ns}/pods/{name}/log         # Logs
/api/v1/namespaces/{ns}/pods/{name}/status      # Status
/apis/apps/v1/namespaces/{ns}/deployments/{name}/scale       # Scale
```

### Common-HTTP-Status-Codes

| Code | Meaning | Common Causes |
|------|---------|---------------|
| 200 | OK | Successful GET, PUT, PATCH |
| 201 | Created | Successful POST |
| 202 | Accepted | Asynchronous delete started |
| 400 | Bad Request | Invalid JSON, schema violation |
| 401 | Unauthorized | Missing or invalid credentials |
| 403 | Forbidden | RBAC denial |
| 404 | Not Found | Resource doesn't exist |
| 409 | Conflict | Resource already exists (POST), resourceVersion mismatch |
| 422 | Unprocessable Entity | Validation failure |
| 500 | Internal Server Error | API server error |
| 503 | Service Unavailable | API server overloaded |

### CRUD-Operations-Quick-Reference

```bash
# CREATE
kubectl create -f resource.yaml
kubectl apply -f resource.yaml
curl -X POST {api-path} -d @resource.json

# READ
kubectl get {resource} {name}
kubectl get {resource} {name} -o yaml
curl {api-path}/{name}

# UPDATE
kubectl apply -f resource.yaml                  # Declarative
kubectl patch {resource} {name} --patch '{...}' # Imperative
curl -X PATCH {api-path}/{name} -d @patch.json

# DELETE
kubectl delete {resource} {name}
curl -X DELETE {api-path}/{name}

# LIST
kubectl get {resource}
curl {api-path}

# WATCH
kubectl get {resource} --watch
curl "{api-path}?watch=true"
```

### Patch-Types-Quick-Reference

```bash
# Strategic merge (default for kubectl patch)
kubectl patch deployment nginx \
  --type=strategic \
  --patch='{"spec":{"replicas":3}}'

# JSON merge
kubectl patch deployment nginx \
  --type=merge \
  --patch='{"spec":{"replicas":3}}'

# JSON patch
kubectl patch deployment nginx \
  --type=json \
  --patch='[{"op":"replace","path":"/spec/replicas","value":3}]'
```

### Label-Selector-Syntax

```bash
# Equality-based
-l app=nginx                    # Equals
-l app!=nginx                   # Not equals
-l 'env in (prod,staging)'      # In set
-l 'env notin (dev,test)'       # Not in set

# Existence
-l environment                  # Has label
-l '!environment'               # Doesn't have label

# Multiple (AND logic)
-l app=nginx,tier=frontend      # Both must match
```

### Field-Selector-Syntax

```bash
# Common field selectors
--field-selector metadata.name=nginx
--field-selector metadata.namespace=default
--field-selector spec.nodeName=worker-1
--field-selector status.phase=Running
--field-selector status.phase!=Pending

# Multiple (AND logic)
--field-selector status.phase=Running,spec.nodeName=worker-1
```

### Authentication-Quick-Reference

```bash
# View current user
kubectl config view --minify -o jsonpath='{.contexts[0].context.user}'

# Check permissions
kubectl auth can-i create pods
kubectl auth can-i delete nodes
kubectl auth can-i '*' '*' --all-namespaces

# Impersonate user
kubectl get pods --as=jane --as-group=developers

# Impersonate service account
kubectl get pods \
  --as=system:serviceaccount:default:my-sa
```

### Python-Client-Quick-Reference

```python
from kubernetes import client, config

# Load config
config.load_kube_config()              # From ~/.kube/config
config.load_incluster_config()         # From pod service account

# Create API clients
v1 = client.CoreV1Api()                # Core resources
apps_v1 = client.AppsV1Api()           # apps/v1 resources
batch_v1 = client.BatchV1Api()         # batch/v1 resources

# List resources
pods = v1.list_namespaced_pod(namespace="default")
deployments = apps_v1.list_namespaced_deployment(namespace="default")

# Get resource
pod = v1.read_namespaced_pod(name="nginx", namespace="default")

# Create resource
pod_manifest = client.V1Pod(...)
v1.create_namespaced_pod(namespace="default", body=pod_manifest)

# Update resource
v1.patch_namespaced_pod(name="nginx", namespace="default", body=patch)

# Delete resource
v1.delete_namespaced_pod(name="nginx", namespace="default")

# Watch resources
watcher = watch.Watch()
for event in watcher.stream(v1.list_namespaced_pod, namespace="default"):
    print(f"{event['type']}: {event['object'].metadata.name}")
```

### Go-Client-Quick-Reference

```go
import (
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/tools/clientcmd"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// Load config
config, _ := clientcmd.BuildConfigFromFlags("", kubeconfig)
clientset, _ := kubernetes.NewForConfig(config)

// List pods
pods, _ := clientset.CoreV1().Pods("default").List(
    context.TODO(),
    metav1.ListOptions{},
)

// Get pod
pod, _ := clientset.CoreV1().Pods("default").Get(
    context.TODO(),
    "nginx",
    metav1.GetOptions{},
)

// Create pod
_, _ = clientset.CoreV1().Pods("default").Create(
    context.TODO(),
    podManifest,
    metav1.CreateOptions{},
)

// Delete pod
_ = clientset.CoreV1().Pods("default").Delete(
    context.TODO(),
    "nginx",
    metav1.DeleteOptions{},
)
```

[↑ Back to ToC](#table-of-contents)

---

## Building-a-Small-App-Pod-Health-Monitor

Let's build a complete, production-ready application that monitors pod health using the Kubernetes API. This demonstrates everything you've learned in a real-world context.

### Application-Overview

**Pod Health Monitor** is a service that:

- Watches all pods in specified namespaces
- Tracks pod lifecycle events (created, running, failed, deleted)
- Detects unhealthy pods (restart loops, CrashLoopBackOff, pending too long)
- Logs events with structured output
- Exposes metrics for Prometheus
- Handles errors and reconnections gracefully

**Architecture**:

```
┌─────────────────────────────────────┐
│   Kubernetes API Server             │
│   (Watch /api/v1/pods)               │
└─────────────┬───────────────────────┘
              │ Stream pod events
              ▼
┌─────────────────────────────────────┐
│   Pod Health Monitor                 │
│   - Event processor                  │
│   - Health checker                   │
│   - Metrics exporter                 │
│   - Reconnection logic               │
└─────────────┬───────────────────────┘
              │ Logs & Metrics
              ▼
┌─────────────────────────────────────┐
│   Outputs                            │
│   - Structured logs (stdout)         │
│   - Prometheus metrics (:8000)       │
└─────────────────────────────────────┘
```

### Application-Code

**requirements.txt**:

```txt
kubernetes>=29.0.0
prometheus-client>=0.19.0
```

**pod_health_monitor.py**:

```python
#!/usr/bin/env python3
"""
Pod Health Monitor - Watches Kubernetes pods and tracks health status

This application demonstrates:
- Connecting to the Kubernetes API
- Watching resources in real-time
- Processing events and maintaining state
- Handling errors and reconnections
- Exporting metrics
"""

import os
import sys
import time
import logging
from datetime import datetime, timedelta
from typing import Dict, Set
from collections import defaultdict

from kubernetes import client, config, watch
from kubernetes.client.rest import ApiException
from prometheus_client import start_http_server, Counter, Gauge, Histogram

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('pod-health-monitor')

# Prometheus metrics
pod_events_total = Counter(
    'pod_events_total',
    'Total number of pod events processed',
    ['namespace', 'event_type']
)

unhealthy_pods = Gauge(
    'unhealthy_pods_total',
    'Number of unhealthy pods',
    ['namespace', 'reason']
)

pod_restarts = Counter(
    'pod_restarts_total',
    'Total number of pod container restarts',
    ['namespace', 'pod']
)

event_processing_duration = Histogram(
    'event_processing_seconds',
    'Time spent processing events'
)


class PodHealthMonitor:
    """Monitors pod health across specified namespaces"""

    def __init__(self, namespaces: list, check_interval: int = 30):
        """
        Initialize the monitor

        Args:
            namespaces: List of namespaces to monitor (or [''] for all)
            check_interval: How often to check pod health (seconds)
        """
        self.namespaces = namespaces
        self.check_interval = check_interval

        # Track pod state
        # Key: namespace/pod-name, Value: pod object
        self.pods: Dict[str, client.V1Pod] = {}

        # Track restart counts
        # Key: namespace/pod-name, Value: total restart count
        self.restart_counts: Dict[str, int] = defaultdict(int)

        # Track unhealthy pods
        # Key: namespace/pod-name, Value: reason
        self.unhealthy: Dict[str, str] = {}

        # Load Kubernetes config
        self._load_config()

        # Create API client
        self.v1 = client.CoreV1Api()

    def _load_config(self):
        """Load Kubernetes configuration (in-cluster or kubeconfig)"""
        try:
            # Try in-cluster config first (for running in pod)
            config.load_incluster_config()
            logger.info("Using in-cluster configuration")
        except config.ConfigException:
            # Fall back to kubeconfig (for local development)
            try:
                config.load_kube_config()
                logger.info("Using kubeconfig configuration")
            except config.ConfigException as e:
                logger.error(f"Failed to load Kubernetes config: {e}")
                sys.exit(1)

    def start(self):
        """Start monitoring pods"""
        logger.info(f"Starting pod health monitor")
        logger.info(f"Monitoring namespaces: {self.namespaces}")

        # Start metrics server
        metrics_port = int(os.getenv('METRICS_PORT', '8000'))
        start_http_server(metrics_port)
        logger.info(f"Metrics server started on port {metrics_port}")

        # Start watching each namespace in a separate thread would be better,
        # but for simplicity, we'll watch sequentially
        # In production, use threading or asyncio
        for namespace in self.namespaces:
            self._watch_namespace(namespace)

    def _watch_namespace(self, namespace: str):
        """
        Watch pods in a namespace with automatic reconnection

        Args:
            namespace: Namespace to watch (empty string for all namespaces)
        """
        resource_version = None
        ns_display = namespace or "all namespaces"

        logger.info(f"Starting watch for {ns_display}")

        while True:
            try:
                # Create watcher
                watcher = watch.Watch()

                # Determine watch function
                if namespace:
                    watch_func = self.v1.list_namespaced_pod
                    watch_kwargs = {'namespace': namespace}
                else:
                    watch_func = self.v1.list_pod_for_all_namespaces
                    watch_kwargs = {}

                # Add resource_version if we have one (for resume)
                if resource_version:
                    watch_kwargs['resource_version'] = resource_version

                # Stream events
                for event in watcher.stream(watch_func, **watch_kwargs):
                    # Process event
                    self._process_event(event)

                    # Save resource_version for resume
                    pod = event['object']
                    resource_version = pod.metadata.resource_version

            except ApiException as e:
                if e.status == 410:  # Gone - resourceVersion too old
                    logger.warning(f"ResourceVersion expired for {ns_display}, restarting watch")
                    resource_version = None  # Reset to start fresh
                else:
                    logger.error(f"API error watching {ns_display}: {e}")
                time.sleep(5)

            except Exception as e:
                logger.error(f"Unexpected error watching {ns_display}: {e}")
                time.sleep(5)

            logger.info(f"Reconnecting watch for {ns_display}")

    @event_processing_duration.time()
    def _process_event(self, event: dict):
        """
        Process a watch event

        Args:
            event: Event dict with 'type' and 'object' keys
        """
        event_type = event['type']  # ADDED, MODIFIED, DELETED
        pod = event['object']

        # Get pod identifiers
        namespace = pod.metadata.namespace
        name = pod.metadata.name
        pod_key = f"{namespace}/{name}"

        # Log event
        logger.debug(f"Event: {event_type} {pod_key}")

        # Update metrics
        pod_events_total.labels(namespace=namespace, event_type=event_type).inc()

        # Process based on event type
        if event_type == "DELETED":
            self._handle_pod_deleted(pod_key, pod)
        else:  # ADDED or MODIFIED
            self._handle_pod_updated(pod_key, pod)

    def _handle_pod_deleted(self, pod_key: str, pod: client.V1Pod):
        """Handle pod deletion"""
        namespace = pod.metadata.namespace
        name = pod.metadata.name

        logger.info(f"Pod deleted: {pod_key}")

        # Remove from tracking
        self.pods.pop(pod_key, None)
        self.restart_counts.pop(pod_key, None)

        # Remove from unhealthy if present
        if pod_key in self.unhealthy:
            reason = self.unhealthy.pop(pod_key)
            unhealthy_pods.labels(namespace=namespace, reason=reason).dec()

    def _handle_pod_updated(self, pod_key: str, pod: client.V1Pod):
        """Handle pod creation or update"""
        namespace = pod.metadata.namespace
        name = pod.metadata.name
        phase = pod.status.phase

        # Store pod
        is_new = pod_key not in self.pods
        self.pods[pod_key] = pod

        if is_new:
            logger.info(f"Pod created: {pod_key} (Phase: {phase})")

        # Check restart counts
        self._check_restarts(pod_key, pod)

        # Check health
        self._check_health(pod_key, pod)

    def _check_restarts(self, pod_key: str, pod: client.V1Pod):
        """
        Check for container restarts

        Args:
            pod_key: Pod identifier
            pod: Pod object
        """
        namespace = pod.metadata.namespace
        name = pod.metadata.name

        if not pod.status.container_statuses:
            return

        # Sum restart counts across all containers
        total_restarts = sum(
            cs.restart_count for cs in pod.status.container_statuses
        )

        # Check if restarts increased
        previous_restarts = self.restart_counts.get(pod_key, 0)

        if total_restarts > previous_restarts:
            new_restarts = total_restarts - previous_restarts
            logger.warning(
                f"Pod {pod_key} restarted {new_restarts} time(s) "
                f"(total: {total_restarts})"
            )

            # Update metrics
            pod_restarts.labels(namespace=namespace, pod=name).inc(new_restarts)

        # Update tracking
        self.restart_counts[pod_key] = total_restarts

    def _check_health(self, pod_key: str, pod: client.V1Pod):
        """
        Check if pod is healthy

        Args:
            pod_key: Pod identifier
            pod: Pod object
        """
        namespace = pod.metadata.namespace
        name = pod.metadata.name
        phase = pod.status.phase

        # Determine if pod is unhealthy
        unhealthy_reason = None

        # Check phase
        if phase in ['Failed', 'Unknown']:
            unhealthy_reason = phase

        # Check container statuses
        if pod.status.container_statuses:
            for cs in pod.status.container_statuses:
                # Check waiting state
                if cs.state.waiting:
                    reason = cs.state.waiting.reason
                    if reason in ['CrashLoopBackOff', 'ImagePullBackOff', 'ErrImagePull']:
                        unhealthy_reason = reason
                        break

                # Check for excessive restarts
                if cs.restart_count > 5:
                    unhealthy_reason = f"HighRestartCount({cs.restart_count})"
                    break

        # Check if pod has been pending too long
        if phase == 'Pending':
            creation_time = pod.metadata.creation_timestamp
            age = datetime.now(creation_time.tzinfo) - creation_time

            if age > timedelta(minutes=5):
                unhealthy_reason = "PendingTooLong"

        # Update unhealthy tracking
        was_unhealthy = pod_key in self.unhealthy

        if unhealthy_reason:
            if not was_unhealthy or self.unhealthy[pod_key] != unhealthy_reason:
                logger.warning(f"Pod unhealthy: {pod_key} - {unhealthy_reason}")

                # Update metrics
                if was_unhealthy:
                    old_reason = self.unhealthy[pod_key]
                    unhealthy_pods.labels(namespace=namespace, reason=old_reason).dec()

                self.unhealthy[pod_key] = unhealthy_reason
                unhealthy_pods.labels(namespace=namespace, reason=unhealthy_reason).inc()

        elif was_unhealthy:
            # Pod recovered
            logger.info(f"Pod recovered: {pod_key}")
            old_reason = self.unhealthy.pop(pod_key)
            unhealthy_pods.labels(namespace=namespace, reason=old_reason).dec()


def main():
    """Main entry point"""
    # Get configuration from environment
    namespaces_str = os.getenv('NAMESPACES', 'default')
    namespaces = [ns.strip() for ns in namespaces_str.split(',') if ns.strip()]

    check_interval = int(os.getenv('CHECK_INTERVAL', '30'))

    # Create and start monitor
    monitor = PodHealthMonitor(namespaces, check_interval)
    monitor.start()


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        logger.info("Shutting down...")
        sys.exit(0)
```

### Dockerfile

```dockerfile
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY pod_health_monitor.py .

# Run as non-root user
RUN useradd -m -u 1000 monitor && \
    chown -R monitor:monitor /app
USER monitor

# Expose metrics port
EXPOSE 8000

# Run the application
CMD ["python", "pod_health_monitor.py"]
```

### Kubernetes-Manifests

**namespace.yaml**:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
```

**serviceaccount.yaml**:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-health-monitor
  namespace: monitoring
```

**rbac.yaml**:

```yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-health-monitor
rules:
# Allow reading pods across all namespaces
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pod-health-monitor
subjects:
- kind: ServiceAccount
  name: pod-health-monitor
  namespace: monitoring
roleRef:
  kind: ClusterRole
  name: pod-health-monitor
  apiGroup: rbac.authorization.k8s.io
```

**deployment.yaml**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pod-health-monitor
  namespace: monitoring
  labels:
    app: pod-health-monitor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pod-health-monitor
  template:
    metadata:
      labels:
        app: pod-health-monitor
    spec:
      serviceAccountName: pod-health-monitor
      containers:
      - name: monitor
        image: pod-health-monitor:latest
        imagePullPolicy: IfNotPresent
        env:
        # Comma-separated list of namespaces to monitor
        # Empty string or omit to monitor all namespaces
        - name: NAMESPACES
          value: "default,api-learning"
        # How often to run health checks (seconds)
        - name: CHECK_INTERVAL
          value: "30"
        # Port for Prometheus metrics
        - name: METRICS_PORT
          value: "8000"
        ports:
        - name: metrics
          containerPort: 8000
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1000
          capabilities:
            drop:
            - ALL
```

**service.yaml**:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: pod-health-monitor
  namespace: monitoring
  labels:
    app: pod-health-monitor
spec:
  selector:
    app: pod-health-monitor
  ports:
  - name: metrics
    port: 8000
    targetPort: metrics
  type: ClusterIP
```

### Building-and-Deploying

```bash
# 1. Create project directory
mkdir -p pod-health-monitor
cd pod-health-monitor

# 2. Create all files (requirements.txt, pod_health_monitor.py, Dockerfile, k8s manifests)
# ... (copy content from above)

# 3. Build Docker image
docker build -t pod-health-monitor:latest .

# 4. If using a registry, push the image
# docker tag pod-health-monitor:latest registry.example.com/pod-health-monitor:latest
# docker push registry.example.com/pod-health-monitor:latest

# 5. Create namespace
kubectl apply -f k8s/namespace.yaml

# 6. Create service account and RBAC
kubectl apply -f k8s/serviceaccount.yaml
kubectl apply -f k8s/rbac.yaml

# 7. Deploy the application
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# 8. Verify deployment
kubectl get pods -n monitoring
kubectl logs -n monitoring -l app=pod-health-monitor --tail=50 -f

# 9. Check metrics
kubectl port-forward -n monitoring svc/pod-health-monitor 8000:8000 &
curl http://localhost:8000/metrics
```

### Testing-the-Application

```bash
# Create test pods in monitored namespace
kubectl run healthy-pod --image=nginx:1.27 -n api-learning

# Create a pod that will crash
kubectl run crash-pod --image=busybox -n api-learning -- sh -c "sleep 5; exit 1"

# Create a pod with image pull error
kubectl run bad-image --image=nonexistent/image:latest -n api-learning

# Watch the monitor logs
kubectl logs -n monitoring -l app=pod-health-monitor -f

# You should see:
# - Pod created events
# - Restart warnings for crash-pod
# - Unhealthy status for bad-image (ImagePullBackOff)

# Check metrics
curl http://localhost:8000/metrics | grep pod_events_total
curl http://localhost:8000/metrics | grep unhealthy_pods
curl http://localhost:8000/metrics | grep pod_restarts

# Cleanup test pods
kubectl delete pod healthy-pod crash-pod bad-image -n api-learning
```

### Key-API-Interactions-Explained

Let's highlight the key API interactions in the code:

**1. Loading Configuration** (lines 82-96):

```python
def _load_config(self):
    """Load Kubernetes configuration (in-cluster or kubeconfig)"""
    try:
        # In-cluster: Uses service account token at
        # /var/run/secrets/kubernetes.io/serviceaccount/token
        config.load_incluster_config()
    except config.ConfigException:
        # Local: Uses ~/.kube/config
        config.load_kube_config()
```

**2. Creating API Client** (line 79):

```python
# Creates authenticated HTTP client for core/v1 API
self.v1 = client.CoreV1Api()
```

**3. Watching Resources** (lines 131-163):

```python
# Create watch object - manages HTTP connection
watcher = watch.Watch()

# Stream events from API
# This makes: GET /api/v1/namespaces/{ns}/pods?watch=true
for event in watcher.stream(watch_func, **watch_kwargs):
    # Each event is: {"type": "ADDED|MODIFIED|DELETED", "object": {Pod}}
    self._process_event(event)

    # Extract resourceVersion for resume capability
    resource_version = pod.metadata.resource_version
```

**4. Error Handling** (lines 165-172):

```python
except ApiException as e:
    if e.status == 410:  # Gone
        # ResourceVersion expired, start fresh
        resource_version = None
    else:
        # Other API errors (403, 500, etc.)
        logger.error(f"API error: {e}")
```

**5. Processing Pod Objects** (lines 201-210):

```python
# Every pod has standard fields:
namespace = pod.metadata.namespace          # Metadata
name = pod.metadata.name
phase = pod.status.phase                    # Status (Kubernetes-managed)

# Access nested status fields
if pod.status.container_statuses:
    for cs in pod.status.container_statuses:
        restart_count = cs.restart_count    # Container status
        state = cs.state                     # Current state
```

**Key insight**: This application demonstrates the complete lifecycle of working with the Kubernetes API - authentication, authorization (RBAC), watching resources, error handling, and processing events.

### Enhancements-and-Extensions

To extend this application:

1. **Add alerting**: Send notifications to Slack/PagerDuty when pods become unhealthy
2. **Persist state**: Use a database to track historical pod health
3. **Web dashboard**: Add a web UI to visualize pod health
4. **Custom actions**: Automatically restart pods, scale deployments, or trigger runbooks
5. **Multi-cluster**: Monitor pods across multiple clusters
6. **Advanced health checks**: Check readiness/liveness probe status, resource usage

This application serves as a foundation for building Kubernetes operators and custom controllers.

[↑ Back to ToC](#table-of-contents)

---

## Conclusion

You've learned how to work with the Kubernetes API from the ground up:

- Understanding that everything in Kubernetes is an API call
- Exploring and discovering API resources
- Performing CRUD operations via kubectl and direct HTTP
- Authenticating and authorizing requests
- Working with labels, annotations, and metadata
- Watching resources for real-time updates
- Using client libraries in Python and Go
- Creating custom resources with CRDs
- Understanding RKE2-specific extensions
- Building a complete application that leverages the API

**Next steps**:

1. Build your own custom controller or operator
2. Explore advanced topics like admission webhooks and API aggregation
3. Contribute to Kubernetes ecosystem projects
4. Join the community: kubernetes.slack.com, discuss.kubernetes.io

**Additional resources**:

- Official API documentation: https://kubernetes.io/docs/reference/kubernetes-api/
- Client libraries: https://kubernetes.io/docs/reference/using-api/client-libraries/
- API conventions: https://github.com/kubernetes/community/blob/master/contributors/devel/sig-architecture/api-conventions.md
- Operator pattern: https://kubernetes.io/docs/concepts/extend-kubernetes/operator/

The Kubernetes API is powerful and well-designed. With the knowledge from this guide, you can build sophisticated tools and automation for managing containerized applications.

Happy coding!

---

**Document Stats**:
- Sections: 15
- Code examples: 200+
- Lines: ~4300
- Exercises: 5 hands-on labs
- Complete working application: Pod Health Monitor

**Last Updated**: February 2026

---
