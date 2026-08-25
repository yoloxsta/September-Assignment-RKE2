# Production Ingress Lab

## Overview

In this lab, you'll learn how to expose your applications in production **without cloud LoadBalancer**. You'll implement:

1. **HostNetwork** - Simplest option (direct port 80/443 binding)
2. **MetalLB** - Production LoadBalancer for bare metal
3. **Testing and verification** - Confirm each method works

---

## Prerequisites

- RKE2 cluster running (✅ you have this)
- Ingress controller installed (✅ you have NGINX ingress)
- Demo application deployed (✅ you have frontend app)
- SSH access to your EC2 instance

---

## Lab 1: HostNetwork Method (Simplest)

### What is HostNetwork?

HostNetwork makes the ingress controller pod use the node's network namespace directly. The pod binds to ports 80 and 443 on the node's IP address.

**Pros:**
- Simplest configuration
- No extra components needed
- Direct access on standard ports
- Good for single-node clusters

**Cons:**
- Only one pod can bind to ports 80/443 per node
- Not suitable for multi-node HA
- Less isolation

---

### Step 1: Check Current Configuration

```bash
# SSH to your EC2 instance
ssh -i your-key.pem ubuntu@13.58.33.90

# Check current ingress controller pod
kubectl get pods -n kube-system | grep ingress

# Check current service
kubectl get svc -A | grep ingress

# Check if port 80/443 are already in use
sudo ss -tlnp | grep -E ':80|:443'
```

---

### Step 2: Update Ingress Controller to Use HostNetwork

```bash
# Delete the existing NodePort service (if you created one)
kubectl delete svc ingress-nginx-controller -n kube-system --ignore-not-found=true

# Get the current deployment
kubectl get deployment -n kube-system | grep ingress

# Patch the deployment to use hostNetwork
kubectl patch deployment rke2-ingress-nginx-controller -n kube-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/hostNetwork",
    "value": true
  }
]'

# Watch the pod restart
kubectl get pods -n kube-system -l app.kubernetes.io/component=controller -w
```

Wait until you see the pod restart and become `Running`. Press `Ctrl+C` to stop watching.

---

### Step 3: Verify HostNetwork is Working

```bash
# Check that the pod is using hostNetwork
kubectl get pod -n kube-system -l app.kubernetes.io/component=controller -o yaml | grep -A2 hostNetwork

# Check that nginx is listening on ports 80 and 443
sudo ss -tlnp | grep nginx

# Expected output:
# LISTEN  0  511  0.0.0.0:80   0.0.0.0:*  users:(("nginx",pid=...))
# LISTEN  0  511  0.0.0.0:443  0.0.0.0:*  users:(("nginx",pid=...))
```

---

### Step 4: Test Direct Access on Port 80

```bash
# Test from inside the instance
curl -s http://localhost/demo/

# Test the public IP (make sure AWS security group allows port 80)
curl -s http://13.58.33.90/demo/

# Test from your local machine (outside AWS)
# Open browser: http://13.58.33.90/demo/
```

**You should see your demo app HTML!**

---

### Step 5: Check Ingress Status

```bash
# Check ingress
kubectl get ingress -n demo-app

# Describe ingress to see events
kubectl describe ingress demo-ingress -n demo-app

# Check ingress controller logs
kubectl logs -n kube-system -l app.kubernetes.io/component=controller --tail=20
```

---

### Step 6: AWS Security Group - Allow Port 80/443

**Important:** Make sure your AWS security group allows inbound traffic on ports 80 and 443.

```bash
# In AWS Console:
# 1. Go to EC2 > Security Groups
# 2. Find the security group for your instance
# 3. Add inbound rules:
#    - Port 80 (HTTP) - Source: 0.0.0.0/0
#    - Port 443 (HTTPS) - Source: 0.0.0.0/0
```

Or use AWS CLI:
```bash
# Get your security group ID
aws ec2 describe-instances --instance-ids i-04132a4f184d52ad9 --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text

# Add HTTP rule (replace sg-xxxxx with your security group ID)
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# Add HTTPS rule
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0
```

---

### Step 7: Verify from Browser

Open your browser and navigate to:
- `http://13.58.33.90/demo/`

You should see your demo application!

---

## Lab 2: MetalLB Method (Production LoadBalancer)

### What is MetalLB?

MetalLB is a load-balancer implementation for bare metal Kubernetes clusters. It provides the standard `LoadBalancer` service type without requiring a cloud provider.

**Pros:**
- Real LoadBalancer behavior
- Works with standard Kubernetes service type
- Supports multiple protocols (L2, BGP)
- Production-ready

**Cons:**
- Requires additional installation
- Needs IP address pool configuration
- More complex than HostNetwork

---

### Step 1: Prepare IP Address Pool

First, decide which IP addresses MetalLB will use. In your EC2 setup, you have:
- **Public IP:** 13.58.33.90 (this is NAT'd)
- **Private IP:** 172.31.0.169 (this is your node's actual IP)

**Important:** For AWS EC2, you can't use the public IP directly. You need to either:
1. Use private IPs from your VPC subnet (172.31.0.x)
2. Or allocate a new Elastic IP and associate it

For this lab, we'll use a range of **private IPs** that don't conflict with existing resources:

```bash
# Check your VPC subnet
ip addr show eth0

# Note your IP: 172.31.0.169
# We'll use: 172.31.0.200-172.31.0.210 (11 IPs for MetalLB)
```

---

### Step 2: Install MetalLB

```bash
# Install MetalLB using manifests
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

# Wait for MetalLB components to be ready
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s

# Verify installation
kubectl get pods -n metallb-system
```

Expected output:
```
NAME                          READY   STATUS    RESTARTS   AGE
controller-7df9b5b5f4-x8j2k   1/1     Running   0          30s
speaker-4kl2j                 1/1     Running   0          30s
```

---

### Step 3: Configure MetalLB IP Address Pool

```bash
# Create IPAddressPool
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: production-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.31.0.200-172.31.0.210
EOF

# Create L2Advertisement (Layer 2 mode)
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: layer2
  namespace: metallb-system
spec:
  ipAddressPools:
  - production-pool
EOF

# Verify configuration
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

---

### Step 4: Switch Ingress Controller to LoadBalancer Type

**Option A: Keep HostNetwork and test MetalLB separately**

```bash
# Create a test service with LoadBalancer type
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: test-lb
  namespace: default
spec:
  type: LoadBalancer
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
EOF

# Check if MetalLB assigned an IP
kubectl get svc test-lb

# Expected output:
# NAME      TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)        AGE
# test-lb   LoadBalancer   10.43.x.x      172.31.0.200    80:xxxxx/TCP   10s
```

**Option B: Switch ingress controller to LoadBalancer**

```bash
# First, undo hostNetwork
kubectl patch deployment rke2-ingress-nginx-controller -n kube-system --type='json' -p='[
  {
    "op": "remove",
    "path": "/spec/template/spec/hostNetwork"
  }
]'

# Wait for pod to restart
kubectl get pods -n kube-system -l app.kubernetes.io/component=controller -w
```

Press `Ctrl+C` after pod is running.

```bash
# Create LoadBalancer service for ingress
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: kube-system
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/component: controller
  ports:
  - name: http
    port: 80
    targetPort: 80
    protocol: TCP
  - name: https
    port: 443
    targetPort: 443
    protocol: TCP
EOF

# Check the service - MetalLB should assign an external IP
kubectl get svc ingress-nginx-controller -n kube-system

# Expected output:
# NAME                       TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)                      AGE
# ingress-nginx-controller   LoadBalancer   10.43.x.x      172.31.0.200    80:xxxxx/TCP,443:xxxxx/TCP   10s
```

---

### Step 5: Test MetalLB LoadBalancer

```bash
# Test from inside the instance using the LoadBalancer IP
curl -s http://172.31.0.200/demo/

# Check MetalLB logs
kubectl logs -n metallb-system -l app=metallb --tail=20

# Check the service details
kubectl describe svc ingress-nginx-controller -n kube-system
```

---

### Step 6: Understand MetalLB in AWS EC2 Context

**Important limitation in AWS EC2:**

The LoadBalancer IP (172.31.0.200) is a **private IP** inside your VPC. It's **not directly accessible** from the internet.

To make it accessible from outside AWS:

**Option 1: Use port forwarding**
```bash
# On your EC2 instance, forward traffic
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to-destination 172.31.0.200:80
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 443 -j DNAT --to-destination 172.31.0.200:443
```

**Option 2: Add secondary IP to the instance**
```bash
# In AWS Console, assign a secondary private IP to your instance
# Then use that IP in MetalLB pool
```

**Option 3: Use in internal applications only**
- MetalLB works great for internal services
- For external access, use HostNetwork or a reverse proxy

---

## Lab 3: Comparison Testing

### Test HostNetwork

```bash
# Switch back to HostNetwork
kubectl patch deployment rke2-ingress-nginx-controller -n kube-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/hostNetwork",
    "value": true
  }
]'

# Delete LoadBalancer service
kubectl delete svc ingress-nginx-controller -n kube-system --ignore-not-found=true

# Wait for pod restart
kubectl get pods -n kube-system -l app.kubernetes.io/component=controller -w
```

Press `Ctrl+C` after pod is running.

```bash
# Test
curl -s http://localhost/demo/
curl -s http://13.58.33.90/demo/

# Check ports
sudo ss -tlnp | grep nginx
```

---

### Test MetalLB LoadBalancer

```bash
# Undo hostNetwork
kubectl patch deployment rke2-ingress-nginx-controller -n kube-system --type='json' -p='[
  {
    "op": "remove",
    "path": "/spec/template/spec/hostNetwork"
  }
]'

# Wait for pod restart
sleep 10

# Create LoadBalancer service
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: kube-system
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/component: controller
  ports:
  - name: http
    port: 80
    targetPort: 80
  - name: https
    port: 443
    targetPort: 443
EOF

# Check external IP
kubectl get svc ingress-nginx-controller -n kube-system

# Test using LoadBalancer IP
curl -s http://172.31.0.200/demo/
```

---

## Lab 4: Create Multiple Services with MetalLB

Now let's see MetalLB's power - it automatically assigns IPs to multiple services!

```bash
# Create a second test service
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: test-lb-2
  namespace: default
spec:
  type: LoadBalancer
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
EOF

# Check services - MetalLB should assign different IPs
kubectl get svc -A | grep LoadBalancer

# Expected output:
# NAMESPACE    NAME                       TYPE           CLUSTER-IP     EXTERNAL-IP
# kube-system  ingress-nginx-controller   LoadBalancer   10.43.x.x      172.31.0.200
# default      test-lb-2                  LoadBalancer   10.43.x.x      172.31.0.201
```

**MetalLB automatically assigns the next available IP!**

---

## Lab 5: Clean Up

```bash
# Delete test services
kubectl delete svc test-lb test-lb-2 -n default --ignore-not-found=true

# Remove MetalLB (optional - keep it if you want to use it)
# kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

# Or keep MetalLB but switch back to HostNetwork for simplicity
kubectl patch deployment rke2-ingress-nginx-controller -n kube-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/hostNetwork",
    "value": true
  }
]'

kubectl delete svc ingress-nginx-controller -n kube-system --ignore-not-found=true
```

---

## Summary

### HostNetwork (Recommended for your single-node lab)

✅ **Use when:**
- Single-node cluster
- Simple setup needed
- Direct internet access required

**Configuration:**
```bash
kubectl patch deployment rke2-ingress-nginx-controller -n kube-system --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true}
]'
```

---

### MetalLB (Recommended for multi-node production)

✅ **Use when:**
- Multi-node cluster
- Need LoadBalancer-type services
- On-premise or bare metal
- Internal services need load balancing

**Configuration:**
```bash
# Install
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

# Configure IP pool
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: production-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.31.0.200-172.31.0.210
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: layer2
  namespace: metallb-system
spec:
  ipAddressPools:
  - production-pool
EOF
```

---

## Decision Matrix

| Requirement | HostNetwork | MetalLB |
|-------------|-------------|---------|
| **Single node** | ✅ Perfect | ✅ Works but overkill |
| **Multi-node** | ❌ One node only | ✅ Perfect |
| **Simplicity** | ✅ Very simple | ⚠️ More setup |
| **Standard ports** | ✅ Yes (80/443) | ✅ Yes |
| **LoadBalancer type** | ❌ No | ✅ Yes |
| **AWS EC2 internet** | ✅ Works directly | ⚠️ Needs NAT/forwarding |
| **Production ready** | ✅ Yes | ✅ Yes |

---

## Next Steps

Now that you understand both methods:

1. **For your current single-node lab:** Use **HostNetwork** - it's simpler
2. **For future multi-node clusters:** Use **MetalLB** for production
3. **For AWS production:** Consider **AWS Load Balancer Controller** with NLB/ALB

---

## Troubleshooting

### HostNetwork Issues

```bash
# If port 80/443 are already in use
sudo ss -tlnp | grep -E ':80|:443'

# Check what's using the port
sudo lsof -i :80
sudo lsof -i :443

# Check pod logs
kubectl logs -n kube-system -l app.kubernetes.io/component=controller --tail=50
```

### MetalLB Issues

```bash
# Check MetalLB pods
kubectl get pods -n metallb-system

# Check MetalLB logs
kubectl logs -n metallb-system -l app=metallb

# Check if IP pool is configured
kubectl get ipaddresspool -n metallb-system -o yaml

# Check service events
kubectl describe svc ingress-nginx-controller -n kube-system
```

### General Debugging

```bash
# Check ingress controller logs
kubectl logs -n kube-system -l app.kubernetes.io/component=controller --tail=50

# Check ingress status
kubectl describe ingress -n demo-app

# Test connectivity
curl -v http://localhost/demo/
curl -v http://13.58.33.90/demo/

# Check AWS security group
# Make sure ports 80 and 443 are allowed!
```

---

## Files Created

- `d:\2026\rke2\docs\08-production-ingress-lab.md` - This lab guide

---

## References

- [MetalLB Documentation](https://metallb.universe.tf/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [RKE2 Ingress Configuration](https://docs.rke2.io/networking/networking_services#nginx-ingress-controller)
