#!/bin/bash
#
# RKE2 Server Installation Script
# This script installs RKE2 on Amazon Linux 2023 (or compatible systems)
#
# Usage:
#   chmod +x install-rke2-server.sh
#   sudo ./install-rke2-server.sh
#
# Prerequisites:
#   - Amazon Linux 2023 or compatible Linux distribution
#   - Root or sudo access
#   - Internet connectivity
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root. Use: sudo $0"
fi

log "Starting RKE2 server installation..."

# ============================================
# Step 1: Update System
# ============================================
log "Step 1: Updating system packages..."
if command -v dnf &> /dev/null; then
    dnf update -y
elif command -v yum &> /dev/null; then
    yum update -y
else
    warn "Neither dnf nor yum found. Skipping system update."
fi

# ============================================
# Step 2: Install Required Packages
# ============================================
log "Step 2: Installing required packages..."
PACKAGES="curl wget git conntrack socat nfs-utils iptables"

if command -v dnf &> /dev/null; then
    dnf install -y $PACKAGES
elif command -v yum &> /dev/null; then
    yum install -y $PACKAGES
fi

# ============================================
# Step 3: Configure Kernel Modules
# ============================================
log "Step 3: Configuring kernel modules..."

# Load modules
modprobe overlay || warn "Could not load overlay module"
modprobe br_netfilter || warn "Could not load br_netfilter module"

# Persist modules
cat <<EOF > /etc/modules-load.d/rke2.conf
overlay
br_netfilter
EOF

# ============================================
# Step 4: Configure Sysctl
# ============================================
log "Step 4: Configuring sysctl settings..."

cat <<EOF > /etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system > /dev/null

# ============================================
# Step 5: Disable Swap
# ============================================
log "Step 5: Disabling swap..."
swapoff -a

# Remove swap from fstab
sed -i '/swap/d' /etc/fstab 2>/dev/null || warn "Could not modify fstab"

# ============================================
# Step 6: Get Instance Metadata (AWS)
# ============================================
log "Step 6: Getting instance metadata..."

# Try to get AWS metadata
PUBLIC_IP=""
PUBLIC_HOSTNAME=""
PRIVATE_IP=""

# Check if we're on AWS
if curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/ > /dev/null 2>&1; then
    log "Detected AWS environment..."
    
    # Get token for IMDSv2
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")
    
    if [[ -n "$TOKEN" ]]; then
        # Use IMDSv2
        PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || hostname -I | awk '{print $1}')
        PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
        PUBLIC_HOSTNAME=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-hostname 2>/dev/null || echo "")
    else
        # Fallback to IMDSv1
        PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || hostname -I | awk '{print $1}')
        PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
        PUBLIC_HOSTNAME=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname 2>/dev/null || echo "")
    fi
fi

# Fallback if not on AWS or metadata unavailable
if [[ -z "$PRIVATE_IP" ]]; then
    PRIVATE_IP=$(hostname -I | awk '{print $1}')
fi

log "Private IP: $PRIVATE_IP"
[[ -n "$PUBLIC_IP" ]] && log "Public IP: $PUBLIC_IP"
[[ -n "$PUBLIC_HOSTNAME" ]] && log "Public Hostname: $PUBLIC_HOSTNAME"

# ============================================
# Step 7: Install RKE2
# ============================================
log "Step 7: Installing RKE2..."
log "This may take a few minutes..."

curl -sfL https://get.rke2.io | sh -

# ============================================
# Step 8: Configure RKE2
# ============================================
log "Step 8: Configuring RKE2..."

mkdir -p /etc/rancher/rke2

# Build TLS SANs list
TLS_SANS="node-ip: \"${PRIVATE_IP}\"\n"
TLS_SANS+="tls-san:\n"
TLS_SANS+="  - \"${PRIVATE_IP}\"\n"

if [[ -n "$PUBLIC_IP" ]]; then
    TLS_SANS+="  - \"${PUBLIC_IP}\"\n"
fi

if [[ -n "$PUBLIC_HOSTNAME" ]]; then
    TLS_SANS+="  - \"${PUBLIC_HOSTNAME}\"\n"
fi

# Create config file
cat <<EOF > /etc/rancher/rke2/config.yaml
# RKE2 Server Configuration
# Generated by install-rke2-server.sh

# Node configuration
node-name: "$(hostname)"
node-ip: "${PRIVATE_IP}"

# TLS SANs for API server
tls-san:
  - "${PRIVATE_IP}"
$(if [[ -n "$PUBLIC_IP" ]]; then echo "  - \"${PUBLIC_IP}\""; fi)
$(if [[ -n "$PUBLIC_HOSTNAME" ]]; then echo "  - \"${PUBLIC_HOSTNAME}\""; fi)

# Kubeconfig permissions (lab convenience - restrict in production!)
write-kubeconfig-mode: "0644"

# Cluster networking
cluster-cidr: "10.42.0.0/16"
service-cidr: "10.43.0.0/16"
cluster-dns: "10.43.0.10"

# Disable components (uncomment if needed)
# ingress-controller: []
EOF

log "Configuration file created at /etc/rancher/rke2/config.yaml"

# ============================================
# Step 9: Enable and Start RKE2
# ============================================
log "Step 9: Enabling RKE2 service..."
systemctl enable rke2-server.service

log "Starting RKE2 service..."
systemctl start rke2-server.service

# ============================================
# Step 10: Wait for RKE2 to be Ready
# ============================================
log "Step 10: Waiting for RKE2 to be ready..."
log "This may take 2-5 minutes..."

# Set up environment for kubectl
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# Wait for kubeconfig to exist
for i in {1..60}; do
    if [[ -f /etc/rancher/rke2/rke2.yaml ]]; then
        break
    fi
    sleep 5
done

# Wait for API server to be ready
for i in {1..60}; do
    if kubectl get nodes > /dev/null 2>&1; then
        break
    fi
    sleep 5
done

# Wait for node to be ready
NODE_NAME=$(hostname)
for i in {1..60}; do
    NODE_STATUS=$(kubectl get node $NODE_NAME -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [[ "$NODE_STATUS" == "True" ]]; then
        log "Node $NODE_NAME is Ready!"
        break
    fi
    sleep 5
done

# ============================================
# Step 11: Configure User Environment
# ============================================
log "Step 11: Configuring user environment..."

# Add to ec2-user profile if it exists
if id "ec2-user" &>/dev/null; then
    USER_HOME="/home/ec2-user"
elif id "ubuntu" &>/dev/null; then
    USER_HOME="/home/ubuntu"
else
    USER_HOME="$HOME"
fi

# Add to bashrc
cat <<EOF >> ${USER_HOME}/.bashrc

# RKE2 configuration
export PATH=\$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
EOF

chown $(stat -c '%U:%G' ${USER_HOME}) ${USER_HOME}/.bashrc 2>/dev/null || true

log "Added RKE2 environment to ${USER_HOME}/.bashrc"

# ============================================
# Step 12: Display Summary
# ============================================
echo ""
echo "=========================================="
log "RKE2 Installation Complete!"
echo "=========================================="
echo ""
echo "Node Name:       $(hostname)"
echo "Private IP:      ${PRIVATE_IP}"
echo "Public IP:       ${PUBLIC_IP:-N/A}"
echo "Public Hostname: ${PUBLIC_HOSTNAME:-N/A}"
echo ""
echo "Kubernetes Version: $(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}')"
echo "RKE2 Version:       $(rke2 --version | head -1)"
echo ""
echo "Important Files:"
echo "  Config:     /etc/rancher/rke2/config.yaml"
echo "  Kubeconfig: /etc/rancher/rke2/rke2.yaml"
echo "  Node Token: /var/lib/rancher/rke2/server/node-token"
echo ""
echo "To use kubectl:"
echo "  export PATH=\$PATH:/var/lib/rancher/rke2/bin"
echo "  export KUBECONFIG=/etc/rancher/rke2/rke2.yaml"
echo ""
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo ""
echo "To view logs:"
echo "  journalctl -u rke2-server -f"
echo ""
echo "Node Token (for joining additional nodes):"
echo "  $(cat /var/lib/rancher/rke2/server/node-token 2>/dev/null || echo 'Run: sudo cat /var/lib/rancher/rke2/server/node-token')"
echo ""
echo "To join worker nodes:"
echo "  curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=\"agent\" sh -"
echo "  # Then configure /etc/rancher/rke2/config.yaml with:"
echo "  # server: https://${PRIVATE_IP}:9345"
echo "  # token: <NODE_TOKEN>"
echo ""
