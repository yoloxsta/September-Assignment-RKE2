# RKE2 Installation Guide

This guide covers installing RKE2 on your AWS EC2 instance. We'll set up a single-node cluster suitable for learning and development.

## Table of Contents
- [Installation Methods](#installation-methods)
- [Single Node Installation](#single-node-installation)
- [Multi-Node Setup (Optional)](#multi-node-setup-optional)
- [Configure kubectl](#configure-kubectl)
- [Verify Installation](#verify-installation)
- [Understanding RKE2 Components](#understanding-rke2-components)

---

## Installation Methods

RKE2 can be installed via:
1. **Tarball** (recommended for most cases)
2. **RPM** (for RPM-based systems like Amazon Linux, RHEL, CentOS)
3. **Install Script** (wrapper around tarball/RPM)

We'll use the **install script** method as it's the simplest for getting started.

---

## Single Node Installation

### Step 1: Install RKE2

```bash
# Run the RKE2 installer
curl -sfL https://get.rke2.io | sudo sh -

# This will:
# - Download the latest stable RKE2 version
# - Install the rke2-server binary
# - Install systemd service files
# - Take about 2-5 minutes depending on network speed
```

**For a specific version:**
```bash
# Example: Install specific version
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION=v1.34.6+rke2r3 sh -
```

### Step 2: Configure RKE2 Server

Create the RKE2 configuration file:

```bash
# Create config directory
sudo mkdir -p /etc/rancher/rke2

# Create configuration file
sudo tee /etc/rancher/rke2/config.yaml <<EOF
# Node configuration
node-name: "rke2-server-1"

# TLS SANs for API server (add your public IP)
tls-san:
  - "$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
  - "$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)"

# Enable writing kubeconfig with world-readable permissions (for lab only!)
write-kubeconfig-mode: "0644"

# Disable default ingress if you want to install your own later
# ingress-controller: []

# Set cluster CIDR (default is 10.42.0.0/16)
cluster-cidr: "10.42.0.0/16"

# Set service CIDR (default is 10.43.0.0/16)
service-cidr: "10.43.0.0/16"

# Set cluster DNS IP (default is 10.43.0.10)
cluster-dns: "10.43.0.10"
EOF
```

**What this configuration does:**
- `node-name`: Sets a friendly name for your node
- `tls-san`: Adds your public IP/hostname to API server certificate (allows remote kubectl access)
- `write-kubeconfig-mode`: Makes kubeconfig readable (convenience for lab)
- `cluster-cidr`: IP range for pods
- `service-cidr`: IP range for services

### Step 3: Enable and Start RKE2

```bash
# Enable RKE2 server service to start on boot
sudo systemctl enable rke2-server.service

# Start RKE2 server
sudo systemctl start rke2-server.service

# Watch the logs (press Ctrl+C to exit after you see "Started RKE2 Server")
sudo journalctl -u rke2-server -f
```

**Expected startup sequence:**
```
Aug 24 20:00:00 rke2-server-1 rke2[12345]: INFO  [etcd] single-node cluster, skipping health check
Aug 24 20:00:05 rke2-server-1 rke2[12345]: INFO  [kubelet] kubelet is running
Aug 24 20:00:15 rke2-server-1 rke2[12345]: INFO  [kube-apiserver] kube-apiserver is running
Aug 24 20:00:20 rke2-server-1 rke2[12345]: INFO  [kube-controller-manager] kube-controller-manager is running
Aug 24 20:00:25 rke2-server-1 rke2[12345]: INFO  [kube-scheduler] kube-scheduler is running
Aug 24 20:01:00 rke2-server-1 systemd[1]: Started RKE2 Server.
```

**Startup takes approximately 1-3 minutes.** Wait until you see "Started RKE2 Server" before proceeding.

### Step 4: Wait for Node Ready

```bash
# Set up kubectl (see next section for details)
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# Wait for node to be ready (this may take 1-2 minutes)
kubectl wait --for=condition=Ready node/rke2-server-1 --timeout=300s
```

### Step 5: Verify Core Components

```bash
# Check node status
kubectl get nodes

# Check system pods
kubectl get pods -A

# Check system services
kubectl get svc -A
```

**Expected output:**
```
NAME            STATUS   ROLES                       AGE   VERSION
rke2-server-1   Ready    control-plane,etcd,master   2m    v1.34.6+rke2r3

NAMESPACE     NAME                                      READY   STATUS      RESTARTS   AGE
kube-system   etcd-rke2-server-1                        1/1     Running     0          2m
kube-system   helm-install-rke2-canal-r8n9l             0/1     Completed   0          2m
kube-system   helm-install-rke2-coredns-8bmhb           0/1     Completed   0          2m
kube-system   helm-install-rke2-metrics-server-9xhkb    0/1     Completed   0          2m
kube-system   helm-install-rke2-traefik-crd-mx2xq       0/1     Completed   0          2m
kube-system   helm-install-rke2-traefik-x7j2f           0/1     Completed   0          2m
kube-system   kube-apiserver-rke2-server-1              1/1     Running     0          2m
kube-system   kube-controller-manager-rke2-server-1    1/1     Running     0          2m
kube-system   kube-proxy-rke2-server-1                  1/1     Running     0          2m
kube-system   kube-scheduler-rke2-server-1              1/1     Running     0          2m
kube-system   rke2-canal-gzfcl                          2/2     Running     0          2m
kube-system   rke2-coredns-rke2-coredns-7f9f8d4b6-abc12 1/1     Running     0          2m
kube-system   rke2-metrics-server-7f9f8d4b6-xyz34      1/1     Running     0          2m
kube-system   svclb-traefik-3f4d5f                      2/2     Running     0          2m
kube-system   traefik-6b9f7f8d4b-xyz12                  1/1     Running     0          2m
```

---

## Configure kubectl

You have two options for managing your cluster:

### Option A: Use kubectl on the EC2 instance (recommended for lab)

```bash
# Add RKE2 binaries to PATH
echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> ~/.bashrc

# Set KUBECONFIG
echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' >> ~/.bashrc

# Reload shell
source ~/.bashrc

# Verify
kubectl version
kubectl cluster-info
```

### Option B: Use kubectl from your local machine

This allows you to manage the cluster from your laptop without SSH-ing into the instance.

#### Step 1: Copy kubeconfig to local machine

On your **local machine**:

```bash
# SSH into instance and display kubeconfig
ssh -i rke2-lab-key.pem ec2-user@<PUBLIC_IP> "sudo cat /etc/rancher/rke2/rke2.yaml"
```

Copy the output and save it locally:

```bash
# Create kubeconfig directory if it doesn't exist
mkdir -p ~/.kube

# Create/edit the config file
nano ~/.kube/rke2-lab-config
```

Paste the kubeconfig content and modify the server line:

```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: <BASE64_DATA>
    server: https://<PUBLIC_IP>:6443  # Change 127.0.0.1 to your EC2 public IP
  name: default
contexts:
- context:
    cluster: default
    user: default
  name: default
current-context: default
kind: Config
preferences: {}
users:
- name: default
  user:
    client-certificate-data: <BASE64_DATA>
    client-key-data: <BASE64_DATA>
```

#### Step 2: Use the kubeconfig

```bash
# Set KUBECONFIG environment variable
export KUBECONFIG=~/.kube/rke2-lab-config

# Or merge with existing config
export KUBECONFIG=~/.kube/config:~/.kube/rke2-lab-config
kubectl config use-context default

# Test connection
kubectl get nodes
```

**Note**: Ensure your security group allows access to port 6443 from your local IP.

---

## Multi-Node Setup (Optional)

For a production-like setup with multiple nodes, you'll need:
- 1 or 3 control plane nodes (odd number for etcd quorum)
- 1 or more worker nodes

### Step 1: Get Server Token

On your first server node:

```bash
# Get the node token
sudo cat /var/lib/rancher/rke2/server/node-token
```

Output will look like:
```
K10abcdef1234567890::server:abcdefghij1234567890
```

Save this token - you'll need it for all additional nodes.

### Step 2: Launch Additional EC2 Instances

Launch additional EC2 instances following the same steps as before (same AMI, security group, etc.)

### Step 3: Install RKE2 Agent on Worker Nodes

On each worker node:

```bash
# Install RKE2 agent
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sh -

# Create config
sudo mkdir -p /etc/rancher/rke2
sudo tee /etc/rancher/rke2/config.yaml <<EOF
server: https://<SERVER_PUBLIC_IP>:9345
token: <NODE_TOKEN>
node-name: "rke2-worker-1"
EOF

# Enable and start agent
sudo systemctl enable rke2-agent.service
sudo systemctl start rke2-agent.service

# Watch logs
sudo journalctl -u rke2-agent -f
```

### Step 4: Add Additional Server Nodes (for HA)

On additional server nodes:

```bash
# Install RKE2 server
curl -sfL https://get.rke2.io | sh -

# Create config
sudo mkdir -p /etc/rancher/rke2
sudo tee /etc/rancher/rke2/config.yaml <<EOF
server: https://<FIRST_SERVER_PUBLIC_IP>:9345
token: <NODE_TOKEN>
node-name: "rke2-server-2"
tls-san:
  - "$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
write-kubeconfig-mode: "0644"
EOF

# Enable and start
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service
```

### Step 5: Verify Cluster

On any server node:

```bash
# List all nodes
kubectl get nodes

# Should show all servers and workers
NAME            STATUS   ROLES                       AGE   VERSION
rke2-server-1   Ready    control-plane,etcd,master   10m   v1.34.6+rke2r3
rke2-server-2   Ready    control-plane,etcd,master   5m    v1.34.6+rke2r3
rke2-worker-1   Ready    <none>                      3m    v1.34.6+rke2r3
```

---

## Verify Installation

### Check Cluster Health

```bash
# Cluster info
kubectl cluster-info

# Node status
kubectl get nodes -o wide

# System pods
kubectl get pods -A -o wide

# Check etcd health
kubectl get endpoints -n kube-system kube-controller-manager-api -o yaml

# Check component statuses
kubectl get componentstatuses
```

### Check Networking

```bash
# Verify CNI is working
kubectl get pods -n kube-system -l k8s-app=canal -o wide

# Check service CIDR
kubectl get svc -A

# Test DNS resolution
kubectl run -it --rm --restart=Never busybox --image=busybox:1.36 -- nslookup kubernetes.default
```

### Check Ingress Controller

```bash
# Traefik pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# Traefik service
kubectl get svc -n kube-system traefik

# Check Traefik ingress class
kubectl get ingressclass
```

---

## Understanding RKE2 Components

### Control Plane Components

| Component | Purpose | Location |
|-----------|---------|----------|
| kube-apiserver | Kubernetes API | Port 6443 |
| etcd | Cluster data store | Ports 2379-2380 |
| kube-scheduler | Schedules pods | Internal |
| kube-controller-manager | Controllers | Internal |
| rke2-server | Supervisor | Port 9345 |

### Networking Components

| Component | Purpose | Notes |
|-----------|---------|-------|
| Canal (CNI) | Pod networking | VXLAN on port 8472/UDP |
| CoreDNS | Cluster DNS | Service IP: 10.43.0.10 |
| Traefik | Ingress controller | HTTP/HTTPS routing |
| kube-proxy | Service routing | iptables mode |

### Default Namespaces

```bash
# List namespaces
kubectl get namespaces

NAME              STATUS   AGE
default           Active   10m
kube-node-lease   Active   10m
kube-public       Active   10m
kube-system       Active   10m
```

### Important File Locations

| File/Directory | Purpose |
|----------------|---------|
| `/etc/rancher/rke2/config.yaml` | RKE2 configuration |
| `/etc/rancher/rke2/rke2.yaml` | kubeconfig file |
| `/var/lib/rancher/rke2/` | RKE2 data directory |
| `/var/lib/rancher/rke2/server/node-token` | Node join token |
| `/var/lib/rancher/rke2/bin/` | Binary files (kubectl, crictl, etc.) |
| `/opt/cni/bin/` | CNI plugins |
| `/run/k3s/containerd/` | Containerd socket |

---

## Useful Commands

### Service Management

```bash
# Check RKE2 service status
sudo systemctl status rke2-server

# Restart RKE2
sudo systemctl restart rke2-server

# Stop RKE2
sudo systemctl stop rke2-server

# View logs
sudo journalctl -u rke2-server -f

# View recent logs
sudo journalctl -u rke2-server --since "10 minutes ago"
```

### Container Management

```bash
# List containers (using crictl)
sudo /var/lib/rancher/rke2/bin/crictl --config /run/k3s/containerd/containerd.sock ps

# List images
sudo /var/lib/rancher/rke2/bin/crictl --config /run/k3s/containerd/containerd.sock images

# View container logs
sudo /var/lib/rancher/rke2/bin/crictl --config /run/k3s/containerd/containerd.sock logs <CONTAINER_ID>
```

---

## Troubleshooting

### Node Not Ready

```bash
# Check CNI pods
kubectl get pods -n kube-system -l k8s-app=canal

# Check CNI logs
kubectl logs -n kube-system -l k8s-app=canal -c calico-node

# Check kubelet logs
sudo journalctl -u rke2-server | grep kubelet
```

### Cannot Pull Images

```bash
# Test internet connectivity
curl -I https://registry.k8s.io

# Check containerd status
sudo /var/lib/rancher/rke2/bin/crictl --config /run/k3s/containerd/containerd.sock info
```

### API Server Unreachable

```bash
# Check API server pod
kubectl get pods -n kube-system -l component=kube-apiserver

# Check API server logs
kubectl logs -n kube-system kube-apiserver-$(hostname)

# Check if port is open
sudo netstat -tulpn | grep 6443
```

### Reset RKE2 (Last Resort)

```bash
# Stop RKE2
sudo systemctl stop rke2-server

# Run uninstall script
sudo /usr/local/bin/rke2-uninstall.sh

# Clean up directories
sudo rm -rf /etc/rancher/rke2
sudo rm -rf /var/lib/rancher/rke2

# Reinstall
curl -sfL https://get.rke2.io | sudo sh -
```

---

## Next Steps

Your RKE2 cluster is now running! Continue to:
- **[03-demo-application.md](03-demo-application.md)** - Deploy your first application

---

## Additional Resources

- [RKE2 Documentation](https://docs.rke2.io/)
- [RKE2 Configuration Options](https://docs.rke2.io/install/configuration)
- [RKE2 Cluster Autoscaler on AWS](https://docs.rke2.io/cluster_autoscaler_aws)
