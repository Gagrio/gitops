# Kubernetes Cluster API with SUSE Edge: Complete Beginner's Guide

**Version Information:**
- Cluster API: v1.12 (February 2026)
- SUSE Edge: 3.5
- Kubernetes: 1.29-1.35 (workload), 1.31-1.35 (management)
- RKE2: v1.34.2+rke2r1
- K3s: v1.34.2+k3s1
- Metal3: v1.8 (installed via SUSE Edge Helm charts)
- Rancher Turtles: Installed via SUSE Edge (version varies by release)
- Edge Image Builder: 1.3.2

**Last Updated:** February 2026

**Note on versions:** Specific component versions for Metal3 and Rancher Turtles are managed by SUSE Edge releases and installed via Helm charts from registry.suse.com/edge/. Refer to official SUSE Edge 3.5 documentation for exact versions.

---

## Table-of-Contents

1. [Prerequisites](#prerequisites)
2. [What-is-Cluster-API](#what-is-cluster-api)
3. [Core-CAPI-Concepts](#core-capi-concepts)
4. [CAPI-Architecture-and-Lifecycle](#capi-architecture-and-lifecycle)
5. [Introduction-to-SUSE-Edge](#introduction-to-suse-edge)
6. [SUSE-Edge-and-Cluster-API-Integration](#suse-edge-and-cluster-api-integration)
7. [Metal3-for-Bare-Metal-Provisioning](#metal3-for-bare-metal-provisioning)
8. [Rancher-Turtles-Integration](#rancher-turtles-integration)
9. [Hands-On-Setting-Up-Management-Cluster](#hands-on-setting-up-management-cluster)
10. [Hands-On-Provisioning-Your-First-Workload-Cluster](#hands-on-provisioning-your-first-workload-cluster)
11. [Working-with-ClusterClass](#working-with-clusterclass)
12. [SUSE-Edge-Bare-Metal-Deployment-Walkthrough](#suse-edge-bare-metal-deployment-walkthrough)
13. [Cluster-Lifecycle-Operations](#cluster-lifecycle-operations)
14. [GitOps-Workflows-with-SUSE-Edge](#gitops-workflows-with-suse-edge)
15. [Monitoring-and-Observability](#monitoring-and-observability)
16. [Security-Considerations](#security-considerations)
17. [Advanced-Topics](#advanced-topics)
18. [Practical-Exercises](#practical-exercises)
19. [Common-Mistakes-and-Troubleshooting](#common-mistakes-and-troubleshooting)
20. [Knowledge-Checks-with-Answers](#knowledge-checks-with-answers)
21. [Quick-Reference](#quick-reference)
22. [Additional-Resources](#additional-resources)

---

## Prerequisites

Before diving into Cluster API and SUSE Edge, ensure you have the following tools and access ready.

### Required-Tools

**1. kubectl (v1.29+)**

```bash
# Download latest kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Verify installation
kubectl version --client
```

**2. clusterctl (v1.12+)**

```bash
# Download clusterctl
curl -L https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.12.0/clusterctl-linux-amd64 -o clusterctl
chmod +x clusterctl
sudo mv clusterctl /usr/local/bin/

# Verify installation
clusterctl version
```

**3. helm (v3.10+)**

```bash
# Download and install helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version
```

**4. Additional Utilities**

```bash
# jq for JSON parsing
sudo apt-get install jq -y  # Debian/Ubuntu
sudo yum install jq -y      # RHEL/CentOS

# yq for YAML parsing
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq

# kind for local testing (optional)
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

### Cluster-Access-Requirements

**Management Cluster Options:**

1. **Existing Kubernetes cluster** (recommended for production)
   - Minimum: 2 vCPUs, 4GB RAM, 20GB disk
   - Kubernetes version 1.31+ (management clusters need newer versions)
   - kubectl configured with admin access

2. **kind cluster** (local development/testing)
   - Docker installed and running
   - Sufficient resources on host machine

3. **RKE2 cluster** (SUSE Edge recommended)
   - See SUSE Edge installation guide
   - Can serve as both management and workload cluster

**Network Requirements:**

- Management cluster must reach infrastructure provider APIs (cloud providers, BMCs for bare metal)
- Workload clusters must be routable from management cluster
- Internet access for pulling images (or configured private registry)

### Environment-Verification

Create a verification script to ensure all prerequisites are met:

```bash
#!/bin/bash
# save as check-prereqs.sh

echo "Checking Cluster API prerequisites..."

# Check kubectl
if command -v kubectl &> /dev/null; then
    KUBECTL_VERSION=$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')
    echo "✓ kubectl installed: $KUBECTL_VERSION"
else
    echo "✗ kubectl not found"
    exit 1
fi

# Check clusterctl
if command -v clusterctl &> /dev/null; then
    CLUSTERCTL_VERSION=$(clusterctl version -o short)
    echo "✓ clusterctl installed: $CLUSTERCTL_VERSION"
else
    echo "✗ clusterctl not found"
    exit 1
fi

# Check helm
if command -v helm &> /dev/null; then
    HELM_VERSION=$(helm version --short)
    echo "✓ helm installed: $HELM_VERSION"
else
    echo "✗ helm not found"
    exit 1
fi

# Check cluster access
if kubectl cluster-info &> /dev/null; then
    CLUSTER_VERSION=$(kubectl version -o json | jq -r '.serverVersion.gitVersion')
    echo "✓ Cluster access configured: $CLUSTER_VERSION"
else
    echo "✗ Cannot access Kubernetes cluster"
    exit 1
fi

# Check cluster resources
NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
echo "✓ Cluster has $NODES node(s)"

echo ""
echo "All prerequisites met! Ready to install Cluster API."
```

Run the verification:

```bash
chmod +x check-prereqs.sh
./check-prereqs.sh
```

**Expected output:**
```
Checking Cluster API prerequisites...
✓ kubectl installed: v1.35.0
✓ clusterctl installed: v1.12.0
✓ helm installed: v3.14.0
✓ Cluster access configured: v1.31.0
✓ Cluster has 3 node(s)

All prerequisites met! Ready to install Cluster API.
```

### Configuration-Files

Create a working directory structure:

```bash
mkdir -p ~/capi-workspace/{configs,clusters,templates,logs}
cd ~/capi-workspace

# Create environment file
cat > .env <<EOF
# Cluster API Configuration
export CAPI_VERSION=v1.12.0
export RKE2_PROVIDER_VERSION=v0.9.0
export METAL3_PROVIDER_VERSION=v1.8.0

# Management cluster
export MGMT_CLUSTER_NAME=capi-mgmt
export MGMT_KUBECONFIG=$HOME/.kube/config

# Default workload cluster settings
export CLUSTER_NAME=workload-01
export KUBERNETES_VERSION=v1.35.0
export CONTROL_PLANE_MACHINE_COUNT=3
export WORKER_MACHINE_COUNT=3

# Infrastructure specific (set as needed)
# export AWS_REGION=us-west-2
# export METAL3_BMC_ENDPOINT=https://bmc.example.com
EOF

source .env
```

> **Note:** Always source your environment file when starting a new shell session working with Cluster API.

[↑ Back to ToC](#table-of-contents)

---

## What-is-Cluster-API

Cluster API (CAPI) is a Kubernetes sub-project that brings declarative, Kubernetes-style APIs to cluster creation, configuration, and management. It represents a fundamental shift in how we think about Kubernetes cluster lifecycle management.

### The-Problem-CAPI-Solves

**Before Cluster API:**

Organizations faced significant challenges managing multiple Kubernetes clusters:

1. **Fragmentation:** Each infrastructure provider had its own tooling (kops for AWS, kubeadm for bare metal, GKE CLI for Google Cloud)
2. **Imperative workflows:** Cluster creation involved running commands, not managing resources
3. **No standardization:** Different APIs, configuration formats, and operational patterns
4. **Complex automation:** Building automation required provider-specific scripts and logic
5. **Lifecycle gaps:** Upgrades, scaling, and maintenance had inconsistent patterns

**Example of pre-CAPI complexity:**

```bash
# AWS cluster with kops
kops create cluster --name=prod.k8s.local --state=s3://clusters --zones=us-east-1a
kops update cluster --yes prod.k8s.local
kops rolling-update cluster --yes prod.k8s.local

# GCP cluster with gcloud
gcloud container clusters create prod --zone us-central1-a --num-nodes 3
gcloud container clusters upgrade prod --master --cluster-version 1.35.0

# Bare metal with kubeadm
# ... manual server provisioning ...
kubeadm init --config kubeadm-config.yaml
# ... join worker nodes manually ...
```

Each approach requires different expertise, tooling, and operational procedures.

### The-Cluster-API-Solution

Cluster API introduces **Kubernetes managing Kubernetes** - treating clusters as Kubernetes resources:

```yaml
# With Cluster API - universal approach
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: production-cluster
  namespace: default
spec:
  clusterNetwork:
    pods:
      cidrBlocks: ["10.244.0.0/16"]
    services:
      cidrBlocks: ["10.96.0.0/12"]
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: AWSCluster  # or Metal3Cluster, GCPCluster, etc.
    name: production-cluster
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: production-cluster-control-plane
```

**Key advantages:**

1. **Declarative:** Define desired state in YAML, controllers reconcile
2. **Provider-agnostic:** Same API across AWS, Azure, GCP, bare metal, etc.
3. **GitOps-ready:** Cluster definitions live in Git, standard K8s tooling applies
4. **Kubernetes-native:** Use kubectl, apply standard RBAC, integrate with existing tools
5. **Extensible:** Provider implementations handle infrastructure specifics

### Core-Philosophy

**Kubernetes managing Kubernetes:**

```
┌─────────────────────────────────────────┐
│      Management Cluster                 │
│  ┌───────────────────────────────────┐  │
│  │  CAPI Controllers                 │  │
│  │  - Cluster Controller             │  │
│  │  - Machine Controller             │  │
│  │  - MachineDeployment Controller   │  │
│  └───────────────────────────────────┘  │
│              ↓ manages ↓                │
│  ┌───────────────────────────────────┐  │
│  │  Cluster Resources (CRDs)         │  │
│  │  - Cluster objects                │  │
│  │  - Machine objects                │  │
│  │  - MachineDeployment objects      │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
                  ↓
                  ↓ provisions/manages
                  ↓
┌─────────────────────────────────────────┐
│     Workload Clusters                   │
│  ┌─────────────┐  ┌─────────────┐      │
│  │ Cluster A   │  │ Cluster B   │  ... │
│  └─────────────┘  └─────────────┘      │
└─────────────────────────────────────────┘
```

### When-to-Use-Cluster-API

**Ideal use cases:**

1. **Multi-cluster management:** Managing 5+ clusters across environments
2. **Self-service platforms:** Enabling teams to provision clusters via GitOps
3. **Edge deployments:** Managing hundreds/thousands of edge clusters (SUSE Edge focus)
4. **Hybrid/multi-cloud:** Standardizing cluster management across providers
5. **Automated lifecycle:** Need for automated upgrades, scaling, remediation
6. **Compliance requirements:** Standardized, auditable cluster provisioning

**Example: Edge retail deployment**

A retail chain with 500 stores needs Kubernetes at each location:

```yaml
# ClusterClass-based template approach
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: store-{{.StoreID}}
  namespace: retail-edge
spec:
  topology:
    class: suse-edge-retail  # ClusterClass reference
    version: v1.35.0
    workers:
      machineDeployments:
      - class: edge-worker
        replicas: 2
    variables:
    - name: storeId
      value: "{{.StoreID}}"
    - name: region
      value: "{{.Region}}"
```

Generate 500 clusters from this template with GitOps automation.

### What-Cluster-API-is-NOT

**Common misconceptions:**

1. **NOT a replacement for kubectl:** CAPI manages cluster lifecycle, not workload applications
2. **NOT a Kubernetes distribution:** CAPI provisions clusters; distributions (RKE2, K3s, kubeadm) run inside them
3. **NOT only for cloud:** Bare metal support via Metal3 is production-ready
4. **NOT simple for single clusters:** Overhead may not justify for 1-2 manually managed clusters
5. **NOT zero-configuration:** Requires understanding of Kubernetes and infrastructure

**What you still need:**

- Application deployment tools (Helm, Kustomize, ArgoCD)
- Monitoring and observability (Prometheus, Grafana)
- Policy enforcement (OPA, Kyverno)
- Backup solutions (Velero, etcd backups)
- Certificate management (cert-manager)

### CAPI-and-SUSE-Edge-Together

SUSE Edge integrates Cluster API with Metal3 to enable scalable bare metal cluster provisioning for edge deployments:

**Edge challenges addressed:**

1. **Scale:** Manage thousands of edge locations from central management cluster
2. **Standardization:** Consistent Kubernetes deployment across diverse hardware
3. **Automation:** Zero-touch provisioning for remote sites
4. **Lifecycle:** Automated updates across fleet without site visits
5. **Resilience:** Declarative recovery from failures

**SUSE Edge with CAPI/Metal3 architecture:**

```
┌────────────────────────────────────────────────────────┐
│  Central Management Cluster (Data Center)              │
│  ┌──────────────────────────────────────────────────┐  │
│  │  SUSE Edge Management Stack                      │  │
│  │  - Rancher Multi-Cluster Manager                 │  │
│  │  - Cluster API controllers                       │  │
│  │  - RKE2 bootstrap/control-plane providers        │  │
│  │  - Metal3 infrastructure provider                │  │
│  │  - Rancher Turtles (CAPI ↔ Rancher bridge)      │  │
│  │  - Fleet GitOps (cluster fleet management)       │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘
                       ↓
                 Direct BMC Access
                  (Metal3/CAPI)
                       ↓
┌────────────────────────────────────────────────────────┐
│  Edge Locations (Telco Sites, Data Centers, etc.)      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │
│  │ Edge Site 1 │  │ Edge Site 2 │  │ Edge Site 3 │   │
│  │ RKE2/K3s    │  │ RKE2/K3s    │  │ RKE2/K3s    │   │
│  │ SLE Micro   │  │ SLE Micro   │  │ SLE Micro   │   │
│  └─────────────┘  └─────────────┘  └─────────────┘   │
└────────────────────────────────────────────────────────┘
```

**Key insight:** This guide focuses on SUSE Edge's Cluster API integration with Metal3 for bare metal provisioning. SUSE Edge also supports other provisioning methods (Elemental for phone-home registration, Edge Image Builder for air-gapped deployments) - see SUSE Edge documentation for those workflows.

SUSE Edge combines enterprise-grade OS (SLE Micro), lightweight Kubernetes (RKE2/K3s), and operational tooling (Fleet, Rancher) for comprehensive edge management.

[↑ Back to ToC](#table-of-contents)

---

## Core-CAPI-Concepts

Understanding Cluster API requires familiarity with its core concepts and resource types. This section covers the fundamental building blocks.

### Management-vs-Workload-Clusters

**Management Cluster:**

The Kubernetes cluster where Cluster API components run. It manages the lifecycle of workload clusters.

**Characteristics:**
- Runs CAPI controllers and provider components
- Stores cluster definitions as Kubernetes resources
- Requires stable infrastructure (typically in data center or cloud)
- Minimum K8s version: 1.31+ (as of CAPI v1.12)
- Should have backup and HA configuration

**Workload Cluster:**

The Kubernetes clusters created and managed by the management cluster. These run your actual workloads.

**Characteristics:**
- Provisioned declaratively via management cluster
- Can run any supported K8s version (1.29-1.35 with CAPI v1.12)
- Lifecycle fully managed (create, upgrade, scale, delete)
- Can be on any supported infrastructure provider

```
Management Cluster              Workload Clusters
┌─────────────────┐            ┌─────────────────┐
│ CAPI Controllers│───manages──▶│ Production App  │
│ Provider Comps  │            └─────────────────┘
│ Cluster Objects │            ┌─────────────────┐
└─────────────────┘───manages──▶│ Staging Env     │
                               └─────────────────┘
                               ┌─────────────────┐
                        manages─▶│ Edge Location 1 │
                               └─────────────────┘
```

> **Note:** A cluster can be both management and workload (self-managing), but this is typically only for development/testing.

### Provider-Types

Cluster API uses a provider model to support different infrastructure platforms. There are four provider types:

#### 1-Infrastructure-Providers

Handle infrastructure-specific operations (VMs, networking, load balancers, etc.).

**Popular infrastructure providers:**

| Provider | Use Case | Maturity |
|----------|----------|----------|
| CAPA (AWS) | AWS EC2-based clusters | GA |
| CAPZ (Azure) | Azure VM-based clusters | GA |
| CAPG (GCP) | Google Cloud clusters | GA |
| CAPV (vSphere) | VMware vSphere clusters | GA |
| Metal3 | Bare metal servers | GA |
| CAPRKE2 | RKE2 on any infrastructure | Beta |

**Infrastructure provider resources:**

```yaml
# AWS example
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: AWSCluster
metadata:
  name: my-cluster
spec:
  region: us-west-2
  sshKeyName: my-key

---
# Metal3 example
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3Cluster
metadata:
  name: my-cluster
spec:
  controlPlaneEndpoint:
    host: 192.168.1.100
    port: 6443
  noCloudProvider: true
```

#### 2-Bootstrap-Providers

Handle bootstrapping logic - turning a server into a Kubernetes node.

**Common bootstrap providers:**

- **kubeadm:** Standard Kubernetes bootstrapping (most common)
- **RKE2:** SUSE RKE2 bootstrapping
- **K3s:** Lightweight K3s bootstrapping
- **Talos:** Talos Linux bootstrapping

**Bootstrap provider resources:**

```yaml
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: KubeadmConfig
metadata:
  name: my-machine-bootstrap
spec:
  clusterConfiguration:
    kubernetesVersion: v1.35.0
  initConfiguration:
    nodeRegistration:
      name: '{{ ds.meta_data.hostname }}'
      kubeletExtraArgs:
        cloud-provider: external
  joinConfiguration:
    nodeRegistration:
      name: '{{ ds.meta_data.hostname }}'
      kubeletExtraArgs:
        cloud-provider: external
```

#### 3-Control-Plane-Providers

Manage control plane lifecycle (API server, etcd, controller-manager, scheduler).

**Common control plane providers:**

- **KubeadmControlPlane:** Standard kubeadm-based control plane
- **RKE2ControlPlane:** RKE2-specific control plane management
- **K3sControlPlane:** K3s control plane management

**Control plane provider resources:**

```yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: my-cluster-control-plane
spec:
  replicas: 3
  version: v1.35.0
  machineTemplate:
    infrastructureRef:
      apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
      kind: AWSMachineTemplate
      name: my-cluster-control-plane
  kubeadmConfigSpec:
    clusterConfiguration:
      apiServer:
        extraArgs:
          cloud-provider: external
      controllerManager:
        extraArgs:
          cloud-provider: external
    initConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          cloud-provider: external
    joinConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          cloud-provider: external
```

#### 4-Add-on-Providers

Manage cluster add-ons (CNI, CSI, CCM, etc.). Optional but useful for complete automation.

**Example add-on providers:**

- **Helm:** Deploy Helm charts as part of cluster provisioning
- **ClusterResourceSet:** Apply manifests to new clusters automatically

```yaml
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  name: cni-calico
spec:
  clusterSelector:
    matchLabels:
      cni: calico
  resources:
  - kind: ConfigMap
    name: calico-manifest
```

### Core-Resource-Types

#### Cluster

The top-level resource representing a Kubernetes cluster.

**Key fields:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: my-cluster
  namespace: default
spec:
  # Network configuration
  clusterNetwork:
    pods:
      cidrBlocks: ["10.244.0.0/16"]
    services:
      cidrBlocks: ["10.96.0.0/12"]

  # Reference to infrastructure provider
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
    kind: AWSCluster
    name: my-cluster

  # Reference to control plane
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: my-cluster-control-plane

status:
  phase: Provisioned  # Pending, Provisioning, Provisioned, Deleting, Failed
  infrastructureReady: true
  controlPlaneReady: true
```

**Cluster lifecycle phases:**

1. **Pending:** Cluster created, infrastructure provisioning starting
2. **Provisioning:** Infrastructure being created
3. **Provisioned:** Cluster fully operational
4. **Deleting:** Cluster deletion in progress
5. **Failed:** Cluster provisioning or operation failed

#### Machine

Represents a single Kubernetes node (control plane or worker).

**Key fields:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Machine
metadata:
  name: my-cluster-worker-0
  namespace: default
  labels:
    cluster.x-k8s.io/cluster-name: my-cluster
spec:
  clusterName: my-cluster
  version: v1.35.0

  # Infrastructure reference
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
    kind: AWSMachine
    name: my-cluster-worker-0

  # Bootstrap reference
  bootstrap:
    configRef:
      apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
      kind: KubeadmConfig
      name: my-cluster-worker-0

status:
  phase: Running  # Pending, Provisioning, Running, Deleting, Failed
  nodeRef:
    kind: Node
    name: ip-10-0-1-100.ec2.internal
```

**Machine lifecycle phases:**

1. **Pending:** Machine spec created
2. **Provisioning:** Infrastructure provisioning (VM/server creation)
3. **Running:** Node joined cluster and operational
4. **Deleting:** Machine deletion in progress
5. **Failed:** Machine provisioning failed

> **Key insight:** Machine is CAPI's abstraction, Node is Kubernetes' abstraction. A Machine creates/manages a Node.

#### MachineDeployment

Like a Deployment for Machines - manages a replicated set of Machines with rolling updates.

**Key fields:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: my-cluster-workers
  namespace: default
spec:
  clusterName: my-cluster
  replicas: 3

  selector:
    matchLabels:
      cluster.x-k8s.io/cluster-name: my-cluster
      node-role: worker

  template:
    metadata:
      labels:
        cluster.x-k8s.io/cluster-name: my-cluster
        node-role: worker
    spec:
      clusterName: my-cluster
      version: v1.35.0
      infrastructureRef:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
        kind: AWSMachineTemplate
        name: my-cluster-worker
      bootstrap:
        configRef:
          apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
          kind: KubeadmConfigTemplate
          name: my-cluster-worker

  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
```

**Use cases:**
- Worker node pools
- Rolling updates of worker nodes
- Scaling worker nodes

#### MachineSet

Intermediate resource created by MachineDeployment (similar to ReplicaSet for Deployments). You typically don't create these manually.

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineSet
metadata:
  name: my-cluster-workers-abc123
  namespace: default
  ownerReferences:
  - apiVersion: cluster.x-k8s.io/v1beta1
    kind: MachineDeployment
    name: my-cluster-workers
spec:
  clusterName: my-cluster
  replicas: 3
  selector:
    matchLabels:
      cluster.x-k8s.io/cluster-name: my-cluster
      machine-deployment-hash: abc123
  template:
    # Same as MachineDeployment template
```

#### ClusterClass

Template for creating standardized clusters (introduced in CAPI v1.1, stable in v1.2+).

**Key benefit:** Define cluster topology once, instantiate many times with variables.

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: ClusterClass
metadata:
  name: production-cluster-class
spec:
  # Control plane definition
  controlPlane:
    ref:
      apiVersion: controlplane.cluster.x-k8s.io/v1beta1
      kind: KubeadmControlPlaneTemplate
      name: prod-control-plane-template
    machineInfrastructure:
      ref:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
        kind: AWSMachineTemplate
        name: prod-control-plane-machines

  # Infrastructure definition
  infrastructure:
    ref:
      apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
      kind: AWSClusterTemplate
      name: prod-cluster-template

  # Worker definitions
  workers:
    machineDeployments:
    - class: default-worker
      template:
        bootstrap:
          ref:
            apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
            kind: KubeadmConfigTemplate
            name: prod-worker-bootstrap
        infrastructure:
          ref:
            apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
            kind: AWSMachineTemplate
            name: prod-worker-machines

  # Variables with validation
  variables:
  - name: region
    required: true
    schema:
      openAPIV3Schema:
        type: string
        enum: ["us-east-1", "us-west-2", "eu-central-1"]
  - name: instanceType
    required: false
    schema:
      openAPIV3Schema:
        type: string
        default: "t3.medium"
```

**Using ClusterClass:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: prod-us-west
spec:
  topology:
    class: production-cluster-class
    version: v1.35.0
    controlPlane:
      replicas: 3
    workers:
      machineDeployments:
      - class: default-worker
        name: worker-pool-1
        replicas: 5
    variables:
    - name: region
      value: "us-west-2"
    - name: instanceType
      value: "t3.large"
```

**ClusterClass advantages:**

1. **Standardization:** Enforce organizational standards
2. **Simplification:** Users provide minimal variables, not full specs
3. **Version management:** Update ClusterClass to update all clusters
4. **Validation:** Built-in variable validation
5. **Multi-tenancy:** Different ClusterClasses for different teams/environments

### Resource-Relationships

Understanding how resources relate is crucial:

```
Cluster
  ├─▶ infrastructureRef ───▶ <Provider>Cluster (e.g., AWSCluster)
  │
  ├─▶ controlPlaneRef ───▶ KubeadmControlPlane
  │                          ├─▶ machineTemplate ───▶ <Provider>MachineTemplate
  │                          └─▶ Creates/manages ───▶ Machine (control plane)
  │                                                     ├─▶ infrastructureRef ───▶ <Provider>Machine
  │                                                     ├─▶ bootstrap.configRef ───▶ KubeadmConfig
  │                                                     └─▶ Creates ───▶ Node (in workload cluster)
  │
  └─▶ Referenced by ───▶ MachineDeployment (workers)
                          └─▶ Creates ───▶ MachineSet
                                           └─▶ Creates ───▶ Machine (worker)
                                                            ├─▶ infrastructureRef ───▶ <Provider>Machine
                                                            ├─▶ bootstrap.configRef ───▶ KubeadmConfig
                                                            └─▶ Creates ───▶ Node (in workload cluster)
```

**Key relationships:**

1. **Cluster** is the root object
2. **Cluster** references provider-specific infrastructure and control plane
3. **Control plane provider** manages control plane Machines
4. **MachineDeployment** manages worker Machines
5. **Machine** creates actual Node in workload cluster
6. **Machine** references infrastructure (VM/server) and bootstrap config

[↑ Back to ToC](#table-of-contents)

---

## CAPI-Architecture-and-Lifecycle

Understanding the architecture and lifecycle of Cluster API is essential for effective troubleshooting and advanced usage.

### High-Level-Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                     Management Cluster                             │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │                  CAPI Core Controllers                        │ │
│  │  ┌────────────┐  ┌────────────┐  ┌─────────────────────┐   │ │
│  │  │  Cluster   │  │  Machine   │  │  MachineDeployment  │   │ │
│  │  │ Controller │  │ Controller │  │    Controller       │   │ │
│  │  └────────────┘  └────────────┘  └─────────────────────┘   │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │                Provider-Specific Controllers                  │ │
│  │  ┌──────────────────┐  ┌──────────────────┐                 │ │
│  │  │  Infrastructure  │  │   Bootstrap      │                 │ │
│  │  │    Provider      │  │    Provider      │                 │ │
│  │  │ (AWS/Metal3/etc) │  │ (kubeadm/RKE2)   │                 │ │
│  │  └──────────────────┘  └──────────────────┘                 │ │
│  │  ┌──────────────────┐                                        │ │
│  │  │  Control Plane   │                                        │ │
│  │  │    Provider      │                                        │ │
│  │  │(KubeadmCP/RKE2CP)│                                        │ │
│  │  └──────────────────┘                                        │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │                 Kubernetes API Server                         │ │
│  │                 (stores CAPI resources)                       │ │
│  └──────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
                              ↓
                              ↓ Provisions & Manages
                              ↓
┌────────────────────────────────────────────────────────────────────┐
│                      Workload Cluster                              │
│  ┌───────────────────────┐     ┌───────────────────────┐          │
│  │   Control Plane       │     │   Worker Nodes        │          │
│  │   ┌──────────────┐    │     │   ┌──────────────┐   │          │
│  │   │ API Server   │    │     │   │  Kubelet     │   │          │
│  │   │ etcd         │    │     │   │  Kube-proxy  │   │          │
│  │   │ Controller-  │    │     │   │  CNI         │   │          │
│  │   │   Manager    │    │     │   └──────────────┘   │          │
│  │   │ Scheduler    │    │     │                       │          │
│  │   └──────────────┘    │     └───────────────────────┘          │
│  └───────────────────────┘                                         │
└────────────────────────────────────────────────────────────────────┘
```

### Controller-Reconciliation-Loops

CAPI follows the standard Kubernetes controller pattern: **observe** → **analyze** → **act**.

#### Cluster-Controller

**Responsibility:** Manages Cluster resources and coordinates overall cluster lifecycle.

**Reconciliation logic:**

```
1. Watch Cluster resource
2. If Cluster created/updated:
   a. Validate spec (network CIDRs, references exist)
   b. Create infrastructure if infrastructureRef exists
   c. Wait for infrastructure to be ready (infrastructureReady: true)
   d. Create control plane if controlPlaneRef exists
   e. Wait for control plane to be ready (controlPlaneReady: true)
   f. Update Cluster status.phase to "Provisioned"
   g. Generate kubeconfig for workload cluster
3. If Cluster deleted:
   a. Delete all child resources (Machines, etc.)
   b. Delete control plane
   c. Delete infrastructure
   d. Remove finalizers
```

**Example status progression:**

```bash
# Watch cluster provisioning
kubectl get cluster my-cluster -w

# Output shows progression:
NAME         PHASE         AGE
my-cluster   Pending       5s
my-cluster   Provisioning  15s
my-cluster   Provisioning  45s   # Infrastructure ready
my-cluster   Provisioning  90s   # Control plane initializing
my-cluster   Provisioned   120s  # Cluster ready
```

#### Machine-Controller

**Responsibility:** Manages individual Machine resources (nodes).

**Reconciliation logic:**

```
1. Watch Machine resource
2. If Machine created:
   a. Validate spec (version, references)
   b. Create infrastructure (infrastructureRef)
   c. Wait for infrastructure ready (status.ready: true)
   d. Generate bootstrap data (bootstrap.configRef)
   e. Provision infrastructure with bootstrap data
   f. Wait for Node to appear in workload cluster
   g. Update Machine status with nodeRef
   h. Update phase to "Running"
3. If Machine updated:
   a. Check if in-place update possible (CAPI v1.12+)
   b. If not, perform rolling replacement
4. If Machine unhealthy:
   a. Apply remediation strategy (delete/reboot)
5. If Machine deleted:
   a. Drain node (respect PDBs)
   b. Delete Node from workload cluster
   c. Delete infrastructure
   d. Remove finalizers
```

**Machine health checks:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineHealthCheck
metadata:
  name: my-cluster-worker-health
spec:
  clusterName: my-cluster
  selector:
    matchLabels:
      node-role: worker
  unhealthyConditions:
  - type: Ready
    status: Unknown
    timeout: 5m
  - type: Ready
    status: "False"
    timeout: 5m
  maxUnhealthy: 40%
  nodeStartupTimeout: 10m
  remediationTemplate:
    kind: Metal3RemediationTemplate
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    name: worker-remediation
```

#### MachineDeployment-Controller

**Responsibility:** Manages MachineDeployment resources (like Deployment controller).

**Reconciliation logic:**

```
1. Watch MachineDeployment resource
2. If created/updated:
   a. Create/update MachineSet with desired spec
   b. Scale up new MachineSet
   c. Scale down old MachineSet (if rolling update)
   d. Respect maxUnavailable and maxSurge
   e. Wait for Machines to be Running
   f. Update status.replicas, status.readyReplicas
3. If scaled:
   a. Update current MachineSet replicas
4. If deleted:
   a. Delete all MachineSets
   b. Wait for all Machines to be deleted
   c. Remove finalizers
```

### Cluster-Provisioning-Flow

Detailed step-by-step flow for creating a new cluster:

```
Time  Action                                          Component
────  ──────────────────────────────────────────────  ─────────────────────
t0    User applies Cluster manifest                   kubectl
t1    Cluster created in etcd                         API Server
t2    Cluster Controller detects new Cluster          Cluster Controller
t3    Cluster Controller validates spec               Cluster Controller
t4    Cluster Controller creates infra provider res   Cluster Controller

t5    Infra Provider detects new resource             Infra Provider
t6    Infra Provider creates network/LB/etc           Infra Provider
t10   Infrastructure ready                            Infra Provider
      Infra Provider updates status.ready: true

t11   Cluster Controller detects infra ready          Cluster Controller
t12   Cluster Controller creates control plane        Cluster Controller

t13   Control Plane Provider detects new resource     CP Provider
t14   CP Provider creates first control plane Machine CP Provider
t15   Machine Controller detects new Machine          Machine Controller
t16   Machine Controller creates infra for Machine    Machine Controller

t17   Infra Provider provisions VM/server             Infra Provider
t20   Infrastructure ready for Machine                Infra Provider

t21   Machine Controller detects infra ready          Machine Controller
t22   Bootstrap Provider generates cloud-init         Bootstrap Provider
t23   Machine Controller applies bootstrap data       Machine Controller

t30   Server boots, runs cloud-init                   Workload Node
t35   Kubeadm init runs (first control plane)         Workload Node
t45   Control plane initialized                       Workload Node
t46   Node joins cluster                              Workload Node

t47   Machine Controller detects Node                 Machine Controller
t48   Machine Controller updates Machine status       Machine Controller
      Status.phase: Running, nodeRef: <node>

t49   CP Provider detects first CP ready              CP Provider
t50   CP Provider creates additional CP Machines      CP Provider
      (repeat t15-t48 for each additional node)

t120  All control plane nodes ready                   CP Provider
      CP Provider updates status.ready: true

t121  Cluster Controller detects CP ready             Cluster Controller
t122  Cluster Controller generates kubeconfig         Cluster Controller
t123  Cluster Controller creates Secret               Cluster Controller
t124  Cluster Controller updates Cluster status       Cluster Controller
      Phase: Provisioned

t125  User creates MachineDeployment for workers      kubectl
      (repeat similar flow for worker Machines)
```

**Typical timing (AWS example):**

- Infrastructure creation: 1-2 minutes
- First control plane node: 3-5 minutes
- Additional control plane nodes: 2-3 minutes each
- Worker nodes: 2-3 minutes each (parallel)
- **Total for 3 CP + 3 worker cluster: ~10-15 minutes**

### Machine-State-Transitions

```
          ┌─────────┐
          │ Pending │
          └────┬────┘
               │ Infrastructure provisioning started
               ▼
       ┌──────────────┐
       │ Provisioning │◀──┐
       └──────┬───────┘   │
              │            │ Retry on failure
              │            │
              │ Infrastructure ready + bootstrap complete
              ▼            │
          ┌─────────┐     │
          │ Running │─────┘
          └────┬────┘      Failed health check
               │
               │ Deletion requested OR remediation
               ▼
         ┌──────────┐
         │ Deleting │
         └────┬─────┘
              │ Infrastructure deleted
              ▼
          ┌────────┐
          │ Deleted│ (resource removed)
          └────────┘
```

**Status conditions to monitor:**

```bash
# Check Machine status
kubectl get machine my-cluster-cp-0 -o yaml

# Key status fields:
# status.phase: Current lifecycle phase
# status.nodeRef: Reference to Node in workload cluster
# status.infrastructureReady: Infrastructure provisioned
# status.bootstrapReady: Bootstrap config ready
# status.conditions: Detailed condition history
```

### Upgrade-Strategies

CAPI v1.12 supports multiple upgrade strategies:

#### 1-Rolling-Update-(Default)

New machines created, old machines deleted after new ones are ready.

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: workers
spec:
  replicas: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1  # Max nodes unavailable during update
      maxSurge: 1        # Max extra nodes during update
  template:
    spec:
      version: v1.35.0  # Updated from v1.34.0
```

**Flow:**
1. Create 1 new machine (v1.35.0) - surge
2. Wait for new machine Running
3. Delete 1 old machine (v1.34.0) - respects maxUnavailable
4. Repeat until all machines upgraded

**Pros:** Safe, respects PDBs, minimal disruption
**Cons:** Requires extra capacity (surge), slower

#### 2-In-Place-Updates-(CAPI-v1.12+)

Update existing machines without replacement (provider-dependent).

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: my-cluster
  annotations:
    cluster.x-k8s.io/in-place-upgrade: "true"  # Enable feature
spec:
  topology:
    class: my-class
    version: v1.35.0  # Updated from v1.34.0
```

**Flow:**
1. SSH/remote execute kubeadm upgrade on existing node
2. Restart kubelet with new version
3. No machine replacement

**Pros:** Faster, no extra capacity needed, preserves storage
**Cons:** Riskier, less provider support, harder rollback

#### 3-Chained-Upgrades-(CAPI-v1.12+)

Automatically upgrade through intermediate versions.

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: my-cluster
spec:
  topology:
    class: my-class
    version: v1.35.0  # Jumping from v1.31.0
    variables:
    - name: enableChainedUpgrades
      value: true
```

**Flow:**
1. CAPI detects multi-version jump (v1.31 → v1.35)
2. CAPI automatically upgrades: v1.31 → v1.32 → v1.33 → v1.34 → v1.35
3. Each intermediate upgrade follows normal process

**Pros:** Handles skipped versions automatically
**Cons:** Takes longer, requires supported version matrix

> **Key insight:** Always upgrade control plane before workers. CAPI enforces this ordering automatically.

[↑ Back to ToC](#table-of-contents)

---

## Introduction-to-SUSE-Edge

SUSE Edge is an enterprise-grade platform for deploying and managing Kubernetes at the edge. It's built on a foundation of proven SUSE technologies and integrates seamlessly with Cluster API.

### What-is-SUSE-Edge

SUSE Edge is **not just a telco solution** - it's a comprehensive edge computing platform for any industry requiring distributed Kubernetes deployments.

**Core value proposition:**

1. **Lightweight OS:** SLE Micro - immutable, minimal footprint
2. **Lightweight K8s:** RKE2 or K3s - production-ready, resource-efficient
3. **Centralized management:** Rancher + Fleet for multi-cluster management
4. **Declarative lifecycle:** Cluster API + GitOps for automation
5. **Enterprise support:** SUSE backing with SLAs and certification

**SUSE Edge != Rancher**

While SUSE Edge can integrate with Rancher, they serve different purposes:

```
Rancher: Multi-cluster management UI and API
         Works with any Kubernetes distribution
         Focused on Day 2 operations (monitoring, RBAC, catalogs)

SUSE Edge: Complete edge platform
           Opinionated stack (SLE Micro + RKE2/K3s)
           Focused on Day 0-2 (provisioning + operations)
           Optimized for edge constraints
```

### SUSE-Edge-Provisioning-Methods

SUSE Edge supports three distinct provisioning approaches, each optimized for different deployment scenarios:

#### 1-Directed-Network-Provisioning-(CAPI-+-Metal3)

**What it is:** Fully automated provisioning from a centralized location when you have direct access to bare-metal hardware management interfaces.

**How it works:**
- Management cluster has out-of-band access to server BMCs (Redfish/IPMI)
- Metal3 discovers and inventories bare-metal servers
- CAPI orchestrates cluster provisioning declaratively
- Zero-touch deployment once hardware is racked and cabled

**Best suited for:**
- Data center deployments with BMC-equipped servers
- Controlled environments with network management access
- Telecommunications infrastructure with known hardware inventory
- Regulated industries requiring full automation and audit trails

**Example use cases:**
- 5G edge compute nodes in telecom networks
- Edge data centers with standardized hardware
- Manufacturing facilities with IT-managed infrastructure

```
┌─────────────────────────────────────────────┐
│     Management Cluster (Data Center)        │
│  ┌───────────────────────────────────────┐  │
│  │  CAPI + Metal3 + Rancher Turtles     │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
                  ↓
          Direct BMC Access (Redfish)
                  ↓
┌─────────────────────────────────────────────┐
│     Edge Sites with BMC-enabled servers     │
│  ┌───────┐  ┌───────┐  ┌───────┐           │
│  │Server1│  │Server2│  │Server3│           │
│  │+ BMC  │  │+ BMC  │  │+ BMC  │           │
│  └───────┘  └───────┘  └───────┘           │
└─────────────────────────────────────────────┘
```


### Use-Cases-Beyond-Telco

#### 1-Retail-Edge

**Scenario:** 1,000 retail stores, each needs Kubernetes for POS, inventory, local AI inference.

**Requirements:**
- Consistent deployment across all stores
- Zero-touch provisioning (no IT staff on-site)
- Automated updates during off-hours
- Resilient to network outages
- Low hardware footprint

**SUSE Edge with CAPI solution:**

```yaml
# ClusterClass-based deployment for retail edge
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: retail-store-001
  namespace: retail-fleet
spec:
  topology:
    class: retail-edge
    version: v1.35.0
    workers:
      machineDeployments:
      - class: retail-worker
        replicas: 2
    variables:
    - name: storeId
      value: "STORE-001"
    - name: region
      value: "us-west"
```

#### 2-Manufacturing-Edge

**Scenario:** Factory floor with 50 zones, each needs Kubernetes for SCADA, MES integration, quality control vision AI.

**Requirements:**
- Real-time capabilities (low latency)
- Air-gapped deployment (security requirement)
- Integration with OT protocols (OPC-UA, MQTT)
- Ruggedized hardware support
- Strict change control

**SUSE Edge with CAPI solution:**

```yaml
# Air-gapped configuration for manufacturing
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: factory-zone-1
  namespace: manufacturing
spec:
  topology:
    class: manufacturing-edge
    version: v1.35.0
    variables:
    - name: imageRegistry
      value: "factory-registry.local:5000"  # Local registry
    - name: ntpServers
      value: ["10.0.0.1", "10.0.0.2"]  # Local NTP
    - name: dnsServers
      value: ["10.0.0.10"]
    - name: proxyConfig
      value: ""  # No proxy in air-gapped
```

#### 3-Energy-and-Utilities

**Scenario:** 500 solar farms and wind turbines, each needs Kubernetes for monitoring, predictive maintenance, grid integration.

**Requirements:**
- Intermittent connectivity
- Harsh environmental conditions
- Decades-long hardware lifecycle
- Compliance requirements (NERC CIP)
- Remote management

**SUSE Edge with CAPI solution:**

```yaml
# Resilient configuration for intermittent connectivity
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: solar-farm-tx-001
  namespace: energy-fleet
spec:
  topology:
    class: energy-edge
    version: v1.35.0
    variables:
    - name: offlineMode
      value: "true"  # Tolerate mgmt cluster disconnect
    - name: localDataRetention
      value: "30d"  # Buffer data during outages
    - name: autoCertRotation
      value: "true"  # No manual intervention
```

#### 4-Smart-Buildings

**Scenario:** 200 commercial buildings, each needs Kubernetes for BMS, IoT devices, occupancy AI, energy optimization.

**Requirements:**
- Minimal hardware budget per site
- Integration with existing BACnet/Modbus systems
- Multi-tenancy (building management + tenant apps)
- Automated provisioning by contractors

**SUSE Edge with CAPI solution:**

```yaml
# Minimal footprint with K3s
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: building-downtown-01
  namespace: smart-buildings
spec:
  topology:
    class: building-edge-k3s
    version: v1.35.0
    variables:
    - name: buildingId
      value: "BLDG-DT-01"
    - name: maxPods
      value: "50"
    - name: datastoreType
      value: "embedded"  # SQLite for small deployments
```

### SUSE-Edge-Component-Stack

```
┌─────────────────────────────────────────────────────────────┐
│                    Management Layer                         │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Rancher Multi-Cluster Manager                        │  │
│  │  - Web UI                                             │  │
│  │  - RBAC                                               │  │
│  │  - App Catalog                                        │  │
│  │  - Monitoring                                         │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Fleet (GitOps Controller)                            │  │
│  │  - Cluster registration                               │  │
│  │  - Configuration management                           │  │
│  │  - Multi-cluster deployment                           │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Cluster API Provisioning (CAPI + Metal3)             │  │
│  │  - Cluster API controllers                            │  │
│  │  - CAPRKE2/CAPK3s (RKE2/K3s providers)                │  │
│  │  - Metal3 (bare metal infrastructure provider)        │  │
│  │  - Rancher Turtles (CAPI ↔ Rancher bridge)           │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                          ↓ Manages
┌─────────────────────────────────────────────────────────────┐
│                    Edge Cluster (per site)                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Kubernetes Distribution                              │  │
│  │  - RKE2 (production workloads)                        │  │
│  │  - K3s (ultra-lightweight)                            │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Operating System                                     │  │
│  │  - SLE Micro (SUSE Linux Enterprise Micro)            │  │
│  │    * Immutable OS                                     │  │
│  │    * Transactional updates                            │  │
│  │    * Minimal attack surface                           │  │
│  │    * ~350MB footprint                                 │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Hardware                                             │  │
│  │  - x86_64 or ARM64                                    │  │
│  │  - Bare metal or VM                                   │  │
│  │  - Minimum: 2 vCPU, 2GB RAM, 20GB disk               │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### SLE-Micro-Details

**What makes SLE Micro ideal for edge:**

1. **Immutable root filesystem**
   - Root FS mounted read-only
   - Changes applied as transactional snapshots
   - Automatic rollback on failure

2. **Minimal footprint**
   - Base image: ~350MB
   - No GUI, documentation, development tools
   - Only essential packages

3. **Transactional updates**
   ```bash
   # Update process on edge node
   transactional-update pkg install podman
   # Creates new snapshot
   # Reboot to activate new snapshot
   # Old snapshot available for rollback
   ```

4. **Security hardening**
   - SELinux or AppArmor enforcing
   - No SSH by default (combustion for initial config)
   - Regular CVE patching

5. **Long-term support**
   - 10+ year lifecycle
   - Predictable update schedule
   - Enterprise support

### RKE2-vs-K3s-Decision-Matrix

| Criteria | RKE2 | K3s |
|----------|------|-----|
| **Footprint** | ~600MB | ~200MB |
| **Control plane HA** | Native (etcd) | Native (embedded DB or etcd) |
| **CIS compliance** | Built-in CIS hardening | Manual hardening needed |
| **FIPS 140-2** | Available | Not available |
| **Use case** | Production, regulated | Development, ultra-constrained |
| **Support** | Full SUSE support | Community + SUSE support |
| **Multi-master** | Recommended 3+ | Works with 1 (embedded DB) |

**Recommendation:**
- **RKE2:** Production edge deployments, compliance requirements, >2GB RAM
- **K3s:** Development, testing, extreme constraints (<2GB RAM), single-node

### Why-CAPI-and-Metal3-for-Edge

SUSE Edge integrates Cluster API with Metal3 to provide declarative, scalable bare metal provisioning:

**Benefits of CAPI/Metal3 for edge deployments:**

1. **Scale:** Managing thousands of edge clusters from a central management cluster
2. **Automation:** Full automation when hardware management interfaces (BMC) are available
3. **Declarative:** Kubernetes-native API for infrastructure provisioning and lifecycle management
4. **GitOps-native:** Edge cluster configurations live in Git repositories
5. **Vendor-neutral:** Not locked into proprietary management APIs
6. **Continuous reconciliation:** Prevents configuration drift across the fleet

**Key capabilities:**

- Automated bare metal server provisioning via BMC (Redfish, IPMI)
- Consistent cluster deployment across diverse hardware
- Declarative cluster lifecycle management (create, upgrade, scale, delete)
- Integration with Rancher for multi-cluster visibility and management
- Fleet GitOps for configuration management at scale

> **Note:** SUSE Edge also provides alternative provisioning methods (Elemental for phone-home registration, Edge Image Builder for air-gapped deployments) for scenarios where different deployment models are needed. See the SUSE Edge documentation for details on those approaches.

[↑ Back to ToC](#table-of-contents)

---

## SUSE-Edge-and-Cluster-API-Integration

SUSE Edge deeply integrates with Cluster API through custom providers and extensions. This section covers how the integration works and how to leverage it.

### CAPRKE2-Provider-Deep-Dive

CAPRKE2 is the Cluster API provider for RKE2 and K3s. It implements both bootstrap and control plane providers.

**Repository:** https://github.com/rancher/cluster-api-provider-rke2

**Components:**

1. **RKE2BootstrapProvider** - Generates RKE2/K3s bootstrap configuration
2. **RKE2ControlPlaneProvider** - Manages RKE2/K3s control plane lifecycle

**Installation:**

```bash
# Install CAPRKE2 with clusterctl
clusterctl init --bootstrap rke2 --control-plane rke2

# Verify installation
kubectl get pods -n rke2-bootstrap-system
kubectl get pods -n rke2-control-plane-system
```

**Expected output:**

```
NAMESPACE                       NAME                                                    READY   STATUS
rke2-bootstrap-system           rke2-bootstrap-controller-manager-xxx                   1/1     Running
rke2-control-plane-system       rke2-control-plane-controller-manager-xxx               1/1     Running
```

#### RKE2-Bootstrap-Configuration

**RKE2Config** generates cloud-init or ignition config for RKE2:

```yaml
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: RKE2Config
metadata:
  name: my-cluster-worker-config
  namespace: default
spec:
  # RKE2-specific configuration
  agentConfig:
    version: v1.35.0+rke2r1
    nodeName: '{{ ds.meta_data.hostname }}'
    nodeLabels:
    - environment=production
    - workload=inference
    nodeTaints:
    - key: gpu
      value: "true"
      effect: NoSchedule
    kubeletArgs:
    - "max-pods=110"
    - "kube-reserved=cpu=200m,memory=512Mi"
    - "system-reserved=cpu=200m,memory=512Mi"

    # RKE2-specific settings
    runtimeImage: "rancher/rke2-runtime:v1.35.0-rke2r1"

    # Additional manifests to deploy
    additionalManifests:
      enabled: true
      manifests:
      - https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

  # Pre-RKE2 commands (run before RKE2 installation)
  preRKE2Commands:
  - "sysctl -w net.ipv4.ip_forward=1"
  - "modprobe br_netfilter"
  - "echo 'br_netfilter' > /etc/modules-load.d/br_netfilter.conf"

  # Post-RKE2 commands (run after RKE2 installation)
  postRKE2Commands:
  - "kubectl label node $(hostname) node-role.kubernetes.io/worker=true"

  # Files to write before RKE2 starts
  files:
  - path: /etc/rancher/rke2/config.yaml.d/99-custom.yaml
    owner: root:root
    permissions: "0600"
    content: |
      write-kubeconfig-mode: "0644"
      tls-san:
      - my-cluster.example.com
      disable:
      - rke2-ingress-nginx

  - path: /etc/rancher/rke2/registries.yaml
    owner: root:root
    permissions: "0600"
    content: |
      mirrors:
        docker.io:
          endpoint:
          - "https://registry.example.com"
      configs:
        "registry.example.com":
          auth:
            username: registry-user
            password: registry-pass

  # Private registry configuration
  privateRegistriesConfig:
    mirrors:
      docker.io:
        endpoint:
        - https://registry.example.com
    configs:
      registry.example.com:
        auth:
          username: registry-user
          password: registry-pass
        tls:
          insecureSkipVerify: false
```

**For control plane nodes (first node):**

```yaml
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: RKE2Config
metadata:
  name: my-cluster-control-plane-init
spec:
  serverConfig:
    version: v1.35.0+rke2r1
    cni: calico
    cloudProviderName: external

    # etcd configuration
    etcd:
      exposeMetrics: true
      backupConfig:
        enabled: true
        directory: /var/lib/rancher/rke2/server/db/etcd-snapshots
        retention: 5
        scheduleCron: "0 */12 * * *"

    # Control plane components
    kubeAPIServer:
      extraArgs:
      - "oidc-issuer-url=https://dex.example.com"
      - "oidc-client-id=kubernetes"
      - "oidc-username-claim=email"
      - "oidc-groups-claim=groups"
      - "audit-log-path=/var/log/kubernetes/audit.log"
      - "audit-log-maxage=30"
      extraMounts:
      - name: audit-log
        hostPath: /var/log/kubernetes
        mountPath: /var/log/kubernetes

    kubeControllerManager:
      extraArgs:
      - "node-monitor-grace-period=40s"
      - "pod-eviction-timeout=5m"

    kubeScheduler:
      extraArgs:
      - "v=2"

    # TLS SANs
    tlsSan:
    - my-cluster.example.com
    - 192.168.1.100

  files:
  - path: /var/lib/rancher/rke2/server/manifests/kube-vip.yaml
    owner: root:root
    permissions: "0600"
    content: |
      apiVersion: v1
      kind: Pod
      metadata:
        name: kube-vip
        namespace: kube-system
      spec:
        containers:
        - name: kube-vip
          image: ghcr.io/kube-vip/kube-vip:v0.7.0
          args:
          - manager
          env:
          - name: vip_interface
            value: eth0
          - name: vip_arp
            value: "true"
          - name: address
            value: "192.168.1.100"
          securityContext:
            capabilities:
              add:
              - NET_ADMIN
              - NET_RAW
          volumeMounts:
          - mountPath: /etc/kubernetes/admin.conf
            name: kubeconfig
        hostNetwork: true
        volumes:
        - name: kubeconfig
          hostPath:
            path: /etc/rancher/rke2/rke2.yaml
```

**For joining control plane nodes:**

```yaml
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: RKE2Config
metadata:
  name: my-cluster-control-plane-join
spec:
  serverConfig:
    version: v1.35.0+rke2r1
  # Cluster will provide token and server URL automatically
```

#### RKE2-Control-Plane-Management

**RKE2ControlPlane** manages the control plane lifecycle:

```yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: RKE2ControlPlane
metadata:
  name: my-cluster-control-plane
  namespace: default
spec:
  # Desired control plane replicas
  replicas: 3

  # RKE2 version
  version: v1.35.0+rke2r1

  # Reference to infrastructure template for control plane machines
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: Metal3MachineTemplate
    name: my-cluster-control-plane

  # RKE2 configuration
  serverConfig:
    cni: calico
    cloudProviderName: external

    # etcd configuration
    etcd:
      exposeMetrics: true
      backupConfig:
        enabled: true
        retention: 10
        scheduleCron: "0 */6 * * *"
        directory: /var/lib/rancher/rke2/server/db/snapshots
        s3Config:
          bucket: my-etcd-backups
          endpoint: s3.amazonaws.com
          folder: my-cluster
          region: us-west-2
          accessKey:
            name: etcd-backup-creds
            key: access-key
          secretKey:
            name: etcd-backup-creds
            key: secret-key

    # Disable built-in components
    disable:
    - rke2-ingress-nginx  # Will use custom ingress
    - rke2-metrics-server  # Will use custom metrics-server

    # TLS SANs
    tlsSan:
    - my-cluster-api.example.com
    - 10.0.0.100  # VIP address

    # API server arguments
    kubeAPIServer:
      extraArgs:
      - "enable-admission-plugins=NodeRestriction,PodSecurityPolicy"
      - "audit-log-path=/var/log/kubernetes/audit.log"
      - "audit-log-maxage=30"
      - "audit-log-maxbackup=10"
      - "audit-log-maxsize=100"

  # Files to add to control plane nodes
  files:
  - path: /etc/rancher/rke2/registries.yaml
    owner: root:root
    permissions: "0600"
    contentFrom:
      secret:
        name: registry-config
        key: registries.yaml

  # Pre/post commands
  preRKE2Commands:
  - "systemctl stop firewalld"
  - "setenforce 0"

  postRKE2Commands:
  - "kubectl label node $(hostname) node-role.kubernetes.io/control-plane=true"

  # Registration method for nodes joining
  registrationMethod: "control-plane-endpoint"  # or "internal-first-node"

  # Rollout strategy
  rolloutStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1

  # Machine health check
  machineHealthCheck:
    maxUnhealthy: 33%
    unhealthyConditions:
    - type: Ready
      status: Unknown
      timeout: 5m
    - type: Ready
      status: "False"
      timeout: 5m
    nodeStartupTimeout: 10m
```

**Control plane provisioning flow:**

```
1. RKE2ControlPlane controller creates first Machine
2. Machine controller provisions infrastructure
3. RKE2 bootstrap creates init config (cluster init)
4. First node starts RKE2 server (kubeadm init equivalent)
5. etcd initialized, API server starts
6. RKE2ControlPlane controller detects first node ready
7. Controller creates additional Machines (replicas - 1)
8. Additional nodes join using cluster token
9. Control plane reaches desired replicas
10. RKE2ControlPlane status.ready = true
```

#### CAPRKE2-with-Multiple-Infrastructure-Providers

CAPRKE2 works with any infrastructure provider:

**With Metal3 (bare metal):**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: edge-cluster
spec:
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: Metal3Cluster
    name: edge-cluster
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: RKE2ControlPlane  # RKE2 on bare metal
    name: edge-cluster-cp
```

**With AWS (cloud):**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: cloud-cluster
spec:
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
    kind: AWSCluster
    name: cloud-cluster
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: RKE2ControlPlane  # RKE2 on AWS
    name: cloud-cluster-cp
```

**With Docker (local testing):**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: local-cluster
spec:
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: DockerCluster
    name: local-cluster
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: RKE2ControlPlane  # RKE2 in Docker
    name: local-cluster-cp
```

### ClusterClass-Usage-in-SUSE-Edge

SUSE Edge extensively uses ClusterClass for standardization. Here's a production-ready example:

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: ClusterClass
metadata:
  name: suse-edge-production
  namespace: default
spec:
  # Control plane definition
  controlPlane:
    ref:
      apiVersion: controlplane.cluster.x-k8s.io/v1beta1
      kind: RKE2ControlPlaneTemplate
      name: suse-edge-control-plane
    machineInfrastructure:
      ref:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: Metal3MachineTemplate
        name: suse-edge-control-plane-machines
    machineHealthCheck:
      maxUnhealthy: 33%
      nodeStartupTimeout: 10m
      unhealthyConditions:
      - type: Ready
        status: Unknown
        timeout: 5m
      - type: Ready
        status: "False"
        timeout: 5m

  # Infrastructure definition
  infrastructure:
    ref:
      apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
      kind: Metal3ClusterTemplate
      name: suse-edge-cluster

  # Worker definitions (multiple classes for different roles)
  workers:
    machineDeployments:
    - class: standard-worker
      template:
        bootstrap:
          ref:
            apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
            kind: RKE2ConfigTemplate
            name: suse-edge-worker-bootstrap
        infrastructure:
          ref:
            apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
            kind: Metal3MachineTemplate
            name: suse-edge-standard-workers
      machineHealthCheck:
        maxUnhealthy: 40%
        nodeStartupTimeout: 10m
        unhealthyConditions:
        - type: Ready
          status: Unknown
          timeout: 5m

    - class: gpu-worker
      template:
        bootstrap:
          ref:
            apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
            kind: RKE2ConfigTemplate
            name: suse-edge-gpu-worker-bootstrap
        infrastructure:
          ref:
            apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
            kind: Metal3MachineTemplate
            name: suse-edge-gpu-workers
      machineHealthCheck:
        maxUnhealthy: 40%
        nodeStartupTimeout: 15m

  # Patches for customization
  patches:
  - name: regionPatch
    description: "Set region-specific configuration"
    enabledIf: '{{ if .region }}true{{ end }}'
    definitions:
    - selector:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: Metal3ClusterTemplate
        matchResources:
          infrastructureCluster: true
      jsonPatches:
      - op: add
        path: /spec/template/spec/region
        valueFrom:
          variable: region

  - name: registryPatch
    description: "Configure private registry"
    enabledIf: '{{ if .privateRegistry }}true{{ end }}'
    definitions:
    - selector:
        apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
        kind: RKE2ConfigTemplate
        matchResources:
          controlPlane: true
          machineDeploymentClass:
            names:
            - standard-worker
            - gpu-worker
      jsonPatches:
      - op: add
        path: /spec/template/spec/privateRegistriesConfig
        valueFrom:
          template: |
            mirrors:
              docker.io:
                endpoint:
                - "{{ .privateRegistry }}"

  # Variables with validation and defaults
  variables:
  - name: region
    required: true
    schema:
      openAPIV3Schema:
        type: string
        enum:
        - us-west
        - us-east
        - eu-central
        - ap-southeast

  - name: privateRegistry
    required: false
    schema:
      openAPIV3Schema:
        type: string
        pattern: '^https?://.*'
        default: ""

  - name: kubernetesVersion
    required: true
    schema:
      openAPIV3Schema:
        type: string
        pattern: '^v1\.(29|30|31|32|33|34|35)\.[0-9]+\+rke2r[0-9]+$'
        default: "v1.35.0+rke2r1"

  - name: controlPlaneEndpoint
    required: true
    schema:
      openAPIV3Schema:
        type: string
        format: ipv4

  - name: podCIDR
    required: false
    schema:
      openAPIV3Schema:
        type: string
        default: "10.244.0.0/16"

  - name: serviceCIDR
    required: false
    schema:
      openAPIV3Schema:
        type: string
        default: "10.96.0.0/12"
```

**Using the ClusterClass:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: factory-floor-01
  namespace: manufacturing
spec:
  topology:
    class: suse-edge-production
    version: v1.35.0+rke2r1

    controlPlane:
      replicas: 3

    workers:
      machineDeployments:
      - class: standard-worker
        name: general-workers
        replicas: 5
      - class: gpu-worker
        name: ai-workers
        replicas: 2

    variables:
    - name: region
      value: "us-west"
    - name: privateRegistry
      value: "https://registry.factory.local:5000"
    - name: controlPlaneEndpoint
      value: "10.10.1.100"
    - name: podCIDR
      value: "10.244.0.0/16"
    - name: serviceCIDR
      value: "10.96.0.0/12"
```

This single manifest creates a complete cluster with 3 control plane nodes, 5 standard workers, and 2 GPU workers, all configured for the specific region and private registry.

### Fleet-GitOps-Integration

SUSE Edge uses Rancher Fleet for GitOps-based cluster and application management.

**Architecture:**

```
┌───────────────────────────────────────────────────────────┐
│  Management Cluster                                       │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  Fleet Controller                                   │  │
│  │  - Watches Git repositories                         │  │
│  │  - Creates CAPI resources                           │  │
│  │  - Manages cluster lifecycle                        │  │
│  └─────────────────────────────────────────────────────┘  │
│                        ↓                                  │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  CAPI Controllers                                   │  │
│  │  - Provisions clusters from Fleet-created resources │  │
│  └─────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────┘
              ↑ Pull cluster configs
┌─────────────┴─────────────┐
│  Git Repository            │
│  clusters/                 │
│    ├── cluster1.yaml       │
│    ├── cluster2.yaml       │
│    └── fleet.yaml          │
└────────────────────────────┘
```

**Fleet configuration:**

```yaml
# fleet.yaml - Fleet bundle configuration
defaultNamespace: edge-clusters

targetCustomizations:
- name: retail-stores
  clusterSelector:
    matchLabels:
      environment: production
      type: retail

  helm:
    values:
      clusterClass: suse-edge-retail
      workerCount: 2
      controlPlaneEndpoint: "{{ .ClusterLabels.vip }}"

- name: manufacturing-sites
  clusterSelector:
    matchLabels:
      environment: production
      type: manufacturing

  helm:
    values:
      clusterClass: suse-edge-manufacturing
      workerCount: 5
      controlPlaneEndpoint: "{{ .ClusterLabels.vip }}"
```

**Git repository structure:**

```
gitops-repo/
├── fleet.yaml
├── clusters/
│   ├── base/
│   │   ├── clusterclass.yaml
│   │   └── kustomization.yaml
│   ├── retail/
│   │   ├── store-001.yaml
│   │   ├── store-002.yaml
│   │   └── kustomization.yaml
│   └── manufacturing/
│       ├── factory-01.yaml
│       ├── factory-02.yaml
│       └── kustomization.yaml
└── applications/
    ├── monitoring/
    │   └── prometheus-stack.yaml
    └── edge-apps/
        └── inference-service.yaml
```

**Register Git repo with Fleet:**

```bash
# Create GitRepo resource
kubectl apply -f - <<EOF
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: edge-clusters
  namespace: fleet-default
spec:
  repo: https://github.com/myorg/edge-gitops
  branch: main
  paths:
  - clusters
  targets:
  - clusterSelector:
      matchLabels:
        fleet.cattle.io/managed: "true"
EOF
```

**Workflow:**

1. Developer/operator commits cluster YAML to Git
2. Fleet controller detects change
3. Fleet creates CAPI resources in management cluster
4. CAPI provisions workload cluster
5. Once cluster ready, Fleet deploys applications to it
6. Drift detection: Fleet continuously reconciles desired state

[↑ Back to ToC](#table-of-contents)

---

## Metal3-for-Bare-Metal-Provisioning

Metal3 provides Kubernetes-native bare metal provisioning for Cluster API. It's essential for SUSE Edge deployments on physical hardware.

### Why-Bare-Metal-at-Edge

**Edge requirements favor bare metal:**

1. **Cost:** No cloud provider costs, no hypervisor licensing
2. **Performance:** Direct hardware access, no virtualization overhead
3. **Reliability:** Fewer software layers, predictable behavior
4. **Security:** Physical control, air-gapped possible
5. **Latency:** Critical for real-time edge workloads
6. **Longevity:** Hardware lifecycle measured in years/decades

**Challenges Metal3 solves:**

- Heterogeneous hardware (different vendors, BMC types)
- Remote provisioning (no physical access)
- Automated lifecycle (provision, repurpose, decommission)
- Failure remediation (automatic recovery)
- Inventory management (track hardware state)

### Metal3-Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Management Cluster                                          │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  CAPI Core Controllers                                 │  │
│  └────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Metal3 CAPI Provider (CAPM3)                          │  │
│  │  - Metal3Cluster controller                            │  │
│  │  - Metal3Machine controller                            │  │
│  │  - Metal3MachineTemplate controller                    │  │
│  └────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Bare Metal Operator (BMO)                             │  │
│  │  - BareMetalHost controller                            │  │
│  │  - Hardware inspection                                 │  │
│  │  - Provisioning orchestration                          │  │
│  └────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Ironic (OpenStack Bare Metal)                         │  │
│  │  - ironic-api                                          │  │
│  │  - ironic-conductor                                    │  │
│  │  - ironic-inspector                                    │  │
│  │  - ironic-dnsmasq (DHCP/PXE)                           │  │
│  │  - httpd (image server)                                │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
                        ↓ BMC Communication
                        ↓ (Redfish/IPMI)
┌──────────────────────────────────────────────────────────────┐
│  Physical Bare Metal Servers                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │   Server 1  │  │   Server 2  │  │   Server N  │          │
│  │   BMC       │  │   BMC       │  │   BMC       │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
└──────────────────────────────────────────────────────────────┘
```

**Components:**

1. **Bare Metal Operator (BMO):** Kubernetes operator managing BareMetalHost resources
2. **Ironic:** OpenStack bare metal provisioning service (runs in containers)
3. **CAPM3:** Cluster API provider implementing Metal3Cluster and Metal3Machine
4. **Image server:** HTTP server hosting OS images for provisioning

### Core-Metal3-Resources

#### BareMetalHost

Represents a physical server. Created manually or via discovery.

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: edge-server-01
  namespace: metal3
  labels:
    environment: production
    site: factory-floor-1
spec:
  # BMC connection details
  bmc:
    address: redfish://192.168.1.101/redfish/v1/Systems/1
    credentialsName: edge-server-01-bmc-secret
    disableCertificateVerification: false

  # Boot configuration
  bootMACAddress: "00:1a:2b:3c:4d:5e"
  bootMode: UEFI  # or legacy

  # Hardware profile (optional, for filtering)
  hardwareProfile: "dell-r640"

  # Online state
  online: true  # Set to false to power off

  # Image to provision (set by Metal3Machine controller)
  image:
    url: http://image-server.metal3.svc/sle-micro-5.5-rke2.qcow2
    checksum: http://image-server.metal3.svc/sle-micro-5.5-rke2.qcow2.sha256sum
    checksumType: sha256
    format: qcow2

  # User data (cloud-init/ignition)
  userData:
    name: edge-server-01-userdata
    namespace: metal3

  # Network data (optional)
  networkData:
    name: edge-server-01-networkdata
    namespace: metal3

  # Automated cleaning (wipe disks between uses)
  automatedCleaningMode: metadata  # or disabled

  # Root device hints (which disk to use)
  rootDeviceHints:
    deviceName: "/dev/sda"
    # Or use hints:
    # minSizeGigabytes: 500
    # rotational: false  # SSD
    # model: "Samsung SSD"

status:
  # Current state
  operationalStatus: OK  # OK, discovered, error, ...
  provisioning:
    state: provisioned  # Lifecycle state (see below)
    ID: "abc-123"
    image:
      url: http://image-server.metal3.svc/sle-micro-5.5-rke2.qcow2

  # Hardware details (from inspection)
  hardware:
    systemVendor:
      manufacturer: "Dell Inc."
      productName: "PowerEdge R640"
      serialNumber: "ABC123"
    firmware:
      bios:
        date: "10/17/2023"
        vendor: "Dell Inc."
        version: "2.19.1"
    ramMebibytes: 65536
    nics:
    - name: "eno1"
      mac: "00:1a:2b:3c:4d:5e"
      ip: "192.168.1.201"
      speedGbps: 10
    storage:
    - name: "/dev/sda"
      sizeBytes: 1000204886016
      model: "Samsung SSD 960"
      rotational: false
    cpu:
      arch: "x86_64"
      model: "Intel(R) Xeon(R) Gold 6140"
      clockMegahertz: 2300
      count: 36
      flags:
      - "aes"
      - "avx"
      - "avx2"

  # Power status
  poweredOn: true

  # Error message (if any)
  errorMessage: ""
  errorType: ""
```

**BMC credential secret:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: edge-server-01-bmc-secret
  namespace: metal3
type: Opaque
stringData:
  username: "root"
  password: "calvin"  # Dell iDRAC default (change in production!)
```

**BareMetalHost lifecycle states:**

```
registering → inspecting → available → provisioning → provisioned
     ↓            ↓            ↓            ↓             ↓
   [discovering] [testing]  [ready]     [writing]    [deployed]
                                           ↓
                                       [cleaning] ← deprovisioning
```

| State | Description |
|-------|-------------|
| **registering** | BMC connection established, awaiting inspection |
| **inspecting** | Hardware inspection in progress |
| **available** | Ready to be provisioned |
| **provisioning** | Image being written to disk |
| **provisioned** | Server provisioned and running |
| **deprovisioning** | Server being cleaned for reuse |
| **error** | Provisioning failed |

#### Metal3Cluster

Infrastructure provider cluster resource for Metal3.

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3Cluster
metadata:
  name: edge-cluster-01
  namespace: default
spec:
  # Control plane endpoint (VIP or load balancer)
  controlPlaneEndpoint:
    host: 192.168.1.100
    port: 6443

  # Disable cloud provider (Metal3 doesn't provide cloud controller)
  noCloudProvider: true

status:
  ready: true
  failureReason: ""
  failureMessage: ""
```

#### Metal3Machine

Infrastructure provider machine resource for Metal3.

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3Machine
metadata:
  name: edge-cluster-01-control-plane-0
  namespace: default
  ownerReferences:
  - apiVersion: cluster.x-k8s.io/v1beta1
    kind: Machine
    name: edge-cluster-01-control-plane-0
spec:
  # Image to provision
  image:
    url: http://image-server.metal3.svc/sle-micro-5.5-rke2.qcow2
    checksum: http://image-server.metal3.svc/sle-micro-5.5-rke2.qcow2.sha256sum
    checksumType: sha256
    format: qcow2

  # User data reference (generated by bootstrap provider)
  userData:
    name: edge-cluster-01-control-plane-0-user-data
    namespace: default

  # Host selector (which BareMetalHost to claim)
  hostSelector:
    matchLabels:
      environment: production
      site: factory-floor-1
    matchExpressions:
    - key: hardware.cpu.count
      operator: Gte
      values:
      - "16"
    - key: hardware.ramMebibytes
      operator: Gte
      values:
      - "32768"

status:
  ready: true
  addresses:
  - type: InternalIP
    address: 192.168.1.201
  - type: Hostname
    address: edge-server-01
  # Reference to claimed BareMetalHost
  userData:
    name: edge-cluster-01-control-plane-0-user-data
    namespace: default
```

**Metal3Machine workflow:**

1. Metal3Machine created by CAPI Machine controller
2. CAPM3 controller finds available BareMetalHost matching hostSelector
3. CAPM3 claims BareMetalHost (sets spec.consumerRef)
4. CAPM3 updates BareMetalHost with image and userData
5. BMO provisions server via Ironic
6. Server boots, runs cloud-init with userData (RKE2 installation)
7. Node joins cluster
8. Metal3Machine status.ready = true

### BMC-Protocols-(Redfish-vs-IPMI)

**BMC (Baseboard Management Controller):** Out-of-band management interface on servers.

#### Redfish-(Modern-Standard)

**Preferred for new hardware.**

**Advantages:**
- RESTful API (JSON over HTTPS)
- Standard DMTF specification
- Secure (TLS, authentication)
- Rich feature set
- Good vendor support (Dell iDRAC 9+, HPE iLO 5+, Supermicro X11+)

**BMC address format:**

```yaml
bmc:
  address: redfish://192.168.1.101/redfish/v1/Systems/1
  # Or with virtual media:
  address: redfish-virtualmedia://192.168.1.101/redfish/v1/Systems/1
```

**Example Redfish BMC addresses by vendor:**

| Vendor | Format |
|--------|--------|
| Dell iDRAC | `redfish://idrac-ip/redfish/v1/Systems/System.Embedded.1` |
| HPE iLO | `redfish://ilo-ip/redfish/v1/Systems/1` |
| Supermicro | `redfish://bmc-ip/redfish/v1/Systems/1` |
| Lenovo XClarity | `redfish://xcc-ip/redfish/v1/Systems/1` |

#### IPMI-(Legacy)

**Still common on older hardware.**

**Disadvantages:**
- Plaintext protocol (security risk)
- Less feature-rich
- Vendor-specific quirks
- Being phased out

**BMC address format:**

```yaml
bmc:
  address: ipmi://192.168.1.101
```

> **Security note:** IPMI sends credentials in cleartext. Use only on isolated management networks. Prefer Redfish whenever possible.

### Provisioning-Flow-Detailed

Step-by-step provisioning process:

```
1. User creates BareMetalHost with BMC details
   ↓
2. BMO validates BMC connectivity
   Status: registering
   ↓
3. BMO triggers Ironic inspection
   - Server powered on via BMC
   - Server PXE boots inspection image (from Ironic DHCP)
   - Inspection agent collects hardware info
   - Agent sends info to Ironic
   - Server powered off
   Status: inspecting → available
   ↓
4. BareMetalHost hardware details populated in status
   ↓
5. User creates Cluster with Metal3 infrastructure
   ↓
6. CAPI creates Machine
   ↓
7. CAPM3 creates Metal3Machine
   ↓
8. CAPM3 finds available BareMetalHost matching selector
   ↓
9. CAPM3 claims BareMetalHost (spec.consumerRef)
   ↓
10. Bootstrap provider generates userData (cloud-init)
   ↓
11. CAPM3 updates BareMetalHost:
    - spec.image (OS image URL)
    - spec.userData (reference to cloud-init secret)
   Status: provisioning
   ↓
12. BMO triggers Ironic provisioning:
    a. Power on server via BMC
    b. Server PXE boots deploy ramdisk
    c. Deploy ramdisk downloads OS image from HTTP server
    d. Deploy ramdisk writes image to disk
    e. Deploy ramdisk injects userData (cloud-init)
    f. Deploy ramdisk configures bootloader
    g. Server reboots to deployed OS
   Status: provisioned
   ↓
13. OS boots, cloud-init runs
    - Network configuration
    - RKE2/K3s installation
    - Join cluster
   ↓
14. Kubelet registers Node with API server
   ↓
15. Machine controller sees Node, updates Machine status
   ↓
16. Metal3Machine status.ready = true
   ↓
17. Cluster provisioning continues (additional nodes)
```

**Timing (typical):**

- BMC validation: 10-30 seconds
- Inspection: 3-5 minutes
- Image download + write: 5-10 minutes (depends on image size and network)
- OS boot + cloud-init: 2-5 minutes
- **Total per server: 10-20 minutes**

### Network-Configuration

#### Static-IP-Configuration

Preferred for edge deployments (no DHCP dependency).

**NetworkData secret:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: edge-server-01-networkdata
  namespace: metal3
type: Opaque
stringData:
  networkData: |
    version: 2
    ethernets:
      eno1:
        addresses:
        - 192.168.1.201/24
        gateway4: 192.168.1.1
        nameservers:
          addresses:
          - 192.168.1.10
          - 192.168.1.11
        routes:
        - to: 0.0.0.0/0
          via: 192.168.1.1
      eno2:
        addresses:
        - 10.0.1.201/24
    bonds:
      bond0:
        interfaces:
        - eno3
        - eno4
        parameters:
          mode: 802.3ad
          mii-monitor-interval: 100
        addresses:
        - 172.16.1.201/24
```

**Reference in BareMetalHost:**

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: edge-server-01
spec:
  bmc:
    address: redfish://192.168.1.101/redfish/v1/Systems/1
  networkData:
    name: edge-server-01-networkdata
    namespace: metal3
```

#### DHCP-Configuration

Simpler but requires DHCP server at edge site.

```yaml
# No networkData specified - use DHCP
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: edge-server-01
spec:
  bmc:
    address: redfish://192.168.1.101/redfish/v1/Systems/1
  # networkData omitted - will use DHCP
```

#### Ironic-DHCP-Range-Configuration

Ironic needs a DHCP range for PXE booting during inspection/provisioning. This is separate from the node's final IP.

**Configure in Metal3 deployment:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ironic-bmo-configmap
  namespace: baremetal-operator-system
data:
  DHCP_RANGE: "192.168.10.100,192.168.10.200"
  PROVISIONING_INTERFACE: "eno1"
  IRONIC_INSPECTOR_VLAN_INTERFACES: "all"
```

**Network architecture:**

```
┌─────────────────────────────────────────────────────────┐
│ Management Cluster Network                              │
│ VLAN 10: 192.168.1.0/24 (management/BMC)                │
│ VLAN 20: 192.168.10.0/24 (provisioning/PXE)             │
│                                                         │
│ ┌─────────────────┐         ┌──────────────────────┐   │
│ │ Ironic Services │         │ BareMetalHost Nodes  │   │
│ │ 192.168.10.1    │◀──PXE──▶│ 192.168.10.100-200   │   │
│ │ DHCP/TFTP       │         │ (during provisioning)│   │
│ └─────────────────┘         └──────────────────────┘   │
│                                       ↓                 │
│                                  After provisioning     │
│                                       ↓                 │
│                             ┌──────────────────────┐    │
│                             │ Provisioned Nodes    │    │
│                             │ 192.168.1.201-250    │    │
│                             │ (static IPs)         │    │
│                             └──────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

[↑ Back to ToC](#table-of-contents)

---

## Rancher-Turtles-Integration

Rancher Turtles is a Kubernetes operator that bridges Cluster API and Rancher, enabling seamless integration between CAPI-managed clusters and Rancher's multi-cluster management capabilities.

### What-Rancher-Turtles-Solves

**The integration gap:**

Without Turtles, managing CAPI clusters in Rancher requires manual steps:
1. Create cluster with CAPI
2. Get kubeconfig from CAPI cluster
3. Manually import into Rancher
4. Configure Rancher agent
5. Repeat for each cluster

**With Turtles:**

```
CAPI Cluster Created → Turtles Detects → Auto-Import to Rancher → Agent Deployed
```

**Benefits:**

1. **Automatic import:** CAPI clusters automatically appear in Rancher UI
2. **Unified management:** Single pane of glass for all clusters (CAPI or not)
3. **Rancher features:** Use Rancher RBAC, monitoring, app catalog with CAPI clusters
4. **GitOps friendly:** Cluster definitions remain in Git, management in Rancher UI
5. **Label propagation:** CAPI labels automatically become Rancher labels

### Rancher-Turtles-Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  Management Cluster                                            │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Rancher Manager                                         │  │
│  │  - Web UI                                                │  │
│  │  - Multi-cluster management                              │  │
│  │  - RBAC                                                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                          ↑                                     │
│                          │ Registers clusters                 │
│                          │                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Rancher Turtles Operator                                │  │
│  │  - Watches CAPI Cluster resources                        │  │
│  │  - Creates Rancher cluster registrations                 │  │
│  │  - Manages import lifecycle                              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                          ↓                                     │
│                          │ Watches                            │
│                          ↓                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Cluster API                                             │  │
│  │  - Cluster resources                                     │  │
│  │  - Machine resources                                     │  │
│  │  - Providers                                             │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
                          ↓ Provisions
┌────────────────────────────────────────────────────────────────┐
│  Workload Clusters                                             │
│  ┌──────────────────┐  ┌──────────────────┐                   │
│  │  Cluster A       │  │  Cluster B       │                   │
│  │  + Rancher Agent │  │  + Rancher Agent │  ...              │
│  └──────────────────┘  └──────────────────┘                   │
└────────────────────────────────────────────────────────────────┘
```

### Installation

**Prerequisites:**

- Management cluster with CAPI already installed
- Rancher Manager installed (v2.9.0+)
- Helm 3 installed

**Step 1: Install Rancher (if not already installed)**

```bash
# Add Rancher Helm repository
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update

# Create namespace
kubectl create namespace cattle-system

# Install cert-manager (Rancher dependency)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

# Wait for cert-manager
kubectl wait --for=condition=Available --timeout=300s \
  -n cert-manager deployment/cert-manager \
  deployment/cert-manager-cainjector \
  deployment/cert-manager-webhook

# Install Rancher
helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=rancher.example.com \
  --set bootstrapPassword=admin \
  --set replicas=1

# Wait for Rancher to be ready
kubectl -n cattle-system rollout status deployment/rancher
```

**Step 2: Install Rancher Turtles**

```bash
# Add Rancher Turtles Helm repository
helm repo add turtles https://rancher.github.io/turtles
helm repo update

# Install Rancher Turtles
helm install rancher-turtles turtles/rancher-turtles \
  --namespace rancher-turtles-system \
  --create-namespace \
  --version v0.14.0 \
  --wait

# Verify installation
kubectl get pods -n rancher-turtles-system
```

**Expected output:**

```
NAME                                           READY   STATUS    RESTARTS   AGE
rancher-turtles-controller-manager-xxx         1/1     Running   0          60s
rancher-turtles-cluster-api-operator-xxx       1/1     Running   0          60s
```

**Step 3: Verify integration**

```bash
# Check that Turtles can communicate with Rancher
kubectl get clusters.management.cattle.io -A

# Check Turtles logs
kubectl logs -n rancher-turtles-system \
  deployment/rancher-turtles-controller-manager
```

### Auto-Import-Workflow

**Workflow steps:**

```
1. User creates CAPI Cluster resource
   ↓
2. CAPI provisions workload cluster
   ↓
3. Cluster status.phase = "Provisioned"
   ↓
4. Turtles controller detects provisioned CAPI cluster
   ↓
5. Turtles creates Rancher import token
   ↓
6. Turtles retrieves workload cluster kubeconfig
   ↓
7. Turtles applies Rancher agent manifest to workload cluster
   ↓
8. Rancher agent starts in workload cluster
   ↓
9. Agent connects to Rancher Manager
   ↓
10. Cluster appears in Rancher UI as "Active"
```

**Controlling auto-import:**

Use labels to control which clusters get auto-imported:

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: my-cluster
  namespace: default
  labels:
    # Enable auto-import (default behavior)
    cluster-api.cattle.io/rancher-auto-import: "true"
    
    # Add custom labels (propagated to Rancher)
    environment: production
    team: platform
spec:
  # ... cluster spec ...
```

**Disable auto-import for specific cluster:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: dev-cluster
  labels:
    cluster-api.cattle.io/rancher-auto-import: "false"
```

### Managing-CAPI-Clusters-in-Rancher-UI

Once imported, CAPI clusters appear in Rancher with full management capabilities:

**Access Rancher UI:**

```bash
# Get Rancher URL
kubectl -n cattle-system get ingress

# Get bootstrap password (if needed)
kubectl -n cattle-system get secret bootstrap-secret -o jsonpath='{.data.bootstrapPassword}' | base64 -d
```

**UI capabilities for CAPI clusters:**

1. **Cluster Dashboard:**
   - View cluster health, resources, events
   - Access kubectl shell directly in browser
   - Download kubeconfig

2. **Workload Management:**
   - Deploy applications via Rancher catalog
   - View Deployments, StatefulSets, DaemonSets
   - Access pod logs and shells

3. **RBAC:**
   - Assign users/groups to cluster
   - Role-based permissions
   - Project-level isolation

4. **Monitoring:**
   - Built-in Prometheus + Grafana
   - Resource utilization dashboards
   - Alerting rules

5. **Apps & Marketplace:**
   - Install Helm charts
   - Rancher app catalog
   - GitOps with Fleet

**Important distinction:**

```
Rancher UI: Day 2 operations (apps, monitoring, access)
CAPI/GitOps: Day 0-1 operations (provisioning, scaling, upgrades)
```

**Cluster lifecycle remains in CAPI:**

- Scaling nodes: Update CAPI MachineDeployment, not Rancher UI
- Upgrading K8s: Update CAPI Cluster spec, not Rancher UI
- Deleting cluster: Delete CAPI Cluster resource

> **Key insight:** Rancher Turtles creates a "read-only" import - Rancher manages workloads/access, CAPI manages infrastructure lifecycle.

### GitOps-with-Fleet-and-Turtles

Combining Fleet (Rancher's GitOps tool) with Turtles creates a powerful edge management solution:

**Architecture:**

```
┌─────────────────────────────────────────────────────────┐
│  Git Repository (Source of Truth)                       │
│  ├── clusters/                                          │
│  │   ├── cluster1.yaml  (CAPI manifests)               │
│  │   └── cluster2.yaml                                 │
│  └── apps/                                              │
│      ├── monitoring/     (Helm charts)                  │
│      └── edge-apps/                                     │
└─────────────────────────────────────────────────────────┘
              ↓ Synced by Fleet/ArgoCD
┌─────────────────────────────────────────────────────────┐
│  Management Cluster                                     │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Fleet Controller                                 │  │
│  │  - Syncs cluster definitions                      │  │
│  │  - Creates CAPI resources                         │  │
│  └───────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────┐  │
│  │  CAPI + Turtles                                   │  │
│  │  - Provisions clusters                            │  │
│  │  - Auto-imports to Rancher                        │  │
│  └───────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Fleet Controller (cluster targets)              │  │
│  │  - Detects new clusters                           │  │
│  │  - Deploys apps from Git                          │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
              ↓ Applications deployed
┌─────────────────────────────────────────────────────────┐
│  Workload Clusters                                      │
│  - CAPI managed                                         │
│  - Rancher connected                                    │
│  - Fleet apps deployed                                  │
└─────────────────────────────────────────────────────────┘
```

**Example Fleet + CAPI configuration:**

```yaml
# fleet.yaml - Fleet configuration
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: edge-clusters
  namespace: fleet-default
spec:
  repo: https://github.com/myorg/edge-infrastructure
  branch: main
  paths:
  - clusters
  targets:
  - clusterSelector: {}  # Apply to management cluster

---
# clusters/retail-store-001.yaml - CAPI cluster definition
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: retail-store-001
  namespace: edge-clusters
  labels:
    cluster-api.cattle.io/rancher-auto-import: "true"
    environment: production
    type: retail
    region: us-west
spec:
  topology:
    class: suse-edge-retail
    version: v1.35.0+rke2r1
    controlPlane:
      replicas: 1
    workers:
      machineDeployments:
      - class: standard-worker
        replicas: 2

---
# fleet.yaml for applications (separate GitRepo)
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: edge-applications
  namespace: fleet-default
spec:
  repo: https://github.com/myorg/edge-applications
  branch: main
  paths:
  - apps
  targets:
  - clusterSelector:
      matchLabels:
        type: retail
        environment: production
  # Cluster-specific customization
  targetCustomizations:
  - name: monitoring-config
    clusterSelector:
      matchLabels:
        type: retail
    helm:
      values:
        prometheus:
          retention: 7d
          resources:
            limits:
              memory: 2Gi
```

**Complete workflow:**

1. **Commit cluster definition to Git** (clusters repo)
2. **Fleet syncs and creates CAPI resources**
3. **CAPI provisions cluster**
4. **Turtles auto-imports to Rancher**
5. **Fleet detects new cluster** (via clusterSelector)
6. **Fleet deploys applications** (from apps repo)

**Benefits:**

- Single Git commit provisions cluster AND deploys apps
- All clusters track same app versions (or selectively different)
- Declarative, auditable, recoverable
- Works offline (clusters can reconcile when connectivity restored)

### Troubleshooting-Turtles

**Issue: Cluster not auto-importing**

```bash
# Check Turtles is running
kubectl get pods -n rancher-turtles-system

# Check Turtles logs
kubectl logs -n rancher-turtles-system \
  deployment/rancher-turtles-controller-manager -f

# Check Cluster has correct label
kubectl get cluster my-cluster -o yaml | grep rancher-auto-import

# Check Cluster is Provisioned
kubectl get cluster my-cluster -o jsonpath='{.status.phase}'
# Should output: Provisioned

# Manually trigger import (if needed)
kubectl annotate cluster my-cluster \
  cluster-api.cattle.io/rancher-import-trigger="$(date +%s)"
```

**Issue: Agent not connecting**

```bash
# Get workload cluster kubeconfig
clusterctl get kubeconfig my-cluster > /tmp/workload-kubeconfig

# Check agent pods in workload cluster
kubectl --kubeconfig=/tmp/workload-kubeconfig \
  get pods -n cattle-system

# Check agent logs
kubectl --kubeconfig=/tmp/workload-kubeconfig \
  logs -n cattle-system -l app=cattle-cluster-agent

# Common issues:
# - Network connectivity (agent can't reach Rancher)
# - Certificate issues (check cert-manager)
# - Firewall blocking (check ports 80/443)
```

**Issue: Import stuck in "Pending"**

```bash
# Check import status in Rancher
kubectl get clusters.management.cattle.io -A

# Check for import token secret
kubectl get secret -n default | grep my-cluster-import

# Force regenerate import token
kubectl delete secret -n default $(kubectl get secret -n default | grep my-cluster-import | awk '{print $1}')
kubectl annotate cluster my-cluster \
  cluster-api.cattle.io/rancher-import-trigger="$(date +%s)"
```

**Debugging checklist:**

- [ ] Turtles operator running
- [ ] Rancher Manager accessible
- [ ] CAPI cluster status.phase = "Provisioned"
- [ ] Auto-import label present and set to "true"
- [ ] Workload cluster API accessible from management cluster
- [ ] Network connectivity between workload cluster and Rancher
- [ ] Rancher agent deployed in workload cluster
- [ ] Agent logs show successful registration

[↑ Back to ToC](#table-of-contents)

---

## Hands-On-Setting-Up-Management-Cluster

This section provides step-by-step instructions for setting up a Cluster API management cluster with SUSE Edge providers.

### Lab-Environment-Options

**Option 1: Existing Kubernetes cluster** (Production-like)

- Existing K8s cluster (v1.31+)
- kubectl configured with admin access
- Most realistic for production path

**Option 2: kind (Docker-based)** (Development/Testing)

- Requires: Docker, kind installed
- Fast setup, no cloud costs
- Limited to development use

**Option 3: RKE2 cluster** (SUSE Edge recommended)

- RKE2 installation on VM/bare metal
- Authentic SUSE Edge experience
- Can be used for production

**This guide uses Option 2 (kind) for accessibility.** Instructions are similar for other options.

### Step-1-Create-Management-Cluster

**Using kind:**

```bash
# Create kind cluster with extra configuration
cat > kind-mgmt-cluster.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: capi-mgmt
nodes:
- role: control-plane
  extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
  extraPortMappings:
  - containerPort: 6443
    hostPort: 6443
## Working-with-ClusterClass

ClusterClass enables template-based cluster management - define topology once, instantiate many times with variables. This section shows advanced ClusterClass usage.

### Benefits-of-ClusterClass

**Traditional approach (without ClusterClass):**

Each cluster requires full manifest with all provider-specific details:
- 7-10 resource types
- 200-500 lines of YAML
- Repeated configuration
- Error-prone customization

**ClusterClass approach:**

Single cluster definition with topology:
- 1 Cluster resource
- 50-100 lines of YAML
- Standardized configuration
- Variable-based customization

**Comparison:**

```yaml
# WITHOUT ClusterClass - must define everything
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: prod-cluster-1
spec:
  clusterNetwork:
    pods:
      cidrBlocks: ["10.244.0.0/16"]
    services:
      cidrBlocks: ["10.96.0.0/12"]
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: Metal3Cluster
    name: prod-cluster-1
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: RKE2ControlPlane
    name: prod-cluster-1-cp
---
# ... plus 5-8 more resources (templates, configs, etc.)
# Repeat for every cluster!
```

```yaml
# WITH ClusterClass - reference template
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: prod-cluster-1
spec:
  topology:
    class: production-edge  # Reference to ClusterClass
    version: v1.35.0+rke2r1
    controlPlane:
      replicas: 3
    workers:
      machineDeployments:
      - class: standard-worker
        replicas: 5
    variables:
    - name: region
      value: "us-west"
# That's it! ClusterClass defines the rest
```

### Creating-a-ClusterClass

**Step-by-step ClusterClass creation:**

**1. Create infrastructure template:**

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3ClusterTemplate
metadata:
  name: edge-cluster-template
  namespace: default
spec:
  template:
    spec:
      controlPlaneEndpoint:
        host: "{{ .controlPlaneEndpoint }}"  # Variable
        port: 6443
      noCloudProvider: true
```

**2. Create control plane machine template:**

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3MachineTemplate
metadata:
  name: edge-control-plane-machines
  namespace: default
spec:
  template:
    spec:
      image:
        url: http://image-server.metal3.svc/sle-micro-rke2-{{ .kubernetesVersion }}.qcow2
        checksum: http://image-server.metal3.svc/sle-micro-rke2-{{ .kubernetesVersion }}.qcow2.sha256sum
        checksumType: sha256
        format: qcow2
      hostSelector:
        matchLabels:
          role: control-plane
          site: "{{ .site }}"
```

**3. Create control plane template:**

```yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: RKE2ControlPlaneTemplate
metadata:
  name: edge-control-plane-template
  namespace: default
spec:
  template:
    spec:
      serverConfig:
        cni: calico
        cloudProviderName: external
        etcd:
          exposeMetrics: true
          backupConfig:
            enabled: true
            retention: 10
            scheduleCron: "0 */6 * * *"
            directory: /var/lib/rancher/rke2/server/db/snapshots
      infrastructureRef:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: Metal3MachineTemplate
        name: edge-control-plane-machines
      rolloutStrategy:
        type: RollingUpdate
        rollingUpdate:
          maxSurge: 1
```

**4. Create worker machine template:**

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3MachineTemplate
metadata:
  name: edge-standard-workers
  namespace: default
spec:
  template:
    spec:
      image:
        url: http://image-server.metal3.svc/sle-micro-rke2-{{ .kubernetesVersion }}.qcow2
        checksum: http://image-server.metal3.svc/sle-micro-rke2-{{ .kubernetesVersion }}.qcow2.sha256sum
        checksumType: sha256
        format: qcow2
      hostSelector:
        matchLabels:
          role: worker
          site: "{{ .site }}"
```

**5. Create worker bootstrap template:**

```yaml
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: RKE2ConfigTemplate
metadata:
  name: edge-worker-bootstrap
  namespace: default
spec:
  template:
    spec:
      agentConfig:
        version: "{{ .builtin.controlPlane.version }}"
        kubeletArgs:
        - "max-pods={{ .maxPodsPerNode | default 110 }}"
        - "kube-reserved=cpu=100m,memory=512Mi"
      preRKE2Commands:
      - "sysctl -w net.ipv4.ip_forward=1"
      postRKE2Commands:
      - "echo 'Node provisioned at' $(date) > /var/log/provision-timestamp"
```

**6. Create ClusterClass:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: ClusterClass
metadata:
  name: production-edge
  namespace: default
spec:
  # Control plane definition
  controlPlane:
    ref:
      apiVersion: controlplane.cluster.x-k8s.io/v1beta1
      kind: RKE2ControlPlaneTemplate
      name: edge-control-plane-template
    machineInfrastructure:
      ref:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: Metal3MachineTemplate
        name: edge-control-plane-machines
    machineHealthCheck:
      maxUnhealthy: 33%
      nodeStartupTimeout: 10m
      unhealthyConditions:
      - type: Ready
        status: Unknown
        timeout: 5m
      - type: Ready
        status: "False"
        timeout: 5m

  # Infrastructure definition
  infrastructure:
    ref:
      apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
      kind: Metal3ClusterTemplate
      name: edge-cluster-template

  # Worker classes (multiple types supported)
  workers:
    machineDeployments:
    - class: standard-worker
      template:
        bootstrap:
          ref:
            apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
            kind: RKE2ConfigTemplate
            name: edge-worker-bootstrap
        infrastructure:
          ref:
            apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
            kind: Metal3MachineTemplate
            name: edge-standard-workers
      machineHealthCheck:
        maxUnhealthy: 40%
        nodeStartupTimeout: 10m
        unhealthyConditions:
        - type: Ready
          status: Unknown
          timeout: 5m

  # Patches for customization
  patches:
  - name: controlPlaneEndpointPatch
    description: "Set control plane endpoint from variable"
    definitions:
    - selector:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: Metal3ClusterTemplate
        matchResources:
          infrastructureCluster: true
      jsonPatches:
      - op: replace
        path: /spec/template/spec/controlPlaneEndpoint/host
        valueFrom:
          variable: controlPlaneEndpoint

  - name: sitePatch
    description: "Set site label for host selection"
    definitions:
    - selector:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: Metal3MachineTemplate
        matchResources:
          controlPlane: true
          machineDeploymentClass:
            names:
            - standard-worker
      jsonPatches:
      - op: replace
        path: /spec/template/spec/hostSelector/matchLabels/site
        valueFrom:
          variable: site

  - name: maxPodsPatch
    description: "Set max pods per node"
    enabledIf: '{{ if .maxPodsPerNode }}true{{ end }}'
    definitions:
    - selector:
        apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
        kind: RKE2ConfigTemplate
        matchResources:
          machineDeploymentClass:
            names:
            - standard-worker
      jsonPatches:
      - op: replace
        path: /spec/template/spec/agentConfig/kubeletArgs/0
        valueFrom:
          template: 'max-pods={{ .maxPodsPerNode }}'

  # Variables with validation
  variables:
  - name: controlPlaneEndpoint
    required: true
    schema:
      openAPIV3Schema:
        type: string
        format: ipv4
        description: "VIP or load balancer IP for control plane"

  - name: site
    required: true
    schema:
      openAPIV3Schema:
        type: string
        pattern: '^[a-z0-9-]+$'
        description: "Site identifier for hardware selection"

  - name: maxPodsPerNode
    required: false
    schema:
      openAPIV3Schema:
        type: integer
        minimum: 10
        maximum: 250
        default: 110
        description: "Maximum pods per node"
```

**Apply ClusterClass:**

```bash
# Apply all templates and ClusterClass
kubectl apply -f infrastructure-template.yaml
kubectl apply -f control-plane-machine-template.yaml
kubectl apply -f control-plane-template.yaml
kubectl apply -f worker-machine-template.yaml
kubectl apply -f worker-bootstrap-template.yaml
kubectl apply -f clusterclass.yaml

# Verify
kubectl get clusterclass
```

### Instantiating-Clusters-from-ClusterClass

**Create cluster from ClusterClass:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: factory-floor-01
  namespace: default
  labels:
    environment: production
    type: manufacturing
spec:
  topology:
    class: production-edge
    version: v1.35.0+rke2r1

    controlPlane:
      replicas: 3

    workers:
      machineDeployments:
      - class: standard-worker
        name: general-workers
        replicas: 5

    variables:
    - name: controlPlaneEndpoint
      value: "192.168.10.100"
    - name: site
      value: "factory-floor-01"
    - name: maxPodsPerNode
      value: 150
```

**Apply and watch:**

```bash
kubectl apply -f cluster-from-clusterclass.yaml

# Watch provisioning
kubectl get cluster factory-floor-01 -w

# Describe cluster
clusterctl describe cluster factory-floor-01
```

**Create multiple clusters easily:**

```bash
# Generate clusters for multiple sites
for site in factory-01 factory-02 factory-03; do
  cat > ${site}-cluster.yaml <<EOF
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: ${site}
  namespace: manufacturing
spec:
  topology:
    class: production-edge
    version: v1.35.0+rke2r1
    controlPlane:
      replicas: 3
    workers:
      machineDeployments:
      - class: standard-worker
        name: workers
        replicas: 5
    variables:
    - name: controlPlaneEndpoint
      value: "$(get-site-vip ${site})"
    - name: site
      value: "${site}"
EOF
  kubectl apply -f ${site}-cluster.yaml
done
```

### Patching-ClusterClass-Clusters

**Modify cluster after creation:**

```bash
# Scale workers
kubectl patch cluster factory-floor-01 --type=merge -p '
spec:
  topology:
    workers:
      machineDeployments:
      - class: standard-worker
        name: general-workers
        replicas: 10  # Scaled from 5 to 10
'

# Change variable
kubectl patch cluster factory-floor-01 --type=merge -p '
spec:
  topology:
    variables:
    - name: maxPodsPerNode
      value: 200  # Increased from 150
'

# Add new worker pool
kubectl patch cluster factory-floor-01 --type=merge -p '
spec:
  topology:
    workers:
      machineDeployments:
      - class: standard-worker
        name: general-workers
        replicas: 10
      - class: standard-worker  # New pool
        name: gpu-workers
        replicas: 2
'
```

### SUSE-Edge-ClusterClass-Examples

**Example 1: Retail store ClusterClass**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: ClusterClass
metadata:
  name: retail-store
  namespace: default
spec:
  controlPlane:
    ref:
      apiVersion: controlplane.cluster.x-k8s.io/v1beta1
      kind: RKE2ControlPlaneTemplate
      name: retail-control-plane
    machineInfrastructure:
      ref:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: Metal3MachineTemplate
        name: retail-nuc-machines  # Intel NUC form factor

  infrastructure:
    ref:
      apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
      kind: Metal3ClusterTemplate
      name: retail-cluster

  workers:
    machineDeployments:
    - class: pos-worker  # Point-of-sale workload
      template:
        bootstrap:
          ref:
            apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
            kind: RKE2ConfigTemplate
            name: retail-pos-bootstrap
        infrastructure:
          ref:
            apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
            kind: Metal3MachineTemplate
            name: retail-pos-machines

  variables:
  - name: storeId
    required: true
    schema:
      openAPIV3Schema:
        type: string
        pattern: '^STORE-[0-9]{4}$'
  - name: region
    required: true
    schema:
      openAPIV3Schema:
        type: string
        enum: ["north", "south", "east", "west"]
  - name: updateWindow
    required: false
    schema:
      openAPIV3Schema:
        type: string
        pattern: '^[0-9]{2}:[0-9]{2}-[0-9]{2}:[0-9]{2}$'
        default: "02:00-04:00"  # 2-4 AM
```

**Usage:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: store-0042
  namespace: retail
spec:
  topology:
    class: retail-store
    version: v1.35.0+rke2r1
    controlPlane:
      replicas: 1  # Single node for small store
    workers:
      machineDeployments:
      - class: pos-worker
        replicas: 2
    variables:
    - name: storeId
      value: "STORE-0042"
    - name: region
      value: "west"
    - name: updateWindow
      value: "03:00-05:00"  # Custom window
```

**Example 2: Telco edge ClusterClass**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: ClusterClass
metadata:
  name: telco-edge
  namespace: default
spec:
  controlPlane:
    ref:
      apiVersion: controlplane.cluster.x-k8s.io/v1beta1
      kind: RKE2ControlPlaneTemplate
      name: telco-control-plane
    machineInfrastructure:
      ref:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: Metal3MachineTemplate
        name: telco-cp-machines

  infrastructure:
    ref:
      apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
      kind: Metal3ClusterTemplate
      name: telco-cluster

  workers:
    machineDeployments:
    - class: ran-worker  # Radio Access Network
      template:
        bootstrap:
          ref:
            apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
            kind: RKE2ConfigTemplate
            name: telco-ran-bootstrap
        infrastructure:
          ref:
            apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
            kind: Metal3MachineTemplate
            name: telco-ran-machines
    - class: upf-worker  # User Plane Function
      template:
        bootstrap:
          ref:
            apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
            kind: RKE2ConfigTemplate
            name: telco-upf-bootstrap
        infrastructure:
          ref:
            apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
            kind: Metal3MachineTemplate
            name: telco-upf-machines

  patches:
  - name: sriovPatch
    description: "Enable SR-IOV for network acceleration"
    enabledIf: '{{ if .enableSRIOV }}true{{ end }}'
    definitions:
    - selector:
        apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
        kind: RKE2ConfigTemplate
        matchResources:
          machineDeploymentClass:
            names:
            - ran-worker
            - upf-worker
      jsonPatches:
      - op: add
        path: /spec/template/spec/preRKE2Commands/-
        value: "modprobe vfio-pci"

  variables:
  - name: cellId
    required: true
    schema:
      openAPIV3Schema:
        type: string
  - name: enableSRIOV
    required: false
    schema:
      openAPIV3Schema:
        type: boolean
        default: true
  - name: mcc-mnc
    required: true
    schema:
      openAPIV3Schema:
        type: string
        pattern: '^[0-9]{3}-[0-9]{2,3}$'  # e.g., 310-410
```

### Version-Management-with-ClusterClass

**Update Kubernetes version across fleet:**

```bash
# Option 1: Update ClusterClass default version
# All NEW clusters will use new version, existing unchanged
kubectl patch clusterclass production-edge --type=merge -p '
spec:
  # Update templates to reference new version
  # This is complex - better to create new ClusterClass version
'

# Option 2: Update individual cluster
kubectl patch cluster factory-floor-01 --type=merge -p '
spec:
  topology:
    version: v1.36.0+rke2r1  # Upgrade to new version
'

# Option 3: Update multiple clusters with label selector
for cluster in $(kubectl get clusters -l environment=production -o name); do
  kubectl patch ${cluster} --type=merge -p '
  spec:
    topology:
      version: v1.36.0+rke2r1
  '
done
```

**ClusterClass versioning strategy:**

```
production-edge-v1      # K8s 1.34
production-edge-v2      # K8s 1.35 (add alongside v1)
production-edge-v3      # K8s 1.36

# Clusters reference specific version
spec:
  topology:
    class: production-edge-v2  # Explicit version
```

**Create versioned ClusterClass:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: ClusterClass
metadata:
  name: production-edge-v2
  namespace: default
  labels:
    version: "v2"
    kubernetes-version: "1.35"
spec:
  # ... same as before but with v1.35-specific templates
```

**Benefits of versioned ClusterClasses:**

- Multiple K8s versions coexist
- Gradual migration (test v2, rollout, deprecate v1)
- Rollback capability (revert cluster to v1)
- Clear audit trail

[↑ Back to ToC](#table-of-contents)

---

## SUSE-Edge-Bare-Metal-Deployment-Walkthrough

Complete walkthrough of provisioning a SUSE Edge cluster on bare metal using Metal3.

### Prerequisites-for-Bare-Metal

**Hardware requirements:**

- **Servers:** 3+ physical servers with BMC (iDRAC, iLO, etc.)
  - Redfish or IPMI support
  - Network boot (PXE) capability
  - Minimum per server: 2 vCPU, 4GB RAM, 40GB disk

- **Network:**
  - Management network (BMC access)
  - Provisioning network (PXE boot)
  - Production network (cluster traffic)
  - VLANs configured (if using separate networks)

- **Management cluster:**
  - CAPI installed
  - Metal3 provider installed
  - Network access to BMCs
  - Network access to provisioning network

**Network topology:**

```
┌──────────────────────────────────────────────────────────────┐
│  Management Cluster Network                                  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Management Cluster (VLAN 10: 192.168.1.0/24)         │  │
│  │  - CAPI controllers                                    │  │
│  │  - Metal3 + Ironic                                     │  │
│  │  - Can reach BMCs and provisioning network             │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  BMC Network (VLAN 10: 192.168.1.0/24)                      │
│  ┌───────┐  ┌───────┐  ┌───────┐                           │
│  │ BMC 1 │  │ BMC 2 │  │ BMC 3 │                           │
│  │ .101  │  │ .102  │  │ .103  │                           │
│  └───────┘  └───────┘  └───────┘                           │
│                                                              │
│  Provisioning Network (VLAN 20: 192.168.10.0/24)            │
│  - DHCP range: 192.168.10.100-200                           │
│  - Used during hardware inspection and OS deployment        │
│                                                              │
│  Production Network (VLAN 30: 10.0.0.0/24)                  │
│  - Final cluster network                                    │
│  - Static IPs assigned via NetworkData                      │
└──────────────────────────────────────────────────────────────┘
```

### Step-1-Prepare-OS-Image

**Build SLE Micro image with embedded RKE2:**

```bash
# Edge Image Builder (EIB) runs as a container
# Documentation: https://github.com/suse-edge/edge-image-builder
# Pull the EIB container image:
# podman pull registry.suse.com/edge/3.5/edge-image-builder:1.3.2

# Create image definition
cat > sle-micro-rke2-image.yaml <<EOF
apiVersion: 1.0
image:
  imageType: raw
  arch: x86_64
  baseImage: SLE-Micro.x86_64-5.5.0-Default-SelfInstall-GM.install.iso
  outputImageName: sle-micro-rke2.raw

operatingSystem:
  users:
  - username: root
    encryptedPassword: \$6\$rounds=4096\$salt\$hashedpassword
    sshAuthorizedKeys:
    - "ssh-rsa AAAAB3NzaC1yc2..."

kubernetes:
  version: v1.35.0+rke2r1
  network:
    apiHost: "{{ .ControlPlaneEndpoint }}"
    apiPort: 6443

packages:
  packageList:
  - podman
  - jq
  - htop

systemd:
  enable:
  - rke2-server.service

EOF

# Build image using EIB container
podman run --rm -it --privileged \
  -v $PWD:/eib \
  registry.suse.com/edge/3.5/edge-image-builder:1.3.2 \
  build --definition-file sle-micro-rke2-image.yaml

# Image output: ./sle-micro-rke2.raw (in current directory)
# Convert to qcow2 for Metal3
qemu-img convert -f raw -O qcow2 ./images/sle-micro-rke2.raw ./images/sle-micro-rke2.qcow2

# Generate checksum
sha256sum ./images/sle-micro-rke2.qcow2 > ./images/sle-micro-rke2.qcow2.sha256sum

# Host image on HTTP server accessible from Ironic
# Option 1: Use Ironic's built-in httpd
kubectl cp ./images/sle-micro-rke2.qcow2 \
  baremetal-operator-system/ironic-xxx:/shared/html/ -c httpd

# Option 2: Host on separate HTTP server
# Copy to web server: /var/www/html/images/
```

**Image URL will be:**
```
http://ironic.baremetal-operator-system.svc/images/sle-micro-rke2.qcow2
# or
http://image-server.example.com/images/sle-micro-rke2.qcow2
```

### Step-2-Create-BareMetalHost-Resources

**Discover BMC credentials:**

```bash
# Test BMC connectivity (Dell iDRAC example)
curl -k -u root:calvin https://192.168.1.101/redfish/v1/Systems

# Expected: JSON response with system information
```

**Create BMC credential secrets:**

```yaml
# bmc-secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: server-01-bmc-secret
  namespace: metal3
type: Opaque
stringData:
  username: "root"
  password: "calvin"  # Change to actual password!

---
apiVersion: v1
kind: Secret
metadata:
  name: server-02-bmc-secret
  namespace: metal3
type: Opaque
stringData:
  username: "root"
  password: "calvin"

---
apiVersion: v1
kind: Secret
metadata:
  name: server-03-bmc-secret
  namespace: metal3
type: Opaque
stringData:
  username: "root"
  password: "calvin"
```

**Create BareMetalHost resources:**

```yaml
# baremetalhosts.yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: server-01
  namespace: metal3
  labels:
    site: edge-site-01
    role: control-plane
spec:
  online: true
  bootMACAddress: "00:1a:2b:3c:4d:01"
  bootMode: UEFI
  bmc:
    address: redfish://192.168.1.101/redfish/v1/Systems/System.Embedded.1
    credentialsName: server-01-bmc-secret
    disableCertificateVerification: true  # Set false in production with valid certs
  rootDeviceHints:
    deviceName: "/dev/sda"
  automatedCleaningMode: metadata

---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: server-02
  namespace: metal3
  labels:
    site: edge-site-01
    role: control-plane
spec:
  online: true
  bootMACAddress: "00:1a:2b:3c:4d:02"
  bootMode: UEFI
  bmc:
    address: redfish://192.168.1.102/redfish/v1/Systems/System.Embedded.1
    credentialsName: server-02-bmc-secret
    disableCertificateVerification: true
  rootDeviceHints:
    deviceName: "/dev/sda"
  automatedCleaningMode: metadata

---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: server-03
  namespace: metal3
  labels:
    site: edge-site-01
    role: control-plane
spec:
  online: true
  bootMACAddress: "00:1a:2b:3c:4d:03"
  bootMode: UEFI
  bmc:
    address: redfish://192.168.1.103/redfish/v1/Systems/System.Embedded.1
    credentialsName: server-03-bmc-secret
    disableCertificateVerification: true
  rootDeviceHints:
    deviceName: "/dev/sda"
  automatedCleaningMode: metadata

---
# Worker nodes
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: server-04
  namespace: metal3
  labels:
    site: edge-site-01
    role: worker
spec:
  online: true
  bootMACAddress: "00:1a:2b:3c:4d:04"
  bootMode: UEFI
  bmc:
    address: redfish://192.168.1.104/redfish/v1/Systems/System.Embedded.1
    credentialsName: server-04-bmc-secret
    disableCertificateVerification: true
  rootDeviceHints:
    deviceName: "/dev/sda"
  automatedCleaningMode: metadata

---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: server-05
  namespace: metal3
  labels:
    site: edge-site-01
    role: worker
spec:
  online: true
  bootMACAddress: "00:1a:2b:3c:4d:05"
  bootMode: UEFI
  bmc:
    address: redfish://192.168.1.105/redfish/v1/Systems/System.Embedded.1
    credentialsName: server-05-bmc-secret
    disableCertificateVerification: true
  rootDeviceHints:
    deviceName: "/dev/sda"
  automatedCleaningMode: metadata
```

**Apply resources:**

```bash
# Create namespace
kubectl create namespace metal3

# Apply secrets
kubectl apply -f bmc-secrets.yaml

# Apply BareMetalHosts
kubectl apply -f baremetalhosts.yaml

# Watch inspection
kubectl get baremetalhosts -n metal3 -w
```

### Step-3-Hardware-Inspection

**Monitor inspection process:**

```bash
# Watch BareMetalHost status
watch kubectl get baremetalhosts -n metal3

# Expected progression:
# NAME        STATE          CONSUMER   ONLINE   ERROR
# server-01   registering               true
# server-01   inspecting                true
# server-01   available                 true     # Inspection complete

# Check detailed status
kubectl get baremetalhost server-01 -n metal3 -o yaml
```

**View inspected hardware details:**

```bash
# Get hardware info
kubectl get baremetalhost server-01 -n metal3 -o jsonpath='{.status.hardware}' | jq

# Example output:
{
  "systemVendor": {
    "manufacturer": "Dell Inc.",
    "productName": "PowerEdge R640",
    "serialNumber": "ABC1234"
  },
  "cpu": {
    "arch": "x86_64",
    "model": "Intel Xeon Gold 6140",
    "clockMegahertz": 2300,
    "count": 36
  },
  "ramMebibytes": 65536,
  "nics": [
    {
      "name": "eno1",
      "mac": "00:1a:2b:3c:4d:01",
      "ip": "192.168.10.101",
      "speedGbps": 10
    }
  ],
  "storage": [
    {
      "name": "/dev/sda",
      "sizeBytes": 1000204886016,
      "model": "DELL PERC H740P",
      "rotational": false
    }
  ]
}
```

**Troubleshooting inspection:**

```bash
# If inspection fails or hangs
kubectl describe baremetalhost server-01 -n metal3

# Check Ironic logs
kubectl logs -n baremetal-operator-system deployment/baremetal-operator-controller-manager

# Check if server is PXE booting
# Physical access: monitor server console during inspection
# Should see:
# 1. Power on via BMC
# 2. PXE boot from DHCP
# 3. Download inspection image
# 4. Boot inspection image
# 5. Collect hardware info
# 6. Send to Ironic
# 7. Power off

# Common issues:
# - BMC credentials wrong
# - PXE not enabled in BIOS
# - DHCP not reaching server
# - Network connectivity issues
```

### Step-4-Create-Network-Configuration

**Create static network configurations:**

```yaml
# network-configs.yaml
apiVersion: v1
kind: Secret
metadata:
  name: server-01-networkdata
  namespace: metal3
type: Opaque
stringData:
  networkData: |
    version: 2
    ethernets:
      eno1:
        addresses:
        - 10.0.0.11/24
        gateway4: 10.0.0.1
        nameservers:
          addresses:
          - 10.0.0.10
          - 8.8.8.8
        routes:
        - to: 0.0.0.0/0
          via: 10.0.0.1

---
apiVersion: v1
kind: Secret
metadata:
  name: server-02-networkdata
  namespace: metal3
type: Opaque
stringData:
  networkData: |
    version: 2
    ethernets:
      eno1:
        addresses:
        - 10.0.0.12/24
        gateway4: 10.0.0.1
        nameservers:
          addresses:
          - 10.0.0.10
          - 8.8.8.8

---
apiVersion: v1
kind: Secret
metadata:
  name: server-03-networkdata
  namespace: metal3
type: Opaque
stringData:
  networkData: |
    version: 2
    ethernets:
      eno1:
        addresses:
        - 10.0.0.13/24
        gateway4: 10.0.0.1
        nameservers:
          addresses:
          - 10.0.0.10
          - 8.8.8.8

---
# Workers
apiVersion: v1
kind: Secret
metadata:
  name: server-04-networkdata
  namespace: metal3
type: Opaque
stringData:
  networkData: |
    version: 2
    ethernets:
      eno1:
        addresses:
        - 10.0.0.14/24
        gateway4: 10.0.0.1
        nameservers:
          addresses:
          - 10.0.0.10
          - 8.8.8.8

---
apiVersion: v1
kind: Secret
metadata:
  name: server-05-networkdata
  namespace: metal3
type: Opaque
stringData:
  networkData: |
    version: 2
    ethernets:
      eno1:
        addresses:
        - 10.0.0.15/24
        gateway4: 10.0.0.1
        nameservers:
          addresses:
          - 10.0.0.10
          - 8.8.8.8
```

**Apply network configs:**

```bash
kubectl apply -f network-configs.yaml
```

**Update BareMetalHosts with network config:**

```bash
# Patch each BareMetalHost
kubectl patch baremetalhost server-01 -n metal3 --type=merge -p '
spec:
  networkData:
    name: server-01-networkdata
    namespace: metal3
'

# Repeat for other servers
for i in 02 03 04 05; do
  kubectl patch baremetalhost server-${i} -n metal3 --type=merge -p "
spec:
  networkData:
    name: server-${i}-networkdata
    namespace: metal3
"
done
```

### Step-5-Create-Cluster-with-Metal3

**Create Metal3 cluster manifest:**

```yaml
# edge-cluster-metal3.yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: edge-cluster-01
  namespace: default
  labels:
    site: edge-site-01
    environment: production
spec:
  clusterNetwork:
    pods:
      cidrBlocks:
      - 10.244.0.0/16
    services:
      cidrBlocks:
      - 10.96.0.0/12
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: RKE2ControlPlane
    name: edge-cluster-01-control-plane
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: Metal3Cluster
    name: edge-cluster-01

---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3Cluster
metadata:
  name: edge-cluster-01
  namespace: default
spec:
  controlPlaneEndpoint:
    host: 10.0.0.10  # VIP (configure kube-vip or similar)
    port: 6443
  noCloudProvider: true

---
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: RKE2ControlPlane
metadata:
  name: edge-cluster-01-control-plane
  namespace: default
spec:
  replicas: 3
  version: v1.35.0+rke2r1
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: Metal3MachineTemplate
    name: edge-cluster-01-control-plane
  serverConfig:
    cni: calico
    cloudProviderName: external
    etcd:
      exposeMetrics: true
      backupConfig:
        enabled: true
        retention: 10
        scheduleCron: "0 */6 * * *"
  files:
  # kube-vip for VIP (control plane endpoint)
  - path: /var/lib/rancher/rke2/server/manifests/kube-vip.yaml
    owner: root:root
    permissions: "0600"
    content: |
      apiVersion: v1
      kind: Pod
      metadata:
        name: kube-vip
        namespace: kube-system
      spec:
        containers:
        - name: kube-vip
          image: ghcr.io/kube-vip/kube-vip:v0.7.0
          args:
          - manager
          env:
          - name: vip_interface
            value: eno1
          - name: vip_arp
            value: "true"
          - name: address
            value: "10.0.0.10"
          - name: port
            value: "6443"
          securityContext:
            capabilities:
              add:
              - NET_ADMIN
              - NET_RAW
          volumeMounts:
          - mountPath: /etc/kubernetes/admin.conf
            name: kubeconfig
        hostNetwork: true
        volumes:
        - name: kubeconfig
          hostPath:
            path: /etc/rancher/rke2/rke2.yaml

---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3MachineTemplate
metadata:
  name: edge-cluster-01-control-plane
  namespace: default
spec:
  template:
    spec:
      image:
        url: http://image-server.example.com/images/sle-micro-rke2.qcow2
        checksum: http://image-server.example.com/images/sle-micro-rke2.qcow2.sha256sum
        checksumType: sha256
        format: qcow2
      hostSelector:
        matchLabels:
          site: edge-site-01
          role: control-plane

---
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: edge-cluster-01-workers
  namespace: default
spec:
  clusterName: edge-cluster-01
  replicas: 2
  selector:
    matchLabels:
      cluster.x-k8s.io/cluster-name: edge-cluster-01
      node-role: worker
  template:
    metadata:
      labels:
        cluster.x-k8s.io/cluster-name: edge-cluster-01
        node-role: worker
    spec:
      clusterName: edge-cluster-01
      version: v1.35.0+rke2r1
      bootstrap:
        configRef:
          apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
          kind: RKE2ConfigTemplate
          name: edge-cluster-01-workers
      infrastructureRef:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: Metal3MachineTemplate
        name: edge-cluster-01-workers

---
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: RKE2ConfigTemplate
metadata:
  name: edge-cluster-01-workers
  namespace: default
spec:
  template:
    spec:
      agentConfig:
        version: v1.35.0+rke2r1

---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3MachineTemplate
metadata:
  name: edge-cluster-01-workers
  namespace: default
spec:
  template:
    spec:
      image:
        url: http://image-server.example.com/images/sle-micro-rke2.qcow2
        checksum: http://image-server.example.com/images/sle-micro-rke2.qcow2.sha256sum
        checksumType: sha256
        format: qcow2
      hostSelector:
        matchLabels:
          site: edge-site-01
          role: worker
```

**Apply cluster:**

```bash
kubectl apply -f edge-cluster-metal3.yaml

# Watch provisioning
kubectl get cluster edge-cluster-01 -w
kubectl get baremetalhosts -n metal3 -w
kubectl get machines -l cluster.x-k8s.io/cluster-name=edge-cluster-01 -w
```

### Step-6-Monitor-Provisioning

**Check BareMetalHost claiming:**

```bash
# BareMetalHosts should transition: available → provisioning → provisioned
kubectl get baremetalhosts -n metal3

# Check which hosts are claimed
kubectl get baremetalhosts -n metal3 -o custom-columns=NAME:.metadata.name,STATE:.status.provisioning.state,CONSUMER:.spec.consumerRef.name
```

**Watch Machine creation:**

```bash
# Machines should appear for each BareMetalHost
kubectl get machines -l cluster.x-k8s.io/cluster-name=edge-cluster-01

# Check Machine details
kubectl describe machine edge-cluster-01-control-plane-xxx
```

**Monitor provisioning logs:**

```bash
# Bare Metal Operator logs
kubectl logs -n baremetal-operator-system deployment/baremetal-operator-controller-manager -f

# CAPM3 logs
kubectl logs -n capm3-system deployment/capm3-controller-manager -f

# RKE2 control plane logs
kubectl logs -n rke2-control-plane-system deployment/rke2-control-plane-controller-manager -f
```

**Expected timeline:**

- t=0: Cluster applied
- t=30s: Metal3Machines created, claim BareMetalHosts
- t=60s: BareMetalHosts enter "provisioning" state
- t=5min: Image download and write (depends on network/image size)
- t=10min: First control plane node boots, RKE2 initializes
- t=15min: First control plane ready
- t=20min: Additional control plane nodes join
- t=25min: Worker nodes provisioning
- t=30min: Cluster fully provisioned

### Step-7-Access-and-Validate

**Get kubeconfig:**

```bash
# Wait for cluster to be Provisioned
kubectl get cluster edge-cluster-01 -o jsonpath='{.status.phase}'
# Output: Provisioned

# Get kubeconfig
clusterctl get kubeconfig edge-cluster-01 > edge-cluster-01.kubeconfig

# Set KUBECONFIG
export KUBECONFIG=edge-cluster-01.kubeconfig

# Verify nodes
kubectl get nodes -o wide
```

**Expected output:**

```
NAME        STATUS   ROLES           AGE   VERSION           INTERNAL-IP   EXTERNAL-IP
server-01   Ready    control-plane   15m   v1.35.0+rke2r1    10.0.0.11     <none>
server-02   Ready    control-plane   14m   v1.35.0+rke2r1    10.0.0.12     <none>
server-03   Ready    control-plane   13m   v1.35.0+rke2r1    10.0.0.13     <none>
server-04   Ready    <none>          10m   v1.35.0+rke2r1    10.0.0.14     <none>
server-05   Ready    <none>          10m   v1.35.0+rke2r1    10.0.0.15     <none>
```

**Validate cluster health:**

```bash
# Check pods
kubectl get pods -A

# Check cluster info
kubectl cluster-info

# Deploy test workload
kubectl create deployment nginx --image=nginx --replicas=3
kubectl get pods -o wide

# Test networking
kubectl run test --rm -it --image=busybox -- wget -O- http://nginx-service
```

### Troubleshooting-Bare-Metal-Deployment

**Issue: BareMetalHost stuck in "registering"**

```bash
# Check BMC connectivity
kubectl describe baremetalhost server-01 -n metal3

# Look for events like:
# Warning  RegistrationError  BMC authentication failed

# Test BMC manually
curl -k -u root:password https://192.168.1.101/redfish/v1/Systems

# Fix: Update BMC credentials
kubectl delete secret server-01-bmc-secret -n metal3
# Recreate with correct credentials
```

**Issue: Inspection failing**

```bash
# Check Ironic logs
kubectl logs -n baremetal-operator-system -l app=ironic -c ironic-inspector

# Common causes:
# - PXE boot disabled in BIOS
# - DHCP not reaching server
# - Provisioning network misconfigured

# Verify DHCP range
kubectl get configmap -n baremetal-operator-system ironic-bmo-configmap -o yaml | grep DHCP_RANGE

# Check if server is receiving DHCP (requires physical access or remote console)
```

**Issue: Provisioning fails during image write**

```bash
# Check BareMetalHost status
kubectl get baremetalhost server-01 -n metal3 -o jsonpath='{.status.errorMessage}'

# Check Ironic conductor logs
kubectl logs -n baremetal-operator-system -l app=ironic -c ironic-conductor

# Common causes:
# - Image URL not accessible
# - Checksum mismatch
# - Disk too small
# - Write errors

# Verify image accessibility from Ironic pod
kubectl exec -n baremetal-operator-system -it <ironic-pod> -c ironic-conductor -- \
  curl -I http://image-server.example.com/images/sle-micro-rke2.qcow2
```

**Issue: Node not joining cluster**

```bash
# Check Machine status
kubectl describe machine edge-cluster-01-control-plane-xxx

# Get node logs (requires console access or SSH)
# SSH to node (if accessible):
ssh root@10.0.0.11

# Check RKE2 logs
journalctl -u rke2-server -f  # Control plane
journalctl -u rke2-agent -f   # Worker

# Common causes:
# - Control plane endpoint unreachable (check VIP)
# - Certificate issues
# - Network policies blocking
```

**Clean up and retry:**

```bash
# Delete cluster
kubectl delete cluster edge-cluster-01

# Wait for BareMetalHosts to return to "available"
kubectl get baremetalhosts -n metal3 -w

# If stuck, power cycle server via BMC
kubectl patch baremetalhost server-01 -n metal3 --type=merge -p '{"spec":{"online":false}}'
# Wait...
kubectl patch baremetalhost server-01 -n metal3 --type=merge -p '{"spec":{"online":true}}'

# Retry cluster creation
kubectl apply -f edge-cluster-metal3.yaml
```

[↑ Back to ToC](#table-of-contents)

---

## Cluster-Lifecycle-Operations

Day 2 operations for managing Cluster API workload clusters.

### Scaling-Clusters

#### Scaling-Worker-Nodes

**Scale up:**

```bash
# Using kubectl patch
kubectl patch machinedeployment edge-cluster-01-workers --type=merge -p '{"spec":{"replicas":5}}'

# Using kubectl scale
kubectl scale machinedeployment edge-cluster-01-workers --replicas=5

# Watch scaling
kubectl get machines -l cluster.x-k8s.io/cluster-name=edge-cluster-01 -w
```

**Scale down:**

```bash
# Scale down to 2 replicas
kubectl scale machinedeployment edge-cluster-01-workers --replicas=2

# CAPI will:
# 1. Select Machines to delete (oldest first by default)
# 2. Cordon nodes
# 3. Drain nodes (respecting PDBs)
# 4. Delete Machines
# 5. Deprovision infrastructure

# Monitor eviction
kubectl get nodes -w
kubectl get machines -w
```

**With ClusterClass:**

```bash
# Update topology
kubectl patch cluster edge-cluster-01 --type=merge -p '
spec:
  topology:
    workers:
      machineDeployments:
      - class: standard-worker
        name: workers
        replicas: 10
'
```

#### Scaling-Control-Plane

**Scale control plane (careful!):**

```bash
# Scale from 3 to 5
kubectl patch rke2controlplane edge-cluster-01-control-plane --type=merge -p '{"spec":{"replicas":5}}'

# OR with ClusterClass
kubectl patch cluster edge-cluster-01 --type=merge -p '
spec:
  topology:
    controlPlane:
      replicas: 5
'

# IMPORTANT: Always use odd numbers for control plane (etcd quorum)
# Valid: 1, 3, 5, 7
# Invalid: 2, 4, 6
```

**Scale down control plane:**

```bash
# Scale from 5 to 3 (safe)
kubectl patch rke2controlplane edge-cluster-01-control-plane --type=merge -p '{"spec":{"replicas":3}}'

# CAPI will:
# 1. Select control plane Machines to remove
# 2. Remove from etcd cluster
# 3. Delete Machine
# 4. Deprovision infrastructure

# Monitor
kubectl get machines -l cluster.x-k8s.io/control-plane-name=edge-cluster-01-control-plane -w
```

> **Warning:** Never scale control plane to even numbers. etcd requires majority quorum. With 2 nodes, losing 1 loses quorum.

#### Autoscaling-(Cluster-Autoscaler)

**Install Cluster Autoscaler:**

```yaml
# In workload cluster
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
    spec:
      serviceAccountName: cluster-autoscaler
      containers:
      - image: k8s.gcr.io/autoscaling/cluster-autoscaler:v1.35.0
        name: cluster-autoscaler
        command:
        - ./cluster-autoscaler
        - --cloud-provider=clusterapi
        - --kubeconfig=/etc/kubernetes/mgmt-kubeconfig
        - --clusterapi-cloud-config-authoritative
        - --node-group-auto-discovery=clusterapi:namespace=default
        volumeMounts:
        - name: mgmt-kubeconfig
          mountPath: /etc/kubernetes
          readOnly: true
      volumes:
      - name: mgmt-kubeconfig
        secret:
          secretName: mgmt-kubeconfig
```

**Configure MachineDeployment for autoscaling:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: edge-cluster-01-workers
  annotations:
    cluster.x-k8s.io/cluster-api-autoscaler-node-group-min-size: "2"
    cluster.x-k8s.io/cluster-api-autoscaler-node-group-max-size: "10"
spec:
  replicas: 2  # Initial size
  # ...
```

### Upgrading-Clusters

#### Rolling-Upgrade-(Workers)

**Upgrade worker nodes:**

```bash
# Update MachineDeployment version
kubectl patch machinedeployment edge-cluster-01-workers --type=merge -p '
spec:
  template:
    spec:
      version: v1.36.0+rke2r1
'

# CAPI will:
# 1. Create new MachineSet with v1.36.0
# 2. Scale up new MachineSet
# 3. Scale down old MachineSet
# 4. Respect maxSurge and maxUnavailable

# Monitor rollout
kubectl get machinesets -l cluster.x-k8s.io/deployment-name=edge-cluster-01-workers -w
kubectl get machines -l cluster.x-k8s.io/deployment-name=edge-cluster-01-workers -w
```

**Configure rollout strategy:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: edge-cluster-01-workers
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1          # Create 1 extra node during upgrade
      maxUnavailable: 0    # Don't allow any unavailable nodes
      # OR
      maxSurge: 0
      maxUnavailable: 1    # Replace 1 at a time, no extras
  # ...
```

#### Rolling-Upgrade-(Control-Plane)

**Upgrade control plane:**

```bash
# Update RKE2ControlPlane version
kubectl patch rke2controlplane edge-cluster-01-control-plane --type=merge -p '
spec:
  version: v1.36.0+rke2r1
'

# CAPI will:
# 1. Upgrade one control plane node at a time
# 2. Wait for node to be Ready before next
# 3. Maintain quorum throughout

# Monitor
kubectl get machines -l cluster.x-k8s.io/control-plane-name=edge-cluster-01-control-plane -w
```

**Control plane rollout strategy:**

```yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: RKE2ControlPlane
metadata:
  name: edge-cluster-01-control-plane
spec:
  rolloutStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1  # Create 1 extra before deleting old (4 nodes briefly)
  # ...
```

#### In-Place-Upgrades-(CAPI-v1.12+)

**Enable in-place upgrades:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: edge-cluster-01
  annotations:
    cluster.x-k8s.io/in-place-upgrade: "true"
spec:
  # ...
```

**Trigger upgrade:**

```bash
# Update cluster version (with ClusterClass)
kubectl patch cluster edge-cluster-01 --type=merge -p '
spec:
  topology:
    version: v1.36.0+rke2r1
'

# CAPI will:
# 1. SSH to existing nodes (or use provider-specific method)
# 2. Run upgrade command (e.g., rke2 upgrade)
# 3. Restart services
# 4. No machine replacement

# Advantages:
# - Faster (no provisioning)
# - Preserves local storage
# - Less infrastructure churn

# Disadvantages:
# - Riskier (harder rollback)
# - Requires provider support
# - Node must remain accessible
```

#### Chained-Upgrades-(CAPI-v1.12+)

**Automatically handle multi-version jumps:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: edge-cluster-01
spec:
  topology:
    class: production-edge
    version: v1.36.0+rke2r1  # Jumping from v1.32.0
    variables:
    - name: enableChainedUpgrades
      value: "true"
```

```bash
# CAPI will automatically chain: v1.32 → v1.33 → v1.34 → v1.35 → v1.36
# Each intermediate version is fully upgraded before next

# Monitor chain progress
kubectl get cluster edge-cluster-01 -o jsonpath='{.status.conditions[?(@.type=="ControlPlaneReady")].message}'
```

### Node-Remediation

**Automatic remediation with MachineHealthCheck:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineHealthCheck
metadata:
  name: edge-cluster-01-worker-health
  namespace: default
spec:
  clusterName: edge-cluster-01
  selector:
    matchLabels:
      node-role: worker
  unhealthyConditions:
  - type: Ready
    status: Unknown
    timeout: 5m
  - type: Ready
    status: "False"
    timeout: 5m
  maxUnhealthy: 40%  # Don't remediate if >40% unhealthy (avoid cascading failure)
  nodeStartupTimeout: 10m
  remediationTemplate:
    kind: Metal3RemediationTemplate
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    name: worker-remediation
```

**Remediation template:**

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3RemediationTemplate
metadata:
  name: worker-remediation
  namespace: default
spec:
  template:
    spec:
      strategy:
        type: Reboot  # or "Replace"
        retryLimit: 3
        timeout: 5m
```

**Manual remediation:**

```bash
# Force delete unhealthy Machine
kubectl delete machine edge-cluster-01-workers-xxx

# MachineDeployment will create replacement automatically
```

### Cluster-Backup-and-Restore

#### etcd-Backup

**Automated backups (configured in RKE2ControlPlane):**

```yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: RKE2ControlPlane
metadata:
  name: edge-cluster-01-control-plane
spec:
  serverConfig:
    etcd:
      backupConfig:
        enabled: true
        directory: /var/lib/rancher/rke2/server/db/snapshots
        retention: 10  # Keep 10 snapshots
        scheduleCron: "0 */6 * * *"  # Every 6 hours
        s3Config:  # Optional: backup to S3
          bucket: my-etcd-backups
          endpoint: s3.amazonaws.com
          folder: edge-cluster-01
          region: us-west-2
          accessKey:
            name: etcd-backup-creds
            key: access-key
          secretKey:
            name: etcd-backup-creds
            key: secret-key
```

**Manual etcd snapshot:**

```bash
# SSH to control plane node
ssh root@10.0.0.11

# Create snapshot
rke2 etcd-snapshot save --name manual-backup-$(date +%Y%m%d-%H%M%S)

# List snapshots
rke2 etcd-snapshot ls

# Snapshots stored in:
ls -l /var/lib/rancher/rke2/server/db/snapshots/
```

#### etcd-Restore

**Restore from snapshot:**

```bash
# 1. Stop all control plane nodes except one
# SSH to nodes 2 and 3:
systemctl stop rke2-server

# 2. On node 1, restore snapshot
ssh root@10.0.0.11
rke2 etcd-snapshot restore --name snapshot-name.db

# 3. Restart RKE2 on node 1
systemctl restart rke2-server

# 4. Reset and rejoin other control plane nodes
# On nodes 2 and 3:
rke2 server --cluster-reset

# 5. Verify cluster
kubectl get nodes
kubectl get pods -A
```

#### Application-Backup-(Velero)

**Install Velero in workload cluster:**

```bash
# Install Velero CLI
wget https://github.com/vmware-tanzu/velero/releases/download/v1.13.0/velero-v1.13.0-linux-amd64.tar.gz
tar -xvf velero-v1.13.0-linux-amd64.tar.gz
sudo mv velero-v1.13.0-linux-amd64/velero /usr/local/bin/

# Install Velero in cluster
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket my-velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=us-west-2

# Create backup
velero backup create full-backup --include-namespaces '*'

# Schedule regular backups
velero schedule create daily-backup --schedule="0 2 * * *"
```

### Cluster-Deletion

**Delete workload cluster:**

```bash
# Delete Cluster resource
kubectl delete cluster edge-cluster-01

# CAPI will:
# 1. Delete all Machines
# 2. Deprovision all infrastructure (VMs/BareMetalHosts)
# 3. Delete control plane
# 4. Delete cluster infrastructure
# 5. Clean up all related resources

# Watch deletion
kubectl get cluster edge-cluster-01 -w
kubectl get machines -l cluster.x-k8s.io/cluster-name=edge-cluster-01 -w
kubectl get baremetalhosts -n metal3 -w  # (Metal3)

# BareMetalHosts will return to "available" state
```

**Force delete stuck cluster:**

```bash
# If cluster stuck in "Deleting"
kubectl get cluster edge-cluster-01 -o yaml | grep -A 5 finalizers

# Remove finalizers (DANGER: may leave orphaned resources)
kubectl patch cluster edge-cluster-01 --type=merge -p '{"metadata":{"finalizers":[]}}'

# Manually clean up resources
kubectl delete machines -l cluster.x-k8s.io/cluster-name=edge-cluster-01
kubectl delete metal3clusters edge-cluster-01
kubectl delete rke2controlplane edge-cluster-01-control-plane
```

**Cluster deletion with retention (Metal3):**

```yaml
# Prevent BareMetalHost deprovisioning
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: edge-cluster-01
  annotations:
    cluster.x-k8s.io/paused: "true"  # Pause cluster operations
spec:
  # ...
```

```bash
# Delete cluster without deprovisioning hosts
kubectl delete cluster edge-cluster-01

# Manually unclaim BareMetalHosts
kubectl patch baremetalhost server-01 -n metal3 --type=merge -p '{"spec":{"consumerRef":null}}'
# Hosts remain "provisioned" with OS, can be reused
```

[↑ Back to ToC](#table-of-contents)

---

## GitOps-Workflows-with-SUSE-Edge

Implementing GitOps for SUSE Edge cluster and application management.

### Declarative-Cluster-Definitions-in-Git

**Repository structure:**

```
edge-gitops/
├── README.md
├── clusters/
│   ├── base/
│   │   ├── clusterclass.yaml
│   │   └── templates/
│   │       ├── infrastructure.yaml
│   │       ├── control-plane.yaml
│   │       └── workers.yaml
│   ├── production/
│   │   ├── site-001/
│   │   │   ├── cluster.yaml
│   │   │   ├── baremetalhosts.yaml
│   │   │   └── kustomization.yaml
│   │   ├── site-002/
│   │   │   ├── cluster.yaml
│   │   │   ├── baremetalhosts.yaml
│   │   │   └── kustomization.yaml
│   │   └── kustomization.yaml
│   ├── staging/
│   │   └── ...
│   └── fleet.yaml
├── applications/
│   ├── base/
│   │   ├── monitoring/
│   │   │   ├── prometheus/
│   │   │   └── grafana/
│   │   └── logging/
│   ├── overlays/
│   │   ├── production/
│   │   └── staging/
│   └── fleet.yaml
└── .github/
    └── workflows/
        └── validate.yaml
```

**Example cluster definition:**

```yaml
# clusters/production/site-001/cluster.yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: prod-site-001
  namespace: production
  labels:
    environment: production
    site: site-001
    region: us-west
    type: manufacturing
spec:
  topology:
    class: suse-edge-production
    version: v1.35.0+rke2r1
    controlPlane:
      replicas: 3
    workers:
      machineDeployments:
      - class: standard-worker
        name: workers
        replicas: 5
    variables:
    - name: controlPlaneEndpoint
      value: "10.10.1.100"
    - name: site
      value: "site-001"
```

**Kustomization:**

```yaml
# clusters/production/site-001/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: production

resources:
- cluster.yaml
- baremetalhosts.yaml

commonLabels:
  environment: production
  site: site-001

patches:
- target:
    kind: Cluster
  patch: |-
    - op: add
      path: /metadata/annotations
      value:
        cluster-api.cattle.io/rancher-auto-import: "true"
```

### Fleet-for-Cluster-Management

**Install Fleet:**

```bash
# Helm install
helm repo add fleet https://rancher.github.io/fleet-helm-charts/
helm repo update

helm install fleet fleet/fleet \
  --namespace cattle-fleet-system \
  --create-namespace

# Verify
kubectl get pods -n cattle-fleet-system
```

**Create GitRepo for cluster management:**

```yaml
# gitrepo-clusters.yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: edge-clusters
  namespace: fleet-default
spec:
  repo: https://github.com/myorg/edge-gitops
  branch: main
  paths:
  - clusters/production
  - clusters/staging

  # Poll interval
  pollingInterval: 15s

  # Target: deploy to management cluster
  targets:
  - clusterSelector: {}

  # Service account with permissions to create clusters
  serviceAccount: fleet-cluster-manager
```

**Apply GitRepo:**

```bash
kubectl apply -f gitrepo-clusters.yaml

# Watch Fleet sync
kubectl get gitrepo -n fleet-default
kubectl get bundles -n fleet-default

# Check bundle status
kubectl describe bundle -n fleet-default edge-clusters-clusters-production
```

**Workflow:**

```
1. Developer commits cluster.yaml to Git
2. Fleet detects change (polling or webhook)
3. Fleet creates Bundle resource
4. Fleet applies CAPI resources to management cluster
5. CAPI provisions workload cluster
6. Turtles auto-imports to Rancher (if configured)
7. Fleet detects new cluster
8. Fleet deploys applications (from applications GitRepo)
```

### ArgoCD-Patterns-for-CAPI

**Install ArgoCD:**

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD
kubectl wait --for=condition=Available --timeout=300s \
  -n argocd deployment/argocd-server

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**ArgoCD Application for cluster management:**

```yaml
# argocd-clusters-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: edge-clusters
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/edge-gitops
    targetRevision: main
    path: clusters/production
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: false  # DON'T auto-delete clusters!
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

**ApplicationSet for multi-cluster:**

```yaml
# argocd-clusters-appset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: edge-clusters
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/myorg/edge-gitops
      revision: main
      directories:
      - path: clusters/production/*
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/myorg/edge-gitops
        targetRevision: main
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: production
      syncPolicy:
        automated:
          prune: false
          selfHeal: true
```

### Promotion-Strategies

**Strategy 1: Branch-based promotion**

```
Git branches:
  main (production)
  staging
  dev

Workflow:
1. Commit cluster to dev branch
2. Test in dev environment
3. Merge dev → staging
4. Test in staging
5. Merge staging → main
6. Deploys to production
```

**Strategy 2: Directory-based promotion**

```
clusters/
  dev/
    site-001/
  staging/
    site-001/
  production/
    site-001/

Workflow:
1. Create cluster in dev/
2. Copy to staging/ when ready
3. Copy to production/ when validated
```

**Strategy 3: Version-based promotion**

```yaml
# Use ClusterClass versions
spec:
  topology:
    class: production-edge-v1  # Stable
    # OR
    class: production-edge-v2  # New version, testing

# Gradually migrate clusters from v1 to v2
```

**Example promotion with Fleet:**

```yaml
# fleet.yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: edge-clusters
spec:
  repo: https://github.com/myorg/edge-gitops
  branch: main
  paths:
  - clusters

  targetCustomizations:
  # Dev environment
  - name: dev
    clusterSelector:
      matchLabels:
        environment: dev
    helm:
      values:
        clusterClass: production-edge-dev
        replicaCount: 1

  # Staging environment
  - name: staging
    clusterSelector:
      matchLabels:
        environment: staging
    helm:
      values:
        clusterClass: production-edge-staging
        replicaCount: 2

  # Production environment
  - name: production
    clusterSelector:
      matchLabels:
        environment: production
    helm:
      values:
        clusterClass: production-edge-v1
        replicaCount: 3
```

### Secret-Management

**Option 1: Sealed Secrets**

```bash
# Install Sealed Secrets controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/controller.yaml

# Install kubeseal CLI
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/kubeseal-0.26.0-linux-amd64.tar.gz
tar -xvzf kubeseal-0.26.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Create sealed secret
kubectl create secret generic bmc-secret \
  --from-literal=username=root \
  --from-literal=password=calvin \
  --dry-run=client -o yaml | \
  kubeseal -o yaml > bmc-sealed-secret.yaml

# Commit sealed secret to Git (safe!)
git add bmc-sealed-secret.yaml
git commit -m "Add BMC credentials"
```

**Sealed secret in cluster definition:**

```yaml
# bmc-sealed-secret.yaml (safe to commit)
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: server-01-bmc-secret
  namespace: metal3
spec:
  encryptedData:
    username: AgBX7Qn... (encrypted)
    password: AgC9Km... (encrypted)
  template:
    type: Opaque
```

**Option 2: External Secrets Operator**

```bash
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace
```

**Configure secret backend (Vault example):**

```yaml
# secretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: metal3
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets"
```

**External secret:**

```yaml
# external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: server-01-bmc-secret
  namespace: metal3
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: server-01-bmc-secret
    creationPolicy: Owner
  data:
  - secretKey: username
    remoteRef:
      key: bmc/server-01
      property: username
  - secretKey: password
    remoteRef:
      key: bmc/server-01
      property: password
```

**Option 3: SOPS (Mozilla)**

```bash
# Install SOPS
wget https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops

# Configure SOPS with age or GPG key
# Create .sops.yaml in repo root
cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: .*.enc.yaml$
    encrypted_regex: ^(data|stringData)$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
EOF

# Encrypt secret
sops --encrypt secret.yaml > secret.enc.yaml

# Commit encrypted file
git add secret.enc.yaml
```

**Decrypt in GitOps pipeline:**

```yaml
# ArgoCD with SOPS plugin
# Or Fleet with pre-sync hook to decrypt
```

### Drift-Remediation

**Detect drift:**

```bash
# ArgoCD shows drift in UI
# Access ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443

# Or CLI
argocd app diff edge-clusters

# Fleet shows drift in bundle status
kubectl get bundles -n fleet-default -o wide
```

**Auto-remediation with Fleet:**

```yaml
# fleet.yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: edge-clusters
spec:
  # ...
  correctDrift:
    enabled: true
    force: false  # Don't force-delete resources
    keepFailHistory: 10
```

**Auto-remediation with ArgoCD:**

```yaml
# Application with self-heal
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: edge-clusters
spec:
  # ...
  syncPolicy:
    automated:
      selfHeal: true  # Auto-remediate drift
      prune: false    # Don't auto-delete
```

**Manual remediation:**

```bash
# With ArgoCD
argocd app sync edge-clusters

# With Fleet
# Delete and recreate bundle
kubectl delete bundle -n fleet-default edge-clusters-clusters-production
# Fleet will recreate from Git

# With kubectl
# Reapply from Git
git pull
kubectl apply -f clusters/production/site-001/
```

**Prevent drift:**

```yaml
# Add annotation to prevent modifications
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: prod-site-001
  annotations:
    fleet.cattle.io/managed: "true"  # Fleet manages this
    argocd.argoproj.io/sync-wave: "1"  # ArgoCD controls this
spec:
  # ...
```

[↑ Back to ToC](#table-of-contents)

---

## Monitoring-and-Observability

Comprehensive monitoring strategy for Cluster API and SUSE Edge deployments.

### CAPI-Controller-Logs

**View controller logs:**

```bash
# Core CAPI controller
kubectl logs -n cluster-api-system deployment/capi-controller-manager -f

# Filter for specific cluster
kubectl logs -n cluster-api-system deployment/capi-controller-manager | grep "cluster=edge-cluster-01"

# RKE2 control plane controller
kubectl logs -n rke2-control-plane-system deployment/rke2-control-plane-controller-manager -f

# RKE2 bootstrap controller
kubectl logs -n rke2-bootstrap-system deployment/rke2-bootstrap-controller-manager -f

# Metal3 infrastructure controller
kubectl logs -n capm3-system deployment/capm3-controller-manager -f

# Bare Metal Operator
kubectl logs -n baremetal-operator-system deployment/baremetal-operator-controller-manager -f

# Ironic (multiple containers)
kubectl logs -n baremetal-operator-system deployment/ironic -c ironic-api -f
kubectl logs -n baremetal-operator-system deployment/ironic -c ironic-conductor -f
kubectl logs -n baremetal-operator-system deployment/ironic -c ironic-inspector -f
```

**Increase log verbosity:**

```bash
# Edit deployment to add -v flag
kubectl edit deployment -n cluster-api-system capi-controller-manager

# Add to container args:
# - --v=5  (levels: 0=errors only, 5=debug, 10=trace)
```

**Structured logging:**

```bash
# CAPI uses structured logging (JSON)
kubectl logs -n cluster-api-system deployment/capi-controller-manager | jq

# Filter specific events
kubectl logs -n cluster-api-system deployment/capi-controller-manager | \
  jq 'select(.msg == "Reconciling Cluster")'

# Count reconciliation loops
kubectl logs -n cluster-api-system deployment/capi-controller-manager | \
  jq 'select(.msg == "Reconciling Cluster") | .cluster' | \
  sort | uniq -c
```

### Cluster-Provisioning-Metrics

**Expose CAPI metrics:**

```bash
# CAPI controllers expose metrics on :8080/metrics
kubectl port-forward -n cluster-api-system deployment/capi-controller-manager 8080:8080

# Query metrics
curl http://localhost:8080/metrics
```

**Key metrics:**

```
# Cluster count by phase
capi_cluster_count{phase="Provisioned"} 45
capi_cluster_count{phase="Provisioning"} 3
capi_cluster_count{phase="Failed"} 1

# Machine count by phase
capi_machine_count{phase="Running"} 150
capi_machine_count{phase="Provisioning"} 5
capi_machine_count{phase="Failed"} 2

# Reconciliation duration
capi_cluster_reconcile_duration_seconds_bucket{le="1"} 1200
capi_cluster_reconcile_duration_seconds_bucket{le="5"} 1450
capi_cluster_reconcile_duration_seconds_bucket{le="10"} 1480

# Reconciliation errors
capi_cluster_reconcile_errors_total{cluster="edge-cluster-01"} 3
```

**Prometheus ServiceMonitor:**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: capi-controller-metrics
  namespace: cluster-api-system
spec:
  selector:
    matchLabels:
      control-plane: controller-manager
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

### Machine-State-Monitoring

**Track machine states:**

```bash
# Get machine counts by phase
kubectl get machines -A -o json | \
  jq -r '.items | group_by(.status.phase) | map({phase: .[0].status.phase, count: length}) | .[]'

# Output:
# {"phase":"Running","count":150}
# {"phase":"Provisioning","count":5}
# {"phase":"Failed","count":2}
```

**Machine lifecycle duration metrics:**

```yaml
# Custom metric recording in Prometheus
# Calculate time from creation to Running

# PromQL query:
histogram_quantile(0.95,
  rate(capi_machine_provision_duration_seconds_bucket[5m])
)

# This shows 95th percentile machine provisioning time
```

**Machine failure rate:**

```yaml
# PromQL: Machine failure rate
rate(capi_machine_count{phase="Failed"}[1h])
```

**Alert on prolonged provisioning:**

```yaml
# PrometheusRule
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: capi-machine-alerts
  namespace: cluster-api-system
spec:
  groups:
  - name: capi.machines
    interval: 30s
    rules:
    - alert: MachineProvisioningTooLong
      expr: |
        (time() - kube_pod_created{namespace="cluster-api-system"}) > 1800
        and
        capi_machine_phase{phase="Provisioning"} == 1
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Machine {{ $labels.machine }} stuck in Provisioning for >30min"
        description: "Machine {{ $labels.machine }} in cluster {{ $labels.cluster }} has been provisioning for over 30 minutes."
    
    - alert: HighMachineFailureRate
      expr: rate(capi_machine_count{phase="Failed"}[5m]) > 0.1
      for: 10m
      labels:
        severity: critical
      annotations:
        summary: "High machine failure rate detected"
        description: "More than 0.1 machines per second are failing."
```

### Provider-Metrics

**Metal3 metrics:**

```bash
# BareMetalHost states
kubectl get baremetalhosts -A -o json | \
  jq -r '.items | group_by(.status.provisioning.state) | map({state: .[0].status.provisioning.state, count: length})'

# BareMetalHost errors
kubectl get baremetalhosts -A -o json | \
  jq -r '.items[] | select(.status.errorMessage != null) | {name: .metadata.name, error: .status.errorMessage}'
```

**RKE2 provider metrics:**

```bash
# RKE2ControlPlane status
kubectl get rke2controlplane -A -o json | \
  jq -r '.items[] | {name: .metadata.name, ready: .status.ready, replicas: .spec.replicas, readyReplicas: .status.readyReplicas}'
```

**Custom metrics exporter:**

```yaml
# Deploy custom exporter for CAPI resources
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capi-exporter
  namespace: cluster-api-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: capi-exporter
  template:
    metadata:
      labels:
        app: capi-exporter
    spec:
      serviceAccountName: capi-exporter
      containers:
      - name: exporter
        image: my-registry/capi-exporter:v1.0.0
        ports:
        - containerPort: 9090
          name: metrics
        command:
        - /capi-exporter
        - --metrics-port=9090
        - --namespaces=default,production,staging
---
apiVersion: v1
kind: Service
metadata:
  name: capi-exporter
  namespace: cluster-api-system
  labels:
    app: capi-exporter
spec:
  ports:
  - port: 9090
    name: metrics
  selector:
    app: capi-exporter
```

### Prometheus-and-Grafana-Integration

**Install kube-prometheus-stack:**

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin
```

**ServiceMonitor for CAPI:**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: capi-controllers
  namespace: monitoring
spec:
  namespaceSelector:
    matchNames:
    - cluster-api-system
    - rke2-control-plane-system
    - rke2-bootstrap-system
    - capm3-system
    - baremetal-operator-system
  selector:
    matchLabels:
      control-plane: controller-manager
  endpoints:
  - port: metrics
    interval: 30s
```

**Grafana dashboard for CAPI:**

```json
{
  "dashboard": {
    "title": "Cluster API Overview",
    "panels": [
      {
        "title": "Cluster Count by Phase",
        "targets": [{
          "expr": "sum by (phase) (capi_cluster_count)"
        }],
        "type": "stat"
      },
      {
        "title": "Machine Count by Phase",
        "targets": [{
          "expr": "sum by (phase) (capi_machine_count)"
        }],
        "type": "piechart"
      },
      {
        "title": "Cluster Reconciliation Duration (p95)",
        "targets": [{
          "expr": "histogram_quantile(0.95, rate(capi_cluster_reconcile_duration_seconds_bucket[5m]))"
        }],
        "type": "graph"
      },
      {
        "title": "Failed Machines",
        "targets": [{
          "expr": "capi_machine_count{phase=\"Failed\"}"
        }],
        "type": "table"
      },
      {
        "title": "BareMetalHost States (Metal3)",
        "targets": [{
          "expr": "sum by (state) (metal3_baremetalhost_count)"
        }],
        "type": "piechart"
      }
    ]
  }
}
```

**Access Grafana:**

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Open browser: http://localhost:3000
# Username: admin
# Password: admin (or what you set)
```

### Alerting-Rules

**Critical alerts:**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: capi-critical-alerts
  namespace: monitoring
spec:
  groups:
  - name: capi.critical
    interval: 30s
    rules:
    # CAPI controller down
    - alert: CAPIControllerDown
      expr: up{job="capi-controller-manager"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "CAPI controller is down"
        description: "The CAPI controller manager has been down for more than 5 minutes."
    
    # High cluster failure rate
    - alert: HighClusterFailureRate
      expr: rate(capi_cluster_count{phase="Failed"}[10m]) > 0.01
      for: 15m
      labels:
        severity: critical
      annotations:
        summary: "High cluster failure rate"
        description: "More than 0.01 clusters per second are failing."
    
    # Cluster stuck provisioning
    - alert: ClusterStuckProvisioning
      expr: |
        (time() - capi_cluster_creation_timestamp) > 3600
        and
        capi_cluster_phase{phase="Provisioning"} == 1
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Cluster {{ $labels.cluster }} stuck in Provisioning"
        description: "Cluster {{ $labels.cluster }} has been provisioning for over 1 hour."
    
    # Control plane not ready
    - alert: ControlPlaneNotReady
      expr: capi_cluster_control_plane_ready == 0
      for: 10m
      labels:
        severity: critical
      annotations:
        summary: "Control plane not ready for {{ $labels.cluster }}"
        description: "Control plane for cluster {{ $labels.cluster }} has been not ready for 10 minutes."
    
    # Infrastructure not ready
    - alert: InfrastructureNotReady
      expr: capi_cluster_infrastructure_ready == 0
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Infrastructure not ready for {{ $labels.cluster }}"
        description: "Infrastructure for cluster {{ $labels.cluster }} has been not ready for 10 minutes."
```

**Warning alerts:**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: capi-warning-alerts
  namespace: monitoring
spec:
  groups:
  - name: capi.warnings
    interval: 1m
    rules:
    # Machine health check failures
    - alert: MachineHealthCheckFailing
      expr: capi_machinehealthcheck_unhealthy_machines > 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Unhealthy machines detected"
        description: "{{ $value }} machines are unhealthy in cluster {{ $labels.cluster }}."
    
    # Slow reconciliation
    - alert: SlowReconciliation
      expr: histogram_quantile(0.95, rate(capi_cluster_reconcile_duration_seconds_bucket[5m])) > 30
      for: 15m
      labels:
        severity: warning
      annotations:
        summary: "CAPI reconciliation is slow"
        description: "95th percentile reconciliation time is above 30 seconds."
    
    # BareMetalHost errors (Metal3)
    - alert: BareMetalHostErrors
      expr: metal3_baremetalhost_error_count > 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "BareMetalHost errors detected"
        description: "{{ $value }} BareMetalHosts are in error state."
```

**AlertManager configuration:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-kube-prometheus-stack-alertmanager
  namespace: monitoring
type: Opaque
stringData:
  alertmanager.yaml: |
    global:
      resolve_timeout: 5m
    
    route:
      group_by: ['alertname', 'cluster']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'default'
      routes:
      - match:
          severity: critical
        receiver: 'pagerduty'
        continue: true
      - match:
          severity: warning
        receiver: 'slack'
    
    receivers:
    - name: 'default'
      webhook_configs:
      - url: 'http://webhook-receiver:8080/alert'
    
    - name: 'slack'
      slack_configs:
      - api_url: 'https://hooks.slack.com/services/xxx/yyy/zzz'
        channel: '#capi-alerts'
        title: 'CAPI Alert: {{ .CommonAnnotations.summary }}'
        text: '{{ .CommonAnnotations.description }}'
    
    - name: 'pagerduty'
      pagerduty_configs:
      - service_key: 'your-pagerduty-key'
        description: '{{ .CommonAnnotations.summary }}'
```

[↑ Back to ToC](#table-of-contents)

---

## Security-Considerations

Security best practices for Cluster API and SUSE Edge deployments.

### RBAC-for-Management-Cluster

**Principle of least privilege:**

```yaml
# Role for cluster operators (can create/manage clusters)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-operator
rules:
# Cluster API resources
- apiGroups: ["cluster.x-k8s.io"]
  resources: ["clusters", "machines", "machinedeployments", "machinesets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["controlplane.cluster.x-k8s.io"]
  resources: ["rke2controlplanes", "kubeadmcontrolplanes"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["bootstrap.cluster.x-k8s.io"]
  resources: ["rke2configs", "kubeadmconfigs"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["infrastructure.cluster.x-k8s.io"]
  resources: ["metal3clusters", "metal3machines", "awsclusters", "awsmachines"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
# Secrets (for kubeconfig access)
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
  resourceNames: ["*-kubeconfig"]  # Only kubeconfig secrets
---
# Role binding
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-operators
subjects:
- kind: Group
  name: cluster-operators
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-operator
  apiGroup: rbac.authorization.k8s.io
```

**Read-only cluster viewer:**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-viewer
rules:
- apiGroups: ["cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["controlplane.cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["bootstrap.cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["infrastructure.cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
```

**Namespace-scoped cluster management:**

```yaml
# Allow team to manage clusters only in their namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: team-cluster-manager
  namespace: team-a
rules:
- apiGroups: ["cluster.x-k8s.io"]
  resources: ["clusters", "machines", "machinedeployments"]
  verbs: ["*"]
- apiGroups: ["controlplane.cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["bootstrap.cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["infrastructure.cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-a-cluster-managers
  namespace: team-a
subjects:
- kind: Group
  name: team-a
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: team-cluster-manager
  apiGroup: rbac.authorization.k8s.io
```

**ServiceAccount for GitOps:**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitops-cluster-manager
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: gitops-cluster-manager
rules:
- apiGroups: ["cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["controlplane.cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["bootstrap.cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["infrastructure.cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "create", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gitops-cluster-manager
subjects:
- kind: ServiceAccount
  name: gitops-cluster-manager
  namespace: default
roleRef:
  kind: ClusterRole
  name: gitops-cluster-manager
  apiGroup: rbac.authorization.k8s.io
```

### Provider-Credentials-Security

**Never hardcode credentials:**

```yaml
# BAD - hardcoded password
apiVersion: v1
kind: Secret
metadata:
  name: bmc-secret
type: Opaque
stringData:
  username: root
  password: calvin123  # DON'T DO THIS IN PRODUCTION!
```

**Use external secret management:**

```yaml
# GOOD - reference external secret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: bmc-secret
  namespace: metal3
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: bmc-secret
    creationPolicy: Owner
  data:
  - secretKey: username
    remoteRef:
      key: bmc/production/server-01
      property: username
  - secretKey: password
    remoteRef:
      key: bmc/production/server-01
      property: password
```

**Rotate credentials regularly:**

```bash
# Script to rotate BMC credentials
#!/bin/bash
BMC_HOST="192.168.1.101"
OLD_PASSWORD="current-password"
NEW_PASSWORD=$(openssl rand -base64 32)

# Update BMC password
curl -k -u root:${OLD_PASSWORD} -X PATCH https://${BMC_HOST}/redfish/v1/AccountService/Accounts/1 \
  -H "Content-Type: application/json" \
  -d "{\"Password\": \"${NEW_PASSWORD}\"}"

# Update Kubernetes secret
kubectl create secret generic bmc-secret \
  --from-literal=username=root \
  --from-literal=password=${NEW_PASSWORD} \
  --dry-run=client -o yaml | kubectl apply -f -

# Store new password in Vault
vault kv put secret/bmc/production/server-01 \
  username=root \
  password=${NEW_PASSWORD}
```

**Limit secret access:**

```yaml
# RBAC to restrict secret access
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
  namespace: metal3
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
  # Only specific secrets
  resourceNames:
  - "allowed-secret-1"
  - "allowed-secret-2"
```

### Workload-Cluster-Isolation

**Network policies for management cluster:**

```yaml
# Deny all ingress to CAPI controllers by default
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: cluster-api-system
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
# Allow only necessary ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-capi-controller
  namespace: cluster-api-system
spec:
  podSelector:
    matchLabels:
      control-plane: controller-manager
  policyTypes:
  - Ingress
  ingress:
  # Allow metrics scraping from Prometheus
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 8080
  # Allow webhooks from API server
  - from:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          component: kube-apiserver
    ports:
    - protocol: TCP
      port: 9443
```

**Separate namespaces per environment:**

```yaml
# Production clusters
apiVersion: v1
kind: Namespace
metadata:
  name: production-clusters
  labels:
    environment: production
---
# Staging clusters
apiVersion: v1
kind: Namespace
metadata:
  name: staging-clusters
  labels:
    environment: staging
---
# Network policy: production can't access staging
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: isolate-environments
  namespace: production-clusters
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          environment: production
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          environment: production
```

**Resource quotas per team:**

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-a-quota
  namespace: team-a
spec:
  hard:
    # Limit number of clusters
    count/clusters.cluster.x-k8s.io: "10"
    # Limit number of machines
    count/machines.cluster.x-k8s.io: "100"
    # Compute resources (for management cluster overhead)
    requests.cpu: "10"
    requests.memory: 20Gi
```

### Network-Security

**Isolate BMC network:**

```
VLAN 10 (Management)   - CAPI controllers only
VLAN 20 (BMC)          - BMC access only, no internet
VLAN 30 (Provisioning) - PXE/DHCP for provisioning
VLAN 40 (Production)   - Workload cluster traffic
```

**Firewall rules:**

```
Management → BMC:           Allow HTTPS (443) to BMC IPs
Management → Provisioning:  Allow DHCP (67/68), TFTP (69), HTTP (80)
BMC → Internet:             Deny all
Provisioning → Internet:    Deny all
Production → Internet:      Allow (with proxy/NAT)
```

**VPN for remote management:**

```yaml
# Require VPN for management cluster access
# Use Wireguard or similar

# kube-apiserver audit log to track access
apiVersion: v1
kind: Pod
metadata:
  name: kube-apiserver
  namespace: kube-system
spec:
  containers:
  - name: kube-apiserver
    command:
    - kube-apiserver
    - --audit-log-path=/var/log/kubernetes/audit.log
    - --audit-policy-file=/etc/kubernetes/audit-policy.yaml
    - --audit-log-maxage=30
    - --audit-log-maxbackup=10
    - --audit-log-maxsize=100
```

**Audit policy:**

```yaml
# /etc/kubernetes/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
# Log all CAPI resource changes
- level: RequestResponse
  resources:
  - group: "cluster.x-k8s.io"
  - group: "controlplane.cluster.x-k8s.io"
  - group: "bootstrap.cluster.x-k8s.io"
  - group: "infrastructure.cluster.x-k8s.io"

# Log secret access
- level: Metadata
  resources:
  - group: ""
    resources: ["secrets"]

# Don't log read-only requests
- level: None
  verbs: ["get", "list", "watch"]
```

### Image-Security

**Scan images before deployment:**

```bash
# Scan SLE Micro image
trivy image file://sle-micro-rke2.qcow2

# Or use Anchore, Clair, etc.
```

**Image signing and verification:**

```bash
# Sign image with cosign
cosign sign --key cosign.key ghcr.io/myorg/sle-micro-rke2:v1.35.0

# Verify signature
cosign verify --key cosign.pub ghcr.io/myorg/sle-micro-rke2:v1.35.0
```

**Admission controller for image verification:**

```yaml
# Using Kyverno or OPA Gatekeeper
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-images
spec:
  validationFailureAction: enforce
  rules:
  - name: verify-image-signature
    match:
      any:
      - resources:
          kinds:
          - Pod
    verifyImages:
    - imageReferences:
      - "ghcr.io/myorg/*"
      attestors:
      - count: 1
        entries:
        - keys:
            publicKeys: |-
              -----BEGIN PUBLIC KEY-----
              MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
              -----END PUBLIC KEY-----
```

**Private registry with authentication:**

```yaml
# Registry credentials
apiVersion: v1
kind: Secret
metadata:
  name: registry-creds
  namespace: metal3
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: <base64-encoded-docker-config>

---
# Reference in RKE2Config
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: RKE2Config
metadata:
  name: worker-config
spec:
  privateRegistriesConfig:
    mirrors:
      docker.io:
        endpoint:
        - https://registry.example.com
    configs:
      registry.example.com:
        auth:
          username: registry-user
          password: registry-pass
        tls:
          insecureSkipVerify: false
          caFile: /etc/ssl/certs/ca-certificates.crt
```

### Supply-Chain-Security

**SBOM generation:**

```bash
# Generate SBOM for image
syft packages file://sle-micro-rke2.qcow2 -o spdx-json > sbom.json

# Scan SBOM for vulnerabilities
grype sbom:./sbom.json
```

**Provenance attestation:**

```bash
# Generate provenance (what built this image)
cosign attest --predicate provenance.json --key cosign.key \
  ghcr.io/myorg/sle-micro-rke2:v1.35.0
```

**Policy enforcement:**

```yaml
# Require SBOM and provenance
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-attestations
spec:
  validationFailureAction: enforce
  rules:
  - name: check-sbom-exists
    match:
      any:
      - resources:
          kinds:
          - Pod
    verifyImages:
    - imageReferences:
      - "ghcr.io/myorg/*"
      attestations:
      - predicateType: https://spdx.dev/Document
        attestors:
        - count: 1
          entries:
          - keys:
              publicKeys: |-
                -----BEGIN PUBLIC KEY-----
                ...
                -----END PUBLIC KEY-----
```

### CIS-Compliance

**RKE2 is CIS hardened by default:**

```bash
# RKE2 includes:
# - Pod Security Standards enforced
# - Restrictive default network policies
# - Audit logging enabled
# - Secrets encryption at rest
# - TLS everywhere

# Verify CIS compliance
kubectl get psp  # PodSecurityPolicies configured

# Check RKE2 config
cat /etc/rancher/rke2/config.yaml
```

**Run CIS benchmark:**

```bash
# kube-bench for Kubernetes CIS benchmark
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml

# View results
kubectl logs job/kube-bench
```

**Remediate findings:**

```yaml
# Example: Enable audit logging
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: RKE2ControlPlane
metadata:
  name: cluster-cp
spec:
  serverConfig:
    kubeAPIServer:
      extraArgs:
      - --audit-log-path=/var/log/kubernetes/audit.log
      - --audit-policy-file=/etc/kubernetes/audit-policy.yaml
      - --audit-log-maxage=30
      - --audit-log-maxbackup=10
      - --audit-log-maxsize=100
    kubeControllerManager:
      extraArgs:
      - --profiling=false
      - --terminated-pod-gc-threshold=100
    kubeScheduler:
      extraArgs:
      - --profiling=false
```

[↑ Back to ToC](#table-of-contents)

---

## Advanced-Topics

Advanced Cluster API and SUSE Edge scenarios.

### Custom-Health-Checks

**Custom MachineHealthCheck conditions:**

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineHealthCheck
metadata:
  name: custom-health-check
spec:
  clusterName: edge-cluster-01
  selector:
    matchLabels:
      node-role: worker
  
  # Standard health checks
  unhealthyConditions:
  - type: Ready
    status: Unknown
    timeout: 5m
  - type: Ready
    status: "False"
    timeout: 5m
  
  # Custom condition checks
  - type: DiskPressure
    status: "True"
    timeout: 10m
  - type: MemoryPressure
    status: "True"
    timeout: 10m
  - type: PIDPressure
    status: "True"
    timeout: 10m
  
  # Network connectivity check (custom)
  - type: NetworkReachable
    status: "False"
    timeout: 3m
  
  maxUnhealthy: 40%
  nodeStartupTimeout: 15m
```

**Custom remediation strategies:**

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3RemediationTemplate
metadata:
  name: custom-remediation
spec:
  template:
    spec:
      strategy:
        type: Custom
        retryLimit: 3
        timeout: 10m
      
      # Custom remediation script
      remediationScript: |
        #!/bin/bash
        # Try soft reboot first
        echo "Attempting graceful reboot..."
        shutdown -r +1 "Automated remediation reboot"
        
        # If node doesn't recover, power cycle via BMC
        sleep 120
        if ! ping -c 3 $NODE_IP; then
          echo "Graceful reboot failed, power cycling..."
          ipmitool -I lanplus -H $BMC_IP -U $BMC_USER -P $BMC_PASS power cycle
        fi
```

### External-etcd

**Separate etcd cluster from control plane:**

```yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: RKE2ControlPlane
metadata:
  name: cluster-cp
spec:
  replicas: 3
  version: v1.35.0+rke2r1
  
  serverConfig:
    # Use external etcd
    etcd:
      # Don't run embedded etcd
      disable: true
    
    # Point to external etcd cluster
    etcdServers:
    - https://etcd-1.example.com:2379
    - https://etcd-2.example.com:2379
    - https://etcd-3.example.com:2379
    
    # etcd client certificates
    etcdCA: |
      -----BEGIN CERTIFICATE-----
      ...
      -----END CERTIFICATE-----
    etcdCert: |
      -----BEGIN CERTIFICATE-----
      ...
      -----END CERTIFICATE-----
    etcdKey: |
      -----BEGIN RSA PRIVATE KEY-----
      ...
      -----END RSA PRIVATE KEY-----
```

**Benefits:**
- etcd upgrades independent of control plane
- Better performance (dedicated etcd nodes)
- Easier backup/restore
- Support for larger clusters

**Drawbacks:**
- More complex setup
- Additional infrastructure
- Network latency considerations

### Custom-CAPI-Extensions

**Create custom infrastructure provider:**

```go
// Custom provider for proprietary infrastructure
package main

import (
    "context"
    
    clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
    "sigs.k8s.io/controller-runtime/pkg/client"
    "sigs.k8s.io/controller-runtime/pkg/controller"
    "sigs.k8s.io/controller-runtime/pkg/handler"
    "sigs.k8s.io/controller-runtime/pkg/source"
)

type CustomClusterReconciler struct {
    client.Client
}

func (r *CustomClusterReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // Fetch Cluster
    cluster := &clusterv1.Cluster{}
    if err := r.Get(ctx, req.NamespacedName, cluster); err != nil {
        return ctrl.Result{}, err
    }
    
    // Fetch CustomCluster (infrastructure ref)
    customCluster := &CustomCluster{}
    if err := r.Get(ctx, client.ObjectKey{
        Namespace: cluster.Namespace,
        Name: cluster.Spec.InfrastructureRef.Name,
    }, customCluster); err != nil {
        return ctrl.Result{}, err
    }
    
    // Provision infrastructure using proprietary API
    if !customCluster.Status.Ready {
        if err := r.provisionInfrastructure(ctx, customCluster); err != nil {
            return ctrl.Result{}, err
        }
    }
    
    // Set status
    customCluster.Status.Ready = true
    if err := r.Status().Update(ctx, customCluster); err != nil {
        return ctrl.Result{}, err
    }
    
    return ctrl.Result{}, nil
}

func (r *CustomClusterReconciler) provisionInfrastructure(ctx context.Context, cluster *CustomCluster) error {
    // Call proprietary infrastructure API
    // ...
    return nil
}
```

**Register custom provider:**

```go
func main() {
    mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
        Scheme: scheme,
    })
    
    if err := (&CustomClusterReconciler{
        Client: mgr.GetClient(),
    }).SetupWithManager(mgr); err != nil {
        panic(err)
    }
    
    if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
        panic(err)
    }
}
```

### Multi-Tenancy

**Namespace-per-tenant isolation:**

```yaml
# Tenant A namespace
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-a
  labels:
    tenant: tenant-a
---
# ResourceQuota for tenant A
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tenant-a-quota
  namespace: tenant-a
spec:
  hard:
    count/clusters.cluster.x-k8s.io: "5"
    count/machines.cluster.x-k8s.io: "50"
    requests.cpu: "20"
    requests.memory: 40Gi
---
# NetworkPolicy to isolate tenant
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tenant-a-isolation
  namespace: tenant-a
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          tenant: tenant-a
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          tenant: tenant-a
---
# RBAC for tenant A users
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tenant-a-cluster-manager
  namespace: tenant-a
rules:
- apiGroups: ["cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["controlplane.cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["bootstrap.cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["infrastructure.cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tenant-a-users
  namespace: tenant-a
subjects:
- kind: Group
  name: tenant-a-users
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: tenant-a-cluster-manager
  apiGroup: rbac.authorization.k8s.io
```

**ClusterClass-per-tenant:**

```yaml
# Tenant-specific ClusterClass
apiVersion: cluster.x-k8s.io/v1beta1
kind: ClusterClass
metadata:
  name: tenant-a-standard
  namespace: tenant-a
spec:
  # Tenant-specific defaults
  controlPlane:
    ref:
      apiVersion: controlplane.cluster.x-k8s.io/v1beta1
      kind: RKE2ControlPlaneTemplate
      name: tenant-a-control-plane
  
  # Enforce tenant labels
  patches:
  - name: tenantLabel
    definitions:
    - selector:
        apiVersion: cluster.x-k8s.io/v1beta1
        kind: Cluster
      jsonPatches:
      - op: add
        path: /metadata/labels/tenant
        value: tenant-a
```

### DR-Strategies

**Active-passive DR:**

```yaml
# Production cluster (active)
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: production
  namespace: default
  labels:
    role: active
spec:
  topology:
    class: production-edge
    version: v1.35.0+rke2r1
    # ...

---
# DR cluster (passive, kept in sync)
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: production-dr
  namespace: default
  labels:
    role: passive
spec:
  topology:
    class: production-edge
    version: v1.35.0+rke2r1
    # Same config as production
    # ...
```

**Velero for DR:**

```bash
# Backup production cluster
velero backup create production-backup --include-namespaces '*'

# Failover: restore to DR cluster
velero restore create --from-backup production-backup \
  --kubeconfig dr-cluster.kubeconfig
```

**etcd snapshot replication:**

```yaml
# etcd backup to S3 (production)
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: RKE2ControlPlane
metadata:
  name: production-cp
spec:
  serverConfig:
    etcd:
      backupConfig:
        enabled: true
        s3Config:
          bucket: production-etcd-backups
          folder: production
          region: us-west-2

---
# Restore from S3 to DR (automated)
apiVersion: batch/v1
kind: CronJob
metadata:
  name: etcd-dr-sync
spec:
  schedule: "*/30 * * * *"  # Every 30 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: sync
            image: amazon/aws-cli
            command:
            - /bin/sh
            - -c
            - |
              # Download latest backup
              aws s3 sync s3://production-etcd-backups/production s3://dr-etcd-backups/production-dr
```

### Cost-Optimization

**Right-sizing worker pools:**

```yaml
# Different worker classes for different workloads
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: cost-optimized
spec:
  topology:
    class: production-edge
    workers:
      machineDeployments:
      # Small pool for low-resource workloads
      - class: small-worker
        name: low-intensity
        replicas: 3
      
      # Medium pool for standard workloads
      - class: medium-worker
        name: standard
        replicas: 5
      
      # Large pool (autoscale) for variable workloads
      - class: large-worker
        name: compute-intensive
        replicas: 2
        metadata:
          annotations:
            cluster.x-k8s.io/cluster-api-autoscaler-node-group-min-size: "2"
            cluster.x-k8s.io/cluster-api-autoscaler-node-group-max-size: "10"
```

**Cluster hibernation (dev/test):**

```bash
# Scale down dev cluster after hours
kubectl scale machinedeployment dev-cluster-workers --replicas=0

# Scale control plane to 1
kubectl patch rke2controlplane dev-cluster-cp --type=merge -p '{"spec":{"replicas":1}}'

# Resume in morning (restore replicas)
kubectl scale machinedeployment dev-cluster-workers --replicas=5
kubectl patch rke2controlplane dev-cluster-cp --type=merge -p '{"spec":{"replicas":3}}'
```

**Scheduled scaling:**

```yaml
# CronJob to scale down after hours
apiVersion: batch/v1
kind: CronJob
metadata:
  name: scale-down-dev
spec:
  schedule: "0 18 * * 1-5"  # 6 PM weekdays
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: cluster-scaler
          containers:
          - name: kubectl
            image: bitnami/kubectl
            command:
            - /bin/sh
            - -c
            - |
              kubectl scale machinedeployment dev-cluster-workers --replicas=0
              kubectl patch rke2controlplane dev-cluster-cp --type=merge -p '{"spec":{"replicas":1}}'
---
# Scale up in morning
apiVersion: batch/v1
kind: CronJob
metadata:
  name: scale-up-dev
spec:
  schedule: "0 8 * * 1-5"  # 8 AM weekdays
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: cluster-scaler
          containers:
          - name: kubectl
            image: bitnami/kubectl
            command:
            - /bin/sh
            - -c
            - |
              kubectl scale machinedeployment dev-cluster-workers --replicas=5
              kubectl patch rke2controlplane dev-cluster-cp --type=merge -p '{"spec":{"replicas":3}}'
```

[↑ Back to ToC](#table-of-contents)

---

## Additional-Resources

### Official-SUSE-Edge-Documentation

**SUSE Edge 3.5 Documentation:**
- Main documentation: https://documentation.suse.com/suse-edge/3.5/single-html/edge/edge.html
- GitHub Pages: https://suse-edge.github.io/

**CAPI/Metal3 Provisioning:**
- Metal3 Quickstart: https://documentation.suse.com/suse-edge/3.4/html/edge/quickstart-metal3.html
- Metal3 Components: https://documentation.suse.com/suse-edge/3.0/html/edge/components-metal3.html
- Rancher Turtles: https://documentation.suse.com/suse-edge/3.4/html/edge/components-rancher-turtles.html
- Management Cluster Setup: https://suse-edge.github.io/atip-management-cluster.html

**Other SUSE Edge Provisioning Methods:**
- Edge Image Builder: https://documentation.suse.com/suse-edge/3.4/html/edge/components-eib.html
- Elemental (phone-home): https://documentation.suse.com/suse-edge/3.4/html/edge/components-elemental.html

### SUSE-Edge-Repositories

**Edge Image Builder:**
- Repository: https://github.com/suse-edge/edge-image-builder
- Container Registry: registry.suse.com/edge/3.5/edge-image-builder:1.3.2

### Cluster-API-Resources

**Official Cluster API:**
- Project home: https://cluster-api.sigs.k8s.io/
- GitHub: https://github.com/kubernetes-sigs/cluster-api
- Book (comprehensive guide): https://cluster-api.sigs.k8s.io/

**CAPI Providers:**
- CAPRKE2: https://github.com/rancher/cluster-api-provider-rke2
- Metal3: https://github.com/metal3-io/cluster-api-provider-metal3
- Provider list: https://cluster-api.sigs.k8s.io/reference/providers.html

### Rancher-Resources

**Rancher and Turtles:**
- Rancher product docs: https://documentation.suse.com/cloudnative/rancher-manager/latest/
- Rancher Turtles: https://rancher.github.io/turtles/
- Rancher CAPI integration: https://documentation.suse.com/cloudnative/rancher-manager/latest/en/integrations/cluster-api/

**Fleet GitOps:**
- Fleet documentation: https://fleet.rancher.io/
- Multi-cluster management with Fleet

### Community-Resources

**SUSE Community:**
- SUSE Edge blog posts: https://www.suse.com/c/tag/suse-edge/
- Edge computing insights: https://www.suse.com/c/edge-computing-empowering-real-time-data-processing-and-analysis/
- Retail edge trends: https://www.suse.com/c/the-future-of-edge-computing-in-retail-emerging-trends-and-strategic-insights-for-2026-and-beyond/

**Kubernetes Community:**
- CNCF Metal3 project: https://metal3.io/
- Kubernetes SIGs: https://github.com/kubernetes-sigs

### Learning-Paths

**Getting Started with SUSE Edge and Cluster API:**

1. **Start with concepts** (this guide, sections 1-7)
2. **Understand CAPI/Metal3 provisioning** (this guide focuses on this method)
3. **Deploy management cluster** (section 9 or SUSE Edge Metal3 quickstart)
4. **Provision first workload cluster** (section 10 or Metal3 quickstart)
5. **Implement GitOps workflows** (section 14)

**Advanced Topics:**

- Multi-cluster fleet management with Fleet
- NeuVector for container security
- Longhorn for storage
- Observability with Prometheus/Grafana
- Custom ClusterClass development

### Support-and-Training

**SUSE Support:**
- Enterprise support: Available with SUSE Edge subscriptions
- Support portal: https://www.suse.com/support/

**Training:**
- SUSE training catalog: https://training.suse.com/
- Kubernetes certifications: CKA, CKAD, CKS

---

**Document Information:**
- Guide focuses on CAPI/Metal3 provisioning method for bare metal edge clusters
- For other SUSE Edge provisioning methods, refer to the SUSE Edge documentation links above
- Version information current as of February 2026 (SUSE Edge 3.5)
- This guide is community-contributed and educational in nature

[↑ Back to ToC](#table-of-contents)

---

(Due to length constraints, I'll continue with the remaining sections in the next response. The guide now includes sections 1-17 and 22. Still need to complete: 18-Practical-Exercises, 19-Common-Mistakes-and-Troubleshooting, 20-Knowledge-Checks-with-Answers, and 21-Quick-Reference)

