# RKE2 Lab with NFS Storage - Complete Guide - August 26, 2026

## Document Purpose

This document provides a complete, step-by-step guide for setting up RKE2 with NFS storage, including:
- **What** - What each component does
- **Why** - Why we need each step
- **How** - How to implement each step
- **Command meanings** - Detailed explanation of each command
- **Troubleshooting** - Issues encountered and solutions

---

## Lab Overview

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      AWS VPC (us-east-2)                    │
│                                                             │
│  ┌────────────────────────┐    ┌────────────────────────┐  │
│  │   Control Plane Node   │    │     NFS Server         │  │
│  │                        │    │                        │  │
│  │  Instance: t2.large    │    │  Instance: t2.medium   │  │
│  │  IP: 3.128.170.22      │    │  IP: 18.224.64.122     │  │
│  │  Private: 172.31.14.91 │    │  Private: 172.31.11.20 │  │
│  │                        │    │                        │  │
│  │  - RKE2 Server         │    │  - NFS Server          │  │
│  │  - Kubernetes API      │◄───┤  - Export: /srv/nfs    │  │
│  │  - NFS CSI Driver      │    │  - Storage: 8GB        │  │
│  │  - StorageClass: nfs   │    │                        │  │
│  └────────────────────────┘    └────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### What You'll Learn

1. Deploy RKE2 control plane on AWS EC2
2. Set up NFS server for shared storage
3. Install NFS CSI driver on Kubernetes
4. Configure StorageClass for dynamic provisioning
5. Test ReadWriteMany (RWX) storage
6. Understand each command and component

---

## Instance Details

### Control Plane Node

| Property | Value |
|----------|-------|
| Instance ID | i-07dc5e39df4506f37 |
| Instance Name | test |
| Instance Type | t2.large (8GB RAM, 2 vCPU, 8GB disk) |
| Public IP | 3.128.170.22 |
| Private IP | 172.31.14.91 |
| OS | Ubuntu 26.04.1 LTS |
| Kernel | 7.0.0-1006-aws |
| Region | us-east-2 |
| Role | RKE2 Control Plane |
| Security Group | Default (needs configuration) |

### NFS Server Node

| Property | Value |
|----------|-------|
| Instance ID | i-0bd4ac60d79d4219f |
| Instance Name | test2 |
| Instance Type | t2.medium (4GB RAM, 2 vCPU, 8GB disk) |
| Public IP | 18.224.64.122 |
| Private IP | 172.31.11.20 |
| OS | Ubuntu |
| Region | us-east-2 |
| Role | NFS Server |
| Security Group | Default (needs configuration) |

---

## Part 1: NFS Server Setup

### Why NFS?

**NFS (Network File System)** provides:
- ✅ **ReadWriteMany (RWX)** - Multiple pods can read/write simultaneously
- ✅ **Centralized storage** - Single source of truth for data
- ✅ **Easy backup** - Direct access from NFS server
- ✅ **Resource efficient** - No storage overhead on cluster nodes
- ✅ **Simple setup** - Easier than distributed storage systems
- ✅ **Cost effective** - Uses existing NFS infrastructure

**When to use NFS:**
- Development and testing environments
- Shared storage requirements (web content, CI/CD artifacts)
- Applications that need RWX access mode
- Simple, centralized storage needs

**When NOT to use NFS:**
- High-performance database workloads
- Production systems requiring data replication
- Applications needing data locality
- Environments with unreliable network

---

### Step 1: SSH to NFS Server

```bash
ssh -i your-key.pem ubuntu@18.224.64.122
```

**What this command does:**
- `ssh` - Secure Shell client for remote login
- `-i your-key.pem` - Use the specified private key file for authentication
- `ubuntu@18.224.64.122` - Connect as user 'ubuntu' to the specified IP

**Why needed:**
- Remote access to the NFS server instance
- Ubuntu is the default user for Ubuntu AMIs on AWS EC2

---

### Step 2: Update System and Install NFS Server

```bash
# Update package lists
sudo apt update && sudo apt upgrade -y
```

**What this command does:**
- `sudo` - Execute as superuser (root)
- `apt update` - Update package lists from repositories
- `apt upgrade -y` - Upgrade all installed packages (-y = auto-confirm)
- `&&` - Run second command only if first succeeds

**Why needed:**
- Ensures system has latest security patches
- Updates package repository metadata
- Prevents compatibility issues with NFS installation

```bash
# Install NFS server and client utilities
sudo apt install -y nfs-kernel-server nfs-common
```

**What this command does:**
- `apt install -y` - Install packages without confirmation
- `nfs-kernel-server` - NFS server daemon (provides NFS services)
- `nfs-common` - NFS client utilities (for testing and client operations)

**Why needed:**
- `nfs-kernel-server` provides the NFS server functionality
- `nfs-common` includes tools like `showmount` for testing

**Package components:**
- `nfsd` - NFS server daemon
- `rpcbind` - RPC port mapper
- `exportfs` - Export table management
- `showmount` - Show NFS exports

---

### Step 3: Enable and Start NFS Service

```bash
# Enable NFS server to start on boot
sudo systemctl enable nfs-kernel-server
```

**What this command does:**
- `systemctl enable` - Create symlinks to start service on boot
- `nfs-kernel-server` - The NFS server systemd service

**Why needed:**
- Ensures NFS server starts automatically after reboot
- Creates persistent service configuration

```bash
# Start NFS server immediately
sudo systemctl start nfs-kernel-server
```

**What this command does:**
- `systemctl start` - Start the service now
- Starts NFS daemon and required RPC services

**Why needed:**
- Activates NFS server without requiring reboot
- Starts `rpcbind`, `nfsd`, and related services

```bash
# Check NFS server status
sudo systemctl status nfs-kernel-server
```

**What this command does:**
- Shows current service status (running, stopped, failed)
- Displays recent logs and process information

**Expected output:**
```
● nfs-server.service - NFS server and services
     Loaded: loaded (/usr/lib/systemd/system/nfs-server.service; enabled; preset: enabled)
     Active: active (exited) since Wed 2026-08-26 14:03:19 UTC; 18s ago
```

**Note:** Status `active (exited)` is normal - NFS server runs as a kernel service, not a continuous daemon.

---

### Step 4: Create NFS Export Directory

```bash
# Create directory for NFS exports
sudo mkdir -p /srv/nfs/kubedata
```

**What this command does:**
- `mkdir` - Make directory
- `-p` - Create parent directories as needed
- `/srv/nfs/kubedata` - Directory path (following FHS standard)

**Why this location:**
- `/srv/` - Standard location for service data (Filesystem Hierarchy Standard)
- `/nfs/` - Indicates NFS-related data
- `/kubedata` - Specific to Kubernetes persistent volumes

**Why needed:**
- NFS requires a directory to export
- This directory will hold all Kubernetes PVC data

```bash
# Set ownership to nobody:nogroup
sudo chown nobody:nogroup /srv/nfs/kubedata
```

**What this command does:**
- `chown` - Change owner
- `nobody:nogroup` - User:Group (standard NFS unprivileged user)

**Why needed:**
- NFS best practice: use unprivileged user for exported directories
- `nobody:nogroup` is the standard NFS anonymous user
- Prevents permission issues with root_squash (explained later)

```bash
# Set permissions to allow read/write/execute
sudo chmod 777 /srv/nfs/kubedata
```

**What this command does:**
- `chmod` - Change mode (permissions)
- `777` - Octal permission: owner, group, and others all have rwx

**Permission breakdown:**
- `7` = 4 (read) + 2 (write) + 1 (execute) = rwx
- First 7: owner (nobody) has rwx
- Second 7: group (nogroup) has rwx
- Third 7: others (everyone) has rwx

**Why needed:**
- Allows any process to write to the directory
- Necessary for Kubernetes dynamic provisioning
- **Security note:** In production, use more restrictive permissions (e.g., 755 or 750)

```bash
# Verify directory setup
ls -la /srv/nfs/
```

**Expected output:**
```
drwxr-xr-x 3 root   root    4096 Aug 26 14:03 .
drwxr-xr-x 3 root   root    4096 Aug 26 14:03 ..
drwxrwxrwx 2 nobody nogroup 4096 Aug 26 14:03 kubedata
```

---

### Step 5: Configure NFS Exports

```bash
# Add export configuration to /etc/exports
sudo tee -a /etc/exports <<EOF
/srv/nfs/kubedata    172.31.0.0/16(rw,sync,no_subtree_check,no_root_squash,insecure)
EOF
```

**What this command does:**
- `tee -a` - Append to file (also display to stdout)
- `/etc/exports` - NFS export configuration file

**Export line breakdown:**

| Component | Meaning | Why Needed |
|-----------|---------|------------|
| `/srv/nfs/kubedata` | Directory to export | The path being shared |
| `172.31.0.0/16` | Client network range | VPC CIDR - allows all instances in VPC |
| `rw` | Read and write access | Pods need to write data |
| `sync` | Synchronous writes | Ensures data integrity |
| `no_subtree_check` | Skip subtree verification | Improves reliability |
| `no_root_squash` | Allow root access | Required for Kubernetes |
| `insecure` | Allow ports > 1024 | Compatibility with some clients |

**Export options explained:**

**`rw` (read/write):**
- Allows clients to read and write to the export
- Default is `ro` (read-only)

**`sync` (synchronous):**
- Server writes data to disk before acknowledging
- Ensures data integrity but slower
- Alternative: `async` (faster but risk of data loss)

**`no_subtree_check`:**
- Disables subtree checking
- Prevents issues when files are renamed or moved
- Recommended for most NFS exports

**`no_root_squash`:**
- By default, NFS maps root (UID 0) to `nobody`
- `no_root_squash` allows root to access files as root
- **Required for Kubernetes** because containers run as various UIDs
- **Security note:** In production, consider more restrictive options

**`insecure`:**
- Allows connections from ports > 1024
- Some NFS clients use high ports
- Improves compatibility

**Network range `172.31.0.0/16`:**
- AWS VPC default CIDR block
- Allows all instances in the VPC to access NFS
- Could restrict to specific IPs: `172.31.14.91/32` (control plane only)

```bash
# Apply export configuration
sudo exportfs -av
```

**What this command does:**
- `exportfs` - Manage NFS export table
- `-a` - Export all directories in /etc/exports
- `-v` - Verbose output

**Expected output:**
```
exporting 172.31.0.0/16:/srv/nfs/kubedata
```

**Why needed:**
- Makes export configuration active immediately
- No need to restart NFS server

```bash
# Restart NFS server to ensure clean state
sudo systemctl restart nfs-kernel-server
```

**What this command does:**
- Restarts all NFS services
- Reloads configuration files

```bash
# Verify exports are active
sudo exportfs -v
```

**What this command does:**
- Shows currently exported directories with options

**Expected output:**
```
/srv/nfs/kubedata
                172.31.0.0/16(sync,wdelay,hide,no_subtree_check,sec=sys,rw,insecure,no_root_squash,no_all_squash)
```

---

### Step 6: Create Test File

```bash
# Create test file to verify NFS is working
echo "NFS test from server - $(date)" | sudo tee /srv/nfs/kubedata/test.txt
```

**What this command does:**
- `echo` - Print text to stdout
- `$(date)` - Command substitution: insert current timestamp
- `|` - Pipe: redirect output to next command
- `sudo tee` - Write to file with root privileges

**Why needed:**
- Verifies NFS export is writable
- Provides test file for client verification

```bash
# Verify file was created
cat /srv/nfs/kubedata/test.txt
```

**Expected output:**
```
NFS test from server - Wed Aug 26 14:05:04 UTC 2026
```

---

### Step 7: AWS Security Group Configuration

**Why needed:**
- AWS security groups act as firewalls
- Default security group blocks most inbound traffic
- NFS requires specific ports to be open

**Required ports for NFS:**

| Port | Protocol | Service | Purpose |
|------|----------|---------|---------|
| 2049 | TCP/UDP | nfsd | NFS protocol |
| 111 | TCP/UDP | rpcbind | RPC port mapper |
| 20048 | TCP/UDP | mountd | Mount daemon |

**AWS Console method:**

1. Go to EC2 > Instances > i-0bd4ac60d79d4219f
2. Click "Security" tab
3. Click security group link
4. Click "Edit inbound rules"
5. Add rules:

```
Type: Custom TCP, Port: 2049, Source: 172.31.14.91/32, Description: NFS from control plane
Type: Custom TCP, Port: 111, Source: 172.31.14.91/32, Description: RPC from control plane
Type: Custom TCP, Port: 20048, Source: 172.31.14.91/32, Description: mountd from control plane
```

**AWS CLI method:**

```bash
# Get security group ID for NFS instance
aws ec2 describe-instances --instance-ids i-0bd4ac60d79d4219f \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text
```

**What this command does:**
- `aws ec2 describe-instances` - Query EC2 instance details
- `--query` - JMESPath query to extract security group ID
- `--output text` - Return plain text instead of JSON

```bash
# Add NFS port rule (replace sg-xxxxx with your security group ID)
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 2049 \
  --cidr 172.31.14.91/32
```

**What this command does:**
- `authorize-security-group-ingress` - Add inbound rule
- `--group-id` - Target security group
- `--protocol tcp` - TCP protocol
- `--port 2049` - NFS port
- `--cidr 172.31.14.91/32` - Allow from control plane IP only

**For entire VPC (less secure):**
```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 2049 \
  --cidr 172.31.0.0/16
```

---

## Part 2: RKE2 Control Plane Setup

### Why RKE2?

**RKE2 (Rancher Kubernetes Engine 2)** provides:
- ✅ **Production-ready** - Hardened Kubernetes distribution
- ✅ **Security-focused** - CIS benchmark compliant
- ✅ **Simple installation** - Single binary installation
- ✅ **Built-in components** - Includes CNI, CSI, Ingress
- ✅ **Air-gap support** - Works in disconnected environments
- ✅ **FIPS compliant** - Government/enterprise requirements

**RKE2 vs k3s:**
- RKE2: Production, security-hardened, full Kubernetes
- k3s: Lightweight, edge computing, development

**RKE2 vs kubeadm:**
- RKE2: Simpler, includes all components, automatic TLS
- kubeadm: More manual, flexible, standard upstream

---

### Step 1: SSH to Control Plane Node

```bash
ssh -i your-key.pem ubuntu@3.128.170.22
```

---

### Step 2: Install NFS Client Utilities

```bash
# Update system and install NFS client
sudo apt update && sudo apt upgrade -y
sudo apt install -y nfs-common curl wget
```

**What this command does:**
- `nfs-common` - NFS client utilities
- `curl` - HTTP client for downloading files
- `wget` - Alternative HTTP client

**Why needed:**
- `nfs-common` provides `showmount` for testing NFS
- `curl`/`wget` for downloading RKE2 installation script

```bash
# Test NFS connectivity from control plane
showmount -e 172.31.11.20
```

**What this command does:**
- `showmount` - Show NFS exports on remote server
- `-e` - Show exports
- `172.31.11.20` - NFS server IP

**Expected output:**
```
Export list for 172.31.11.20:
/srv/nfs/kubedata 172.31.0.0/16
```

**Why needed:**
- Verifies NFS server is accessible
- Confirms security group allows NFS traffic
- Shows available exports

```bash
# Create test mount point
sudo mkdir -p /mnt/nfs-test
```

```bash
# Test mount NFS export
sudo mount -t nfs 172.31.11.20:/srv/nfs/kubedata /mnt/nfs-test
```

**What this command does:**
- `mount` - Mount filesystem
- `-t nfs` - Specify NFS filesystem type
- `172.31.11.20:/srv/nfs/kubedata` - Server:export path
- `/mnt/nfs-test` - Local mount point

**Why needed:**
- Verifies NFS mount works correctly
- Tests read/write permissions

```bash
# Verify mount and read test file
ls -la /mnt/nfs-test
cat /mnt/nfs-test/test.txt
```

**Expected output:**
```
NFS test from server - Wed Aug 26 14:05:04 UTC 2026
```

```bash
# Unmount test
sudo umount /mnt/nfs-test
```

**What this command does:**
- `umount` - Unmount filesystem
- Cleans up test mount

---

### Step 3: Install RKE2

```bash
# Download and install RKE2
curl -sfL https://get.rke2.io | sudo sh -
```

**What this command does:**
- `curl -sfL` - Silent, fail on error, follow redirects
- `https://get.rke2.io` - Official RKE2 installation script
- `| sudo sh -` - Execute script with root privileges

**Installation process:**
1. Detects OS and architecture
2. Downloads RKE2 binary
3. Downloads required images
4. Installs systemd service files
5. Creates default configuration

**Common error: "You need to be root"**

```bash
# WRONG - sudo only applies to curl, not sh
sudo curl -sfL https://get.rke2.io | sh -

# CORRECT - Pipe to sudo sh
curl -sfL https://get.rke2.io | sudo sh -
```

**Why this matters:**
- Installation script needs root privileges
- `sudo` must apply to `sh -` which executes the script

```bash
# Verify installation
dpkg -l | grep rke2
```

**Expected output:**
```
ii  rke2-server  1.35.7+rke2r1  amd64  RKE2 Server
```

**Note:** On Ubuntu, RKE2 is installed as a .deb package. On RHEL/CentOS, it's an RPM.

---

### Step 4: Configure RKE2 Server

```bash
# Create configuration directory
sudo mkdir -p /etc/rancher/rke2
```

**What this command does:**
- Creates RKE2 config directory
- RKE2 looks for configuration here by default

```bash
# Generate random token for cluster
TOKEN=$(openssl rand -hex 32)
echo "Generated token: $TOKEN"
```

**What this command does:**
- `openssl rand -hex 32` - Generate 32 bytes of random data in hex
- Creates a secure token for cluster authentication

**Why needed:**
- Token authenticates nodes joining the cluster
- Must be the same across all nodes in the cluster
- Save this token for future worker node setup

```bash
# Create RKE2 configuration file
sudo tee /etc/rancher/rke2/config.yaml <<EOF
token: b1d882966c3f8039084df3838f5ea8d33ab570b4594b9a62430990f3d017695f
tls-san:
  - 3.128.170.22
  - 172.31.14.91
  - rke2-control-plane-1
  - localhost
node-name: rke2-control-plane-1
EOF
```

**Configuration breakdown:**

| Option | Value | Purpose |
|--------|-------|---------|
| `token` | (random hex) | Cluster authentication secret |
| `tls-san` | IP addresses/DNS names | Subject Alternative Names for API server certificate |
| `node-name` | rke2-control-plane-1 | Custom node name (instead of hostname) |

**Why `token` is important:**
- Authenticates nodes to the cluster
- Must be identical on all control plane nodes
- Must be identical on all worker nodes
- Keep it secret - anyone with this token can join the cluster

**Why `tls-san` is needed:**
- Kubernetes API server uses TLS certificates
- Certificates must include all IPs/DNS names used to access API
- Missing SAN = certificate verification failures
- Includes: public IP, private IP, node name, localhost

**Common issue: "server:" line for first node**

```bash
# WRONG - Don't include server: for the FIRST control plane node
server: https://3.128.170.22:9345  # ❌ This causes bootstrap failure

# CORRECT - Omit server: for the FIRST control plane node
# (no server line)  # ✅ First node bootstraps itself
```

**Why:**
- First control plane node bootstraps the cluster
- It doesn't connect to an existing server
- `server:` is only for joining existing clusters

```bash
# View configuration
cat /etc/rancher/rke2/config.yaml
```

**Expected output:**
```
token: b1d882966c3f8039084df3838f5ea8d33ab570b4594b9a62430990f3d017695f
tls-san:
  - 3.128.170.22
  - 172.31.14.91
  - rke2-control-plane-1
  - localhost
node-name: rke2-control-plane-1
```

---

### Step 5: Start RKE2 Server

```bash
# Enable RKE2 to start on boot
sudo systemctl enable rke2-server
```

**What this command does:**
- Creates systemd symlinks for automatic startup
- RKE2 will start on every boot

```bash
# Start RKE2 server
sudo systemctl start rke2-server
```

**What this command does:**
- Starts RKE2 server process
- Downloads required images (first start takes 2-5 minutes)
- Initializes Kubernetes control plane

**Startup process:**
1. Starts containerd (container runtime)
2. Starts etcd (distributed key-value store)
3. Starts kube-apiserver
4. Starts kube-controller-manager
5. Starts kube-scheduler
6. Deploys system components (CNI, CoreDNS, etc.)

**Check status:**
```bash
sudo systemctl status rke2-server
```

**Expected output:**
```
● rke2-server.service - Rancher Kubernetes Engine v2 (server)
     Loaded: loaded (/usr/local/lib/systemd/system/rke2-server.service; enabled; preset: enabled)
     Active: active (running) since Wed 2026-08-26 13:52:56 UTC; 5min ago
```

**Watch logs:**
```bash
sudo journalctl -u rke2-server -f
```

**What this command does:**
- `journalctl` - Query systemd journal
- `-u rke2-server` - Show logs for RKE2 server unit
- `-f` - Follow (stream new logs as they arrive)

**Press Ctrl+C to stop watching**

---

### Step 6: Configure kubectl

**What is kubectl?**
- Command-line tool for interacting with Kubernetes API
- Uses kubeconfig file for authentication
- Default location: `~/.kube/config`

```bash
# Create .kube directory
mkdir -p ~/.kube
```

```bash
# Copy kubeconfig file
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
```

**What this command does:**
- Copies RKE2 kubeconfig to standard kubectl location
- RKE2 creates kubeconfig at `/etc/rancher/rke2/rke2.yaml`

**Why the unusual location:**
- RKE2 uses `/etc/rancher/rke2/` for all configuration
- Standard location would be `/etc/rancher/rke2/kubeconfig.yaml`
- `rke2.yaml` contains both client certs and cluster CA

```bash
# Fix ownership (current user instead of root)
sudo chown $USER:$USER ~/.kube/config
```

**Why needed:**
- File was created by root (sudo cp)
- kubectl needs read access
- `$USER:$USER` sets owner to your user and group

```bash
# Set environment variable
export KUBECONFIG=~/.kube/config
```

**What this command does:**
- Sets KUBECONFIG environment variable
- Tells kubectl where to find configuration
- Only affects current shell session

```bash
# Add to bashrc for persistence
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
```

**Why needed:**
- Makes KUBECONFIG permanent across shell sessions
- Automatically set on every login

```bash
# Verify cluster access
kubectl get nodes -o wide
```

**Expected output:**
```
NAME                   STATUS   ROLES                AGE     VERSION          INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION   CONTAINER-RUNTIME
rke2-control-plane-1   Ready    control-plane,etcd   6m22s   v1.35.7+rke2r1   172.31.14.91   <none>        Ubuntu 26.04.1 LTS   7.0.0-1006-aws   containerd://2.2.6-k3s1
```

**Output breakdown:**
- `NAME` - Node name (from config.yaml)
- `STATUS` - Ready = node is healthy
- `ROLES` - control-plane,etcd = control plane node
- `AGE` - Time since node was created
- `VERSION` - Kubernetes version
- `INTERNAL-IP` - Node's private IP
- `EXTERNAL-IP` - Node's public IP (none = not configured)
- `OS-IMAGE` - Operating system
- `KERNEL-VERSION` - Linux kernel version
- `CONTAINER-RUNTIME` - containerd version

```bash
# Check system pods
kubectl get pods -A
```

**What this command does:**
- `get pods` - List pods
- `-A` - All namespaces

**Expected pods:**
- `kube-system` - CoreDNS, canal (CNI), metrics-server
- Other system components as needed

---

## Part 3: Install NFS CSI Driver

### What is CSI?

**CSI (Container Storage Interface)** is a standard for exposing storage systems to container orchestrators.

**Why CSI?**
- Kubernetes standardized on CSI for storage
- Allows any storage vendor to write a driver
- Separates Kubernetes core from storage implementations
- Replaces in-tree storage plugins

**How CSI works:**
1. User creates PVC (PersistentVolumeClaim)
2. CSI controller provisions volume on storage backend
3. CSI node driver attaches volume to pod
4. Pod uses volume as normal

---

### Step 1: Install Helm

**What is Helm?**
- Package manager for Kubernetes
- Deploys applications as "charts"
- Manages upgrades, rollbacks, and configuration

```bash
# Download Helm installation script
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
```

**What this command does:**
- `curl -fsSL` - Silent, fail on error, follow redirects, output to file
- `-o get_helm.sh` - Save to file

```bash
# Make script executable
chmod 700 get_helm.sh
```

**What this command does:**
- `chmod 700` - Set permissions: owner can read, write, execute
- Security: only you can run this script

```bash
# Run Helm installer
./get_helm.sh
```

**What this command does:**
- Detects OS and architecture
- Downloads appropriate Helm binary
- Installs to `/usr/local/bin/helm`

```bash
# Verify installation
helm version
```

**Expected output:**
```
version.BuildInfo{Version:"v3.15.0", GitCommit:"...", GitTreeState:"clean", GoVersion:"go1.22.0"}
```

---

### Step 2: Install NFS CSI Driver

```bash
# Add NFS CSI driver Helm repository
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
```

**What this command does:**
- `helm repo add` - Add a chart repository
- `csi-driver-nfs` - Local name for the repository
- URL - Location of the chart repository

**Why needed:**
- Helm needs to know where to find charts
- Repository contains the NFS CSI driver chart

```bash
# Update Helm repository index
helm repo update
```

**What this command does:**
- Downloads latest index from all repositories
- Ensures you get the latest chart versions

```bash
# Install NFS CSI driver
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system \
  --set kubeletDir=/var/lib/kubelet
```

**Command breakdown:**
- `helm install` - Install a chart
- `csi-driver-nfs` - Release name (instance of the chart)
- `csi-driver-nfs/csi-driver-nfs` - Repository/chart name
- `--namespace kube-system` - Install in kube-system namespace
- `--set kubeletDir=/var/lib/kubelet` - Override kubelet directory path

**Why `kubeletDir=/var/lib/kubelet`:**
- RKE2 uses `/var/lib/kubelet` instead of standard `/var/lib/kubelet`
- CSI driver needs to know where kubelet stores data
- Volume plugins and mounts are managed by kubelet

**What gets deployed:**
1. **CSI Controller** (Deployment)
   - `csi-provisioner` - Creates/deletes volumes
   - `csi-attacher` - Attaches/detaches volumes to nodes
   - `csi-resizer` - Resizes volumes
   - `csi-snapshotter` - Creates snapshots (if enabled)
   - `nfs` - NFS driver

2. **CSI Node** (DaemonSet)
   - `csi-node-driver-registrar` - Registers driver with kubelet
   - `liveness-probe` - Health checks
   - `nfs` - NFS driver

```bash
# Verify installation
kubectl get pods -n kube-system -l app.kubernetes.io/name=csi-driver-nfs
```

**Expected output:**
```
NAME                                 READY   STATUS    RESTARTS   AGE
csi-nfs-controller-7f8cc69c8-ts8qr   5/5     Running   0          25s
csi-nfs-node-xlq52                   3/3     Running   0          25s
```

**Pod breakdown:**
- `csi-nfs-controller-*` - Controller component (1 replica)
  - `READY 5/5` = 5 containers running
- `csi-nfs-node-*` - Node component (1 per node)
  - `READY 3/3` = 3 containers running

---

### Step 3: Create StorageClass

**What is a StorageClass?**
- Defines a "class" of storage
- Specifies provisioner (CSI driver)
- Configures parameters for volume creation
- Enables dynamic provisioning

```bash
# Create StorageClass for NFS
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: nfs.csi.k8s.io
parameters:
  server: 172.31.11.20
  share: /srv/nfs/kubedata
reclaimPolicy: Delete
volumeBindingMode: Immediate
mountOptions:
  - hard
  - nfsvers=4.1
EOF
```

**StorageClass breakdown:**

| Field | Value | Purpose |
|-------|-------|---------|
| `apiVersion` | storage.k8s.io/v1 | Kubernetes API version |
| `kind` | StorageClass | Resource type |
| `metadata.name` | nfs-csi | Name to reference this class |
| `provisioner` | nfs.csi.k8s.io | CSI driver to use |
| `parameters.server` | 172.31.11.20 | NFS server IP |
| `parameters.share` | /srv/nfs/kubedata | NFS export path |
| `reclaimPolicy` | Delete | Delete PV when PVC is deleted |
| `volumeBindingMode` | Immediate | Create PV immediately when PVC is created |
| `mountOptions` | hard, nfsvers=4.1 | Mount options for NFS |

**Parameter details:**

**`server: 172.31.11.20`**
- NFS server IP address
- Use private IP (not public IP)
- Private IP is stable across reboots

**`share: /srv/nfs/kubedata`**
- Export path on NFS server
- Must match export in `/etc/exports`

**`reclaimPolicy: Delete`**
- What happens to PV when PVC is deleted
- `Delete` = Remove PV and delete data on NFS
- `Retain` = Keep PV and data (manual cleanup needed)

**`volumeBindingMode: Immediate`**
- `Immediate` = Create PV as soon as PVC is created
- `WaitForFirstConsumer` = Wait until pod uses PVC
- NFS doesn't have topology constraints, so Immediate is fine

**`mountOptions`**:

**`hard`**
- Hard mount: retry indefinitely on NFS failure
- Alternative: `soft` (timeout and return error)
- Hard mounts are safer for data integrity

**`nfsvers=4.1`**
- Use NFS version 4.1
- NFS 4.1 has better performance and features than NFS 3
- NFS 4.2 is newer but not universally supported

```bash
# Verify StorageClass was created
kubectl get storageclass
```

**Expected output:**
```
NAME      PROVISIONER      RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
nfs-csi   nfs.csi.k8s.io   Delete          Immediate           false                  7s
```

**Set as default (optional):**
```bash
kubectl patch storageclass nfs-csi -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

**What this does:**
- Makes `nfs-csi` the default StorageClass
- PVCs without `storageClassName` will use this class
- Only one default StorageClass per cluster

---

## Part 4: Test NFS Storage

### Step 1: Create PersistentVolumeClaim (PVC)

**What is a PVC?**
- Request for storage by a user
- Specifies size, access mode, and storage class
- Kubernetes automatically provisions PV

```bash
# Create test PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-test-pvc
spec:
  accessModes:
  - ReadWriteMany
  storageClassName: nfs-csi
  resources:
    requests:
      storage: 1Gi
EOF
```

**PVC breakdown:**

| Field | Value | Purpose |
|-------|-------|---------|
| `metadata.name` | nfs-test-pvc | PVC name |
| `spec.accessModes` | ReadWriteMany | Access mode |
| `spec.storageClassName` | nfs-csi | Which StorageClass to use |
| `spec.resources.requests.storage` | 1Gi | Requested size |

**Access modes explained:**

| Mode | Abbreviation | Description |
|------|--------------|-------------|
| ReadWriteOnce | RWO | One node can read/write |
| ReadOnlyMany | ROX | Many nodes can read |
| ReadWriteMany | RWX | Many nodes can read/write |
| ReadWriteOncePod | RWOP | One pod can read/write (Kubernetes 1.22+) |

**Why ReadWriteMany (RWX) for NFS:**
- NFS supports multiple readers/writers
- This is NFS's main advantage
- Multiple pods can share same volume
- Useful for: web servers, CI/CD, content management

```bash
# Check PVC status
kubectl get pvc nfs-test-pvc
```

**Expected output:**
```
NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
nfs-test-pvc   Bound    pvc-ce179f69-6b1b-4ff6-9102-8fda3479f3d6   1Gi        RWX            nfs-csi        <unset>                 6s
```

**Status meanings:**
- `Pending` - Waiting for provisioning
- `Bound` - Successfully provisioned and bound to PV
- `Lost` - PV is gone

**Verify PV was created:**
```bash
kubectl get pv
```

**Expected output:**
```
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                  STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
pvc-ce179f69-6b1b-4ff6-9102-8fda3479f3d6   1Gi        RWX            Delete           Bound    default/nfs-test-pvc   nfs-csi        <unset>                          94s
```

**PV breakdown:**
- PV name is auto-generated from PVC UID
- CAPACITY shows requested size
- RECLAIM POLICY from StorageClass
- STATUS Bound means ready to use

---

### Step 2: Create Test Pod

```bash
# Create test pod using the PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nfs-test-pod
spec:
  containers:
  - name: nginx
    image: nginx:latest
    volumeMounts:
    - name: nfs-volume
      mountPath: /usr/share/nginx/html
  volumes:
  - name: nfs-volume
    persistentVolumeClaim:
      claimName: nfs-test-pvc
EOF
```

**Pod spec breakdown:**

| Field | Value | Purpose |
|-------|-------|---------|
| `containers[0].name` | nginx | Container name |
| `containers[0].image` | nginx:latest | Container image |
| `containers[0].volumeMounts[0].name` | nfs-volume | Mount which volume |
| `containers[0].volumeMounts[0].mountPath` | /usr/share/nginx/html | Where to mount |
| `volumes[0].name` | nfs-volume | Volume name (must match) |
| `volumes[0].persistentVolumeClaim.claimName` | nfs-test-pvc | Which PVC to use |

**Volume mounting process:**
1. Pod is scheduled to a node
2. CSI node driver mounts NFS export
3. NFS is bind-mounted into container at `mountPath`
4. Container can read/write to the path

```bash
# Watch pod status
kubectl get pod nfs-test-pod -w
```

**What this command does:**
- `-w` - Watch mode (stream updates)
- Shows status changes in real-time

**Expected progression:**
```
NAME           READY   STATUS    RESTARTS   AGE
nfs-test-pod   0/1     Pending   0          0s
nfs-test-pod   0/1     ContainerCreating   0          1s
nfs-test-pod   1/1     Running   0          5s
```

**Status meanings:**
- `Pending` - Pod is being scheduled
- `ContainerCreating` - Pulling image, mounting volumes
- `Running` - Container started successfully

**Press Ctrl+C to stop watching**

---

### Step 3: Write and Read Test Data

```bash
# Write test data to NFS volume
kubectl exec nfs-test-pod -- sh -c "echo 'NFS storage test from pod - $(date)' > /usr/share/nginx/html/index.html"
```

**What this command does:**
- `kubectl exec nfs-test-pod` - Execute command in pod
- `--` - Separator (end of kubectl flags)
- `sh -c "..."` - Run shell command
- `echo '...' > file` - Write to file

```bash
# Read test data back
kubectl exec nfs-test-pod -- cat /usr/share/nginx/html/index.html
```

**Expected output:**
```
NFS storage test from pod - Wed Aug 26 14:11:52 UTC 2026
```

**Verify on NFS server:**
```bash
# SSH to NFS server
ssh -i your-key.pem ubuntu@18.224.64.122

# List PVC directories
ls -la /srv/nfs/kubedata/

# View the PVC directory
ls -la /srv/nfs/kubedata/pvc-*/

# Read the file directly from NFS server
cat /srv/nfs/kubedata/pvc-*/index.html
```

**What you'll see:**
- NFS server has directory named after PVC
- File exists on NFS server
- Data is persistent outside the pod

---

### Step 4: Test ReadWriteMany (RWX)

**What is RWX?**
- ReadWriteMany = multiple pods can access same volume
- Unique to NFS and a few other storage systems
- Most storage only supports ReadWriteOnce (RWO)

**Why test RWX?**
- Verifies NFS is working correctly
- Demonstrates key advantage of NFS
- Useful pattern for shared content

```bash
# Create second pod using same PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nfs-test-pod-2
spec:
  containers:
  - name: nginx
    image: nginx:latest
    volumeMounts:
    - name: nfs-volume
      mountPath: /data
  volumes:
  - name: nfs-volume
    persistentVolumeClaim:
      claimName: nfs-test-pvc
EOF
```

**Note:** Same PVC (`nfs-test-pvc`) but different mount path (`/data`)

```bash
# Wait for pod to start
kubectl get pod nfs-test-pod-2 -w
```

Press Ctrl+C when running.

```bash
# Verify both pods can see the same data
kubectl exec nfs-test-pod -- cat /usr/share/nginx/html/index.html
kubectl exec nfs-test-pod-2 -- cat /data/index.html
```

**Expected:** Both commands show the same content!

```bash
# Write from pod-2
kubectl exec nfs-test-pod-2 -- sh -c "echo 'Updated from pod-2 - $(date)' >> /data/index.html"

# Read from pod-1 to see the update
kubectl exec nfs-test-pod -- cat /usr/share/nginx/html/index.html
```

**Expected output:**
```
NFS storage test from pod - Wed Aug 26 14:11:52 UTC 2026
Updated from pod-2 - Wed Aug 26 14:14:27 UTC 2026
```

**What this demonstrates:**
- Both pods share the same storage
- Changes from pod-2 are visible to pod-1
- True ReadWriteMany functionality

---

## Troubleshooting Guide

### Issue 1: RKE2 Server Fails to Start

**Error:**
```
failed to validate token: failed to get CA certs: Get "https://3.128.170.22:9345/cacerts": dial tcp 3.128.170.22:9345: connect: connection refused
```

**Root cause:**
- Config includes `server:` line for first control plane node
- First node tries to connect to itself before it's running
- Bootstrap fails because server isn't ready

**Solution:**
```bash
# For FIRST control plane node, remove server: line
sudo tee /etc/rancher/rke2/config.yaml <<EOF
token: your-token-here
tls-san:
  - 3.128.170.22
  - 172.31.14.91
  - rke2-control-plane-1
  - localhost
node-name: rke2-control-plane-1
EOF
```

**Why this works:**
- First node bootstraps the cluster
- No server to connect to yet
- `token:` is sufficient for first node

**For additional control plane nodes, include server:**
```bash
sudo tee /etc/rancher/rke2/config.yaml <<EOF
server: https://172.31.14.91:9345
token: your-token-here
tls-san:
  - 3.128.170.22
  - 172.31.14.91
  - rke2-control-plane-2
  - localhost
node-name: rke2-control-plane-2
EOF
```

---

### Issue 2: showmount: command not found

**Error:**
```
showmount: command not found
```

**Solution:**
```bash
sudo apt install -y nfs-common
```

**Why:**
- `nfs-common` package provides `showmount`
- Required for NFS client operations

---

### Issue 3: mount.nfs: access denied

**Error:**
```
mount.nfs: access denied by server while mounting 172.31.11.20:/srv/nfs/kubedata
```

**Possible causes:**
1. NFS export doesn't include client IP
2. Security group blocks NFS ports
3. NFS server not running

**Check NFS exports on server:**
```bash
# On NFS server
sudo exportfs -v
```

**Verify security group:**
```bash
# Test port connectivity from client
nc -zv 172.31.11.20 2049
```

**Check NFS server status:**
```bash
# On NFS server
sudo systemctl status nfs-kernel-server
```

---

### Issue 4: PVC stuck in Pending

**Error:**
```
kubectl get pvc nfs-test-pvc
NAME           STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
nfs-test-pvc   Pending                                      nfs-csi        30s
```

**Check:**
```bash
# Describe PVC to see events
kubectl describe pvc nfs-test-pvc

# Check CSI driver pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=csi-driver-nfs

# Check CSI driver logs
kubectl logs -n kube-system -l app.kubernetes.io/name=csi-driver-nfs --tail=50
```

**Common causes:**
1. CSI driver not running
2. NFS server unreachable
3. Wrong server IP or share path in StorageClass

---

### Issue 5: Pod stuck in ContainerCreating

**Check:**
```bash
# Describe pod to see events
kubectl describe pod nfs-test-pod

# Check for volume mount errors
kubectl get events --field-selector reason=FailedMount
```

**Common causes:**
1. PVC not bound
2. NFS server unreachable from node
3. Security group blocking NFS

---

## Comparison: NFS vs Other Storage

### NFS vs local-path

| Feature | NFS | local-path |
|---------|-----|------------|
| ReadWriteMany | ✅ Yes | ❌ No |
| Centralized | ✅ Yes | ❌ No (per-node) |
| Setup complexity | ⚠️ Medium | ✅ Simple |
| Performance | ⚠️ Good | ✅ Best (local disk) |
| Data persistence | ✅ Survives node failure | ❌ Tied to node |
| Backup | ✅ Easy (from NFS server) | ⚠️ Manual |
| Use case | Shared storage, multi-pod apps | Single-pod, dev/test |

### NFS vs Longhorn

| Feature | NFS | Longhorn |
|---------|-----|----------|
| Setup complexity | ✅ Simple | ❌ Complex |
| Resource usage | ✅ Minimal | ❌ High (2+ GB RAM) |
| Data replication | ❌ No | ✅ Yes (configurable) |
| High availability | ❌ Single point of failure | ✅ Yes |
| Snapshots | ❌ Manual | ✅ Built-in |
| UI dashboard | ❌ No | ✅ Yes |
| Storage topology | ✅ Centralized | ✅ Distributed |
| Use case | Shared storage, simple setups | Production, HA required |

### When to use each:

**Use local-path when:**
- Single-node cluster
- Development/testing
- No shared storage needed
- Maximum performance required

**Use NFS when:**
- Need ReadWriteMany volumes
- Multiple pods share same data
- Simple centralized storage
- Easy backup required
- Limited cluster resources

**Use Longhorn when:**
- Production environment
- High availability required
- Data replication needed
- Have sufficient resources (RAM, disk)
- Need snapshots and backups

---

## Best Practices

### NFS Server

1. **Use dedicated instances for NFS**
   - Don't run NFS on control plane nodes
   - Separate storage from compute

2. **Proper permissions**
   ```bash
   # For production, use more restrictive permissions
   sudo chown nobody:nogroup /srv/nfs/kubedata
   sudo chmod 755 /srv/nfs/kubedata  # Not 777
   ```

3. **Regular backups**
   ```bash
   # Backup NFS data
   sudo tar -czf /backup/nfs-backup-$(date +%Y%m%d).tar.gz /srv/nfs/kubedata/
   ```

4. **Monitor disk usage**
   ```bash
   # Check disk usage
   df -h /srv/nfs/kubedata/
   ```

### RKE2

1. **Save the token**
   - Store cluster token securely
   - Required for adding nodes

2. **TLS SANs**
   - Include all IPs and DNS names used to access API
   - Prevents certificate errors

3. **Regular updates**
   ```bash
   # Check for RKE2 updates
   curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION=v1.35.7+rke2r1 sh -
   ```

### Kubernetes

1. **Use namespaces**
   ```bash
   # Create namespace for applications
   kubectl create namespace myapp
   ```

2. **Set resource limits**
   ```yaml
   resources:
     requests:
       memory: "128Mi"
       cpu: "100m"
     limits:
       memory: "256Mi"
       cpu: "200m"
   ```

3. **Use labels and annotations**
   ```yaml
   metadata:
     labels:
       app: myapp
       environment: production
   ```

---

## Cleanup

### Clean up test resources

```bash
# Delete test pods
kubectl delete pod nfs-test-pod nfs-test-pod-2 --ignore-not-found=true

# Delete test PVC
kubectl delete pvc nfs-test-pvc --ignore-not-found=true

# Verify cleanup
kubectl get pods
kubectl get pvc
```

### Uninstall CSI driver

```bash
# Uninstall NFS CSI driver
helm uninstall csi-driver-nfs -n kube-system

# Delete StorageClass
kubectl delete storageclass nfs-csi --ignore-not-found=true

# Verify
kubectl get storageclass
```

### Stop NFS server

```bash
# On NFS server
ssh -i your-key.pem ubuntu@18.224.64.122

# Stop NFS service
sudo systemctl stop nfs-kernel-server
sudo systemctl disable nfs-kernel-server

# Remove exports
sudo tee /etc/exports <<EOF
EOF

sudo exportfs -av
```

### Stop RKE2

```bash
# On control plane
sudo systemctl stop rke2-server
sudo systemctl disable rke2-server
```

---

## Summary

### What You Learned

1. ✅ **NFS server setup** - Install, configure, and export NFS
2. ✅ **RKE2 installation** - Deploy single-node Kubernetes cluster
3. ✅ **CSI driver deployment** - Install and configure NFS CSI driver
4. ✅ **StorageClass creation** - Enable dynamic volume provisioning
5. ✅ **PVC creation** - Request persistent storage
6. ✅ **ReadWriteMany testing** - Verify multi-pod access to same volume
7. ✅ **Troubleshooting** - Debug common issues

### Key Commands Reference

```bash
# NFS Server
sudo apt install -y nfs-kernel-server
sudo mkdir -p /srv/nfs/kubedata
sudo chown nobody:nogroup /srv/nfs/kubedata
echo "/srv/nfs/kubedata    172.31.0.0/16(rw,sync,no_subtree_check,no_root_squash,insecure)" | sudo tee -a /etc/exports
sudo exportfs -av
sudo systemctl restart nfs-kernel-server

# RKE2
curl -sfL https://get.rke2.io | sudo sh -
sudo systemctl enable rke2-server
sudo systemctl start rke2-server
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
kubectl get nodes

# NFS CSI Driver
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs --namespace kube-system --set kubeletDir=/var/lib/kubelet

# StorageClass
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: nfs.csi.k8s.io
parameters:
  server: 172.31.11.20
  share: /srv/nfs/kubedata
EOF

# Test
kubectl get storageclass
kubectl get pvc
kubectl get pods -A
```

### Architecture Recap

```
┌─────────────────────────────────────────────────────────────┐
│                      AWS VPC (us-east-2)                    │
│                                                             │
│  ┌────────────────────────┐    ┌────────────────────────┐  │
│  │   Control Plane Node   │    │     NFS Server         │  │
│  │                        │    │                        │  │
│  │  - RKE2 v1.35.7        │    │  - NFS Server          │  │
│  │  - Kubernetes API      │    │  - Export: /srv/nfs    │  │
│  │  - NFS CSI Driver      │◄───┤                        │  │
│  │  - StorageClass: nfs   │    │                        │  │
│  │                        │    │                        │  │
│  │  Pods:                 │    │                        │  │
│  │  - nginx (test pod 1)  │    │                        │  │
│  │  - nginx (test pod 2)  │    │                        │  │
│  │                        │    │                        │  │
│  │  PVC: nfs-test-pvc     │    │  Data:                 │  │
│  │  - Status: Bound       │    │  /srv/nfs/kubedata/    │  │
│  │  - Mode: RWX           │    │    └─ pvc-xxx/         │  │
│  │  - Size: 1Gi           │    │       └─ index.html    │  │
│  └────────────────────────┘    └────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Benefits Achieved

| Benefit | Implementation |
|---------|---------------|
| **Shared Storage** | NFS with RWX |
| **Dynamic Provisioning** | CSI driver + StorageClass |
| **Multi-pod Access** | ReadWriteMany verified |
| **Simple Setup** | NFS easier than Longhorn |
| **Resource Efficient** | No storage overhead on cluster |
| **Easy Backup** | Direct access from NFS server |

---

## Next Steps

1. **Deploy real application** using NFS storage
2. **Add worker nodes** to the cluster
3. **Configure ingress** (NGINX/Traefik) for external access
4. **Set up monitoring** (Prometheus/Grafana)
5. **Implement backup strategy** for NFS data
6. **Security hardening** (network policies, RBAC)

---

## Lab Information

- **Date:** August 26, 2026
- **Duration:** ~1-2 hours
- **Environment:** AWS EC2 (2 instances)
- **RKE2 Version:** v1.35.7+rke2r1
- **Kubernetes Version:** v1.35.7
- **Storage:** NFS (centralized, RWX capable)
- **CSI Driver:** nfs.csi.k8s.io
- **Status:** ✅ Complete

---

## References

- [RKE2 Documentation](https://docs.rke2.io/)
- [NFS CSI Driver](https://github.com/kubernetes-csi/csi-driver-nfs)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [NFS Server Setup (Ubuntu)](https://ubuntu.com/server/docs/service-nfs)

---

**End of Complete Lab Guide** 🎉
