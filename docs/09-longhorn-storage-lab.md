# Longhorn Storage Lab

## Overview

**Longhorn** is a distributed block storage system for Kubernetes. It provides:
- Replicated storage across nodes
- Snapshots and backups
- CSI-compliant persistent volumes
- Web UI for management
- Easy backup/restore to S3/NFS

### Why Longhorn?

| Feature | local-path (current) | Longhorn |
|---------|---------------------|----------|
| **Replication** | ❌ No | ✅ Yes (1-3 replicas) |
| **High Availability** | ❌ No | ✅ Yes |
| **Snapshots** | ❌ No | ✅ Yes |
| **Backups** | ❌ No | ✅ Yes (S3/NFS) |
| **UI Dashboard** | ❌ No | ✅ Yes |
| **Cross-node storage** | ❌ No | ✅ Yes |
| **Use case** | Development, testing | Production |

---

## Prerequisites

### System Requirements

Longhorn requires **open-iscsi** on all nodes:

```bash
# On ALL nodes (master and worker)
# Master node
ssh -i your-key.pem ubuntu@13.58.33.90
sudo apt update && sudo apt install -y open-iscsi
sudo systemctl enable iscsid
sudo systemctl start iscsid

# Worker node
ssh -i your-key.pem ubuntu@18.190.207.77
sudo apt update && sudo apt install -y open-iscsi
sudo systemctl enable iscsid
sudo systemctl start iscsid
```

### Check Kernel Modules

```bash
# Verify required kernel modules
lsmod | grep -E "nbd|overlay"

# Load modules if not present
sudo modprobe nbd
sudo modprobe overlay

# Make persistent
echo "nbd" | sudo tee -a /etc/modules
echo "overlay" | sudo tee -a /etc/modules
```

---

## Installation

### Method 1: Helm (Recommended)

```bash
# On master node
ssh -i your-key.pem ubuntu@13.58.33.90

# Add Longhorn Helm repository
helm repo add longhorn https://charts.longhorn.io
helm repo update

# Create namespace
kubectl create namespace longhorn-system

# Install Longhorn
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --version 1.7.1

# Watch installation progress
kubectl -n longhorn-system get pods -w
```

### Method 2: kubectl (Alternative)

```bash
# Install using kubectl
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.7.1/deploy/longhorn.yaml

# Watch installation
kubectl -n longhorn-system get pods -w
```

---

## Verify Installation

### Step 1: Check Longhorn Pods

```bash
# Check all Longhorn pods
kubectl -n longhorn-system get pods

# Expected output:
# NAME                                        READY   STATUS    RESTARTS   AGE
# csi-attacher-56cf6c9b9b-2l8zm               1/1     Running   0          5m
# csi-attacher-56cf6c9b9b-q8v5v               1/1     Running   0          5m
# csi-attacher-56cf6c9b9b-svwv5               1/1     Running   0          5m
# csi-provisioner-5668bf5dd8-5zn6x            1/1     Running   0          5m
# csi-provisioner-5668bf5dd8-8kzxv            1/1     Running   0          5m
# csi-provisioner-5668bf5dd8-zbx5k            1/1     Running   0          5m
# csi-resizer-7c5bb6fd65-2gqvn                1/1     Running   0          5m
# csi-resizer-7c5bb6fd65-c9snl                1/1     Running   0          5m
# csi-resizer-7c5bb6fd65-lp4qs                1/1     Running   0          5m
# csi-snapshotter-5d4f5c86c8-5flx4            1/1     Running   0          5m
# csi-snapshotter-5d4f5c86c8-5pjzv            1/1     Running   0          5m
# csi-snapshotter-5d4f5c86c8-5wl9h            1/1     Running   0          5m
# engine-image-ei-8e5f488d-8p2v4              1/1     Running   0          5m
# engine-image-ei-8e5f488d-kv82l              1/1     Running   0          5m
# longhorn-csi-plugin-7bmv5                   2/2     Running   0          5m
# longhorn-csi-plugin-vq88p                   2/2     Running   0          5m
# longhorn-driver-deployer-6f86b56fcf-fztg4   1/1     Running   0          5m
# longhorn-manager-7bmv5                      1/1     Running   0          5m
# longhorn-manager-vq88p                      1/1     Running   0          5m
# longhorn-ui-6f54756b7-2h8w9                 1/1     Running   0          5m
```

### Step 2: Check Storage Classes

```bash
# List storage classes
kubectl get storageclass

# Expected output:
# NAME                 PROVISIONER          RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
# longhorn (default)   driver.longhorn.io   Delete          Immediate           true                   5m
# local-path           rancher.io/local-path Delete         WaitForFirstConsumer false                  2h
```

### Step 3: Check Nodes

```bash
# Check Longhorn nodes
kubectl -n longhorn-system get nodes.longhorn.io

# Check node details
kubectl -n longhorn-system describe nodes.longhorn.io
```

---

## Test Longhorn Storage

### Test 1: Create Persistent Volume Claim

```bash
# Create test PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-test-pvc
  namespace: default
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

# Check PVC
kubectl get pvc longhorn-test-pvc

# Output:
# NAME                STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# longhorn-test-pvc   Bound    pvc-12345678-1234-1234-1234-123456789012   1Gi        RWO            longhorn       10s
```

### Test 2: Create Test Pod

```bash
# Create test pod using Longhorn PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-test
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:latest
    volumeMounts:
    - name: data
      mountPath: /usr/share/nginx/html
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: longhorn-test-pvc
EOF

# Wait for pod to start
kubectl get pod longhorn-test -w

# Write data to PVC
kubectl exec longhorn-test -- sh -c "echo 'Longhorn storage test - $(date)' > /usr/share/nginx/html/index.html"

# Read data back
kubectl exec longhorn-test -- cat /usr/share/nginx/html/index.html

# Output:
# Longhorn storage test - Mon Aug 25 15:30:00 UTC 2026
```

### Test 3: Verify Replication

```bash
# Check volume details
kubectl -n longhorn-system get volumes

# Describe volume to see replicas
kubectl -n longhorn-system describe volume <volume-name>

# Check volume on which nodes
kubectl -n longhorn-system get volumes -o wide
```

---

## Access Longhorn UI

### Method 1: Port Forward (Quick Access)

```bash
# Port forward to Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# Access from browser: http://localhost:8080
```

### Method 2: Ingress (Permanent Access)

```bash
# Create ingress for Longhorn UI
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: longhorn-ingress
  namespace: longhorn-system
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /longhorn
        pathType: Prefix
        backend:
          service:
            name: longhorn-frontend
            port:
              number: 80
EOF

# Access from browser: http://13.58.33.90/longhorn/
```

### Longhorn UI Features

From the UI you can:
- 📊 View cluster storage capacity
- 💾 Create and manage volumes
- 📸 Take snapshots
- 🔄 Configure backups
- 📈 Monitor volume performance
- ⚙️ Configure replication settings

---

## Longhorn Configuration

### Default Storage Class Settings

```bash
# View default settings
kubectl -n longhorn-system get settings.longhorn.io

# Update default replica count
kubectl -n longhorn-system patch settings.longhorn.io default-replica-count \
  --type=merge -p '{"value":"2"}'

# Check settings
kubectl -n longhorn-system get settings.longhorn.io default-replica-count -o yaml
```

### Create Custom Storage Class

```bash
# Create custom storage class with specific settings
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-2-replicas
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "2"
  staleReplicaTimeout: "30"
  fromBackup: ""
EOF

# Use in PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: custom-pvc
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: longhorn-2-replicas
  resources:
    requests:
      storage: 5Gi
EOF
```

---

## Backup Configuration

### Configure S3 Backup Target

```bash
# Create Secret for S3 credentials
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: aws-s3-backup-secret
  namespace: longhorn-system
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: YOUR_AWS_ACCESS_KEY
  AWS_SECRET_ACCESS_KEY: YOUR_AWS_SECRET_KEY
EOF

# Configure backup target
kubectl -n longhorn-system patch settings.longhorn.io backup-target \
  --type=merge -p '{"value":"s3://your-bucket-name@us-east-2/longhorn-backups"}'

# Set backup credential
kubectl -n longhorn-system patch settings.longhorn.io backup-target-credential-secret \
  --type=merge -p '{"value":"aws-s3-backup-secret"}'
```

### Create Backup

```bash
# Via kubectl
kubectl -n longhorn-system create -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  name: test-backup
  namespace: longhorn-system
spec:
  snapshotName: <snapshot-name>
EOF

# Or via UI: Click on Volume > Create Backup
```

---

## Use Longhorn with Your Demo App

### Update Demo App to Use Longhorn

```bash
# Create PVC for frontend with Longhorn
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: frontend-data
  namespace: demo-app
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 2Gi
EOF

# Update frontend deployment to use PVC
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: demo-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html-content
          mountPath: /usr/share/nginx/html
        - name: data
          mountPath: /data
      volumes:
      - name: html-content
        configMap:
          name: frontend-html
      - name: data
        persistentVolumeClaim:
          claimName: frontend-data
EOF

# Write persistent data
kubectl exec -n demo-app deployment/frontend -- sh -c "echo 'Persistent data on Longhorn' > /data/test.txt"

# Verify data persists
kubectl exec -n demo-app deployment/frontend -- cat /data/test.txt
```

---

## Monitoring and Maintenance

### Check Volume Health

```bash
# List all volumes
kubectl -n longhorn-system get volumes

# Check volume status
kubectl -n longhorn-system describe volume <volume-name>

# Check volume statistics
kubectl -n longhorn-system get volumes -o wide
```

### Monitor Storage Usage

```bash
# Check node storage
kubectl -n longhorn-system get nodes.longhorn.io

# Check disk usage
kubectl -n longhorn-system describe nodes.longhorn.io <node-name>

# Check volume capacity
kubectl get pv
```

### Troubleshooting

```bash
# Check Longhorn manager logs
kubectl -n longhorn-system logs -l app=longhorn-manager

# Check CSI plugin logs
kubectl -n longhorn-system logs -l app=longhorn-csi-plugin

# Check engine logs
kubectl -n longhorn-system logs -l longhorn.io/component=instance-manager

# View events
kubectl -n longhorn-system get events --sort-by='.lastTimestamp'
```

---

## Cleanup

### Remove Test Resources

```bash
# Delete test pod and PVC
kubectl delete pod longhorn-test
kubectl delete pvc longhorn-test-pvc

# Delete test deployment
kubectl delete -n demo-app deployment frontend
kubectl delete -n demo-app pvc frontend-data
```

### Uninstall Longhorn (if needed)

```bash
# Delete all Longhorn volumes first
kubectl -n longhorn-system get volumes -o name | xargs kubectl -n longhorn-system delete

# Uninstall via Helm
helm uninstall longhorn -n longhorn-system

# Or via kubectl
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v1.7.1/deploy/longhorn.yaml

# Delete namespace
kubectl delete namespace longhorn-system
```

---

## Production Best Practices

### 1. Resource Planning

```bash
# Minimum requirements per node:
# - CPU: 2 cores
# - Memory: 4 GB
# - Disk: 50 GB (for Longhorn data)

# Recommended for production:
# - CPU: 4 cores
# - Memory: 8 GB
# - Disk: 200 GB SSD
```

### 2. Replica Configuration

```bash
# For high availability:
# - Minimum 2 replicas for non-critical data
# - 3 replicas for production databases
# - Place replicas on different nodes/zones

# Configure default replica count
kubectl -n longhorn-system patch settings.longhorn.io default-replica-count \
  --type=merge -p '{"value":"3"}'
```

### 3. Backup Strategy

```bash
# Configure recurring backups
kubectl -n longhorn-system create -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: daily-backup
  namespace: longhorn-system
spec:
  name: daily-backup
  task: backup
  cron: "0 2 * * *"  # Daily at 2 AM
  retain: 7
  concurrency: 2
EOF
```

### 4. Node Scheduling

```bash
# Label nodes for storage
kubectl label node ip-172-31-10-92 node.longhorn.io/create-default-disk=true

# Taint nodes to prevent non-storage workloads
kubectl taint node ip-172-31-10-92 storage=longhorn:NoSchedule
```

---

## Comparison: local-path vs Longhorn

| Feature | local-path | Longhorn |
|---------|-----------|----------|
| **Setup Complexity** | ✅ Simple | ⚠️ Moderate |
| **Resource Usage** | ✅ Low | ⚠️ Higher |
| **Data Replication** | ❌ No | ✅ Yes (configurable) |
| **High Availability** | ❌ No | ✅ Yes |
| **Snapshots** | ❌ No | ✅ Yes |
| **Backups** | ❌ No | ✅ Yes (S3/NFS) |
| **UI Dashboard** | ❌ No | ✅ Yes |
| **Cross-node** | ❌ No | ✅ Yes |
| **Performance** | ✅ Fastest | ⚠️ Good (with overhead) |
| **Use Case** | Dev, testing | Production |

**Recommendation:**
- Use `local-path` for development and testing
- Use `Longhorn` for production workloads requiring HA

---

## Summary

### What You Learned

1. ✅ How to install Longhorn on RKE2
2. ✅ Prerequisites (open-iscsi, kernel modules)
3. ✅ Creating and using Longhorn PVCs
4. ✅ Accessing Longhorn UI
5. ✅ Configuring backups and replicas
6. ✅ Monitoring and troubleshooting

### Key Commands

```bash
# Install Longhorn
helm install longhorn longhorn/longhorn --namespace longhorn-system --version 1.7.1

# Check status
kubectl -n longhorn-system get pods

# View volumes
kubectl -n longhorn-system get volumes

# Access UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# Create PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: longhorn
  resources:
    requests:
      storage: 5Gi
EOF
```

---

## References

- [Longhorn Documentation](https://longhorn.io/docs/)
- [Longhorn GitHub](https://github.com/longhorn/longhorn)
- [RKE2 Storage Documentation](https://docs.rke2.io/storage/storage)
