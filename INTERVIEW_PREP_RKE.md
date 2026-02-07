# RKE/Kubernetes Support Interview Prep - Deep Dive

**Timeline**: 1 day intensive, hands-on learning
**Goal**: Deep understanding of Kubernetes internals and RKE architecture
**Focus**: RKE1/RKE2, Control Plane Components, CRDs, CNI, CSI, Production Troubleshooting

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Day 3: RKE Deep Dive + Kubernetes Internals](#day-3-rke-deep-dive--kubernetes-internals)
   - RKE Architecture & Fundamentals
   - Kubernetes Control Plane Internals
   - CRDs, Controllers & Operators
   - CNI Networking (Canal/Calico/Flannel)
   - CSI Storage & Longhorn
   - Cluster Lifecycle & Troubleshooting
3. [Final Prep Checklist](#day-3---final-prep-checklist)

---

## Prerequisites

This interview prep assumes you have foundational knowledge of Kubernetes, Terraform, and basic cluster operations.

**Required Knowledge:**
- Basic Kubernetes concepts (Pods, Deployments, Services, etc.)
- kubectl command-line usage
- YAML manifest structure
- Basic Linux systems administration
- Networking fundamentals (TCP/IP, DNS, routing)

**For Kubernetes Basics Review:**
Refer to [INTERVIEW_PREP_GITOPS.md](./INTERVIEW_PREP_GITOPS.md) for foundational material on:
- Kubernetes resource types and their purposes
- kubectl debugging commands
- Common troubleshooting patterns
- GitOps workflows with Flux

**Required Tools:**

```bash
# Check required tools are installed
command -v kubectl && echo "✓ kubectl" || echo "✗ kubectl MISSING"
command -v docker && echo "✓ docker" || echo "✗ docker MISSING"
command -v crictl && echo "✓ crictl (optional)" || echo "✗ crictl not installed"
command -v etcdctl && echo "✓ etcdctl (optional)" || echo "✗ etcdctl not installed"
```

**Focus Areas for This Interview:**
- RKE-specific architecture and components
- Deep Kubernetes control plane understanding
- Custom Resource Definitions and operators
- Container networking (CNI) implementation details
- Container storage (CSI) and Longhorn
- Production cluster troubleshooting methodology
- High availability and disaster recovery

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

