# RKE2 & Kubernetes Internals - Learning Guide

**Timeline**: 1-day intensive, hands-on preparation
**Goal**: Deep understanding of RKE2 architecture, Kubernetes internals, and production troubleshooting
**Focus**: RKE2-specific implementation, component communication, failure modes, and systematic debugging

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [RKE2 Architecture](#rke2-architecture)
   - [Why RKE2](#why-rke2)
   - [Architecture Overview](#architecture-overview)
   - [Installation & Configuration](#installation-configuration)
   - [systemd Service Model](#systemd-service-model)
3. [Kubernetes Control Plane Internals](#kubernetes-control-plane-internals)
   - [API Server Deep Dive](#api-server-deep-dive)
   - [Request Flow Through the System](#request-flow-through-the-system)
   - [etcd Operations](#etcd-operations)
   - [Scheduler Internals](#scheduler-internals)
   - [Controller Manager](#controller-manager)
4. [CRDs & Controllers](#crds-controllers)
   - [Custom Resource Definitions](#custom-resource-definitions)
   - [Controller Pattern](#controller-pattern)
   - [Operator Pattern](#operator-pattern)
   - [CRD Versioning & Backward Compatibility](#crd-versioning-backward-compatibility)
5. [Rancher APIs & Extensions](#rancher-apis-extensions)
   - [Rancher Architecture Overview](#rancher-architecture-overview)
   - [Rancher API Structure](#rancher-api-structure)
   - [Rancher Extensions](#rancher-extensions)
   - [Working with Rancher API](#working-with-rancher-api)
6. [CNI Networking](#cni-networking)
   - [CNI Fundamentals](#cni-fundamentals)
   - [Canal (Calico + Flannel)](#canal-calico-flannel)
   - [Network Policies](#network-policies)
7. [CSI Storage & Longhorn](#csi-storage-longhorn)
   - [CSI Architecture](#csi-architecture)
   - [Longhorn Deep Dive](#longhorn-deep-dive)
   - [Backup and Restore](#backup-and-restore)
8. [Cluster Lifecycle](#cluster-lifecycle)
   - [Version Compatibility & Upgrade Paths](#version-compatibility-upgrade-paths)
   - [Upgrades](#upgrades)
   - [Backup & Disaster Recovery](#backup-disaster-recovery)
   - [Certificate Management](#certificate-management)
9. [Troubleshooting Guide](#troubleshooting-guide)
   - [Systematic Debugging Approach](#systematic-debugging-approach)
   - [Advanced Debugging Tools & Best Practices](#advanced-debugging-tools-best-practices)
   - [RKE2-Specific Issues](#rke2-specific-issues)
   - [etcd Troubleshooting](#etcd-troubleshooting)
   - [Networking Issues](#networking-issues)
   - [Storage Issues](#storage-issues)
   - [Node Problems](#node-problems)
   - [Upgrade Failures](#upgrade-failures)
10. [Practice Questions](#practice-questions)
11. [Quick Reference](#quick-reference)

---

## Prerequisites

**Assumed Knowledge:**
- Basic Kubernetes concepts (Pods, Deployments, Services, ConfigMaps, Secrets)
- kubectl command-line usage
- Linux systems administration (systemd, journalctl, basic networking)
- Container fundamentals (not Docker-specific)

**Required Tools:**

```bash
# Check required tools
command -v kubectl && echo "✓ kubectl" || echo "✗ kubectl MISSING"
command -v crictl && echo "✓ crictl" || echo "✗ crictl MISSING"
command -v etcdctl && echo "✓ etcdctl (optional)" || echo "✗ etcdctl not installed"
```

**Focus Areas:**
- **RKE2 architecture** - How it differs from vanilla Kubernetes and RKE1
- **Component communication** - API server ↔ etcd ↔ controllers ↔ kubelet
- **Failure modes** - What happens when components fail
- **Troubleshooting** - Systematic diagnosis of production issues
- **Storage & Networking** - Longhorn and Canal/Calico deep dives

**Estimated Time Breakdown:**
- RKE2 Architecture: 1.5 hours
- Kubernetes Internals: 2 hours
- CRDs & Controllers: 1 hour (conceptual, including versioning)
- Rancher APIs & Extensions: 30 minutes
- CNI Networking: 1 hour
- CSI Storage & Longhorn: 1 hour
- Cluster Lifecycle: 1.5 hours (including version compatibility)
- Troubleshooting Guide: 1.5 hours
- **Total: ~10 hours**

---

## RKE2-Architecture

**Time: 1.5 hours**

### Why-RKE2

RKE2 is Rancher's next-generation Kubernetes distribution, designed for security and compliance from the ground up.

**Key Differentiators:**

| Feature | RKE2 | Vanilla K8s (kubeadm) |
|---------|------|----------------------|
| **Security** | CIS 1.12 compliant by default (K8s 1.32+) | Manual hardening required |
| **Container Runtime** | containerd 2.0 (RKE2 v1.32+) | containerd/CRI-O |
| **Installation** | systemd service (like a distro) | Manual component setup |
| **Architecture** | Server/Agent binary model | Separate component binaries |
| **Pod Security** | Pod Security Standards enabled | Optional |
| **Network Policies** | Enabled by default | Optional |
| **FIPS 140-2** | Available | Manual setup |
| **etcd** | Embedded in rke2-server | External or static pod |

**When to Use RKE2:**
- Production workloads requiring compliance (PCI-DSS, HIPAA, FedRAMP)
- Edge deployments needing minimal footprint
- Air-gapped environments
- Organizations needing security-by-default
- Simplified operations compared to managing individual K8s components

### Architecture-Overview

**RKE2 Process Model:**

```
┌─────────────────────────────────────────────────────────────────┐
│                     Control Plane Node                          │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              rke2-server (systemd service)                │  │
│  │                                                           │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │  │
│  │  │   etcd      │  │ API Server  │  │  Scheduler  │        │  │
│  │  │ (embedded)  │  │             │  │             │        │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘        │  │
│  │  ┌─────────────────────────────────────────────────┐      │  │
│  │  │        Controller Manager                       │      │  │
│  │  └─────────────────────────────────────────────────┘      │  │
│  │  ┌─────────────────────────────────────────────────┐      │  │
│  │  │              kubelet                            │      │  │
│  │  └─────────────────────────────────────────────────┘      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                    ┌─────────┴─────────┐                        │
│                    │   containerd      │                        │
│                    └───────────────────┘                        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                        Worker Node                              │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              rke2-agent (systemd service)                 │  │
│  │                                                           │  │
│  │  ┌─────────────────────────────────────────────────┐      │  │
│  │  │              kubelet                            │      │  │
│  │  └─────────────────────────────────────────────────┘      │  │
│  │  ┌─────────────────────────────────────────────────┐      │  │
│  │  │            kube-proxy                           │      │  │
│  │  └─────────────────────────────────────────────────┘      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                    ┌─────────┴─────────┐                        │
│                    │   containerd      │                        │
│                    └───────────────────┘                        │
└─────────────────────────────────────────────────────────────────┘
```

**Key Architectural Points:**

1. **Single Binary Model**:
   - `rke2-server`: Control plane + kubelet (can schedule workloads on control nodes)
   - `rke2-agent`: Worker node kubelet + kube-proxy
   - Both are systemd services managed by the OS

2. **Embedded etcd**:
   - etcd runs as part of rke2-server process (not a separate container/process)
   - Simplifies HA setup and management
   - Reduces surface area for attacks

3. **containerd Native**:
   - No Docker dependency
   - Uses containerd directly via CRI
   - More secure and lightweight

4. **Static Pods for System Components**:
   - CNI plugins (Canal/Calico)
   - CoreDNS
   - Metrics-server
   - Located in `/var/lib/rancher/rke2/agent/pod-manifests/`

### Installation-Configuration

**Installation (Server Node):**

```bash
# Install RKE2 server
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=server sh -

# Enable and start service
systemctl enable rke2-server.service
systemctl start rke2-server.service

# Check status
systemctl status rke2-server.service

# Watch logs
journalctl -u rke2-server -f

# Get node token for joining agents
cat /var/lib/rancher/rke2/server/node-token
```

**Installation (Agent Node):**

```bash
# Install RKE2 agent
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=agent sh -

# Configure agent
mkdir -p /etc/rancher/rke2/
cat <<EOF > /etc/rancher/rke2/config.yaml
server: https://<server-ip>:9345
token: <node-token-from-server>
EOF

# Enable and start
systemctl enable rke2-agent.service
systemctl start rke2-agent.service

# Check status
systemctl status rke2-agent.service
journalctl -u rke2-agent -f
```

**Configuration File: /etc/rancher/rke2/config.yaml**

```yaml
# Server configuration example
# Location: /etc/rancher/rke2/config.yaml

# Cluster token (for HA)
token: my-shared-secret

# TLS SANs for API server
tls-san:
  - rancher.example.com
  - 192.168.1.100
  - loadbalancer.example.com

# Disable built-in components
disable:
  - rke2-ingress-nginx  # If using custom ingress

# CNI plugin (default: canal)
cni:
  - calico  # Options: canal, calico, cilium, none

# Cluster CIDR
cluster-cidr: 10.42.0.0/16
service-cidr: 10.43.0.0/16

# DNS settings
cluster-dns: 10.43.0.10
cluster-domain: cluster.local

# Node labels
node-label:
  - "node-role=control"
  - "environment=production"

# Node taints
node-taint:
  - "node-role.kubernetes.io/control-plane:NoSchedule"

# etcd snapshot configuration
etcd-snapshot-schedule-cron: "0 */12 * * *"  # Every 12 hours
etcd-snapshot-retention: 5
etcd-snapshot-dir: /var/lib/rancher/rke2/server/db/snapshots

# etcd S3 backup
etcd-s3: true
etcd-s3-endpoint: s3.amazonaws.com
etcd-s3-bucket: my-rke2-backups
etcd-s3-region: us-west-2
etcd-s3-access-key: <access-key>
etcd-s3-secret-key: <secret-key>

# Audit log
audit-policy-file: /etc/rancher/rke2/audit-policy.yaml

# Private registry
system-default-registry: registry.example.com

# Additional API server arguments
kube-apiserver-arg:
  - "anonymous-auth=false"
  - "profiling=false"
  - "audit-log-maxage=30"

# Additional controller manager arguments
kube-controller-manager-arg:
  - "terminated-pod-gc-threshold=1000"

# Additional kubelet arguments
kubelet-arg:
  - "max-pods=110"
  - "eviction-hard=memory.available<500Mi"
```

**Important File Locations:**

```bash
# Configuration
/etc/rancher/rke2/config.yaml              # Main config file

# Binaries and data
/var/lib/rancher/rke2/                     # RKE2 data directory
/var/lib/rancher/rke2/server/              # Server-specific data
/var/lib/rancher/rke2/server/tls/          # Certificates
/var/lib/rancher/rke2/agent/               # Agent-specific data
/var/lib/rancher/rke2/agent/containerd/    # containerd data
/var/lib/rancher/rke2/server/db/           # etcd data

# Kubeconfig
/etc/rancher/rke2/rke2.yaml                # Admin kubeconfig

# Static pod manifests
/var/lib/rancher/rke2/agent/pod-manifests/ # System component manifests

# Logs
journalctl -u rke2-server                   # Server logs
journalctl -u rke2-agent                    # Agent logs

# CNI configuration
/etc/cni/net.d/                            # CNI config
/var/lib/rancher/rke2/agent/etc/cni/net.d/ # RKE2-managed CNI config
```

### systemd-Service-Model

**Understanding rke2-server.service:**

```bash
# View service definition
systemctl cat rke2-server.service

# Key directives:
# - Type=notify: Service signals systemd when ready
# - KillMode=process: Only kill main process on stop
# - Delegate=yes: Allow systemd to manage cgroups

# Service control
systemctl start rke2-server     # Start server
systemctl stop rke2-server      # Stop (drains node gracefully)
systemctl restart rke2-server   # Restart
systemctl status rke2-server    # Check status

# Enable/disable auto-start
systemctl enable rke2-server    # Start on boot
systemctl disable rke2-server   # Don't start on boot
```

**Service Lifecycle:**

```
systemctl start rke2-server
         ↓
1. systemd starts /usr/local/bin/rke2 server
         ↓
2. rke2 initializes embedded etcd (if first server)
         ↓
3. Generates certificates (if needed)
         ↓
4. Starts API server, scheduler, controller-manager (embedded)
         ↓
5. Starts kubelet (registers node)
         ↓
6. Deploys static pod manifests (CoreDNS, CNI)
         ↓
7. Sends READY signal to systemd
         ↓
8. Service marked as active (running)
```

**Troubleshooting systemd Integration:**

```bash
# Service won't start
systemctl status rke2-server -l           # Full status with recent logs
journalctl -u rke2-server --since "10 minutes ago"

# Common issues:
# 1. Port 6443 already in use
netstat -tlnp | grep 6443

# 2. etcd data corruption
# Check: journalctl -u rke2-server | grep etcd
# Fix: Remove /var/lib/rancher/rke2/server/db/ and restore from backup

# 3. Certificate issues
# Check: journalctl -u rke2-server | grep certificate
# Fix: Remove /var/lib/rancher/rke2/server/tls/ and restart

# Service stops unexpectedly
journalctl -u rke2-server -n 100          # Last 100 log lines
systemctl show rke2-server | grep Result  # Exit reason

# Resource limits
systemctl show rke2-server | grep -E "(LimitNOFILE|LimitNPROC|LimitMEMLOCK)"
```

**HA Cluster Setup:**

```bash
# First server (initializes etcd cluster)
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=server sh -
systemctl enable --now rke2-server

# Get token
cat /var/lib/rancher/rke2/server/node-token
# Save output: K10abc123def456...

# Second server (joins etcd cluster)
mkdir -p /etc/rancher/rke2
cat <<EOF > /etc/rancher/rke2/config.yaml
server: https://<first-server-ip>:9345
token: K10abc123def456...
tls-san:
  - loadbalancer.example.com
  - 192.168.1.100
EOF

curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=server sh -
systemctl enable --now rke2-server

# Third server (completes 3-node etcd cluster)
# Same as second server, use first-server-ip or loadbalancer

# Verify cluster
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl get nodes
kubectl get endpoints -n kube-system

# Check etcd members
/var/lib/rancher/rke2/bin/etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key \
  member list
```

**Knowledge Check:**

1. What happens if rke2-server is stopped on a 3-node control plane?
   > **A:** The cluster continues operating with the remaining 2 nodes maintaining etcd quorum (2/3 majority). API requests route to the healthy servers, but you've lost redundancy and should restart the failed server to restore full HA.

2. Where is etcd data stored in RKE2?
   > **A:** `/var/lib/rancher/rke2/server/db/etcd/` - etcd runs embedded within the rke2-server process, not as a separate container.

3. How do you change the CNI plugin after installation?
   > **A:** Add `cni: <plugin-name>` to `/etc/rancher/rke2/config.yaml` and restart, but this is risky in production. It's safer to provision a new cluster with the desired CNI and migrate workloads.

4. What's the difference between `rke2 server` and `rke2 agent`?
   > **A:** `rke2 server` runs control plane components (API server, scheduler, controller-manager, embedded etcd) plus kubelet. `rke2 agent` runs only kubelet and kube-proxy for worker nodes.

5. How do you add a new server to an existing HA cluster?
   > **A:** Install rke2-server, create `/etc/rancher/rke2/config.yaml` with `server: https://<existing-server>:9345` and the cluster token, then start the service. It joins the etcd cluster automatically.

---

## Kubernetes-Control-Plane-Internals

**Time: 2 hours**

### API-Server-Deep-Dive

The API server is the **central hub** of Kubernetes. All components communicate through it, and it's the only component that talks to etcd.

**API Server Responsibilities:**

1. **RESTful API** - HTTP/JSON interface for all cluster operations
2. **Authentication** - Verify user/service identity
3. **Authorization** - Check permissions (RBAC)
4. **Admission Control** - Validate/mutate requests
5. **Schema Validation** - Ensure objects match API specs
6. **etcd Interaction** - Persist cluster state
7. **Watch Mechanism** - Notify clients of changes

**API Server Architecture:**

```
┌─────────────────────────────────────────────────────────────┐
│                      API Server                             │
│                                                             │
│  HTTP Request (kubectl, kubelet, controllers)               │
│         ↓                                                   │
│  ┌────────────────────┐                                     │
│  │  Authentication    │  (Who are you?)                     │
│  │  - X.509 certs     │                                     │
│  │  - Service accounts│                                     │
│  │  - OIDC tokens     │                                     │
│  └─────────┬──────────┘                                     │
│            ↓                                                │
│  ┌────────────────────┐                                     │
│  │  Authorization     │  (What can you do?)                 │
│  │  - RBAC            │                                     │
│  │  - Node            │                                     │
│  │  - Webhook         │                                     │
│  └─────────┬──────────┘                                     │
│            ↓                                                │
│  ┌────────────────────────────────┐                         │
│  │  Admission Controllers         │  (Is it valid/safe?)    │
│  │  - Mutating (modify request)   │                         │
│  │  - Validating (accept/reject)  │                         │
│  └─────────┬──────────────────────┘                         │
│            ↓                                                │
│  ┌────────────────────┐                                     │
│  │  Schema Validation │  (Matches API spec?)                │
│  └─────────┬──────────┘                                     │
│            ↓                                                │
│  ┌────────────────────┐                                     │
│  │  Write to etcd     │                                     │
│  └─────────┬──────────┘                                     │
│            ↓                                                │
│  ┌────────────────────┐                                     │
│  │  Notify Watchers   │  (Inform controllers/kubelet)       │
│  └────────────────────┘                                     │
└─────────────────────────────────────────────────────────────┘
```

**Key Admission Controllers:**

```bash
# List enabled admission controllers (RKE2)
kubectl exec -n kube-system <api-server-pod> -- \
  kube-apiserver --help | grep enable-admission-plugins

# Common admission controllers:
# - NamespaceLifecycle: Prevents operations in terminating namespaces
# - LimitRanger: Enforces resource limits
# - ServiceAccount: Automates service account management
# - ResourceQuota: Enforces namespace quotas
# - PodSecurityPolicy/PodSecurity: Enforces security policies
# - MutatingAdmissionWebhook: Custom mutation logic
# - ValidatingAdmissionWebhook: Custom validation logic
# - NodeRestriction: Limits what kubelets can modify
```

**API Server in RKE2:**

```bash
# API server runs as part of rke2-server process
# Check API server process
ps aux | grep kube-apiserver

# API server arguments configured in config.yaml
# /etc/rancher/rke2/config.yaml:
# kube-apiserver-arg:
#   - "audit-log-path=/var/lib/rancher/rke2/server/logs/audit.log"
#   - "audit-log-maxage=30"

# Check API server health
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/livez?verbose'

# API server metrics
kubectl get --raw='/metrics' | grep apiserver

# Watch API server logs
journalctl -u rke2-server | grep apiserver
```

### Request-Flow-Through-the-System

**Example: Creating a Deployment**

```
User runs: kubectl apply -f deployment.yaml

Step-by-step flow:

1. kubectl reads deployment.yaml
   ↓
2. kubectl sends POST request to API server
   URL: /apis/apps/v1/namespaces/default/deployments
   ↓
3. API Server: Authentication
   - Checks client certificate
   - Validates user identity
   ↓
4. API Server: Authorization (RBAC)
   - Checks if user can create deployments in namespace
   - Queries RBAC rules
   ↓
5. API Server: Admission Control
   - Mutating webhooks (e.g., inject sidecars)
   - Validating webhooks (e.g., policy enforcement)
   ↓
6. API Server: Schema Validation
   - Validates deployment spec against API schema
   ↓
7. API Server: Write to etcd
   - Saves deployment object to etcd
   - Returns HTTP 201 Created to kubectl
   ↓
8. API Server: Notify Watchers
   - Deployment controller has a watch on deployments
   - Controller receives notification
   ↓
9. Deployment Controller:
   - Sees new deployment
   - Calculates desired state (replicas)
   - Creates ReplicaSet object via API server
   ↓
10. ReplicaSet Controller:
    - Sees new ReplicaSet
    - Creates Pod objects via API server
    ↓
11. Scheduler:
    - Watches for unscheduled pods
    - Finds suitable node
    - Updates Pod.spec.nodeName via API server
    ↓
12. Kubelet (on assigned node):
    - Watches for pods assigned to its node
    - Sees new pod assignment
    - Pulls container image
    - Starts containers via containerd
    - Updates Pod.status via API server
    ↓
13. Final State:
    - Deployment → Running
    - ReplicaSet → Desired replicas met
    - Pods → Running on nodes
```

**Visualizing the Flow:**

```
 kubectl                API Server              etcd
    │                       │                    │
    │  POST /deployments    │                    │
    ├──────────────────────>│                    │
    │                       │                    │
    │                       │  Write deployment  │
    │                       ├───────────────────>│
    │                       │                    │
    │                       │  Ack               │
    │  HTTP 201 Created     │<───────────────────┤
    │<──────────────────────┤                    │
    │                       │                    │
                            │
                     ┌──────┴──────┐
                     ↓              ↓
            Deployment Ctrl    Watch Stream
                     │              │
                     │  List/Watch  │
                     ├─────────────>│
                     │              │
                     │  New Deploy  │
                     │<─────────────┤
                     │              │
            Creates ReplicaSet      │
                     │  POST /rs    │
                     ├─────────────>│
                     ...
```

**Component Communication Patterns:**

```bash
# Controllers use LIST + WATCH pattern
# 1. LIST: Get current state of resources
# 2. WATCH: Stream updates as they happen

# Example: How deployment controller works
# Pseudocode:
deployments, err := client.List(context.Background(), &appsv1.DeploymentList{})
watcher, err := client.Watch(context.Background(), &appsv1.DeploymentList{})

for event := range watcher.ResultChan() {
  switch event.Type {
  case "ADDED":
    // New deployment created
    reconcile(event.Object)
  case "MODIFIED":
    // Deployment updated
    reconcile(event.Object)
  case "DELETED":
    // Deployment deleted
    cleanup(event.Object)
  }
}

# This pattern is used by ALL controllers
# - Efficient (streams instead of polling)
# - Resilient (can resume from resource version)
# - Scalable (API server fans out to many watchers)
```

### etcd-Operations

**What is etcd?**

- Distributed, consistent key-value store
- Kubernetes' source of truth for cluster state
- Uses Raft consensus algorithm
- Requires odd number of members (3 or 5 for HA)

**etcd in RKE2:**

```bash
# etcd runs embedded in rke2-server process
# No separate container/process

# etcd data location
/var/lib/rancher/rke2/server/db/etcd/

# etcd certificates
/var/lib/rancher/rke2/server/tls/etcd/
```

**Using etcdctl:**

```bash
# Set etcd alias for convenience
alias etcdctl='/var/lib/rancher/rke2/bin/etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key'

# Check etcd cluster health
etcdctl endpoint health --cluster
etcdctl endpoint status --cluster -w table

# List etcd members
etcdctl member list -w table

# View cluster member details
etcdctl member list --write-out=json | jq

# Check etcd alarms (critical issues)
etcdctl alarm list

# Database size (important for performance)
etcdctl endpoint status -w table | awk '{print $5}' | tail -n +2
```

**Understanding etcd Data Structure:**

```bash
# Kubernetes stores all objects in etcd under /registry/

# List all keys (WARNING: lots of output)
etcdctl get / --prefix --keys-only

# View specific resource types
etcdctl get /registry/pods --prefix --keys-only
etcdctl get /registry/deployments --prefix --keys-only
etcdctl get /registry/configmaps --prefix --keys-only

# Get a specific pod's data
etcdctl get /registry/pods/default/nginx

# Count objects by type
etcdctl get /registry/pods --prefix --keys-only | wc -l
etcdctl get /registry/services --prefix --keys-only | wc -l

# etcd key structure:
# /registry/<resource-type>/<namespace>/<name>
# /registry/pods/kube-system/coredns-abc123
# /registry/deployments/default/nginx
# /registry/secrets/kube-system/bootstrap-token-xyz
```

**etcd Performance Monitoring:**

```bash
# Disk latency (critical metric)
etcdctl check perf

# Watch metrics
etcdctl endpoint status -w table --cluster

# Key metrics:
# - DB SIZE: Should be < 8GB (default limit)
# - LEADER: Only one leader per cluster
# - RAFT INDEX: Should be close across members
# - RAFT APPLIED: Applied log entries

# Performance issues often caused by:
# 1. Slow disk (etcd is disk I/O bound)
# 2. Large database size (too many objects/revisions)
# 3. Network latency between etcd members
# 4. CPU saturation
```

**etcd Maintenance:**

```bash
# Compact old revisions (free space)
# Get current revision
REV=$(etcdctl endpoint status --write-out="json" | jq -r '.[0].Status.header.revision')
echo "Current revision: $REV"

# Compact (remove history up to this revision)
etcdctl compact $REV

# Defragment (reclaim disk space)
# MUST do on each member individually
etcdctl defrag --cluster

# Check space reclaimed
etcdctl endpoint status -w table

# Automate compaction (RKE2 does this automatically)
# API server flag: --etcd-compaction-interval=5m (default)
```

### Scheduler-Internals

**Scheduler Responsibility:**

Assign pods to nodes based on:
- Resource requirements (CPU, memory)
- Affinity/anti-affinity rules
- Taints and tolerations
- Node selectors
- Topology constraints

**Scheduling Process:**

```
1. Watch for Unscheduled Pods
   - Pods with spec.nodeName == ""
   ↓
2. Filtering (Predicates)
   - Eliminate nodes that can't run the pod
   - Checks:
     • Sufficient resources (CPU/memory)?
     • Node selector matches?
     • Pod tolerates node taints?
     • Volume zones match?
     • Ports available?
   ↓
3. Scoring (Priorities)
   - Rank remaining nodes (0-100 score)
   - Factors:
     • Resource balance (spread workloads)
     • Affinity preferences
     • Image locality (image already pulled?)
     • Inter-pod affinity
   ↓
4. Binding
   - Select highest-scoring node
   - Create Binding object (sets pod.spec.nodeName)
   - API server writes to etcd
   ↓
5. Kubelet Picks Up Pod
   - Kubelet watches for pods on its node
   - Starts containers
```

**Scheduler in RKE2:**

```bash
# Scheduler runs as part of rke2-server
# Check scheduler logs
journalctl -u rke2-server | grep scheduler

# Check scheduler health
kubectl get --raw '/healthz/poststarthook/scheduler-scheduling'

# View scheduler events
kubectl get events --all-namespaces | grep Scheduled

# Scheduler metrics
kubectl get --raw '/metrics' | grep scheduler
```

**Debugging Scheduling Failures:**

```bash
# Pod stuck in Pending state
kubectl get pods -A | grep Pending

# Describe pod to see scheduling events
kubectl describe pod <pod-name>

# Common issues:
# - "Insufficient cpu/memory": Node doesn't have resources
# - "node(s) had taint": Pod doesn't tolerate node taints
# - "node(s) didn't match node selector": Label mismatch
# - "pod has unbound immediate PersistentVolumeClaims": No PV available

# Force pod to specific node (for testing)
kubectl run test --image=nginx --overrides='
{
  "spec": {
    "nodeName": "worker-1"
  }
}'
```

**Advanced Scheduling:**

```yaml
# Pod with complex scheduling requirements
apiVersion: v1
kind: Pod
metadata:
  name: complex-scheduling
spec:
  # Node selector: Hard requirement
  nodeSelector:
    disktype: ssd

  # Affinity: Prefer certain nodes
  affinity:
    # Node affinity
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/hostname
            operator: In
            values:
            - worker-1
            - worker-2

    # Pod affinity: Co-locate with other pods
    podAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app
              operator: In
              values:
              - cache
          topologyKey: kubernetes.io/hostname

    # Pod anti-affinity: Spread across nodes
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - complex-scheduling
        topologyKey: kubernetes.io/hostname

  # Tolerations: Allow scheduling on tainted nodes
  tolerations:
  - key: "node-role.kubernetes.io/control-plane"
    operator: "Exists"
    effect: "NoSchedule"

  containers:
  - name: app
    image: nginx
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
```

### Controller-Manager

**What is the Controller Manager?**

A collection of controllers that watch cluster state and make changes to achieve desired state.

**Core Controllers:**

1. **Node Controller**: Monitors node health, evicts pods from unhealthy nodes
2. **ReplicaSet Controller**: Maintains desired number of pod replicas
3. **Deployment Controller**: Manages ReplicaSets for declarative updates
4. **StatefulSet Controller**: Manages stateful applications with stable identities
5. **DaemonSet Controller**: Ensures pods run on all (or selected) nodes
6. **Job Controller**: Runs pods to completion
7. **CronJob Controller**: Schedules jobs
8. **Service Controller**: Creates cloud load balancers for LoadBalancer services
9. **Namespace Controller**: Deletes resources when namespace is deleted
10. **ServiceAccount Controller**: Creates default service accounts in namespaces
11. **PersistentVolume Controller**: Binds PVs to PVCs

**Controller Pattern (Reconciliation Loop):**

```
                ┌─────────────────┐
                │  Watch Resources│
                └────────┬────────┘
                         ↓
                ┌─────────────────┐
                │ Get Current State│
                └────────┬────────┘
                         ↓
                ┌─────────────────┐
                │ Get Desired State│
                └────────┬────────┘
                         ↓
                ┌─────────────────┐
           ┌────┤ Compare States  │
           │    └─────────────────┘
           │            │
    Match? │            │ Differ?
           │            │
           ↓            ↓
    ┌──────────┐  ┌──────────────┐
    │   Done   │  │ Take Action  │
    └──────────┘  │ (Create/Update│
                  │  /Delete)     │
                  └───────┬───────┘
                          │
                          └──────> Loop back to Watch
```

**Example: Deployment Controller Logic**

```
Deployment created with replicas: 3

Deployment Controller:
  1. Watches Deployment objects
  2. Sees new Deployment (desired: 3 replicas)
  3. No ReplicaSet exists (current: 0)
  4. Creates ReplicaSet with replicas: 3

ReplicaSet Controller:
  1. Watches ReplicaSet objects
  2. Sees new ReplicaSet (desired: 3 replicas)
  3. No Pods exist (current: 0)
  4. Creates 3 Pods

User updates Deployment to replicas: 5

Deployment Controller:
  1. Sees Deployment modified (desired: 5)
  2. ReplicaSet exists with replicas: 3 (current: 3)
  3. Updates ReplicaSet to replicas: 5

ReplicaSet Controller:
  1. Sees ReplicaSet modified (desired: 5)
  2. Pods exist: 3 (current: 3)
  3. Creates 2 more Pods

Total: 5 pods running
```

**Controller Manager in RKE2:**

```bash
# Controller manager runs as part of rke2-server
# Check controller manager logs
journalctl -u rke2-server | grep controller-manager

# Controller manager health
kubectl get --raw '/healthz/poststarthook/controller-manager'

# View controller manager metrics
kubectl get --raw '/metrics' | grep controller_manager

# Common controller manager flags (RKE2 config.yaml)
# kube-controller-manager-arg:
#   - "node-monitor-period=5s"           # How often to check node health
#   - "node-monitor-grace-period=40s"     # Grace before marking NotReady
#   - "pod-eviction-timeout=5m"          # Time before evicting pods
#   - "terminated-pod-gc-threshold=12500" # Clean up terminated pods
```

**Understanding Controller Behavior:**

```bash
# Watch what controllers are doing
kubectl get events --watch --all-namespaces

# See specific controller actions
kubectl get events -A | grep ReplicaSet
kubectl get events -A | grep Deployment
kubectl get events -A | grep Node

# Example events:
# - "Scaled up replica set nginx-xxx to 3"
# - "Created pod: nginx-xxx-abc"
# - "Successfully assigned default/nginx-xxx-abc to worker-1"
# - "Pulling image nginx:latest"
# - "Started container nginx"
```

**Knowledge Check:**

1. What happens when API server restarts in a 3-node control plane?
   > **A:** Clients (kubectl, controllers) automatically fail over to the other 2 API servers. Cluster operations continue uninterrupted because etcd quorum is maintained and load balancing distributes requests.

2. If etcd is down, can you still read cluster state via kubectl?
   > **A:** No, kubectl reads fail because the API server cannot query etcd. However, existing pods continue running since kubelets operate on last known state, but no new operations (create/update/delete) are possible.

3. What's the difference between Deployment and ReplicaSet controllers?
   > **A:** Deployment controller manages rolling updates and rollbacks by creating/updating ReplicaSets. ReplicaSet controller ensures the desired number of pod replicas are running by creating or deleting pods.

4. Why does scheduler only assign pods to nodes, not start them?
   > **A:** Separation of concerns - scheduler handles placement decisions (which node is best), while kubelets handle execution (starting containers). This decouples scheduling logic from container runtime operations.

5. What happens if a node becomes unreachable? (Trace through the components)
   > **A:** Kubelet stops sending heartbeats → node controller marks node NotReady after grace period → pod eviction controller waits (default 5min) → pods marked for deletion → scheduler places them on healthy nodes → new kubelets start replacement pods.

---

## CRDs-Controllers

**Time: 1 hour**

### Custom-Resource-Definitions

**What are CRDs?**

Custom Resource Definitions extend Kubernetes API with custom object types. They allow you to define your own resources (like Deployment, Pod, etc.) and store them in etcd.

**Example: Creating a CRD**

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.stable.example.com
spec:
  group: stable.example.com
  names:
    plural: backups
    singular: backup
    kind: Backup
    shortNames:
    - bk
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
              schedule:
                type: string
                pattern: '^(\d+|\*)(/\d+)?(\s+(\d+|\*)(/\d+)?){4}$'
              retention:
                type: integer
                minimum: 1
                maximum: 365
              target:
                type: string
            required:
            - schedule
            - target
          status:
            type: object
            properties:
              lastBackup:
                type: string
                format: date-time
              state:
                type: string
                enum:
                - Pending
                - Running
                - Completed
                - Failed
    additionalPrinterColumns:
    - name: Schedule
      type: string
      jsonPath: .spec.schedule
    - name: Target
      type: string
      jsonPath: .spec.target
    - name: Last Backup
      type: string
      jsonPath: .status.lastBackup
    - name: State
      type: string
      jsonPath: .status.state
```

**Using the Custom Resource:**

```bash
# Create CRD
kubectl apply -f backup-crd.yaml

# Verify CRD is registered
kubectl get crd backups.stable.example.com
kubectl api-resources | grep backup

# Create a custom resource instance
cat <<EOF | kubectl apply -f -
apiVersion: stable.example.com/v1
kind: Backup
metadata:
  name: database-backup
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  retention: 7
  target: "postgresql://db.example.com"
EOF

# List backups (just like any K8s resource)
kubectl get backups
kubectl get bk  # shortname

# Describe backup
kubectl describe backup database-backup

# Watch backups
kubectl get backups --watch

# The CRD is just data at this point - no logic!
# You need a controller to act on it
```

### Controller-Pattern

**What is a Controller?**

A control loop that watches resources and takes action to reconcile current state with desired state.

**Controller Reconciliation Concept:**

Controllers use a reconciliation loop pattern that watches resources and takes action to reconcile current state with desired state. The basic flow is:

1. **Watch for changes** - Controllers establish watch streams to the API server for specific resource types
2. **Receive events** - API server sends events (ADDED/MODIFIED/DELETED) when resources change
3. **Reconcile** - Controller compares current state vs desired state and takes action
4. **Update status** - Controller updates the resource status to reflect observed state
5. **Requeue if needed** - Controller can requeue for periodic checks or retry on failure

**Example Reconciliation Flow:**

When you create a Backup custom resource with a schedule, the controller:
1. Receives the ADDED event for the Backup resource
2. Checks if it's time to run based on the schedule
3. Creates a Kubernetes Job to perform the backup
4. Updates the Backup status to "Running"
5. Requeues for the next scheduled time
6. Cleans old backups based on retention policy

**Key Controller Concepts:**

1. **Reconciliation Loop**
   - Triggered by resource changes (ADDED/MODIFIED/DELETED)
   - Always works toward desired state
   - Idempotent - can be called multiple times safely

2. **Owner References**
   - Child resources reference parent
   - Automatic garbage collection when parent deleted
   - Enables resource hierarchy

3. **Status Subresource**
   - Separate from spec (desired state)
   - Updated by controller (observed state)
   - Prevents conflicts between user edits and controller updates

4. **Requeue Strategies**
   - Requeue immediately when something fails and should be retried
   - Requeue after a duration for periodic checks (e.g., 5 minutes)
   - Don't requeue on success (will be triggered by future watch events)
   - Return error for automatic exponential backoff requeue

5. **Watch Mechanism**
   - Watch primary resources (e.g., Backup CRDs)
   - Watch owned resources (e.g., Jobs created by the controller)
   - Watch arbitrary resources that affect reconciliation (e.g., ConfigMaps)

**Testing Controllers:**

Controllers should be tested using envtest, which provides a real API server for integration testing. Tests should verify:
- Resources are created correctly when CRDs are added
- Status is updated properly
- Owned resources are created with correct owner references
- Reconciliation logic handles edge cases (missing resources, conflicts, etc.)

**Real-World Example: Longhorn Controller**

```bash
# Longhorn uses many CRDs and controllers
kubectl get crd | grep longhorn

# Example CRDs:
# - volumes.longhorn.io
# - replicas.longhorn.io
# - engines.longhorn.io
# - nodes.longhorn.io

# When you create a PVC with Longhorn StorageClass:
# 1. PVC created → PV Controller binds it
# 2. Longhorn Controller sees new PVC
# 3. Creates Volume custom resource
# 4. Volume Controller creates Replicas (for redundancy)
# 5. Replica Controller starts replica pods on different nodes
# 6. Engine Controller creates engine pod to serve I/O
# 7. Volume attached to node and mounted in pod

# Trace this flow:
kubectl get pvc
kubectl get pv
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get replicas.longhorn.io -n longhorn-system
kubectl get engines.longhorn.io -n longhorn-system
```

**Debugging Controllers:**

```bash
# View controller logs
kubectl logs -n <namespace> deployment/<controller> -f

# Common issues:
# 1. RBAC permissions missing
kubectl get clusterrole <controller>-role -o yaml

# 2. Webhook configuration issues
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations

# 3. Rate limiting / API throttling
# Check controller logs for "rate limit" or "throttle"

# 4. Resource leaks
kubectl get <resource> --all-namespaces | wc -l

# 5. Finalizer deadlocks (resources stuck deleting)
kubectl get <resource> -o yaml | grep -A 5 finalizers
# Fix: kubectl patch <resource> -p '{"metadata":{"finalizers":[]}}' --type=merge
```

### Operator-Pattern

**What is an Operator?**

An operator = CRD + Controller + operational knowledge

It encodes domain-specific knowledge to manage complex applications (databases, monitoring, backups, etc.)

**Popular Operators:**

- Prometheus Operator (monitoring)
- Cert-Manager (TLS certificates)
- Longhorn (storage)
- MySQL Operator (database management)
- Velero (backup/restore)

**Example: cert-manager Operator**

```bash
# cert-manager CRDs
kubectl get crd | grep cert-manager
# - certificates.cert-manager.io
# - certificaterequests.cert-manager.io
# - issuers.cert-manager.io
# - clusterissuers.cert-manager.io

# Create ClusterIssuer (tells cert-manager how to issue certs)
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

# Create Certificate (declarative cert request)
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-com-tls
  namespace: default
spec:
  secretName: example-com-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - example.com
  - www.example.com
EOF

# What cert-manager does:
# 1. Watches Certificate resources
# 2. Sees new Certificate request
# 3. Creates CertificateRequest
# 4. Performs ACME challenge (HTTP-01 or DNS-01)
# 5. Obtains certificate from Let's Encrypt
# 6. Stores cert in Secret (example-com-tls)
# 7. Updates Certificate status
# 8. Watches expiry, renews automatically

# Check certificate status
kubectl get certificate
kubectl describe certificate example-com-tls

# View the created secret
kubectl get secret example-com-tls
kubectl describe secret example-com-tls
```

### CRD-Versioning-Backward-Compatibility

**Why CRD Versioning Matters:**

When building production operators, you'll need to evolve your API over time without breaking existing users. Kubernetes provides built-in mechanisms for API versioning and deprecation.

**Multi-Version CRD Example:**

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: databases.stable.example.com
spec:
  group: stable.example.com
  names:
    plural: databases
    singular: database
    kind: Database
  scope: Namespaced
  versions:
  # v1 - Current stable version
  - name: v1
    served: true
    storage: true  # Only ONE version can be storage version
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              engine:
                type: string
                enum: [postgres, mysql, mongodb]
              version:
                type: string
              replicas:
                type: integer
                minimum: 1
                maximum: 5
              resources:
                type: object
                properties:
                  storage:
                    type: string
                  memory:
                    type: string
                  cpu:
                    type: string
            required:
            - engine
            - version

  # v1beta1 - Deprecated but still served
  - name: v1beta1
    served: true
    storage: false
    deprecated: true
    deprecationWarning: "stable.example.com/v1beta1 Database is deprecated; use stable.example.com/v1 Database"
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              engine:
                type: string
              version:
                type: string
              size:  # Old field name
                type: string
                enum: [small, medium, large]
            required:
            - engine
            - version

  # Conversion webhook (optional - for automatic conversion)
  conversion:
    strategy: Webhook
    webhook:
      clientConfig:
        service:
          namespace: default
          name: database-converter
          path: /convert
      conversionReviewVersions:
      - v1
      - v1beta1
```

**Backward Compatibility Strategies:**

1. **Additive Changes Only (Safe)**
   - Add new optional fields
   - Add new API versions while keeping old ones
   - Add new enum values

2. **Breaking Changes (Requires Migration)**
   - Remove fields (requires deprecation cycle)
   - Change field types
   - Make optional fields required

3. **Deprecation Timeline**
   ```
   Release N: Introduce v2, mark v1 as deprecated
   Release N+1: Continue serving both v1 (deprecated) and v2
   Release N+2: Continue serving both, add loud warnings
   Release N+3: Remove v1, only serve v2
   ```

**Conversion Webhook Concept:**

A conversion webhook transforms CRD objects between different API versions. For example, if you deprecated a "size" field (small/medium/large) in favor of explicit "resources" fields, the webhook would:

1. Receive conversion request from API server
2. Check source and destination versions
3. Map old fields to new fields (e.g., size="small" becomes storage="10Gi", memory="2Gi")
4. Remove deprecated fields
5. Return converted object

This allows clients to use any supported API version while the cluster stores data in a single canonical version.

**Real-World Example: Longhorn API Evolution**

```bash
# Longhorn supports multiple API versions
kubectl get crd volumes.longhorn.io -o yaml | grep -A 10 versions:

# Example output shows:
# - v1beta2 (storage: true, served: true)
# - v1beta1 (storage: false, served: true, deprecated)

# You can use either version:
kubectl get volumes.longhorn.io.v1beta2 -n longhorn-system
kubectl get volumes.longhorn.io.v1beta1 -n longhorn-system  # Still works

# Kubernetes automatically converts between versions
```

**Best Practices for API Compatibility:**

1. **Never change storage version without migration**
   - Changing storage version requires re-writing all objects in etcd
   - Use storage version migration tool

2. **Test conversion paths**
   ```bash
   # Create object with old API version
   kubectl apply -f database-v1beta1.yaml

   # Read with new API version
   kubectl get database my-db -o yaml
   # Should show converted fields
   ```

3. **Document migration guides**
   - Provide clear upgrade instructions
   - Include example manifests for each version
   - Explain field mappings

4. **Use validating webhooks for safety**
   ```yaml
   # Prevent creating objects with deprecated fields
   apiVersion: admissionregistration.k8s.io/v1
   kind: ValidatingWebhookConfiguration
   metadata:
     name: database-validator
   webhooks:
   - name: validate.database.stable.example.com
     rules:
     - apiGroups: ["stable.example.com"]
       apiVersions: ["v1"]
       operations: ["CREATE", "UPDATE"]
       resources: ["databases"]
     clientConfig:
       service:
         name: database-validator
         namespace: default
   ```

**Knowledge Check:**

1. What's the difference between a CRD and a controller?
   > **A:** A CRD defines a new resource type (schema) and stores instances in etcd. A controller contains the business logic that watches CRD instances and reconciles them to desired state (takes action).

2. Can you use a CRD without a controller?
   > **A:** Yes, CRDs can store custom data in etcd without controllers, but they're just passive data storage. Controllers provide the automation and reconciliation logic that makes them useful.

3. How do controllers avoid conflicts when multiple instances are running?
   > **A:** Leader election - controllers use a Lease resource to elect a single active leader. Only the leader reconciles resources; others watch and wait to take over if the leader fails.

4. What happens if a controller crashes - is state lost?
   > **A:** No, state is preserved in etcd. When the controller restarts, it re-establishes watches, reads current state from etcd, and resumes reconciliation from where it left off.

5. Name three operators used in production environments.
   > **A:** Prometheus Operator (monitoring), cert-manager (certificate management), and Postgres Operator (database management).

6. How would you safely deprecate a CRD field in production?
   > **A:** Add the new field first, support both old and new fields simultaneously, mark old field as deprecated with API warnings, provide migration period (3+ releases), only remove after all users migrate.

7. What's the purpose of a conversion webhook?
   > **A:** It automatically converts CRD instances between different API versions, enabling bidirectional conversion so clients can use any served version while storage uses one canonical version.

8. Can you serve multiple API versions simultaneously?
   > **A:** Yes, set `served: true` for multiple versions. Only one can have `storage: true` (the canonical version in etcd), and the API server handles conversion between versions.

---

## Rancher-APIs-Extensions

**Time: 45 minutes**

### Rancher-Architecture-Overview

**Rancher Version Notes (February 2026):**
- Latest stable: **Rancher v2.13.2**
- Rancher 2.12.x+ requires Helm 3.18 or newer
- **RKE1 reached End of Life on July 31, 2025** — Rancher 2.12.0+ cannot provision or manage RKE1 clusters
- Migration path: RKE1 → RKE2 via Rancher migration tooling

**Rancher vs RKE2:**

- **RKE2**: Kubernetes distribution (like vanilla K8s, but secure by default)
- **Rancher**: Multi-cluster management platform that can manage RKE2, EKS, AKS, GKE, etc.

**Rancher Components:**

```
┌─────────────────────────────────────────────────────┐
│              Rancher Management Cluster             │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │         Rancher Server                       │   │
│  │  - API Server (extends K8s API)              │   │
│  │  - Authentication Provider                   │   │
│  │  - RBAC Management                           │   │
│  │  - Cluster Agent Management                  │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
        ▼             ▼             ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│  RKE2       │ │  EKS        │ │  GKE        │
│  Cluster 1  │ │  Cluster 2  │ │  Cluster 3  │
│             │ │             │ │             │
│  cattle-    │ │  cattle-    │ │  cattle-    │
│  cluster-   │ │  cluster-   │ │  cluster-   │
│  agent      │ │  agent      │ │  agent      │
└─────────────┘ └─────────────┘ └─────────────┘
```

### Rancher-API-Structure

**Rancher extends Kubernetes API with custom resources:**

```bash
# Rancher-specific CRDs
kubectl get crd | grep cattle.io

# Key Rancher CRDs:
# - clusters.management.cattle.io         # Cluster definitions
# - projects.management.cattle.io         # Project (namespace groups)
# - users.management.cattle.io            # User management
# - apps.catalog.cattle.io                # App catalog
# - clusterrepos.catalog.cattle.io        # Helm chart repos
```

**Rancher API Examples:**

```yaml
# 1. Cluster Resource - Defines a managed cluster
apiVersion: provisioning.cattle.io/v1
kind: Cluster
metadata:
  name: my-rke2-cluster
  namespace: fleet-default
spec:
  kubernetesVersion: v1.34.3+rke2r1
  rkeConfig:
    machineGlobalConfig:
      cni: calico
      disable:
      - rke2-ingress-nginx
      etcd-snapshot-schedule-cron: "0 */12 * * *"
      etcd-snapshot-retention: 5
    machineSelectorConfig:
    - config:
        protect-kernel-defaults: true
      machineLabelSelector:
        matchLabels:
          node-role.kubernetes.io/control-plane: "true"
```

```yaml
# 2. Project Resource - Groups namespaces
apiVersion: management.cattle.io/v3
kind: Project
metadata:
  name: my-project
  namespace: c-abcde  # Cluster ID
spec:
  displayName: "Production Apps"
  description: "Production application namespaces"
  resourceQuota:
    limit:
      limitsCpu: "10000m"
      limitsMemory: "20Gi"
  namespaceDefaultResourceQuota:
    limit:
      limitsCpu: "1000m"
      limitsMemory: "2Gi"
```

### Rancher-Extensions

**1. Custom Catalogs (Helm Charts):**

```yaml
apiVersion: catalog.cattle.io/v1
kind: ClusterRepo
metadata:
  name: my-company-charts
spec:
  url: https://charts.example.com
  gitRepo: https://github.com/example/charts
  gitBranch: main
```

**2. Custom UI Extensions:**

Rancher supports UI extensions for adding custom dashboards and functionality.

```javascript
// Rancher UI extension structure
export function init($plugin, store) {
  // Add custom navigation item
  $plugin.addNavItem({
    label: 'My Custom Tool',
    icon: 'icon-gear',
    to: { name: 'my-custom-route' }
  });

  // Add custom cluster action
  $plugin.addClusterAction({
    label: 'Custom Backup',
    action: (cluster) => {
      // Trigger custom backup logic
    }
  });
}
```

**3. Rancher Webhooks & Drivers:**

```yaml
# Machine driver for custom cloud providers
apiVersion: management.cattle.io/v3
kind: NodeDriver
metadata:
  name: custom-provider
spec:
  active: true
  builtin: false
  url: https://github.com/example/docker-machine-driver-custom/releases/download/v1.0.0/driver.tar.gz
  checksum: abc123...
```

### Working-with-Rancher-API

**API Access:**

```bash
# Get Rancher API endpoint
RANCHER_URL=https://rancher.example.com

# Create API token (from Rancher UI or via API)
TOKEN="token-xxxxx:xxxxxxxxxxxxxxxxx"

# List clusters via API
curl -k -H "Authorization: Bearer ${TOKEN}" \
  "${RANCHER_URL}/v3/clusters"

# Get specific cluster
curl -k -H "Authorization: Bearer ${TOKEN}" \
  "${RANCHER_URL}/v3/clusters/c-abcde"

# List nodes in cluster
curl -k -H "Authorization: Bearer ${TOKEN}" \
  "${RANCHER_URL}/v3/clusters/c-abcde/nodes"

# Create project via API
curl -k -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "project",
    "name": "my-project",
    "clusterId": "c-abcde"
  }' \
  "${RANCHER_URL}/v3/projects"
```

**Python API Client Example:**

```python
import requests

class RancherClient:
    def __init__(self, url, token):
        self.url = url
        self.token = token
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }

    def list_clusters(self):
        response = requests.get(
            f"{self.url}/v3/clusters",
            headers=self.headers,
            verify=False
        )
        return response.json()

    def create_namespace(self, cluster_id, project_id, namespace):
        payload = {
            "type": "namespace",
            "name": namespace,
            "projectId": f"{cluster_id}:{project_id}"
        }
        response = requests.post(
            f"{self.url}/v3/clusters/{cluster_id}/namespaces",
            headers=self.headers,
            json=payload,
            verify=False
        )
        return response.json()

# Usage
client = RancherClient("https://rancher.example.com", "token-xxxxx:xxx")
clusters = client.list_clusters()
```

**Knowledge Check:**

1. What's the difference between Rancher and RKE2?
   > **A:** RKE2 is a Kubernetes distribution (secure K8s implementation). Rancher (v2.13.2 as of Feb 2026) is a multi-cluster management platform that can manage multiple RKE2, EKS, AKS, and GKE clusters through a unified UI and API.

2. How does Rancher extend the Kubernetes API?
   > **A:** Rancher adds custom CRDs (clusters.management.cattle.io, projects.management.cattle.io, users.management.cattle.io) and runs cattle-cluster-agent in managed clusters to provide multi-cluster management capabilities beyond standard Kubernetes.

3. What is a Rancher Project and how does it differ from a namespace?
   > **A:** A Project is a Rancher concept that groups multiple namespaces together for unified RBAC, resource quotas, and network policies. Namespaces are Kubernetes primitives that isolate resources within a single cluster.

4. How would you automate cluster provisioning via Rancher API?
   > **A:** Create a Cluster resource YAML with `apiVersion: provisioning.cattle.io/v1` specifying kubernetesVersion, rkeConfig, and machine pools, then apply it via `kubectl apply` or POST to Rancher's REST API endpoint.

---

## CNI-Networking

**Time: 1 hour**

### CNI-Fundamentals

**What is CNI?**

Container Network Interface - specification for configuring network interfaces in Linux containers.

**CNI Responsibilities:**

1. Assign IP addresses to pods
2. Configure network routes
3. Set up network policies
4. Enable pod-to-pod communication across nodes

**CNI Workflow:**

```
kubelet starts a pod
         ↓
1. Creates network namespace for pod
         ↓
2. Calls CNI plugin binary
   /opt/cni/bin/<plugin> ADD <namespace>
         ↓
3. CNI plugin:
   - Allocates IP from pod CIDR
   - Creates veth pair (virtual ethernet)
   - Attaches one end to pod namespace
   - Attaches other end to host bridge/network
   - Configures routes
   - Returns IP and network config
         ↓
4. kubelet receives network info
         ↓
5. Pod has network connectivity
```

**CNI Files in RKE2:**

```bash
# CNI binaries
ls -la /opt/cni/bin/
# bandwidth, bridge, calico, dhcp, flannel, host-local, etc.

# CNI configuration
ls -la /var/lib/rancher/rke2/agent/etc/cni/net.d/
# 10-canal.conflist or 10-calico.conflist

# Example CNI config
cat /var/lib/rancher/rke2/agent/etc/cni/net.d/10-canal.conflist
```

### Canal-Calico-Flannel

**What is Canal?**

RKE2's default CNI - combines:
- **Flannel**: Simple overlay network (pod-to-pod connectivity)
- **Calico**: Network policies (security/segmentation)

**Canal Architecture:**

```
┌─────────────────────────────────────────────────────────┐
│                    Node 1 (10.0.1.10)                   │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │Pod A     │  │Pod B     │  │Pod C     │              │
│  │10.42.0.1 │  │10.42.0.2 │  │10.42.0.3 │              │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘              │
│       │             │             │                     │
│       └──────┬──────┴──────┬──────┘                     │
│              │             │                            │
│         ┌────┴─────────────┴────┐                       │
│         │  cbr0 bridge          │                       │
│         │  10.42.0.0/24         │                       │
│         └───────────┬───────────┘                       │
│                     │                                   │
│         ┌───────────┴───────────┐                       │
│         │  flannel.1 (VXLAN)    │ ← Overlay network     │
│         └───────────┬───────────┘                       │
│                     │                                   │
│         ┌───────────┴───────────┐                       │
│         │  eth0: 10.0.1.10      │                       │
│         └───────────────────────┘                       │
└─────────────────────┬───────────────────────────────────┘
                      │
            Physical Network
                      │
┌─────────────────────┴───────────────────────────────────┐
│                    Node 2 (10.0.1.11)                   │
│  Pod D: 10.42.1.1                                       │
│  flannel.1 → eth0: 10.0.1.11                            │
└─────────────────────────────────────────────────────────┘

Pod A (10.42.0.1) talks to Pod D (10.42.1.1):
1. Packet leaves Pod A
2. Goes to cbr0 bridge
3. Encapsulated by flannel.1 (VXLAN)
4. Sent to Node 2's eth0 (10.0.1.11)
5. Decapsulated by Node 2's flannel.1
6. Delivered to Pod D
```

**Canal Components:**

```bash
# Canal runs as DaemonSet (one pod per node)
kubectl get ds -n kube-system | grep canal
kubectl get pods -n kube-system -l k8s-app=canal

# On each node:
# 1. calico-node: Manages network policies and routes
# 2. flannel: Manages overlay network (VXLAN)

# Check Canal logs
kubectl logs -n kube-system -l k8s-app=canal -c calico-node
kubectl logs -n kube-system -l k8s-app=canal -c kube-flannel

# Calico configuration
kubectl get configmap -n kube-system canal-config -o yaml

# Pod CIDR allocation
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'
```

**Flannel VXLAN:**

```bash
# View flannel interface
ip -d link show flannel.1

# VXLAN details
# - VNI (VXLAN Network Identifier): 1
# - Port: 8472 (UDP)
# - Encapsulation: VXLAN header + original packet

# View flannel routes
ip route | grep flannel

# Example:
# 10.42.1.0/24 via 10.42.1.0 dev flannel.1 onlink
# (Route to Node 2's pod CIDR goes through flannel.1)

# Flannel subnet file (on each node)
cat /run/flannel/subnet.env
# FLANNEL_NETWORK=10.42.0.0/16
# FLANNEL_SUBNET=10.42.0.1/24
# FLANNEL_MTU=1450
```

### Network-Policies

**What are Network Policies?**

Firewall rules for pods - control ingress/egress traffic at IP and port level.

**Default Behavior (No Network Policies):**

```
ALL pods can talk to ALL pods (no restrictions)
```

**Example: Restrict Database Access**

```yaml
# Only allow web pods to access database pods
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-network-policy
  namespace: production
spec:
  # Apply to pods with label app=database
  podSelector:
    matchLabels:
      app: database

  # Policy types
  policyTypes:
  - Ingress
  - Egress

  # Ingress rules (who can connect TO database)
  ingress:
  - from:
    # Only from pods with app=web label
    - podSelector:
        matchLabels:
          app: web
    # On port 5432 (PostgreSQL)
    ports:
    - protocol: TCP
      port: 5432

  # Egress rules (what database can connect TO)
  egress:
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
  # Allow external backup server
  - to:
    - ipBlock:
        cidr: 192.168.100.10/32
    ports:
    - protocol: TCP
      port: 3306
```

**Network Policy Selectors:**

```yaml
# 1. podSelector - select pods in same namespace
- podSelector:
    matchLabels:
      role: frontend

# 2. namespaceSelector - select entire namespaces
- namespaceSelector:
    matchLabels:
      name: production

# 3. podSelector + namespaceSelector - pods in specific namespace
- namespaceSelector:
    matchLabels:
      name: production
  podSelector:
    matchLabels:
      role: frontend

# 4. ipBlock - IP ranges (external services)
- ipBlock:
    cidr: 10.0.0.0/8
    except:
    - 10.0.1.0/24
```

**Testing Network Policies:**

```bash
# Create test pods
kubectl run web --image=nginx -l app=web
kubectl run db --image=postgres -l app=database
kubectl run other --image=busybox -l app=other -- sleep 3600

# Before network policy: all can connect
kubectl exec web -- curl db:5432
kubectl exec other -- nc -zv db 5432  # Should work

# Apply network policy
kubectl apply -f db-network-policy.yaml

# After network policy:
kubectl exec web -- curl db:5432      # Works (allowed)
kubectl exec other -- nc -zv db 5432  # Fails (blocked)

# Verify policy
kubectl describe networkpolicy db-network-policy
```

**Calico Network Policies (Advanced):**

```yaml
# Calico extends Kubernetes NetworkPolicy with:
# - Egress rules to external IPs
# - Global policies (cluster-wide)
# - Deny rules (explicit deny)

apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: deny-egress-external
spec:
  # Apply to all pods
  selector: all()

  types:
  - Egress

  egress:
  # Allow internal cluster communication
  - action: Allow
    destination:
      nets:
      - 10.42.0.0/16  # Pod CIDR
      - 10.43.0.0/16  # Service CIDR

  # Allow DNS
  - action: Allow
    protocol: UDP
    destination:
      ports:
      - 53

  # Deny everything else
  - action: Deny

# View Calico policies
kubectl get globalnetworkpolicies
kubectl get networkpolicies --all-namespaces
```

**Knowledge Check:**

1. What's the difference between Flannel and Calico in Canal?
   > **A:** Flannel provides the overlay network (VXLAN) for pod-to-pod connectivity across nodes. Calico provides network policy enforcement via iptables rules for security and traffic control.

2. How do pods on different nodes communicate?
   > **A:** Packets leave the pod, go to the cbr0 bridge, get encapsulated by the flannel.1 VXLAN interface, travel over the physical network to the destination node, get decapsulated, and are delivered to the target pod.

3. What happens if you delete a Canal pod?
   > **A:** The Canal DaemonSet immediately recreates it. During the brief restart, existing connections continue (CNI is already configured), but new pods on that node can't get network configuration until the Canal pod is healthy again.

4. Do Network Policies apply to services or pods?
   > **A:** Network Policies apply to pods directly using label selectors. They control traffic between pods, not services (services are just routing abstractions).

5. How would you troubleshoot a pod that can't reach another pod?
   > **A:** Verify both pods are running, test connectivity (ping/curl), check network policies for denials, verify Canal/CNI pods are healthy, check node routing tables, test node-to-node connectivity, and examine CNI logs.

---

## CSI-Storage-Longhorn

**Time: 1 hour**

### CSI-Architecture

**What is CSI?**

Container Storage Interface - standard for exposing storage systems to containers.

**CSI Components:**

```
┌──────────────────────────────────────────────────────┐
│                 Kubernetes Cluster                   │
│                                                      │
│  ┌────────────────┐         ┌────────────────┐      │
│  │  PVC           │         │  Pod           │      │
│  │  my-data       │         │  nginx         │      │
│  └───────┬────────┘         └───────┬────────┘      │
│          │                          │               │
│          │ Binds                    │ Mounts        │
│          ↓                          ↓               │
│  ┌────────────────┐         ┌────────────────┐      │
│  │  PV            │         │  Volume        │      │
│  │  pvc-abc123    │────────→│  /var/lib/data │      │
│  └───────┬────────┘         └────────────────┘      │
│          │                                          │
│          │ Provisioned by                           │
│          ↓                                          │
│  ┌────────────────────────────────┐                 │
│  │  CSI Driver (Longhorn)         │                 │
│  │  - Controller (provision/attach)│                │
│  │  - Node Plugin (mount/unmount) │                 │
│  └────────────────┬───────────────┘                 │
│                   │                                 │
└───────────────────┼─────────────────────────────────┘
                    │
                    ↓
          ┌─────────────────────┐
          │  Storage Backend    │
          │  (Disks, NFS, etc.) │
          └─────────────────────┘
```

**CSI Volume Lifecycle:**

```
1. CREATE: PVC created by user
   ↓
2. PROVISION: CSI controller provisions storage (creates PV)
   ↓
3. BIND: Kubernetes binds PV to PVC
   ↓
4. ATTACH: CSI controller attaches volume to node (if pod scheduled)
   ↓
5. MOUNT: CSI node plugin mounts volume into pod
   ↓
6. USE: Application reads/writes data
   ↓
7. UNMOUNT: CSI node plugin unmounts volume (pod deleted)
   ↓
8. DETACH: CSI controller detaches volume from node
   ↓
9. DELETE: CSI controller deletes volume (if reclaimPolicy: Delete)
```

### Longhorn-Deep-Dive

**What is Longhorn?**

Cloud-native distributed block storage for Kubernetes (current stable: **v1.11.x**):
- Replicated storage (high availability)
- Snapshots and backups
- Disaster recovery
- Easy to use UI
- **V2 Data Engine** (technical preview in v1.11): SPDK-based for improved IOPS and lower latency

**Longhorn Architecture:**

```
┌────────────────────────────────────────────────────────┐
│                 Longhorn System                        │
│                                                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Longhorn Manager (Deployment)                   │  │
│  │  - API server                                    │  │
│  │  - Orchestration                                 │  │
│  └──────────────────────────────────────────────────┘  │
│                                                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Longhorn Driver (DaemonSet)                     │  │
│  │  - CSI plugin on each node                       │  │
│  └──────────────────────────────────────────────────┘  │
│                                                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Longhorn UI (Deployment)                        │  │
│  │  - Web interface for management                  │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│                 Volume: pvc-abc123                     │
│  Replicas: 3, Size: 10Gi                              │
│                                                        │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐       │
│  │ Replica 1  │  │ Replica 2  │  │ Replica 3  │       │
│  │ Node 1     │  │ Node 2     │  │ Node 3     │       │
│  │ /longhorn/ │  │ /longhorn/ │  │ /longhorn/ │       │
│  │ replicas/  │  │ replicas/  │  │ replicas/  │       │
│  └──────┬─────┘  └──────┬─────┘  └──────┬─────┘       │
│         │                │                │            │
│         └────────┬───────┴────────┬───────┘            │
│                  ↓                                     │
│         ┌────────────────┐                             │
│         │ Engine Pod     │                             │
│         │ (Node 1)       │                             │
│         │ - Handles I/O  │                             │
│         │ - Replication  │                             │
│         └───────┬────────┘                             │
│                 │                                      │
│                 ↓                                      │
│         ┌────────────────┐                             │
│         │ Application    │                             │
│         │ Pod (Node 1)   │                             │
│         └────────────────┘                             │
└────────────────────────────────────────────────────────┘
```

**Longhorn Components:**

```bash
# Longhorn namespace
kubectl get all -n longhorn-system

# Key components:
# 1. longhorn-manager (DaemonSet): Orchestration on each node
# 2. longhorn-driver-deployer: CSI driver
# 3. longhorn-ui: Web interface
# 4. instance-manager-* (per node): Manages engine/replica processes

# CRDs
kubectl get crd | grep longhorn
# - volumes.longhorn.io
# - replicas.longhorn.io
# - engines.longhorn.io
# - nodes.longhorn.io
# - settings.longhorn.io

# View volumes
kubectl get volumes.longhorn.io -n longhorn-system

# View replicas (where data is stored)
kubectl get replicas.longhorn.io -n longhorn-system
```

**Longhorn Volume Flow:**

```bash
# 1. Create StorageClass
kubectl get sc longhorn -o yaml

apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "30"
  fromBackup: ""
reclaimPolicy: Delete
volumeBindingMode: Immediate

# 2. Create PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
EOF

# 3. Longhorn controller provisions volume
# - Creates Volume CR
# - Creates 3 Replica CRs (on different nodes)
# - Creates Engine CR

# 4. Use in pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /var/www/html
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: my-data
EOF

# 5. When pod is scheduled:
# - CSI attaches volume to node
# - Engine pod starts on same node as application pod
# - Volume mounted into pod

# Trace the flow:
kubectl get pvc my-data
kubectl get pv <pv-name>
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get engines.longhorn.io -n longhorn-system
kubectl get replicas.longhorn.io -n longhorn-system

# Find replica pods
kubectl get pods -n longhorn-system | grep instance-manager
```

**Longhorn UI:**

```bash
# Access Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# Open browser: http://localhost:8080

# UI shows:
# - Volumes (list, create, attach, snapshot, backup)
# - Nodes (disk usage, scheduling status)
# - Settings (replica count, backup target, etc.)
# - Backups (view, restore)
```

### Backup-and-Restore

**Snapshots (Local):**

```bash
# Create snapshot via kubectl
kubectl create -f - <<EOF
apiVersion: longhorn.io/v1beta1
kind: Snapshot
metadata:
  name: my-data-snapshot-1
  namespace: longhorn-system
spec:
  volumeName: pvc-abc123
EOF

# Or via Longhorn UI or CLI
# Snapshots are stored locally on replica nodes

# List snapshots for a volume
kubectl get snapshots.longhorn.io -n longhorn-system

# Restore from snapshot (creates new volume)
# Use Longhorn UI or create PVC with snapshot parameter
```

**Backups (Remote S3/NFS):**

```bash
# Configure backup target (S3 example)
kubectl edit settings.longhorn.io -n longhorn-system backup-target

# Set:
# backup-target: s3://my-bucket@us-west-2/
# backup-target-credential-secret: aws-secret

# Create AWS credential secret
kubectl create secret generic aws-secret \
  -n longhorn-system \
  --from-literal=AWS_ACCESS_KEY_ID=<key> \
  --from-literal=AWS_SECRET_ACCESS_KEY=<secret>

# Create backup (via UI or CR)
# Backups are incremental and deduplicated

# List backups
kubectl get backups.longhorn.io -n longhorn-system

# Restore from backup
# 1. Create PVC from backup (via UI or annotation)
# 2. Longhorn downloads data from S3
# 3. Creates volume with restored data

# Disaster recovery scenario:
# - Cluster 1 has volume with backups to S3
# - Cluster 2 (new cluster) configured with same S3 backup target
# - In Cluster 2 Longhorn UI, you'll see backups from Cluster 1
# - Restore backup → new volume created in Cluster 2
```

**Troubleshooting Longhorn:**

```bash
# Volume stuck in "Attaching"
kubectl describe volume.longhorn.io -n longhorn-system <volume-name>
# Check: Node has available disk space?
# Check: Engine pod running?

# Replica failed
kubectl get replicas.longhorn.io -n longhorn-system | grep Failed
# Longhorn auto-rebuilds replicas
# Check: journalctl -u rke2-agent | grep longhorn

# Volume read-only
# Cause: All replicas became unavailable
# Fix: Check node disk space, restart instance-manager pods

# Backup fails
kubectl logs -n longhorn-system <longhorn-manager-pod> | grep backup
# Check: S3 credentials correct?
# Check: Network connectivity to S3?

# View support bundle (comprehensive diagnostic info)
# Download from Longhorn UI → Settings → Generate Support Bundle
```

**Knowledge Check:**

1. How many replicas does Longhorn create by default?
   > **A:** 3 replicas (configurable per StorageClass or volume). This provides high availability - a volume can tolerate 2 node failures and still maintain data.

2. What happens if a node with a replica goes down?
   > **A:** The volume remains accessible through replicas on other nodes. Longhorn marks the volume as degraded and automatically rebuilds the missing replica on a healthy node to restore full redundancy.

3. Can you resize a Longhorn volume?
   > **A:** Yes, Longhorn supports online volume expansion. Edit the PVC size, and Longhorn automatically expands the volume and all replicas without downtime.

4. What's the difference between a snapshot and a backup?
   > **A:** Snapshots are point-in-time copies stored locally on replica nodes (fast, for quick recovery). Backups are incremental copies stored remotely on S3/NFS (slower, for disaster recovery and long-term retention).

5. How would you migrate volumes from one cluster to another?
   > **A:** Create Longhorn backups to S3, configure the new cluster's Longhorn with the same S3 backup target, restore the backups in the new cluster to create volumes with the data, then attach to pods.

---

## Cluster-Lifecycle

**Time: 45 minutes**

### Version-Compatibility-Upgrade-Paths

**RKE2 / Kubernetes Version Compatibility:**

Understanding version compatibility is critical for safe upgrades and troubleshooting.

**RKE2 Versioning Scheme:**

```
v1.34.3+rke2r1
 │  │  │   │  └─ RKE2 release number (patch for RKE2-specific fixes)
 │  │  │   └──── RKE2 suffix
 │  │  └──────── Kubernetes patch version
 │  └─────────── Kubernetes minor version
 └────────────── Major version
```

**Kubernetes Version Support Matrix (February 2026):**

| RKE2 Release | K8s Version | Support Status | EOL Date | Key Component Changes |
|--------------|-------------|----------------|----------|-----------------------|
| v1.35.x      | 1.35        | Active         | ~Dec 2026 | etcd 3.6, containerd 2.0 |
| v1.34.x      | 1.34        | Active         | ~Aug 2026 | etcd 3.6.7, containerd 2.0 |
| v1.33.x      | 1.33        | Active         | ~Jun 2026 | etcd 3.5.26, containerd 2.0 |
| v1.32.x      | 1.32        | Maintenance    | Feb 28, 2026 | etcd 3.5.26, containerd 2.0 |
| v1.31.x      | 1.31        | EOL            | Nov 2025 | etcd 3.5.x, containerd 1.7/2.0 |

**Longhorn Version Compatibility:**

| Longhorn Version | Kubernetes Versions | RKE2 Versions | Notes |
|------------------|---------------------|---------------|-------|
| v1.11.x         | 1.26 - 1.35         | v1.32+        | Latest stable, V2 Data Engine (preview) |
| v1.10.x         | 1.25 - 1.34         | v1.31+        | Stable, production recommended |
| v1.9.x          | 1.24 - 1.33         | v1.30+        | Previous stable |
| v1.8.x          | 1.21 - 1.32         | v1.28-v1.32   | Legacy support only |

**CNI Version Compatibility:**

| CNI Plugin | RKE2 Version | Kubernetes | Notes |
|------------|--------------|------------|-------|
| Canal      | All RKE2     | All K8s    | Default, Calico + Flannel |
| Calico v3.31 | v1.34+     | 1.32+      | Latest stable |
| Calico v3.29 | v1.33+     | 1.31+      | Previous stable |
| Flannel    | All RKE2     | All K8s    | Simple overlay |
| Cilium v1.18 | v1.34+     | 1.32+      | Advanced features, bundled in v1.34 |
| Cilium v1.16 | v1.32+     | 1.30+      | Previous stable |

**Upgrade Path Decision Tree:**

```
Current: RKE2 v1.32.11+rke2r1 (K8s 1.32, etcd 3.5.26, containerd 2.0)
Target:  RKE2 v1.35.2+rke2r1 (K8s 1.35, etcd 3.6, containerd 2.0)

Can I upgrade directly?
├─ NO - Never skip minor versions
│
└─ Safe upgrade path:
   1. v1.32.11 → v1.33.7+rke2r1  (First upgrade to latest 1.33)
      - Check: etcd 3.5.26 present ✓ (CRITICAL for next step)
      - Check: Longhorn compatibility ✓
      - Check: CNI compatibility ✓
      - Check: Endpoints API deprecated (migrate to EndpointSlices)
      - Test in staging
      - Backup etcd
      - Upgrade

   2. v1.33.7 → v1.34.3+rke2r1   (Upgrade to 1.34)
      ⚠️ CRITICAL: This upgrades etcd 3.5.26 → 3.6.7
      - Verify etcd 3.5.26 BEFORE proceeding (see migration warning below)
      - Check: API deprecations
      - Test in staging
      - Backup etcd
      - Upgrade
      - Verify etcd cluster health post-upgrade

   3. v1.34.3 → v1.35.2+rke2r1   (Finally to target)
      - Check: In-place pod resize now GA
      - Test in staging
      - Backup etcd
      - Upgrade
```

**⚠️ CRITICAL: etcd 3.6 Migration (RKE2 v1.34+)**

RKE2 v1.34 and v1.35 ship etcd v3.6, which has **no safe direct upgrade path from etcd 3.5.x prior to 3.5.26**. Failure to follow the correct path can cause zombie members, loss of quorum, and complete cluster failure.

```bash
# BEFORE upgrading to RKE2 v1.34, verify etcd version:
/var/lib/rancher/rke2/bin/etcdctl version
# MUST show etcd Version: 3.5.26 or later

# Required upgrade path for etcd 3.6:
# RKE2 v1.31 (etcd 3.5.x) → v1.32/v1.33 (etcd 3.5.26) → v1.34 (etcd 3.6.7)
# NEVER skip the intermediate step!

# After upgrading to v1.34, verify etcd health:
/var/lib/rancher/rke2/bin/etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key \
  endpoint health --cluster
```

**Component Version Dependencies:**

```bash
# Check what versions are running
kubectl version
kubectl get nodes -o wide

# Check Longhorn version
kubectl get settings.longhorn.io -n longhorn-system -o yaml | grep current-longhorn-version

# Check CNI version (example for Calico)
kubectl get pods -n kube-system -l k8s-app=calico-node -o jsonpath='{.items[0].spec.containers[0].image}'

# Check containerd version (RKE2 bundles specific version)
# RKE2 v1.32+: containerd 2.0
# RKE2 v1.30-v1.31: containerd 1.7.23
crictl version

# Check etcd version (CRITICAL before upgrades to v1.34+)
# RKE2 v1.34+: etcd 3.6.7
# RKE2 v1.32-v1.33: etcd 3.5.26
/var/lib/rancher/rke2/bin/etcdctl version
```

**RKE2 v1.34 Bundled Components (reference):**

| Component | Version | Notes |
|-----------|---------|-------|
| Kubernetes | 1.34.3 | Core orchestration |
| etcd | 3.6.7 | ⚠️ Major upgrade from 3.5.x |
| containerd | 2.0 | Bundled since v1.32 |
| CoreDNS | 1.12.x | Cluster DNS |
| Calico | 3.31.2 | Network policy (Canal default) |
| Cilium | 1.18.6 | Alternative CNI option |
| Traefik | 3.6.7 | Default ingress controller |
| ingress-nginx | 1.14.3-hardened1 | Alternative ingress |
| metrics-server | latest | Resource metrics |

**API Version Deprecations:**

Kubernetes deprecates API versions over time. Know what's removed in each version:

| Kubernetes Version | API Removals/Changes | Action Required |
|--------------------|----------------------|-----------------|
| 1.25 | PodSecurityPolicy (v1beta1) removed | Migrate to Pod Security Standards |
| 1.25 | CronJob (v1beta1) removed | Update to batch/v1 |
| 1.26 | HorizontalPodAutoscaler (v2beta2) removed | Update to autoscaling/v2 |
| 1.27 | storage.k8s.io/v1beta1 CSIStorageCapacity removed | Update to storage.k8s.io/v1 |
| 1.29 | flowcontrol.apiserver.k8s.io/v1beta2 removed | Update to v1beta3 |
| 1.32 | flowcontrol.apiserver.k8s.io/v1beta3 removed | Update to flowcontrol/v1 |
| 1.33 | Endpoints API deprecated (warnings emitted) | Migrate to EndpointSlices |
| 1.33 | status.nodeInfo.kubeProxyVersion removed | Remove dependencies on this field |
| 1.33 | nftables kube-proxy backend GA | Consider migrating from iptables |

**Pre-Upgrade Checklist:**

```bash
# 1. Check for deprecated API usage
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis

# 2. Use pluto to scan for deprecated APIs in manifests
pluto detect-files -d .
pluto detect-helm -o wide

# 3. Check cluster health
kubectl get nodes
kubectl get pods -A | grep -v Running
kubectl get --raw='/readyz?verbose'  # Replaced componentstatuses (removed in 1.29)

# 4. Backup etcd
rke2 etcd-snapshot save --name pre-upgrade-$(date +%Y%m%d)

# 5. Verify backup
rke2 etcd-snapshot ls

# 6. Document current state
kubectl get nodes -o yaml > nodes-pre-upgrade.yaml
kubectl version -o yaml > versions-pre-upgrade.txt
```

**Notable Kubernetes Features (1.30-1.35):**

Features relevant to RKE2 operations and learning:

| K8s Version | Feature | Status | Impact |
|-------------|---------|--------|--------|
| 1.31 | AppArmor support | GA | Container security profiles in pod spec |
| 1.32 | Dynamic Resource Allocation (DRA) | GA | Standardized GPU/hardware allocation |
| 1.32 | PVC auto-cleanup for StatefulSets | GA | Automatic PVC deletion on StatefulSet scale-down |
| 1.33 | **Sidecar containers** | GA | Native init containers with `restartPolicy: Always` |
| 1.33 | **nftables kube-proxy backend** | GA | Replaces iptables, better performance at scale |
| 1.33 | Volume populators | GA | Pre-populate volumes from custom data sources |
| 1.33 | Topology-aware routing | GA | `trafficDistribution: PreferClose` for zone-local traffic |
| 1.33 | Endpoints API | Deprecated | Migrate to EndpointSlices |
| 1.34 | Minimal breaking changes | — | Good upgrade target |
| 1.35 | **In-place pod resize** | GA | Resize CPU/memory without pod restart |
| 1.35 | Fine-grained supplemental groups | GA | Better security for shared storage |

**Key takeaway**: K8s 1.33 is a landmark release (sidecar containers, nftables, EndpointSlices migration). K8s 1.35 brings in-place pod resize GA which changes how vertical scaling works.

---

**Longhorn Upgrade Strategy:**

```bash
# 1. Check current Longhorn version
kubectl get settings.longhorn.io -n longhorn-system current-longhorn-version

# 2. Read upgrade notes for target version
# https://longhorn.io/docs/VERSION/deploy/upgrade/

# 3. Create backup of Longhorn volumes
# Via Longhorn UI or CLI

# 4. Upgrade Longhorn (example: Helm)
helm repo update
helm upgrade longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --version 1.11.0

# 5. Wait for rollout
kubectl rollout status deployment/longhorn-driver-deployer -n longhorn-system
kubectl rollout status deployment/longhorn-manager -n longhorn-system

# 6. Verify upgrade
kubectl get pods -n longhorn-system
kubectl get settings.longhorn.io -n longhorn-system current-longhorn-version
```

**Version Skew Policy:**

Kubernetes has strict version skew policies:

```
Control Plane: v1.34.3
Worker Nodes:  v1.34.x or v1.33.x (max -1 minor version)
kubectl:       v1.35.x, v1.34.x, or v1.33.x (±1 minor version)
```

If your control plane is v1.34, you can have:
- Worker nodes on v1.34 or v1.33
- kubectl on v1.35, v1.34, or v1.33

**Knowledge Check:**

1. Can you upgrade from RKE2 v1.32 to v1.35 directly?
   > **A:** No, never skip minor versions. You must upgrade sequentially: v1.32 → v1.33 → v1.34 → v1.35, ensuring compatibility and proper etcd migrations at each step.

2. What happens if you use a deprecated API after it's removed?
   > **A:** API requests fail with 404 Not Found errors. Manifests using removed APIs cannot be applied, and existing resources using deprecated APIs may fail to update.

3. Why is the etcd 3.5 → 3.6 upgrade path critical when moving to RKE2 v1.34?
   > **A:** etcd 3.6 has no safe upgrade path from etcd versions before 3.5.26. You must be on etcd 3.5.26 first (via RKE2 v1.32/v1.33) before upgrading to RKE2 v1.34 to avoid zombie members and quorum loss.

4. What's the maximum version skew allowed between control plane and workers?
   > **A:** Workers can be up to 2 minor versions behind the control plane. For example, if control plane is v1.34, workers can be v1.34, v1.33, or v1.32.

5. Name three things you must do before upgrading a production cluster.
   > **A:** Take an etcd snapshot backup, test the upgrade in staging environment, and review release notes for API deprecations and breaking changes.

### Upgrades

**RKE2 Upgrade Process:**

RKE2 uses a rolling upgrade approach managed via systemd or Rancher.

**Manual Upgrade (systemd):**

```bash
# Check current version
kubectl version
/usr/local/bin/rke2 --version

# Upgrade process (one node at a time)

# 1. Cordon node (prevent new pods)
kubectl cordon node-1

# 2. Drain node (evict existing pods)
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data

# 3. Stop RKE2
systemctl stop rke2-server  # or rke2-agent

# 4. Update RKE2 binary
curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=v1.34.3+rke2r1 sh -

# 5. Start RKE2
systemctl start rke2-server  # or rke2-agent

# 6. Wait for node to be Ready
kubectl get nodes -w

# 7. Uncordon node
kubectl uncordon node-1

# 8. Verify node version
kubectl get node node-1 -o jsonpath='{.status.nodeInfo.kubeletVersion}'

# 9. Repeat for remaining nodes
```

**Automated Upgrade (System Upgrade Controller):**

```bash
# Install system-upgrade-controller
kubectl apply -f https://github.com/rancher/system-upgrade-controller/releases/latest/download/system-upgrade-controller.yaml

# Create upgrade plan
cat <<EOF | kubectl apply -f -
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: server-plan
  namespace: system-upgrade
spec:
  concurrency: 1  # Upgrade 1 node at a time
  cordon: true
  nodeSelector:
    matchExpressions:
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
  serviceAccountName: system-upgrade
  upgrade:
    image: rancher/rke2-upgrade
  version: v1.34.3+rke2r1
---
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: agent-plan
  namespace: system-upgrade
spec:
  concurrency: 2  # Upgrade 2 workers at a time
  cordon: true
  nodeSelector:
    matchExpressions:
    - key: node-role.kubernetes.io/control-plane
      operator: DoesNotExist
  prepare:
    args:
    - prepare
    - server-plan
    image: rancher/rke2-upgrade
  serviceAccountName: system-upgrade
  upgrade:
    image: rancher/rke2-upgrade
  version: v1.34.3+rke2r1
EOF

# Watch upgrade progress
kubectl get plans -n system-upgrade
kubectl get nodes -w
kubectl logs -n system-upgrade -l upgrade.cattle.io/plan=server-plan
```

**Upgrade Best Practices:**

1. **Always backup etcd before upgrading**
2. Upgrade control plane nodes first, then workers
3. Upgrade one control plane node at a time
4. Test in staging environment first
5. Read release notes for breaking changes
6. Upgrade one minor version at a time (1.32 → 1.33 → 1.34, not 1.32 → 1.34)
7. **Before upgrading to v1.34+**: Verify etcd is on v3.5.26 (see etcd 3.6 migration warning above)

### Backup-Disaster-Recovery

**etcd Snapshots:**

```bash
# RKE2 automatic snapshots (configured in config.yaml)
# /etc/rancher/rke2/config.yaml:
# etcd-snapshot-schedule-cron: "0 */12 * * *"  # Every 12 hours
# etcd-snapshot-retention: 5
# etcd-snapshot-dir: /var/lib/rancher/rke2/server/db/snapshots

# List local snapshots
ls -lh /var/lib/rancher/rke2/server/db/snapshots/

# Manual snapshot
rke2 etcd-snapshot save --name manual-snapshot-$(date +%Y%m%d-%H%M%S)

# Or via kubectl (RKE2 exposes etcd snapshot API)
kubectl exec -n kube-system etcd-$(hostname) -- \
  etcdctl snapshot save /var/lib/rancher/rke2/server/db/snapshots/manual.db

# Verify snapshot
rke2 etcd-snapshot ls

# S3 backups (automatic, if configured)
# config.yaml:
# etcd-s3: true
# etcd-s3-bucket: my-backups
# etcd-s3-region: us-west-2
# etcd-s3-access-key: <key>
# etcd-s3-secret-key: <secret>
```

**Restore from Snapshot:**

```bash
# CRITICAL: This is a destructive operation
# All data after snapshot timestamp will be lost

# 1. Stop RKE2 on ALL nodes
systemctl stop rke2-server

# 2. Restore from snapshot (on first server)
rke2 server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/rke2/server/db/snapshots/snapshot.db

# This will:
# - Wipe existing etcd data
# - Restore from snapshot
# - Reset cluster to single-node state

# 3. Start RKE2 on first server
systemctl start rke2-server

# 4. Verify cluster state
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl get nodes
kubectl get pods -A

# 5. Rejoin other control plane nodes
# On each additional server:
# - Remove /var/lib/rancher/rke2/server/db/
# - Start rke2-server (will rejoin cluster)

# 6. Restart worker nodes
systemctl restart rke2-agent
```

**Cluster Backup Checklist:**

```bash
# 1. etcd snapshots (automatic)
# 2. Application data (PVs) - use Longhorn backups
# 3. Cluster configuration
#    - /etc/rancher/rke2/config.yaml
#    - Certificates (auto-regenerated, but backup for reference)
# 4. Critical manifests
#    - Custom CRDs
#    - Namespaces
#    - ConfigMaps/Secrets (encrypted)
#    - RBAC policies

# Backup all manifests
kubectl get all --all-namespaces -o yaml > cluster-backup.yaml
kubectl get crd -o yaml > crd-backup.yaml
kubectl get configmap --all-namespaces -o yaml > configmaps-backup.yaml

# Use Velero for comprehensive backup/restore
# (backs up etcd + PVs + manifests)
```

### Certificate-Management

**RKE2 Certificates:**

RKE2 automatically generates and manages certificates:

```bash
# Certificate locations
/var/lib/rancher/rke2/server/tls/

# Key certificates:
# - server-ca.crt: Server CA (signs server certs)
# - client-ca.crt: Client CA (signs client certs)
# - request-header-ca.crt: API aggregation
# - etcd/server-ca.crt: etcd CA
# - dynamic-cert.json: Serving certificate

# View certificate expiry
for cert in /var/lib/rancher/rke2/server/tls/*.crt; do
  echo "=== $cert ==="
  openssl x509 -in $cert -noout -enddate
done

# Certificate rotation (automatic)
# RKE2 auto-rotates certificates 90 days before expiry

# Manual certificate rotation (if needed)
# 1. Stop rke2-server
systemctl stop rke2-server

# 2. Backup certificates
cp -r /var/lib/rancher/rke2/server/tls /var/lib/rancher/rke2/server/tls.backup

# 3. Remove certificates
rm -rf /var/lib/rancher/rke2/server/tls

# 4. Start rke2-server (regenerates certs)
systemctl start rke2-server

# 5. Update kubeconfig on other nodes
# Copy /etc/rancher/rke2/rke2.yaml from server to clients
```

**Knowledge Check:**

1. What happens if you skip a minor version during upgrade?
   > **A:** Risk of incompatibility issues, API version skew problems, and failed etcd migrations (especially the critical 3.5.26 → 3.6 upgrade). Always upgrade one minor version at a time.

2. How do you rollback a failed upgrade?
   > **A:** Stop all rke2-server instances, restore from etcd snapshot using `rke2 server --cluster-reset --cluster-reset-restore-path=<snapshot>` on the first server, then rejoin other servers by removing their etcd data and restarting.

3. Can you restore an etcd snapshot on a different cluster?
   > **A:** Technically yes, but it's not recommended for production use. The snapshot contains cluster-specific data (node registrations, certificates) that won't match the new cluster, causing operational issues.

4. How long are RKE2 certificates valid?
   > **A:** By default, RKE2 certificates are valid for 365 days (1 year). RKE2 automatically rotates certificates when restarting services before expiration.

5. What's the recommended etcd snapshot retention period?
   > **A:** Keep at least 5-7 snapshots (configurable via `etcd-snapshot-retention`), with daily snapshots retained for 7-14 days depending on RPO requirements and storage capacity.

---

## Troubleshooting-Guide

**Time: 1.5 hours**

This is the most important section for a support engineer role. Focus on systematic diagnosis and root cause analysis.

### Systematic-Debugging-Approach

**The Debugging Workflow:**

```
1. IDENTIFY THE PROBLEM
   What is not working? What is the expected behavior?
   ↓
2. GATHER INFORMATION
   Logs, events, resource status, recent changes
   ↓
3. ISOLATE THE SCOPE
   Is it cluster-wide, namespace-specific, or single resource?
   ↓
4. FORM HYPOTHESIS
   Based on symptoms, what could be the cause?
   ↓
5. TEST HYPOTHESIS
   Run diagnostic commands, check specific components
   ↓
6. APPLY FIX
   Make targeted changes
   ↓
7. VERIFY RESOLUTION
   Confirm problem is solved
   ↓
8. DOCUMENT
   Record root cause and solution
```

**Essential Diagnostic Commands:**

```bash
# Cluster health
kubectl get nodes
kubectl get cs  # component status (deprecated but still useful)
kubectl get pods -A | grep -v Running

# Resource status
kubectl get <resource> -n <namespace>
kubectl describe <resource> <name> -n <namespace>
kubectl logs <pod> -n <namespace>
kubectl logs <pod> -n <namespace> --previous  # Previous container instance

# Events (critical for debugging)
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Resource utilization
kubectl top nodes
kubectl top pods -A

# Configuration
kubectl get <resource> <name> -o yaml
kubectl get <resource> <name> -o json | jq '.spec'

# Network
kubectl exec <pod> -- ping <target>
kubectl exec <pod> -- nslookup <service>
kubectl exec <pod> -- curl -v <url>

# Container runtime (on node)
crictl ps
crictl logs <container-id>
crictl inspect <container-id>

# systemd logs
journalctl -u rke2-server -f
journalctl -u rke2-agent -f
journalctl -u rke2-server --since "10 minutes ago"
```

### Advanced-Debugging-Tools-Best-Practices

**Essential Debugging Toolkit:**

```bash
# 1. kubectl debug - Ephemeral debug containers (K8s 1.23+)
# Add debug container to running pod without modifying it
kubectl debug <pod> -it --image=busybox --target=<container>

# Debug with different image (network tools)
kubectl debug <pod> -it --image=nicolaka/netshoot

# Debug node by creating privileged pod
kubectl debug node/<node-name> -it --image=ubuntu

# 2. stern - Multi-pod log tailing
# Install: https://github.com/stern/stern
stern <pod-name-pattern> -n <namespace>
stern . -n kube-system --since 5m  # All pods in namespace

# 3. kubectx / kubens - Context and namespace switching
kubectx production-cluster
kubens kube-system

# 4. k9s - Terminal UI for Kubernetes
k9s  # Interactive cluster exploration
# Features: real-time updates, logs, exec, port-forward, all in one UI

# 5. Telepresence - Local development against remote cluster
telepresence connect
telepresence intercept <service> --port <local-port>

# 6. ksniff - Packet capture for pods
kubectl sniff <pod> -n <namespace>
kubectl sniff <pod> -o capture.pcap
# Open in Wireshark for analysis
```

**Deep Debugging Techniques:**

**1. API Server Request Tracing:**

```bash
# Enable verbose kubectl output
kubectl get pods -v=8  # Shows API calls
kubectl get pods -v=9  # Shows request/response bodies

# Watch API server metrics
kubectl get --raw /metrics | grep apiserver_request

# Check API server audit logs (if configured)
ssh <control-plane-node>
cat /var/lib/rancher/rke2/server/logs/audit.log | jq '.verb, .objectRef'
```

**2. etcd Deep Dive:**

```bash
# Check etcd database size
etcdctl endpoint status --write-out=table

# List all keys (be careful in production!)
etcdctl get / --prefix --keys-only | head -20

# Check specific resource
etcdctl get /registry/pods/default/nginx -w json | jq .

# Compact etcd database
etcdctl compact <revision>
etcdctl defrag --cluster

# Check etcd performance
etcdctl check perf
# Should be:
# - PASS: 60 MB/s for writes
# - PASS: < 10ms for commits
```

**3. Container Runtime Debugging:**

```bash
# List containers with details
crictl ps -a -o json | jq '.containers[] | {name, state, image}'

# Inspect container for detailed info
crictl inspect <container-id> | jq '.info.runtimeSpec.mounts'

# Check container logs with timestamps
crictl logs --timestamps <container-id>

# Execute command in container (alternative to kubectl exec)
crictl exec -it <container-id> /bin/sh

# Pull image manually for troubleshooting
crictl pull <image>

# Check image layers
crictl inspecti <image-id>
```

**4. Network Debugging:**

```bash
# Deploy debug pod with network tools
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: netshoot
spec:
  containers:
  - name: netshoot
    image: nicolaka/netshoot
    command: ["sleep", "infinity"]
EOF

# Test pod-to-pod connectivity
kubectl exec netshoot -- ping <pod-ip>

# Test service DNS resolution
kubectl exec netshoot -- nslookup <service>.<namespace>.svc.cluster.local

# Check iptables rules (on node)
ssh <node>
iptables-save | grep <service-ip>  # Find service rules
iptables-save | grep KUBE-SVC      # List all service chains

# Trace route between pods
kubectl exec netshoot -- traceroute <pod-ip>

# Check for packet loss
kubectl exec netshoot -- mtr -c 10 <pod-ip>

# Capture traffic
kubectl exec netshoot -- tcpdump -i any -n port 80
```

**5. Storage Debugging:**

```bash
# Check volume attachment
kubectl get volumeattachments
kubectl describe volumeattachment <name>

# Check CSI driver logs
kubectl logs -n longhorn-system -l app=csi-attacher
kubectl logs -n longhorn-system -l app=csi-provisioner

# Verify volume is mounted on node
ssh <node>
mount | grep longhorn
lsblk | grep longhorn

# Check for I/O errors
dmesg | grep -i "i/o error"
journalctl -k | grep -i "ext4\|xfs"

# Longhorn-specific debugging
kubectl get volumes.longhorn.io -n longhorn-system -o wide
kubectl get engines.longhorn.io -n longhorn-system -o wide
kubectl get replicas.longhorn.io -n longhorn-system -o wide
kubectl describe volume.longhorn.io <volume> -n longhorn-system
```

**6. Performance Debugging:**

```bash
# Check API server latency
kubectl get --raw /metrics | grep apiserver_request_duration_seconds

# Check scheduler latency
kubectl get --raw /metrics | grep scheduler_scheduling_duration_seconds

# Check kubelet metrics
curl -k https://localhost:10250/metrics

# Identify resource-intensive pods
kubectl top pods -A --sort-by=cpu
kubectl top pods -A --sort-by=memory

# Check node resource pressure
kubectl describe nodes | grep -A 5 "Allocated resources"

# Profile specific components (if enabled)
kubectl get --raw /debug/pprof/heap > heap.prof
go tool pprof heap.prof
```

**7. Debugging Controller/Operator Issues:**

```bash
# Check controller logs for reconciliation errors
kubectl logs -n <namespace> deployment/<controller> --tail=100

# Watch controller metrics
kubectl port-forward -n <namespace> deployment/<controller> 8080:8080
curl localhost:8080/metrics | grep controller_reconcile

# Check RBAC permissions
kubectl auth can-i create pods --as=system:serviceaccount:<namespace>:<sa>

# Verify webhooks are working
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations
kubectl describe validatingwebhookconfiguration <name>

# Test webhook manually
kubectl create -f test-resource.yaml --dry-run=server -v=8
# Look for webhook calls in verbose output

# Check for finalizer issues
kubectl get <resource> -o jsonpath='{.items[?(@.metadata.deletionTimestamp)].metadata.name}'
# Resources stuck deleting
```

**Debugging Best Practices:**

1. **Always check events first**
   ```bash
   kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20
   ```

2. **Use --previous flag for crashed containers**
   ```bash
   kubectl logs <pod> --previous
   ```

3. **Enable verbose logging temporarily**
   ```bash
   # Increase controller log level
   kubectl set env deployment/<controller> LOG_LEVEL=debug
   ```

4. **Collect comprehensive diagnostics**
   ```bash
   # Must-gather script
   kubectl cluster-info dump > cluster-dump.txt
   kubectl get all -A > all-resources.txt
   kubectl get events -A --sort-by='.lastTimestamp' > events.txt
   ```

5. **Use labels for filtering**
   ```bash
   kubectl logs -l app=nginx --tail=20 -n production
   kubectl get pods -l app=nginx,env=prod
   ```

6. **Watch resources in real-time**
   ```bash
   kubectl get pods -w  # Watch mode
   watch kubectl get pods  # Periodic refresh
   ```

7. **Export resources for offline analysis**
   ```bash
   kubectl get pod <name> -o yaml > pod.yaml
   kubectl get pod <name> -o json | jq '.status' > status.json
   ```

**Common Pitfalls to Avoid:**

1. Modifying production resources without backup
   ```bash
   # Always export first
   kubectl get <resource> <name> -o yaml > backup.yaml
   # Then edit
   kubectl edit <resource> <name>
   ```

2. Not checking resource quotas
   ```bash
   kubectl describe resourcequota -n <namespace>
   ```

3. Ignoring limit ranges
   ```bash
   kubectl describe limitrange -n <namespace>
   ```

4. Not verifying RBAC before operations
   ```bash
   kubectl auth can-i <verb> <resource> -n <namespace>
   ```

5. Deleting namespaces with active resources
   ```bash
   # Check what's in namespace first
   kubectl get all -n <namespace>
   ```

### RKE2-Specific-Issues

**Issue: rke2-server won't start**

```bash
# Symptom
systemctl status rke2-server
# Output: Failed to start RKE2 server

# Diagnosis
journalctl -u rke2-server -n 100

# Common causes:

# 1. Port 6443 already in use
netstat -tlnp | grep 6443
# Fix: Kill conflicting process or change API server port

# 2. etcd data corruption
journalctl -u rke2-server | grep -i "etcd"
# Fix: Restore from snapshot
rm -rf /var/lib/rancher/rke2/server/db/
rke2 server --cluster-reset-restore-path=/path/to/snapshot.db

# 3. Certificate issues
journalctl -u rke2-server | grep -i "certificate"
# Fix: Regenerate certificates
systemctl stop rke2-server
rm -rf /var/lib/rancher/rke2/server/tls/
systemctl start rke2-server

# 4. Insufficient disk space
df -h /var/lib/rancher/rke2
# Fix: Free up space

# 5. SELinux/AppArmor blocking
journalctl -u rke2-server | grep -i "permission denied"
# Check: getenforce (SELinux) or aa-status (AppArmor)
# Fix: Adjust policies or temporarily disable for testing
```

**Issue: Node stuck in NotReady**

```bash
# Check node status
kubectl get nodes
kubectl describe node <node-name>

# Common causes:

# 1. kubelet not running
ssh <node>
systemctl status rke2-server  # or rke2-agent
systemctl restart rke2-agent
journalctl -u rke2-agent -f

# 2. Network plugin issue
kubectl get pods -n kube-system | grep canal
kubectl logs -n kube-system <canal-pod>
# Fix: Restart canal pod if necessary

# 3. Disk pressure / Memory pressure
kubectl describe node <node-name> | grep Conditions -A 10
# Fix: Free up resources or evict pods

# 4. CNI configuration missing
ssh <node>
ls -la /var/lib/rancher/rke2/agent/etc/cni/net.d/
# Should have 10-canal.conflist or similar
# Fix: Restart rke2-server/agent to regenerate

# 5. Certificate expiry
ssh <node>
openssl x509 -in /var/lib/rancher/rke2/agent/client-kubelet.crt -noout -enddate
# Fix: Restart rke2-agent to rotate certificates
```

**Issue: Unable to join new node to cluster**

```bash
# On new node
systemctl status rke2-agent
journalctl -u rke2-agent -f

# Common causes:

# 1. Wrong server URL or token
cat /etc/rancher/rke2/config.yaml
# Verify:
# server: https://<server-ip>:9345
# token: <correct-token>
# Get token from server: cat /var/lib/rancher/rke2/server/node-token

# 2. Firewall blocking port 9345
telnet <server-ip> 9345
# Fix: Open firewall
# RKE2 required ports:
# - 9345 (supervisor API)
# - 6443 (Kubernetes API)
# - 2379-2380 (etcd)
# - 10250 (kubelet)
# - 8472 (VXLAN)

# 3. Server not running / unhealthy
ssh <server>
systemctl status rke2-server
kubectl get nodes

# 4. TLS certificate validation failed
journalctl -u rke2-agent | grep -i "certificate"
# Fix: Ensure clock synchronized (NTP)
timedatectl status
```

### etcd-Troubleshooting

**Issue: etcd cluster unhealthy**

```bash
# Check etcd member health
alias etcdctl='/var/lib/rancher/rke2/bin/etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key'

etcdctl endpoint health --cluster
etcdctl endpoint status --cluster -w table

# Common issues:

# 1. etcd member down
# Status shows: unhealthy for member X
# Fix: Restart rke2-server on that node
ssh <node>
systemctl restart rke2-server

# 2. No leader elected
# Cause: Network partition or >50% members down
# Fix: Ensure majority (quorum) of members are running
# For 3-node cluster: need 2 nodes up
# For 5-node cluster: need 3 nodes up

# 3. etcd database too large (>8GB)
etcdctl endpoint status -w table | awk '{print $5}'
# Fix: Compact and defragment
REV=$(etcdctl endpoint status --write-out="json" | jq -r '.[0].Status.header.revision')
etcdctl compact $REV
etcdctl defrag --cluster

# 4. Slow disk (performance degradation)
etcdctl check perf
# Output should show latency <10ms
# Fix: Move etcd to faster disk (SSD required)
```

**Issue: etcd alarm NOSPACE**

```bash
# Check alarms
etcdctl alarm list
# Output: memberID:xxx alarm:NOSPACE

# Cause: Database size exceeded quota (default 2GB, RKE2 uses 8GB)

# Fix:
# 1. Compact old revisions
REV=$(etcdctl endpoint status --write-out="json" | jq -r '.[0].Status.header.revision')
etcdctl compact $REV

# 2. Defragment
etcdctl defrag --cluster

# 3. Disarm alarm
etcdctl alarm disarm

# 4. Verify
etcdctl endpoint status -w table
etcdctl alarm list  # Should be empty

# Prevention:
# - Enable auto-compaction (RKE2 does this by default)
# - Monitor database size
# - Limit object churn (don't create/delete resources rapidly)
```

**Issue: Restore etcd from backup**

```bash
# Scenario: etcd data corrupted, cluster unusable

# 1. Stop ALL rke2-server instances
ssh node-1 'systemctl stop rke2-server'
ssh node-2 'systemctl stop rke2-server'
ssh node-3 'systemctl stop rke2-server'

# 2. On first server, restore from snapshot
ssh node-1
rke2 server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/rke2/server/db/snapshots/snapshot-2024-02-08.db

# Wait for restore to complete (watch journalctl)

# 3. Start first server
systemctl start rke2-server

# 4. Verify cluster is functional (single-node)
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl get nodes

# 5. On other servers, remove etcd data and rejoin
ssh node-2
systemctl stop rke2-server
rm -rf /var/lib/rancher/rke2/server/db/
systemctl start rke2-server

ssh node-3
systemctl stop rke2-server
rm -rf /var/lib/rancher/rke2/server/db/
systemctl start rke2-server

# 6. Verify all nodes are back
kubectl get nodes
etcdctl member list
etcdctl endpoint health --cluster
```

### Networking-Issues

**Issue: Pod can't reach another pod**

```bash
# Test connectivity
kubectl exec <source-pod> -- ping <target-pod-ip>
kubectl exec <source-pod> -- curl <target-service>

# Diagnosis steps:

# 1. Check pods are running
kubectl get pods -o wide

# 2. Check network policies
kubectl get networkpolicy -n <namespace>
kubectl describe networkpolicy <policy-name>
# Fix: Adjust policy to allow traffic

# 3. Check CNI plugin (Canal)
kubectl get pods -n kube-system -l k8s-app=canal
kubectl logs -n kube-system <canal-pod> -c calico-node
kubectl logs -n kube-system <canal-pod> -c kube-flannel

# 4. Verify routing on nodes
ssh <node>
ip route | grep 10.42  # Pod CIDR
# Should have routes to other nodes via flannel.1

# 5. Check VXLAN interface
ip -d link show flannel.1
# Should be UP

# 6. Test node-to-node connectivity
ssh <node-1>
ping <node-2-ip>

# 7. Firewall rules
iptables-save | grep <pod-ip>
# CNI creates iptables rules for pods
# Check for DROP rules

# 8. CoreDNS (if using service name)
kubectl exec <pod> -- nslookup kubernetes.default
kubectl logs -n kube-system -l k8s-app=kube-dns
```

**Issue: Service not accessible**

```bash
# Check service
kubectl get svc <service-name> -n <namespace>
kubectl describe svc <service-name> -n <namespace>

# Common issues:

# 1. No endpoints (no pods match selector)
kubectl get endpoints <service-name> -n <namespace>
# Fix: Ensure pods have matching labels
kubectl get pods -n <namespace> --show-labels

# 2. Wrong port/targetPort
kubectl describe svc <service-name>
# Verify: port (service port) and targetPort (pod port) are correct

# 3. Network policy blocking traffic
kubectl get networkpolicy -n <namespace>

# 4. kube-proxy issue
ssh <node>
journalctl -u rke2-agent | grep kube-proxy
# Check iptables rules for service
iptables-save | grep <service-name>

# 5. Service type mismatch
# ClusterIP: Only accessible within cluster
# NodePort: Accessible on node IP:port
# LoadBalancer: Requires cloud controller

# Test from different contexts:
# - Pod to service: kubectl exec <pod> -- curl <service>
# - Node to service: ssh <node> && curl <service-ip>:<port>
# - External to NodePort: curl <node-ip>:<nodePort>
```

**Issue: DNS resolution failing**

```bash
# Test DNS
kubectl exec <pod> -- nslookup kubernetes.default
kubectl exec <pod> -- nslookup <service>.<namespace>.svc.cluster.local

# Diagnosis:

# 1. Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# 2. CoreDNS service
kubectl get svc -n kube-system kube-dns
# Should be ClusterIP (usually 10.43.0.10)

# 3. Pod DNS configuration
kubectl exec <pod> -- cat /etc/resolv.conf
# Should have:
# nameserver 10.43.0.10
# search <namespace>.svc.cluster.local svc.cluster.local cluster.local

# 4. CoreDNS ConfigMap
kubectl get configmap -n kube-system coredns -o yaml
# Check for errors in Corefile

# 5. Test DNS from node
ssh <node>
nslookup kubernetes.default.svc.cluster.local 10.43.0.10

# 6. Restart CoreDNS
kubectl rollout restart deployment -n kube-system coredns
```

### Storage-Issues

**Issue: Pod stuck in ContainerCreating (volume mount issue)**

```bash
# Check pod events
kubectl describe pod <pod-name>

# Common volume-related errors:

# 1. "Unable to attach or mount volumes"
# Causes:
# - PVC not bound to PV
# - Volume node affinity conflict
# - CSI driver issue

# Check PVC status
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name>

# For Longhorn:
kubectl get volumes.longhorn.io -n longhorn-system
kubectl describe volume.longhorn.io -n longhorn-system <volume-name>

# 2. "Multi-Attach error"
# Cause: Volume is ReadWriteOnce but pod scheduled on different node
# Fix: Delete old pod or change to ReadWriteMany

# 3. "Volume is already exclusively attached"
# Cause: Previous pod still attached
# Fix: Force delete old pod
kubectl delete pod <old-pod> --force --grace-period=0

# 4. Longhorn volume stuck in "Attaching"
kubectl get volumes.longhorn.io -n longhorn-system
# Check engine and replica status
kubectl get engines.longhorn.io -n longhorn-system
kubectl get replicas.longhorn.io -n longhorn-system

# Fix: Restart Longhorn instance-manager on node
kubectl delete pod -n longhorn-system <instance-manager-pod>
```

**Issue: Longhorn volume degraded**

```bash
# Check volume health
kubectl get volumes.longhorn.io -n longhorn-system
# State: healthy, degraded, faulted

# Degraded: Some replicas unavailable
kubectl describe volume.longhorn.io -n longhorn-system <volume-name>

# Check replicas
kubectl get replicas.longhorn.io -n longhorn-system | grep <volume-name>

# Common causes:

# 1. Node down
kubectl get nodes
# Longhorn will auto-rebuild replica on another node

# 2. Disk full on node
kubectl get nodes.longhorn.io -n longhorn-system -o yaml | grep -A5 diskStatus
# Fix: Free up space or add disk

# 3. Replica rebuilding (slow)
kubectl logs -n longhorn-system <instance-manager-pod>
# Wait for rebuild to complete

# 4. Network issues between replicas
# Check node connectivity
ssh <node-1> && ping <node-2>

# Force replica rebuild
# Via Longhorn UI: Volume → Actions → Salvage
```

**Issue: PVC stuck in Pending**

```bash
# Check PVC
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name>

# Common causes:

# 1. No StorageClass
kubectl get sc
# Fix: Create StorageClass or specify in PVC

# 2. No available PV (static provisioning)
kubectl get pv
# Fix: Create matching PV

# 3. Dynamic provisioning failed
kubectl get events -n <namespace> | grep <pvc-name>
# Check CSI driver logs
kubectl logs -n longhorn-system <csi-provisioner-pod>

# 4. Insufficient storage in cluster
# For Longhorn:
kubectl get nodes.longhorn.io -n longhorn-system -o yaml
# Check: allocatable storage vs. requested

# 5. Volume binding mode WaitForFirstConsumer
kubectl get sc <storage-class> -o yaml | grep volumeBindingMode
# PVC waits until pod is scheduled
# Fix: Create pod to trigger binding
```

### Node-Problems

**Issue: Node out of resources**

```bash
# Check node conditions
kubectl describe node <node-name> | grep -A10 Conditions

# Conditions to watch:
# - MemoryPressure: True (low memory)
# - DiskPressure: True (low disk)
# - PIDPressure: True (too many processes)

# Check resource usage
kubectl top node <node-name>
kubectl top pods -A --sort-by=memory
kubectl top pods -A --sort-by=cpu

# SSH to node
ssh <node>

# Memory
free -h
# Fix: Evict pods or add memory

# Disk
df -h
# Common culprits:
# - /var/lib/rancher/rke2/agent/containerd (images)
# - /var/log (logs)
# - /var/lib/longhorn (storage)

# Clean up images
crictl images
crictl rmi <image-id>

# Clean up logs
journalctl --vacuum-time=7d
find /var/log -type f -name "*.log" -mtime +7 -delete

# PIDs
ps aux | wc -l
# Check kubelet max-pods setting
```

**Issue: Node taints preventing scheduling**

```bash
# Check node taints
kubectl describe node <node-name> | grep Taints

# Common taints:
# - node-role.kubernetes.io/control-plane:NoSchedule (control nodes)
# - node.kubernetes.io/not-ready:NoSchedule (node not ready)
# - node.kubernetes.io/unreachable:NoExecute (node down)
# - node.kubernetes.io/disk-pressure:NoSchedule (disk full)

# Remove taint
kubectl taint nodes <node-name> <taint-key>:<effect>-

# Example: Allow scheduling on control plane
kubectl taint nodes node-1 node-role.kubernetes.io/control-plane:NoSchedule-

# Add toleration to pod (instead of removing taint)
spec:
  tolerations:
  - key: "node-role.kubernetes.io/control-plane"
    operator: "Exists"
    effect: "NoSchedule"
```

### Upgrade-Failures

**Issue: Node stuck during upgrade**

```bash
# Check upgrade plan status
kubectl get plans -n system-upgrade
kubectl describe plan <plan-name> -n system-upgrade

# Check upgrade jobs
kubectl get jobs -n system-upgrade
kubectl logs -n system-upgrade job/<upgrade-job>

# Common issues:

# 1. Pod eviction failed (PDB preventing drain)
kubectl get pdb -A
# Fix: Temporarily adjust PodDisruptionBudget

# 2. Node drain timeout
# Fix: Force drain
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force --grace-period=0

# 3. New version compatibility issue
journalctl -u rke2-server -n 100
# Fix: Rollback
systemctl stop rke2-server
# Install previous version
curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=<old-version> sh -
systemctl start rke2-server
```

**Issue: Post-upgrade API server errors**

```bash
# API server won't start after upgrade
journalctl -u rke2-server | grep apiserver

# Common causes:

# 1. Admission webhook failing
# Symptom: "failed calling webhook"
# Fix: Delete webhook temporarily
kubectl delete validatingwebhookconfig <webhook-name>
kubectl delete mutatingwebhookconfig <webhook-name>

# 2. API version removed
# Symptom: "no matches for kind X in version Y"
# Fix: Update manifests to new API version
# Example: apps/v1beta1 → apps/v1

# 3. Feature gate changed
# Check release notes for deprecated features
# Fix: Update manifests or re-enable feature gate
# kube-apiserver-arg:
#   - "feature-gates=OldFeature=true"

# 4. etcd migration failed
journalctl -u rke2-server | grep "etcd"
# Fix: Restore from pre-upgrade snapshot
```

**Knowledge Check:**

1. What's the first thing you check when a pod won't start?
   > **A:** Run `kubectl describe pod <name>` to check events section for errors like image pull failures, insufficient resources, unbound PVCs, scheduling constraints, or failed health checks.

2. How do you determine if a networking issue is CNI or application-level?
   > **A:** Check if the pod has an IP address and CNI pods are healthy. Test basic connectivity (ping cluster DNS). If CNI is working but app fails, it's application-level (wrong service name, network policies, app misconfiguration).

3. What's the difference between `kubectl logs` and `crictl logs`?
   > **A:** `kubectl logs` queries the API server for logs from running/terminated pods. `crictl logs` directly queries the container runtime on the node, useful when the API server is unavailable or for debugging kubelet issues.

4. How do you troubleshoot an etcd cluster that has lost quorum?
   > **A:** Check etcd member list and health, verify at least (n/2)+1 members are healthy. If quorum is lost, restore from the most recent etcd snapshot using `rke2 server --cluster-reset --cluster-reset-restore-path`.

5. What steps would you take for a complete cluster failure (all control planes down)?
   > **A:** Restore from etcd snapshot on first server with `--cluster-reset`, verify it starts successfully, remove etcd data on remaining servers (`/var/lib/rancher/rke2/server/db/`), restart them to rejoin the cluster, verify all nodes healthy.

---

## Practice-Questions

**RKE2 Architecture:**

1. **Q: Explain the difference between RKE2 and vanilla Kubernetes.**
   - A: RKE2 packages K8s components into a single binary (rke2-server/agent) managed by systemd, includes embedded etcd, is CIS 1.12 hardened by default, uses containerd 2.0 (as of v1.32+), and provides security features out-of-the-box (PSS, network policies). Current stable releases track K8s 1.32-1.35.

2. **Q: How does RKE2 achieve high availability?**
   - A: Multiple server nodes (3 or 5) each run embedded etcd forming a cluster. API requests are load-balanced across servers. etcd uses Raft consensus requiring majority quorum. If one server fails, others continue operating.

3. **Q: Where is etcd data stored in RKE2?**
   - A: `/var/lib/rancher/rke2/server/db/etcd/` - part of the rke2-server process, not a separate container.

4. **Q: What happens if rke2-server crashes on one of three control plane nodes?**
   - A: Cluster continues operating. etcd maintains quorum (2/3). API requests route to remaining servers. Pods on that node eventually get evicted and rescheduled. Restart the service to restore full redundancy.

5. **Q: How do you add a new worker node to an RKE2 cluster?**
   - A: Install rke2-agent, configure `/etc/rancher/rke2/config.yaml` with server URL and token, start service: `systemctl enable --now rke2-agent`. Node joins automatically.

**Kubernetes Internals:**

6. **Q: Trace the flow when you run `kubectl create deployment nginx --replicas=3`.**
   - A: kubectl → API server (authn/authz/admission/validate) → etcd write → deployment controller watches → creates ReplicaSet → RS controller creates 3 Pods → scheduler assigns nodes → kubelets start containers → status updated.

7. **Q: What's the role of the controller manager?**
   - A: Runs control loops (deployment, RS, node, service controllers) that watch cluster state and reconcile to desired state. Each controller continuously compares current vs. desired and takes action.

8. **Q: How does the scheduler decide which node to place a pod on?**
   - A: Filtering phase eliminates incompatible nodes (resources, taints, affinity). Scoring phase ranks remaining nodes (0-100) by resource balance, affinity preferences, etc. Highest score wins. Binds pod to node.

9. **Q: What happens if etcd goes down?**
   - A: API server can't read/write cluster state → no new operations (creates, updates, deletes). Existing workloads continue running (kubelets use last known state). Cluster is read-only. CRITICAL to restore etcd ASAP.

10. **Q: Explain how controllers use the watch mechanism.**
    - A: Controllers establish long-lived watch streams to API server for specific resource types. API server sends events (ADDED/MODIFIED/DELETED) when resources change. Efficient - no polling, immediate notification.

**Networking:**

11. **Q: How does pod-to-pod communication work across nodes in Canal?**
    - A: Flannel creates VXLAN overlay. Packet leaves pod → cbr0 bridge → encapsulated by flannel.1 interface → sent over physical network to destination node → decapsulated → delivered to target pod.

12. **Q: What's the difference between Calico and Flannel in Canal?**
    - A: Flannel provides simple L3 overlay networking (VXLAN). Calico provides network policy enforcement via iptables rules. Canal combines both: Flannel for connectivity, Calico for security.

13. **Q: Explain how Network Policies work.**
    - A: Label-based firewall rules. Select pods, define allowed ingress/egress. Calico translates policies into iptables rules on each node. Default: allow all. With policies: deny by default, allow explicitly defined.

14. **Q: How would you troubleshoot "pod A can't reach pod B"?**
    - A: Check both pods running, verify IPs, test connectivity (ping/curl), check network policies, verify CNI pods healthy, check node routing (ip route), test node-to-node connectivity, check DNS if using service names.

15. **Q: What's the purpose of the flannel.1 interface?**
    - A: VXLAN tunnel endpoint. Encapsulates pod traffic for cross-node communication. Creates overlay network so pods have L3 connectivity regardless of underlying network topology.

**Storage:**

16. **Q: Explain Longhorn's architecture.**
    - A: Distributed block storage. Each volume has multiple replicas (default 3) on different nodes. Engine pod handles I/O and replicates writes. If node fails, replicas on other nodes maintain availability. Auto-rebuilding.

17. **Q: What's the difference between a snapshot and a backup in Longhorn?**
    - A: Snapshot: point-in-time copy stored locally on replica nodes, fast, for quick recovery. Backup: incremental copy to remote S3/NFS, slower, for DR and long-term retention.

18. **Q: How does CSI differ from legacy volume plugins?**
    - A: CSI is out-of-tree (separate from K8s core), standardized interface, allows third-party storage vendors to develop plugins independently. Legacy: in-tree, coupled to K8s release cycle, limited.

19. **Q: What happens when a Longhorn volume becomes degraded?**
    - A: Some replicas unavailable (node down, disk full). Volume still accessible via remaining replicas. Longhorn auto-rebuilds missing replicas on healthy nodes. Temporary reduced redundancy.

20. **Q: How would you migrate volumes from one RKE2 cluster to another?**
    - A: Longhorn backups to S3. Configure new cluster's Longhorn with same S3 target. Backups visible in new cluster's UI. Restore backup → creates volume with data. Attach to pods in new cluster.

**Troubleshooting:**

21. **Q: Pod stuck in Pending. How do you diagnose?**
    - A: `kubectl describe pod` → check events. Common: insufficient resources, unbound PVC, node selector mismatch, taints, scheduling constraints. Check `kubectl get nodes`, `kubectl get pvc`, resource requests.

22. **Q: Node shows NotReady. What's your approach?**
    - A: Check `kubectl describe node` conditions. SSH to node. Check `systemctl status rke2-agent/server`, `journalctl`, disk/memory, CNI pods, network connectivity. Restart service if needed.

23. **Q: How do you recover from etcd data corruption?**
    - A: Stop all rke2-server instances. On first server: `rke2 server --cluster-reset --cluster-reset-restore-path=<snapshot>`. Start first server. Verify. On other servers: remove `/var/lib/rancher/rke2/server/db/`, restart to rejoin.

24. **Q: Service not accessible from pods. Debug steps?**
    - A: Check service exists, has endpoints (`kubectl get endpointslices`), labels match pods, test from pod (`curl <service>`), verify network policies, check kube-proxy logs, iptables/nftables rules for service. Note: Endpoints API is deprecated in K8s 1.33+, use EndpointSlices instead.

25. **Q: Longhorn volume won't attach to pod. What do you check?**
    - A: Check volume state (`kubectl get volumes.longhorn.io`), node has space, engine/replica pods running, previous pod force-deleted, multi-attach error (RWO conflict), instance-manager healthy.

**CRDs & API Versioning:**

26. **Q: How do you safely deprecate a CRD field in production?**
    - A: Add new field first (additive), support both old and new, mark old field as deprecated in documentation and API warnings, provide migration period (3+ releases), remove old field only after all users migrated. Never break existing users immediately.

27. **Q: What's a conversion webhook and when do you need it?**
    - A: Webhook that automatically converts between different API versions of a CRD. Needed when you have multiple served versions and need bidirectional conversion. Allows clients to use any version while storage uses one canonical version.

28. **Q: Can you serve multiple API versions of a CRD simultaneously?**
    - A: Yes. Set `served: true` for all versions you want to support. Only one can be `storage: true` (canonical version in etcd). API server converts between versions automatically (manually or via webhook).

**Rancher & Extensions:**

29. **Q: What's the difference between Rancher and RKE2?**
    - A: RKE2 is a Kubernetes distribution (like kubeadm). Rancher (current: v2.13.2) is a multi-cluster management platform that can manage RKE2, EKS, AKS, GKE, etc. Rancher provides UI, RBAC, app catalog, monitoring across clusters. Note: RKE1 reached EOL July 2025; Rancher 2.12+ only supports RKE2.

30. **Q: How does Rancher extend the Kubernetes API?**
    - A: Adds CRDs for management constructs (clusters.management.cattle.io, projects.management.cattle.io, users.management.cattle.io). Runs cattle-cluster-agent in managed clusters. Provides REST API for management operations beyond K8s API.

31. **Q: What is a Rancher Project and how does it differ from a namespace?**
    - A: Project groups multiple namespaces with shared RBAC and resource quotas. Provides multi-tenancy abstraction. One project can contain many namespaces. Projects exist only in Rancher, not vanilla K8s.

**Version Compatibility & Upgrades:**

32. **Q: Can you upgrade from RKE2 v1.32 to v1.35 directly?**
    - A: No. Never skip minor versions. Must upgrade sequentially: 1.32 → 1.33 → 1.34 → 1.35. Critical: the 1.33→1.34 step upgrades etcd from 3.5.26 to 3.6.7 — verify etcd version before proceeding.

33. **Q: What's the maximum version skew between control plane and worker nodes?**
    - A: Workers can be up to 1 minor version behind control plane. If control plane is 1.34, workers can be 1.34 or 1.33. kubectl can be ±1 version. Never have workers newer than control plane.

34. **Q: What is the etcd 3.6 migration risk and how do you mitigate it?**
    - A: RKE2 v1.34+ ships etcd 3.6. Upgrading from etcd <3.5.26 directly to 3.6 can cause zombie members and loss of quorum. Mitigation: upgrade to RKE2 v1.32/v1.33 first (which includes etcd 3.5.26), verify with `etcdctl version`, then proceed to v1.34.

35. **Q: What major API changes happened in Kubernetes 1.32-1.33?**
    - A: K8s 1.32: flowcontrol v1beta3 removed (use v1). K8s 1.33: Endpoints API deprecated (use EndpointSlices), nftables kube-proxy backend GA, sidecar containers GA, nodeInfo.kubeProxyVersion field removed.

**Operations:**

36. **Q: Describe the RKE2 upgrade process.**
    - A: Backup etcd. Upgrade control plane nodes one at a time (cordon, drain, stop service, install new version, start, uncordon). Then upgrade workers. Use system-upgrade-controller for automation.

37. **Q: What's the recommended etcd backup strategy?**
    - A: Automatic snapshots every 12 hours, retention 5+, backup to S3 for DR, test restores regularly, backup before major changes (upgrades, large deployments). **Critical for v1.34+ upgrades**: always have a verified backup before the etcd 3.5→3.6 migration.

38. **Q: How do RKE2 certificates work?**
    - A: Auto-generated on first start, stored in `/var/lib/rancher/rke2/server/tls/`, auto-rotated 90 days before expiry. Separate CAs for server, client, etcd. kubelet certificates signed and rotated.

39. **Q: What ports does RKE2 require to be open?**
    - A: 6443 (API), 9345 (supervisor), 2379-2380 (etcd), 10250 (kubelet), 8472 (VXLAN), 443/80 (ingress). Control plane needs all, workers need subset.

40. **Q: How would you troubleshoot slow API responses?**
    - A: Check etcd performance (`etcdctl check perf`), disk I/O, etcd database size, API server logs, resource utilization (CPU/memory), network latency, watch stream count, large list operations.

---

## Quick-Reference

**RKE2 Essentials:**

```bash
# Service management
systemctl status rke2-server
systemctl restart rke2-server
journalctl -u rke2-server -f

# Config
/etc/rancher/rke2/config.yaml
/etc/rancher/rke2/rke2.yaml  # kubeconfig

# Data locations
/var/lib/rancher/rke2/server/
/var/lib/rancher/rke2/agent/
/var/lib/rancher/rke2/server/db/etcd/

# etcd
etcdctl endpoint health --cluster
etcdctl member list
rke2 etcd-snapshot save
```

**Troubleshooting Commands:**

```bash
# Cluster health
kubectl get nodes
kubectl get pods -A | grep -v Running
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Pod debugging
kubectl describe pod <pod>
kubectl logs <pod> --previous
kubectl exec <pod> -- sh

# Network
kubectl exec <pod> -- ping <ip>
kubectl exec <pod> -- nslookup <service>

# Storage
kubectl get pvc
kubectl get volumes.longhorn.io -n longhorn-system
crictl ps | grep <volume>

# Node debugging
ssh <node>
crictl ps
crictl logs <container>
df -h
free -h
journalctl -u rke2-agent
```

**Key File Locations:**

```bash
# RKE2
/etc/rancher/rke2/config.yaml           # Configuration
/var/lib/rancher/rke2/                  # Data directory
/var/lib/rancher/rke2/server/tls/       # Certificates
/etc/rancher/rke2/rke2.yaml             # Kubeconfig

# Logs
journalctl -u rke2-server
journalctl -u rke2-agent

# CNI
/opt/cni/bin/                           # CNI binaries
/var/lib/rancher/rke2/agent/etc/cni/net.d/  # CNI config

# Container runtime
/var/lib/rancher/rke2/agent/containerd/
crictl --runtime-endpoint unix:///run/k3s/containerd/containerd.sock
```

**Port Reference:**

| Port | Protocol | Purpose |
|------|----------|---------|
| 6443 | TCP | Kubernetes API |
| 9345 | TCP | RKE2 supervisor API |
| 2379-2380 | TCP | etcd client/peer |
| 10250 | TCP | Kubelet API |
| 10251 | TCP | kube-scheduler (localhost) |
| 10252 | TCP | kube-controller-manager (localhost) |
| 8472 | UDP | Flannel VXLAN |
| 4789 | UDP | Calico VXLAN (if enabled) |
| 179 | TCP | Calico BGP (if enabled) |

**Common Issues & Solutions:**

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------|
| Pod Pending | Resources, PVC, scheduling | `kubectl describe pod` |
| Node NotReady | kubelet, CNI, resources | `systemctl restart rke2-agent` |
| Can't reach pod | Network policy, CNI | Check policies, CNI pods |
| Volume won't attach | Longhorn, node down | Check volume.longhorn.io |
| etcd unhealthy | Member down, disk | Restart rke2-server, check disk |
| API slow | etcd performance, disk | `etcdctl check perf`, defrag |
| DNS failing | CoreDNS down | Restart CoreDNS deployment |
| Can't join node | Token, firewall, server | Verify config, ports, server status |

---
