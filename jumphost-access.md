# Accessing RKE2 Cluster from Jumphost - Complete Guide

## Overview

This guide explains how to access your RKE2 Kubernetes cluster from a **jumphost** (another machine) that is not part of the cluster.

---

## Understanding the Problem

### What is a Jumphost?

A **jumphost** (also called bastion host) is:
- A separate machine used to access resources
- Not part of the Kubernetes cluster
- Could be your laptop, a server, or any machine with kubectl installed

### Why Can't We Just Copy the kubeconfig?

**The problem:**

When you install RKE2, the kubeconfig file contains the **internal IP address** (private IP) or `localhost`:

```yaml
# Inside the kubeconfig file
clusters:
- cluster:
    server: https://172.31.14.91:6443  # ❌ Internal IP
    # or
    server: https://localhost:6443      # ❌ Localhost
    # or
    server: https://127.0.0.1:6443      # ❌ Loopback
```

**Why this is a problem:**

1. **Internal IP (172.31.14.91)** - Only accessible from inside the AWS VPC
   - Your jumphost is outside the VPC
   - Cannot connect to this IP address

2. **localhost / 127.0.0.1** - Means "this machine"
   - On the control plane, it points to the control plane itself ✅
   - On your jumphost, it points to the jumphost itself ❌

**Solution:**

We need to replace these internal addresses with the **public IP address** (3.128.170.22) that is accessible from anywhere on the internet.

---

## Architecture Visualization

### Current Setup

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Cloud                             │
│                                                             │
│  ┌──────────────────────────┐                              │
│  │   Control Plane Node     │                              │
│  │                          │                              │
│  │  Public IP: 3.128.170.22 │◄──── ?? How to access ??     │
│  │  Private IP: 172.31.14.91│                              │
│  │                          │                              │
│  │  kubeconfig has:         │                              │
│  │  server: https://172.31.14.91:6443  ❌ Not accessible  │
│  │  server: https://localhost:6443     ❌ Wrong machine   │
│  └──────────────────────────┘                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘

┌──────────────────────────┐
│   Your Jumphost/Laptop   │
│                          │
│  - Outside AWS VPC       │
│  - Cannot reach private IP │
│  - Cannot use "localhost" │
│  - Needs public IP       │
│                          │
│  ✅ Can reach: 3.128.170.22:6443                          │
└──────────────────────────┘
```

### After Modification

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Cloud                             │
│                                                             │
│  ┌──────────────────────────┐                              │
│  │   Control Plane Node     │                              │
│  │                          │                              │
│  │  Public IP: 3.128.170.22 │◄──── ✅ Accessible!          │
│  │  Private IP: 172.31.14.91│       │                      │
│  │                          │       │                      │
│  │  Kubernetes API Server   │       │                      │
│  │  Listening on port 6443  │◄──────┘                      │
│  └──────────────────────────┘                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                          ▲
                          │ HTTPS (kubectl)
                          │
┌──────────────────────────┐
│   Your Jumphost/Laptop   │
│                          │
│  kubeconfig has:         │
│  server: https://3.128.170.22:6443  ✅ Works!             │
│                          │
│  kubectl get nodes ──────┘                                 │
└──────────────────────────┘
```

---

## Step-by-Step Solution

### Prerequisites

1. **kubectl installed on jumphost**
   ```bash
   # Ubuntu/Debian
   sudo apt update
   sudo apt install -y kubectl
   
   # Or download directly
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   chmod +x kubectl
   sudo mv kubectl /usr/local/bin/
   ```

2. **AWS Security Group allows port 6443**
   
   The Kubernetes API server listens on port 6443. You must open this port.

---

### Step 1: Get kubeconfig from Control Plane

**Option A: From the control plane node itself**

```bash
# SSH to control plane
ssh -i your-key.pem ubuntu@3.128.170.22

# Display kubeconfig content
cat ~/.kube/config
```

**Option B: Using SCP to copy directly**

```bash
# From your jumphost, copy the kubeconfig
scp -i your-key.pem ubuntu@3.128.170.22:/etc/rancher/rke2/rke2.yaml ./rke2-kubeconfig
```

**What this command does:**
- `scp` - Secure copy (copy files over SSH)
- `-i your-key.pem` - Use your SSH private key for authentication
- `ubuntu@3.128.170.22` - User and hostname of control plane
- `/etc/rancher/rke2/rke2.yaml` - Remote file location (source)
- `./rke2-kubeconfig` - Local file location (destination)

**Expected content of the file:**

```yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTi...
    server: https://172.31.14.91:6443  # ← This is the problem!
  name: default
contexts:
- context:
    cluster: default
    user: default
  name: default
current-context: default
users:
- name: default
  user:
    client-certificate-data: LS0tLS1CRUdJTi...
    client-key-data: LS0tLS1CRUdJTi...
```

**The problem line:**
```yaml
server: https://172.31.14.91:6443  # ❌ Private IP
```

This IP address `172.31.14.91` is only accessible from within the AWS VPC. Your jumphost cannot reach it.

---

### Step 2: Understand What Needs to Change

**Kubeconfig file structure:**

```yaml
apiVersion: v1
kind: Config
clusters:                    # List of Kubernetes clusters
- cluster:
    certificate-authority-data: BASE64_ENCODED_CA_CERT
    server: https://<IP_OR_HOSTNAME>:6443  # ← This needs to change
  name: default
contexts:                    # List of contexts (cluster + user combinations)
- context:
    cluster: default
    user: default
  name: default
current-context: default     # Which context to use
users:                       # List of users
- name: default
  user:
    client-certificate-data: BASE64_ENCODED_CLIENT_CERT
    client-key-data: BASE64_ENCODED_CLIENT_KEY
```

**What each part means:**

| Field | Purpose | Needs to Change? |
|-------|---------|------------------|
| `server` | Kubernetes API server URL | ✅ YES - Change to public IP |
| `certificate-authority-data` | CA certificate (Base64 encoded) | ❌ NO - Keep as is |
| `client-certificate-data` | Client certificate (Base64 encoded) | ❌ NO - Keep as is |
| `client-key-data` | Client private key (Base64 encoded) | ❌ NO - Keep as is |

**Only the `server` field needs to be changed.**

---

### Step 3: Modify kubeconfig for External Access

Now we need to replace the internal IP with the public IP.

#### Method 3A: Using sed Command (Recommended)

```bash
# Replace private IP with public IP
sed -i 's/172.31.14.91/3.128.170.22/g' ./rke2-kubeconfig
```

**What this command does:**

| Component | Explanation |
|-----------|-------------|
| `sed` | Stream editor - used to modify text |
| `-i` | Edit file in-place (modify the original file) |
| `'s/OLD/NEW/g'` | Substitute OLD with NEW globally (all occurrences) |
| `172.31.14.91` | The OLD value (private IP to find) |
| `3.128.170.22` | The NEW value (public IP to replace with) |
| `./rke2-kubeconfig` | The file to modify |

**Breaking down the sed syntax:**
- `s` = substitute command
- `/` = delimiter (separates pattern and replacement)
- `g` = global flag (replace all occurrences, not just the first)

**After this command, the file changes from:**
```yaml
server: https://172.31.14.91:6443  # Old
```

**To:**
```yaml
server: https://3.128.170.22:6443  # New - accessible from internet!
```

#### Method 3B: Replace All Possible Internal Addresses

Sometimes the kubeconfig might contain `localhost` or `127.0.0.1` instead of the private IP. Let's replace all of them:

```bash
# Replace private IP
sed -i 's/172.31.14.91/3.128.170.22/g' ./rke2-kubeconfig

# Replace localhost
sed -i 's/localhost/3.128.170.22/g' ./rke2-kubeconfig

# Replace loopback address
sed -i 's/127.0.0.1/3.128.170.22/g' ./rke2-kubeconfig
```

**What each command does:**

1. **Replace private IP:**
   ```bash
   sed -i 's/172.31.14.91/3.128.170.22/g' ./rke2-kubeconfig
   ```
   Changes: `https://172.31.14.91:6443` → `https://3.128.170.22:6443`

2. **Replace localhost:**
   ```bash
   sed -i 's/localhost/3.128.170.22/g' ./rke2-kubeconfig
   ```
   Changes: `https://localhost:6443` → `https://3.128.170.22:6443`

3. **Replace loopback:**
   ```bash
   sed -i 's/127.0.0.1/3.128.170.22/g' ./rke2-kubeconfig
   ```
   Changes: `https://127.0.0.1:6443` → `https://3.128.170.22:6443`

#### Method 3C: Using Text Editor (Alternative)

If you prefer a visual approach:

```bash
# Open in text editor
nano ./rke2-kubeconfig

# Or
vim ./rke2-kubeconfig
```

Then manually find and replace:
- Find: `172.31.14.91` → Replace with: `3.128.170.22`
- Find: `localhost` → Replace with: `3.128.170.22`
- Find: `127.0.0.1` → Replace with: `3.128.170.22`

Save and exit:
- nano: `Ctrl+X`, then `Y`, then `Enter`
- vim: `Esc`, then `:wq`, then `Enter`

---

### Step 4: Verify the Modified kubeconfig

**Check the changes:**

```bash
# Display the server line to verify
grep "server:" ./rke2-kubeconfig
```

**Expected output:**
```
server: https://3.128.170.22:6443
```

**If you see `https://3.128.170.22:6443` - ✅ Success!**

**If you still see `172.31.14.91` or `localhost` - ❌ Run sed again**

---

### Step 5: Configure AWS Security Group

**IMPORTANT:** You must open port 6443 or the connection will fail!

#### Using AWS Console:

1. Go to EC2 Dashboard
2. Click on Instances
3. Click on your control plane instance: `i-07dc5e39df4506f37`
4. Click "Security" tab
5. Click the security group link
6. Click "Edit inbound rules"
7. Click "Add rule"
8. Configure:
   - **Type:** Custom TCP
   - **Port range:** 6443
   - **Source:** 
     - `0.0.0.0/0` (anywhere - less secure)
     - OR `YOUR.PUBLIC.IP/32` (your IP only - more secure)
   - **Description:** Kubernetes API Server
9. Click "Save rules"

#### Using AWS CLI:

```bash
# Get security group ID
aws ec2 describe-instances --instance-ids i-07dc5e39df4506f37 \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text

# Output example: sg-0abc123def456

# Allow Kubernetes API from your IP
aws ec2 authorize-security-group-ingress \
  --group-id sg-0abc123def456 \
  --protocol tcp \
  --port 6443 \
  --cidr YOUR.PUBLIC.IP/32

# Or allow from anywhere (less secure)
aws ec2 authorize-security-group-ingress \
  --group-id sg-0abc123def456 \
  --protocol tcp \
  --port 6443 \
  --cidr 0.0.0.0/0
```

**How to find your public IP:**
```bash
curl https://ifconfig.me
```

---

### Step 6: Use kubeconfig on Jumphost

Now you can use the modified kubeconfig to access your cluster.

#### Option A: Set KUBECONFIG Environment Variable (Recommended)

```bash
# Set environment variable
export KUBECONFIG=./rke2-kubeconfig

# Now kubectl commands work normally
kubectl get nodes
kubectl get pods -A
```

**What this does:**
- Tells kubectl to use `./rke2-kubeconfig` instead of `~/.kube/config`
- Applies to current shell session only
- Must run in each new terminal or add to `~/.bashrc`

**Make it permanent:**
```bash
echo 'export KUBECONFIG=/path/to/rke2-kubeconfig' >> ~/.bashrc
source ~/.bashrc
```

#### Option B: Use --kubeconfig Flag

```bash
# Specify kubeconfig with each command
kubectl --kubeconfig=./rke2-kubeconfig get nodes
kubectl --kubeconfig=./rke2-kubeconfig get pods -A
```

**What this does:**
- Explicitly specifies which kubeconfig to use
- Good for multiple clusters
- More typing required

#### Option C: Copy to Default Location

```bash
# Create .kube directory
mkdir -p ~/.kube

# Copy kubeconfig to default location
cp ./rke2-kubeconfig ~/.kube/config

# Set permissions
chmod 600 ~/.kube/config

# Now kubectl works without any flags
kubectl get nodes
```

**What this does:**
- `kubectl` looks for `~/.kube/config` by default
- No need to set `KUBECONFIG` or use `--kubeconfig`
- Simplest for single-cluster access

---

### Step 7: Test the Connection

```bash
# Test basic connectivity
kubectl get nodes
```

**Expected output:**
```
NAME                   STATUS   ROLES                AGE   VERSION
rke2-control-plane-1   Ready    control-plane,etcd   1h    v1.35.7+rke2r1
```

**If you see this - ✅ SUCCESS! You can access the cluster from your jumphost!**

**If you get an error:**

```bash
# Test connectivity to API server
curl -k https://3.128.170.22:6443/version
```

**Expected response:**
```json
{
  "major": "1",
  "minor": "35",
  "gitVersion": "v1.35.7+rke2r1",
  ...
}
```

---

## Troubleshooting Common Issues

### Issue 1: Connection Refused

**Error:**
```
The connection to the server 3.128.170.22:6443 was refused - did you specify the right host or port?
```

**Causes:**
1. Port 6443 not open in security group
2. RKE2 server not running
3. Wrong IP address

**Solutions:**

```bash
# 1. Check security group (AWS Console or CLI)
aws ec2 describe-security-groups --group-ids sg-xxxxx

# 2. Check if RKE2 is running (SSH to control plane)
ssh -i your-key.pem ubuntu@3.128.170.22
sudo systemctl status rke2-server

# 3. Verify the IP is correct
curl -k https://3.128.170.22:6443/version
```

### Issue 2: Unable to connect to the server: x509: certificate signed by unknown authority

**Error:**
```
Unable to connect to the server: x509: certificate signed by unknown authority
```

**Cause:**
- The Kubernetes API server certificate doesn't include the public IP
- Certificate is valid for internal IP or localhost only

**Solution: Add public IP to certificate SANs**

You need to add the public IP to the `tls-san` configuration when setting up RKE2:

```bash
# On control plane, edit config
sudo tee /etc/rancher/rke2/config.yaml <<EOF
token: your-token-here
tls-san:
  - 3.128.170.22      # ← Public IP must be here
  - 172.31.14.91      # Private IP
  - rke2-control-plane-1
  - localhost
node-name: rke2-control-plane-1
EOF

# Restart RKE2 to regenerate certificates
sudo systemctl restart rke2-server

# Wait for RKE2 to start (2-3 minutes)
sudo systemctl status rke2-server

# Get new kubeconfig
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
```

**Why this works:**
- `tls-san` adds Subject Alternative Names to the API server certificate
- These are the IPs/DNS names the certificate is valid for
- Without the public IP, certificate validation fails

### Issue 3: Unable to connect to the server: dial tcp 3.128.170.22:6443: i/o timeout

**Error:**
```
Unable to connect to the server: dial tcp 3.128.170.22:6443: i/o timeout
```

**Causes:**
1. Security group blocks port 6443
2. Firewall on the instance
3. Network connectivity issue

**Solutions:**

```bash
# 1. Test if port is open
nc -zv 3.128.170.22 6443

# Expected: Connection to 3.128.170.22 6443 port [tcp/*] succeeded!
# If timeout: Port is blocked

# 2. Check security group rules
aws ec2 describe-security-groups --group-ids sg-xxxxx \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`6443`]'

# 3. Add rule if missing
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 6443 \
  --cidr 0.0.0.0/0
```

### Issue 4: You must be logged in to the server (Unauthorized)

**Error:**
```
error: You must be logged in to the server (Unauthorized)
```

**Causes:**
1. Kubeconfig corrupted or incomplete
2. Client certificates expired
3. Wrong kubeconfig file

**Solutions:**

```bash
# 1. Verify kubeconfig has certificates
kubectl config view --kubeconfig=./rke2-kubeconfig

# Check for these fields:
# - certificate-authority-data
# - client-certificate-data
# - client-key-data

# 2. Get fresh kubeconfig from control plane
ssh -i your-key.pem ubuntu@3.128.170.22
sudo cat /etc/rancher/rke2/rke2.yaml

# 3. Copy fresh kubeconfig
scp -i your-key.pem ubuntu@3.128.170.22:/etc/rancher/rke2/rke2.yaml ./rke2-kubeconfig
```

---

## All Methods to Access RKE2 Cluster

There are **4 main methods** to access your RKE2 cluster from a jumphost. Each has different use cases, security levels, and setup requirements.

---

## Method 1: Direct Access with Public IP (Easiest)

### Overview

**How it works:**
- Modify kubeconfig to use public IP
- Open port 6443 to the internet
- Direct connection from jumphost to API server

**Architecture:**
```
Jumphost ──(HTTPS/6443)──► Control Plane Public IP
                                    │
                                    ▼
                            Kubernetes API
```

### When to Use

✅ Development and testing
✅ Learning environments
✅ Quick setup needed
✅ Don't have VPN

❌ Production environments
❌ High security requirements

### Security Level

⚠️ **Medium Risk**
- API server exposed to internet
- Must restrict access by IP
- Uses Kubernetes authentication

### Step-by-Step Setup

#### Step 1: Get kubeconfig from Control Plane

```bash
# Option A: SSH and display
ssh -i your-key.pem ubuntu@3.128.170.22
cat ~/.kube/config
# Copy the entire output

# Option B: Use SCP to copy
scp -i your-key.pem ubuntu@3.128.170.22:/etc/rancher/rke2/rke2.yaml ./rke2-kubeconfig
```

#### Step 2: Modify kubeconfig

```bash
# Replace internal IPs with public IP
sed -i 's/172.31.14.91/3.128.170.22/g' ./rke2-kubeconfig
sed -i 's/localhost/3.128.170.22/g' ./rke2-kubeconfig
sed -i 's/127.0.0.1/3.128.170.22/g' ./rke2-kubeconfig

# Verify changes
grep "server:" ./rke2-kubeconfig
# Should show: server: https://3.128.170.22:6443
```

#### Step 3: Open Security Group

```bash
# Get your public IP
curl https://ifconfig.me

# Open port 6443 for your IP only
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 6443 \
  --cidr YOUR.PUBLIC.IP/32

# Or open to anywhere (less secure)
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 6443 \
  --cidr 0.0.0.0/0
```

#### Step 4: Use kubeconfig

```bash
# Set KUBECONFIG
export KUBECONFIG=./rke2-kubeconfig

# Test
kubectl get nodes
```

### Pros and Cons

| Pros | Cons |
|------|------|
| ✅ Simple setup | ⚠️ API exposed to internet |
| ✅ No SSH tunnel needed | ⚠️ Must manage IP whitelist |
| ✅ Fast connection | ⚠️ Certificate must include public IP |
| ✅ Works from anywhere | ⚠️ Security group dependency |

### Troubleshooting

**Issue: Certificate error**
```
x509: certificate signed by unknown authority
```

**Solution:** Add public IP to `tls-san` in RKE2 config:
```bash
# On control plane
sudo tee /etc/rancher/rke2/config.yaml <<EOF
token: your-token-here
tls-san:
  - 3.128.170.22      # ← Add public IP
  - 172.31.14.91
  - localhost
EOF

# Restart RKE2
sudo systemctl restart rke2-server
```

---

## Method 2: SSH Tunnel (Most Secure)

### Overview

**How it works:**
- Create SSH tunnel from jumphost to control plane
- Forward local port 6443 to remote port 6443
- Access API through localhost

**Architecture:**
```
Jumphost
   │
   ├─ SSH Tunnel (encrypted)
   │     │
   │     └──► Control Plane:22 (SSH)
   │              │
   │              └──► localhost:6443 (API)
   │
   └─ kubectl → localhost:6443 → (tunnel) → API Server
```

### When to Use

✅ Production environments
✅ High security requirements
✅ Don't want to expose API to internet
✅ Have SSH access only

❌ Need multiple simultaneous users
❌ Cannot keep SSH connection open

### Security Level

✅ **High Security**
- No ports exposed to internet
- All traffic encrypted via SSH
- Uses SSH key authentication
- No certificate modifications needed

### Step-by-Step Setup

#### Step 1: Create SSH Tunnel

```bash
# On jumphost, create tunnel
ssh -i your-key.pem -L 6443:localhost:6443 ubuntu@3.128.170.22 -N -f
```

**Command breakdown:**

| Flag | Meaning | Purpose |
|------|---------|---------|
| `-i your-key.pem` | Identity file | Use SSH key for authentication |
| `-L 6443:localhost:6443` | Local forward | Forward local port 6443 to remote's localhost:6443 |
| `ubuntu@3.128.170.22` | Remote server | SSH to control plane |
| `-N` | No command | Don't execute remote command (just forward) |
| `-f` | Fork | Run in background |

**How port forwarding works:**

```
Local (Jumphost)           Remote (Control Plane)
─────────────────────────────────────────────────
Port 6443  ─────(SSH Tunnel)────►  localhost:6443
   │                                    │
   └─ kubectl connects here             └─ API server listens here
```

**What happens:**
1. SSH connects to control plane (port 22)
2. SSH listens on jumphost's port 6443
3. Traffic to localhost:6443 on jumphost goes through SSH tunnel
4. SSH forwards to localhost:6443 on control plane
5. API server receives the request

#### Step 2: Verify Tunnel is Running

```bash
# Check if tunnel is active
ps aux | grep "ssh.*6443"

# Or check if port 6443 is listening locally
ss -tlnp | grep 6443

# Expected output:
# LISTEN  0  128  127.0.0.1:6443  0.0.0.0:*
```

#### Step 3: Get and Use kubeconfig

**Option A: Don't modify kubeconfig (uses localhost)**

```bash
# Copy kubeconfig as-is
scp -i your-key.pem ubuntu@3.128.170.22:/etc/rancher/rke2/rke2.yaml ./rke2-kubeconfig

# Check if it has localhost or private IP
grep "server:" ./rke2-kubeconfig

# If it has localhost - perfect! Use as-is
export KUBECONFIG=./rke2-kubeconfig
kubectl get nodes

# If it has private IP, change to localhost
sed -i 's/172.31.14.91/localhost/g' ./rke2-kubeconfig
sed -i 's/127.0.0.1/localhost/g' ./rke2-kubeconfig
export KUBECONFIG=./rke2-kubeconfig
kubectl get nodes
```

**Option B: Use kubectl directly through tunnel**

```bash
# Set up tunnel first
ssh -i your-key.pem -L 6443:localhost:6443 ubuntu@3.128.170.22 -N -f

# Create minimal kubeconfig pointing to localhost
cat > ./tunnel-kubeconfig <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $(ssh -i your-key.pem ubuntu@3.128.170.22 "sudo cat /etc/rancher/rke2/rke2.yaml" | grep certificate-authority-data | head -1 | awk '{print $2}')
    server: https://localhost:6443
  name: rke2-cluster
contexts:
- context:
    cluster: rke2-cluster
    user: rke2-user
  name: rke2-context
current-context: rke2-context
users:
- name: rke2-user
  user:
    client-certificate-data: $(ssh -i your-key.pem ubuntu@3.128.170.22 "sudo cat /etc/rancher/rke2/rke2.yaml" | grep client-certificate-data | head -1 | awk '{print $2}')
    client-key-data: $(ssh -i your-key.pem ubuntu@3.128.170.22 "sudo cat /etc/rancher/rke2/rke2.yaml" | grep client-key-data | head -1 | awk '{print $2}')
EOF

export KUBECONFIG=./tunnel-kubeconfig
kubectl get nodes
```

#### Step 4: Manage SSH Tunnel

**Check if tunnel is running:**
```bash
ps aux | grep "ssh.*6443"
```

**Kill tunnel:**
```bash
# Find process ID
ps aux | grep "ssh.*6443"

# Kill by PID
kill <PID>

# Or kill all SSH tunnels
pkill -f "ssh.*-L 6443"
```

**Auto-reconnect tunnel:**
```bash
# Create script to keep tunnel alive
cat > ~/keep-tunnel.sh <<'EOF'
#!/bin/bash
while true; do
    ssh -i your-key.pem -L 6443:localhost:6443 ubuntu@3.128.170.22 -N
    echo "SSH tunnel disconnected. Reconnecting in 5 seconds..."
    sleep 5
done
EOF

chmod +x ~/keep-tunnel.sh

# Run in background
nohup ~/keep-tunnel.sh > /dev/null 2>&1 &
```

**Run tunnel on boot (systemd):**
```bash
# Create systemd service
sudo tee /etc/systemd/system/k8s-tunnel.service <<EOF
[Unit]
Description=Kubernetes API SSH Tunnel
After=network.target

[Service]
Type=simple
User=ubuntu
ExecStart=/usr/bin/ssh -i /home/ubuntu/your-key.pem -L 6443:localhost:6443 ubuntu@3.128.170.22 -N
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable k8s-tunnel
sudo systemctl start k8s-tunnel
```

### Pros and Cons

| Pros | Cons |
|------|------|
| ✅ Most secure method | ⚠️ Requires active SSH connection |
| ✅ No port exposure | ⚠️ Tunnel can disconnect |
| ✅ No certificate changes | ⚠️ One user per tunnel |
| ✅ Uses existing SSH auth | ⚠️ Must manage tunnel lifecycle |
| ✅ Works with any kubeconfig | ⚠️ Slight latency overhead |

### Troubleshooting

**Issue: Address already in use**
```
bind: Address already in use
```

**Solution:** Port 6443 already has something listening
```bash
# Check what's using port 6443
sudo ss -tlnp | grep 6443

# Kill existing tunnel
pkill -f "ssh.*6443"

# Or use different local port
ssh -i your-key.pem -L 16443:localhost:6443 ubuntu@3.128.170.22 -N

# Then update kubeconfig
sed -i 's/localhost:6443/localhost:16443/g' ./rke2-kubeconfig
```

**Issue: Tunnel disconnects**
```bash
# Add keepalive options
ssh -i your-key.pem -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -L 6443:localhost:6443 ubuntu@3.128.170.22 -N
```

---

## Method 3: VPN Connection (Enterprise Standard)

### Overview

**How it works:**
- Connect jumphost to AWS VPC via VPN
- Access cluster using private IP
- No port exposure to internet

**Architecture:**
```
Internet
   │
   ▼
VPN Gateway (AWS)
   │
   ├── VPN Connection
   │      │
   │      └──► Jumphost (VPN Client)
   │              │
   │              └──► Can reach VPC private IPs
   │
   └── AWS VPC
          │
          └──► Control Plane (172.31.14.91:6443)
```

### When to Use

✅ Production environments
✅ Multiple users need access
✅ Enterprise security requirements
✅ Need access to multiple AWS resources
✅ Long-term access

❌ Small teams (overkill)
❌ Temporary access
❌ No VPN infrastructure

### Security Level

✅ **Highest Security**
- Enterprise-grade encryption
- Network-level access control
- Private IP access only
- Multi-factor authentication possible
- Centralized audit logging

### AWS VPN Options

#### Option A: AWS Site-to-Site VPN

**Use case:** Connect entire office network to AWS VPC

**Setup:**
1. Create Virtual Private Gateway in AWS
2. Create Customer Gateway (your office router)
3. Create VPN connection
4. Configure your router
5. Access VPC resources using private IPs

#### Option B: AWS Client VPN

**Use case:** Individual users connect to AWS VPC

**Setup:**

**Step 1: Create VPN Endpoint**
```bash
# Create VPN endpoint
aws ec2 create-client-vpn-endpoint \
  --client-cidr-block 10.0.0.0/16 \
  --server-certificate-arn arn:aws:acm:region:account:certificate/cert-id \
  --authentication-options Type=certificate-authentication,MutualAuthentication={ClientRootCertificateChainArn=arn:aws:acm:region:account:certificate/cert-id}

# Associate with VPC
aws ec2 associate-client-vpn-target-network \
  --client-vpn-endpoint-id cvpn-endpoint-xxx \
  --subnet-id subnet-xxx

# Add security group
aws ec2 authorize-client-vpn-ingress \
  --client-vpn-endpoint-id cvpn-endpoint-xxx \
  --target-network-cidr 172.31.0.0/16 \
  --description "Allow access to VPC"
```

**Step 2: Download VPN Client**

```bash
# Download AWS VPN client
# https://aws.amazon.com/vpn/client-vpn-download/

# Or use OpenVPN client
sudo apt install -y openvpn
```

**Step 3: Connect to VPN**

```bash
# Download VPN configuration from AWS Console
# Client VPN Endpoints > Download Client Configuration

# Connect using OpenVPN
sudo openvpn --config downloaded-config.ovpn
```

**Step 4: Use private IP in kubeconfig**

```bash
# No modification needed - private IP works through VPN
scp -i your-key.pem ubuntu@172.31.14.91:/etc/rancher/rke2/rke2.yaml ./rke2-kubeconfig

# The kubeconfig already has the private IP - it works!
export KUBECONFIG=./rke2-kubeconfig
kubectl get nodes
```

#### Option C: Third-Party VPN Solutions

**WireGuard (Lightweight):**

**On Control Plane (VPN Server):**
```bash
# Install WireGuard
sudo apt install -y wireguard

# Generate keys
wg genkey | sudo tee /etc/wireguard/private.key
sudo cat /etc/wireguard/private.key | wg pubkey | sudo tee /etc/wireguard/public.key

# Create config
sudo tee /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.100.0.1/24
SaveConfig = true
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
ListenPort = 51820
PrivateKey = $(sudo cat /etc/wireguard/private.key)

[Peer]
PublicKey = JUMPHOST_PUBLIC_KEY
AllowedIPs = 10.100.0.2/32
EOF

# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# Start WireGuard
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
```

**On Jumphost (VPN Client):**
```bash
# Install WireGuard
sudo apt install -y wireguard

# Generate keys
wg genkey | sudo tee /etc/wireguard/private.key
sudo cat /etc/wireguard/private.key | wg pubkey | sudo tee /etc/wireguard/public.key

# Create config
sudo tee /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.100.0.2/24
PrivateKey = $(sudo cat /etc/wireguard/private.key)

[Peer]
PublicKey = CONTROL_PLANE_PUBLIC_KEY
Endpoint = 3.128.170.22:51820
AllowedIPs = 172.31.0.0/16, 10.100.0.0/24
PersistentKeepalive = 25
EOF

# Start WireGuard
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# Test connectivity
ping 172.31.14.91

# Use kubeconfig with private IP
kubectl get nodes
```

**Open WireGuard port in security group:**
```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol udp \
  --port 51820 \
  --cidr YOUR.PUBLIC.IP/32
```

### Pros and Cons

| Pros | Cons |
|------|------|
| ✅ Enterprise-grade security | ⚠️ Complex setup |
| ✅ Access all VPC resources | ⚠️ VPN infrastructure cost |
| ✅ Private IP access | ⚠️ Requires VPN client software |
| ✅ Multiple users supported | ⚠️ VPN connection dependency |
| ✅ Centralized management | ⚠️ Requires network knowledge |
| ✅ Audit logging | ⚠️ Maintenance overhead |

### Troubleshooting

**Issue: Cannot connect to VPN**
```bash
# Check VPN service status
sudo systemctl status wg-quick@wg0

# Check WireGuard interface
sudo wg show

# Check logs
sudo journalctl -u wg-quick@wg0 -f
```

**Issue: Can connect to VPN but can't reach cluster**
```bash
# Test basic connectivity
ping 172.31.14.91

# Check routing
ip route

# Check if VPC security group allows VPN subnet
aws ec2 describe-security-groups --group-ids sg-xxxxx
```

---

## Method 4: Service Account with Token (Automation/CI/CD)

### Overview

**How it works:**
- Create dedicated service account on cluster
- Generate long-lived token
- Create kubeconfig using token instead of certificates
- Suitable for automation and service accounts

**Architecture:**
```
CI/CD System / Automation Tool
       │
       ├── Uses Service Account Token
       │
       └──► API Server (3.128.170.22:6443)
                 │
                 └──► Validates token
                        └──► RBAC checks
                               └──► Executes request
```

### When to Use

✅ CI/CD pipelines (Jenkins, GitLab CI, GitHub Actions)
✅ Automation scripts
✅ Service-to-service authentication
✅ Limited permissions needed
✅ Multiple automated systems

❌ Human users (use certificates instead)
❌ Need cluster-admin access
❌ Short-term access

### Security Level

✅ **Good Security**
- Fine-grained RBAC permissions
- Token can be revoked
- No client certificates to manage
- Limited scope of access
- Audit trail via service account name

### Step-by-Step Setup

#### Step 1: Create Service Account

```bash
# On control plane or from any machine with kubectl access
kubectl create serviceaccount ci-deploy
```

**What this does:**
- Creates a Kubernetes service account named `ci-deploy`
- Service accounts are Kubernetes identities for non-human users
- Stored in Kubernetes API (not in kubeconfig)

#### Step 2: Create Role or ClusterRole

**Option A: ClusterRole (cluster-wide permissions)**

```bash
# Create ClusterRole with specific permissions
kubectl create clusterrole ci-deploy-role \
  --verb=get,list,watch,create,update,patch,delete \
  --resource=deployments,pods,services,configmaps,secrets,persistentvolumeclaims
```

**Option B: Role (namespace-specific permissions)**

```bash
# Create namespace
kubectl create namespace production

# Create Role in specific namespace
kubectl create role ci-deploy-role \
  --verb=get,list,watch,create,update,patch,delete \
  --resource=deployments,pods,services,configmaps,secrets \
  -n production
```

**Permission breakdown:**

| Verb | Meaning | Use Case |
|------|---------|----------|
| `get` | Read single resource | `kubectl get pod my-pod` |
| `list` | List resources | `kubectl get pods` |
| `watch` | Stream changes | `kubectl get pods -w` |
| `create` | Create resources | `kubectl apply -f deployment.yaml` |
| `update` | Update resources | `kubectl edit deployment` |
| `patch` | Patch resources | `kubectl patch deployment` |
| `delete` | Delete resources | `kubectl delete pod my-pod` |

#### Step 3: Bind Role to Service Account

**ClusterRoleBinding (cluster-wide):**
```bash
kubectl create clusterrolebinding ci-deploy-binding \
  --clusterrole=ci-deploy-role \
  --serviceaccount=default:ci-deploy
```

**RoleBinding (namespace-specific):**
```bash
kubectl create rolebinding ci-deploy-binding \
  --role=ci-deploy-role \
  --serviceaccount=default:ci-deploy \
  -n production
```

**What this does:**
- Associates the role with the service account
- Grants the permissions defined in the role to the service account

#### Step 4: Generate Token

**Kubernetes 1.24+ (recommended method):**

```bash
# Generate token with expiration
kubectl create token ci-deploy --duration=8760h
```

**What this does:**
- Creates a JWT token for the service account
- `--duration=8760h` = 1 year (adjust as needed)
- Token is signed by Kubernetes API server

**Alternative: Create long-lived Secret (Kubernetes 1.23 and earlier):**

```bash
# Create secret for service account
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ci-deploy-token
  annotations:
    kubernetes.io/service-account.name: ci-deploy
type: kubernetes.io/service-account-token
EOF

# Get the token
kubectl get secret ci-deploy-token -o jsonpath='{.data.token}' | base64 -d
```

**Important:** Save the token securely! You'll need it for the kubeconfig.

#### Step 5: Get Cluster CA Certificate

```bash
# Get CA certificate from cluster
kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > ca.crt

# Or from control plane
ssh -i your-key.pem ubuntu@3.128.170.22
sudo cat /etc/rancher/rke2/rke2.yaml | grep certificate-authority-data | awk '{print $2}' | base64 -d
```

#### Step 6: Create kubeconfig with Token

```bash
# Create kubeconfig for service account
cat > ./ci-deploy-kubeconfig <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
    server: https://3.128.170.22:6443
  name: rke2-cluster
contexts:
- context:
    cluster: rke2-cluster
    user: ci-deploy-user
  name: ci-deploy-context
current-context: ci-deploy-context
users:
- name: ci-deploy-user
  user:
    token: YOUR_TOKEN_HERE
EOF
```

**Replace `YOUR_TOKEN_HERE` with the token from Step 4:**

```bash
# Get token
TOKEN=$(kubectl create token ci-deploy --duration=8760h)

# Create kubeconfig with token
cat > ./ci-deploy-kubeconfig <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
    server: https://3.128.170.22:6443
  name: rke2-cluster
contexts:
- context:
    cluster: rke2-cluster
    user: ci-deploy-user
  name: ci-deploy-context
current-context: ci-deploy-context
users:
- name: ci-deploy-user
  user:
    token: $TOKEN
EOF
```

#### Step 7: Test Service Account Access

```bash
# Test with kubeconfig
export KUBECONFIG=./ci-deploy-kubeconfig

# List deployments (should work)
kubectl get deployments

# Try to list nodes (should fail - no permission)
kubectl get nodes
# Error: User "system:serviceaccount:default:ci-deploy" cannot list resource "nodes" in API group "" at the cluster scope
```

#### Step 8: Use in CI/CD Pipeline

**Example: GitLab CI**

```yaml
# .gitlab-ci.yml
deploy:
  stage: deploy
  image: bitnami/kubectl:latest
  script:
    - echo "$KUBECONFIG_CONTENT" > kubeconfig
    - export KUBECONFIG=kubeconfig
    - kubectl apply -f deployment.yaml
    - kubectl rollout status deployment/myapp
  variables:
    KUBECONFIG_CONTENT: |
      apiVersion: v1
      kind: Config
      clusters:
      - cluster:
          certificate-authority-data: LS0tLS1...
          server: https://3.128.170.22:6443
        name: rke2-cluster
      contexts:
      - context:
          cluster: rke2-cluster
          user: ci-deploy-user
        name: ci-deploy-context
      current-context: ci-deploy-context
      users:
      - name: ci-deploy-user
        user:
          token: eyJhbGciOiJSUzI1NiIs...
```

**Example: GitHub Actions**

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Deploy to Kubernetes
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBECONFIG }}" | base64 -d > ~/.kube/config
          kubectl apply -f deployment.yaml
          kubectl rollout status deployment/myapp
```

**Store kubeconfig as GitHub Secret:**
```bash
# Encode kubeconfig
base64 -w 0 ./ci-deploy-kubeconfig

# Add to GitHub repository secrets
# Settings > Secrets > Actions > New repository secret
# Name: KUBECONFIG
# Value: <base64 encoded content>
```

### Managing Service Account Tokens

**Check token expiration:**
```bash
# Decode JWT token to check expiration
echo "YOUR_TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq -r '.exp' | xargs -I {} date -d @{}
```

**Revoke token:**
```bash
# Delete service account (revokes all tokens)
kubectl delete serviceaccount ci-deploy

# Or delete specific secret (if created manually)
kubectl delete secret ci-deploy-token
```

**Rotate token:**
```bash
# Generate new token
kubectl create token ci-deploy --duration=8760h

# Update kubeconfig with new token
```

### Pros and Cons

| Pros | Cons |
|------|------|
| ✅ Fine-grained permissions | ⚠️ Token management required |
| ✅ Suitable for automation | ⚠️ Tokens can expire |
| ✅ No certificate management | ⚠️ Must store token securely |
| ✅ Easy to revoke access | ⚠️ Limited to service account permissions |
| ✅ Audit trail | ⚠️ Not suitable for human users |
| ✅ Multiple accounts for different systems | ⚠️ Requires RBAC knowledge |

### Troubleshooting

**Issue: Forbidden - User cannot list resource**
```
Error from server (Forbidden): deployments.apps is forbidden: User "system:serviceaccount:default:ci-deploy" cannot list resource "deployments" in API group "apps" at the cluster scope
```

**Solution:** Grant more permissions
```bash
# Add permissions to existing role
kubectl patch clusterrole ci-deploy-role --type='json' -p='[
  {
    "op": "add",
    "path": "/rules/-",
    "value": {
      "apiGroups": [""],
      "resources": ["nodes"],
      "verbs": ["get", "list"]
    }
  }
]'
```

**Issue: Token expired**
```
error: You must be logged in to the server (Unauthorized)
```

**Solution:** Generate new token
```bash
kubectl create token ci-deploy --duration=8760h
# Update kubeconfig with new token
```

---

## Method Comparison Matrix

| Feature | Method 1: Public IP | Method 2: SSH Tunnel | Method 3: VPN | Method 4: Service Account |
|---------|---------------------|----------------------|---------------|---------------------------|
| **Setup Complexity** | ✅ Simple | ⚠️ Medium | ❌ Complex | ⚠️ Medium |
| **Security Level** | ⚠️ Medium | ✅ High | ✅ Highest | ✅ Good |
| **Scalability** | ✅ Good | ❌ One user | ✅ Unlimited | ✅ Good |
| **Persistence** | ✅ Always on | ⚠️ Can disconnect | ✅ Reconnects | ✅ Until expiry |
| **Access Scope** | Cluster-wide | Cluster-wide | VPC-wide | RBAC-limited |
| **Human Users** | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No |
| **Automation** | ⚠️ Possible | ⚠️ Possible | ⚠️ Possible | ✅ Ideal |
| **Cost** | ✅ Free | ✅ Free | ⚠️ VPN cost | ✅ Free |
| **Performance** | ✅ Direct | ⚠️ SSH overhead | ⚠️ VPN overhead | ✅ Direct |
| **Best For** | Dev/Test, Learning | Secure access | Enterprise | CI/CD, Automation |

---

## Choosing the Right Method

### Decision Tree

```
START
  │
  ├─ Is this for automation/CI/CD?
  │   └─ YES → Method 4: Service Account
  │
  ├─ Do you need maximum security?
  │   └─ YES → Method 2: SSH Tunnel (simple)
  │           OR Method 3: VPN (enterprise)
  │
  ├─ Do you have VPN infrastructure?
  │   └─ YES → Method 3: VPN
  │
  ├─ Is this for temporary access?
  │   └─ YES → Method 1: Public IP
  │           OR Method 2: SSH Tunnel
  │
  ├─ Is this for learning/testing?
  │   └─ YES → Method 1: Public IP
  │
  └─ Is this for production with multiple users?
      └─ YES → Method 3: VPN
```

### Use Case Recommendations

| Use Case | Recommended Method | Why |
|----------|-------------------|-----|
| **Personal learning lab** | Method 1: Public IP | Simple, fast, no infrastructure needed |
| **Development environment** | Method 1: Public IP | Quick access, acceptable security |
| **Testing from laptop** | Method 2: SSH Tunnel | Secure, no permanent exposure |
| **Production environment** | Method 3: VPN | Enterprise security, audit trail |
| **CI/CD pipeline** | Method 4: Service Account | Automation-friendly, fine-grained permissions |
| **Multiple team members** | Method 3: VPN | Scalable, centralized management |
| **Temporary contractor** | Method 2: SSH Tunnel | Quick setup, easy to revoke |
| **GitOps deployment** | Method 4: Service Account | Limited scope, secure for automation |

---

## Summary - Complete Workflow

```
┌─────────────────────────────────────────────────────────────┐
│         Choose Your Access Method                           │
└─────────────────────────────────────────────────────────────┘

Method 1: Public IP (Easiest)
├─ Copy kubeconfig
├─ sed -i 's/private-ip/public-ip/g' kubeconfig
├─ Open port 6443 in security group
└─ kubectl get nodes ✅

Method 2: SSH Tunnel (Most Secure)
├─ ssh -L 6443:localhost:6443 user@server -N
├─ Use kubeconfig with localhost
├─ No security group changes needed
└─ kubectl get nodes ✅

Method 3: VPN (Enterprise)
├─ Set up VPN connection to AWS VPC
├─ Connect to VPN
├─ Use private IP in kubeconfig
└─ kubectl get nodes ✅

Method 4: Service Account (Automation)
├─ Create service account
├─ Create role and binding
├─ Generate token
├─ Create kubeconfig with token
└─ kubectl get deployments ✅
```

---

## Quick Command Reference

```bash
# === Method 1: Public IP ===
scp -i your-key.pem ubuntu@3.128.170.22:/etc/rancher/rke2/rke2.yaml ./kubeconfig
sed -i 's/172.31.14.91/3.128.170.22/g' ./kubeconfig
export KUBECONFIG=./kubeconfig
kubectl get nodes

# === Method 2: SSH Tunnel ===
ssh -i your-key.pem -L 6443:localhost:6443 ubuntu@3.128.170.22 -N -f
sed -i 's/172.31.14.91/localhost/g' ./kubeconfig
export KUBECONFIG=./kubeconfig
kubectl get nodes

# === Method 3: VPN ===
# Connect to VPN first
# Use private IP directly
export KUBECONFIG=./kubeconfig  # has 172.31.14.91
kubectl get nodes

# === Method 4: Service Account ===
kubectl create serviceaccount ci-deploy
kubectl create clusterrolebinding ci-deploy-binding --clusterrole=admin --serviceaccount=default:ci-deploy
TOKEN=$(kubectl create token ci-deploy --duration=8760h)
# Create kubeconfig with token
kubectl --kubeconfig=./ci-kubeconfig get deployments
```

---

## Security Best Practices

### 1. Restrict Access by IP

**Instead of:**
```bash
aws ec2 authorize-security-group-ingress --port 6443 --cidr 0.0.0.0/0
```

**Use:**
```bash
# Only allow your specific IP
aws ec2 authorize-security-group-ingress --port 6443 --cidr YOUR.IP.ADDRESS/32
```

### 2. Use VPN or SSH Tunnel

**More secure approach - don't expose API to internet:**

```bash
# Create SSH tunnel
ssh -i your-key.pem -L 6443:localhost:6443 ubuntu@3.128.170.22 -N

# Keep kubeconfig as localhost
# (don't modify server: line)
server: https://localhost:6443

# Access through tunnel
kubectl get nodes
```

### 3. Use Service Accounts for Automation

**For CI/CD or automation:**

```bash
# Create service account on cluster
kubectl create serviceaccount ci-user

# Create limited role
kubectl create role ci-role --verb=get,list,create,delete --resource=pods,deployments

# Bind role to service account
kubectl create rolebinding ci-binding --role=ci-role --serviceaccount=default:ci-user

# Generate token
kubectl create token ci-user --duration=24h

# Use token in kubeconfig
# (Instead of client certificates)
```

### 4. Rotate Certificates

Kubernetes client certificates expire after 1 year by default. To rotate:

```bash
# On control plane
sudo systemctl restart rke2-server

# Get new kubeconfig
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
```

---

## Frequently Asked Questions

### Q1: Do I need to modify the kubeconfig every time?

**A:** No. Once you modify it, save the file. You only need to:
```bash
export KUBECONFIG=./rke2-kubeconfig
```
Or copy to `~/.kube/config` for permanent use.

### Q2: What if the public IP changes?

**A:** If your control plane gets a new public IP:
1. Update the kubeconfig: `sed -i 's/OLD.IP/NEW.IP/g' ./rke2-kubeconfig`
2. Update security group to allow your IP

**Better solution:** Use an Elastic IP (static IP) in AWS.

### Q3: Can I have multiple kubeconfigs?

**A:** Yes! You can have kubeconfigs for multiple clusters:

```bash
# Option A: Use KUBECONFIG with multiple files
export KUBECONFIG=~/.kube/config-cluster1:~/.kube/config-cluster2

# Option B: Use different files
kubectl --kubeconfig=./cluster1-config get nodes
kubectl --kubeconfig=./cluster2-config get nodes

# Option C: Use contexts in one file
kubectl config get-contexts
kubectl config use-context cluster1-context
```

### Q4: Why does the certificate have private IP?

**A:** Because:
1. RKE2 generates certificates during initialization
2. It uses the node's hostname/IP at that time
3. The private IP is the node's main IP

**Fix:** Add `tls-san` to config before starting RKE2, or regenerate certificates.

---

## Quick Command Reference

```bash
# === On Control Plane ===

# Get kubeconfig
sudo cat /etc/rancher/rke2/rke2.yaml

# Check if API is accessible
curl -k https://localhost:6443/version

# === On Jumphost ===

# Copy kubeconfig
scp -i your-key.pem ubuntu@3.128.170.22:/etc/rancher/rke2/rke2.yaml ./rke2-kubeconfig

# Modify IPs (replace these with your actual IPs)
sed -i 's/172.31.14.91/3.128.170.22/g' ./rke2-kubeconfig
sed -i 's/localhost/3.128.170.22/g' ./rke2-kubeconfig
sed -i 's/127.0.0.1/3.128.170.22/g' ./rke2-kubeconfig

# Verify modification
grep "server:" ./rke2-kubeconfig

# Use kubeconfig
export KUBECONFIG=./rke2-kubeconfig
kubectl get nodes

# Test connectivity
curl -k https://3.128.170.22:6443/version

# === AWS CLI ===

# Get security group ID
aws ec2 describe-instances --instance-ids i-07dc5e39df4506f37 \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text

# Open port 6443
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 6443 \
  --cidr YOUR.PUBLIC.IP/32
```

---

## Lab Information

- **Cluster:** RKE2 v1.35.7+rke2r1
- **Control Plane Public IP:** 3.128.170.22
- **Control Plane Private IP:** 172.31.14.91
- **Kubernetes API Port:** 6443
- **Kubeconfig Location:** /etc/rancher/rke2/rke2.yaml

---

**End of Guide** 🎉
