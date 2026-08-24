# Traefik Ingress & Storage Guide

This guide covers two important topics:
1. **Traefik Installation** - How Traefik is deployed in RKE2
2. **Storage Configuration** - Setting up persistent storage for applications

---

## Part 1: Traefik Ingress Controller

### Automatic Installation (Default)

**Traefik is automatically installed when you install RKE2.** You don't need to install it separately!

RKE2 comes with Traefik as the **default ingress controller** since version 1.36.

#### Verify Traefik Installation

After installing RKE2, verify Traefik is running:

```bash
# Check Traefik pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# Check Traefik service
kubectl get svc -n kube-system traefik

# Check Traefik ingress class
kubectl get ingressclass
```

**Expected Output:**
```
NAME                     READY   STATUS    RESTARTS   AGE
traefik-6b9f7f8d4b-abc   1/1     Running   0          5m

NAME      TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
traefik   ClusterIP   10.43.0.100    <none>        80/TCP,443/TCP   5m

NAME      CONTROLLER          PARAMETERS   AGE
traefik   traefik.io/traefik   <none>       5m
```

#### How Traefik Gets Installed

RKE2 installs Traefik using a **Helm chart** automatically during startup:

1. RKE2 server starts
2. It deploys Traefik from `/var/lib/rancher/rke2/server/manifests/rke2-traefik.yaml`
3. This is a Helm chart that creates:
   - Traefik Deployment
   - Traefik Service (ClusterIP by default)
   - Traefik IngressClass
   - RBAC resources (ServiceAccount, ClusterRole, ClusterRoleBinding)

### Check Traefik Helm Chart

```bash
# List installed Helm charts
kubectl get helmchart -A

# Check Traefik Helm chart
kubectl get helmchart -n kube-system rke2-traefik -o yaml
```

### Configure Traefik

You can customize Traefik by creating a `HelmChartConfig`:

```bash
# Create Traefik configuration
cat <<EOF | kubectl apply -f -
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-traefik
  namespace: kube-system
spec:
  valuesContent: |-
    # Traefik configuration
    service:
      type: LoadBalancer  # Change from ClusterIP to LoadBalancer
    
    # Enable dashboard
    ingressRoute:
      dashboard:
        enabled: true
    
    # Ports configuration
    ports:
      web:
        redirectTo: websecure
      websecure:
        tls:
          enabled: true
    
    # Resource limits
    resources:
      requests:
        cpu: 100m
        memory: 50Mi
      limits:
        cpu: 500m
        memory: 200Mi
EOF
```

### Disable Traefik (Optional)

If you want to use a different ingress controller:

```bash
# Create RKE2 config
sudo tee /etc/rancher/rke2/config.yaml <<EOF
ingress-controller: []
EOF

# Restart RKE2
sudo systemctl restart rke2-server
```

### Expose Traefik Service

By default, Traefik uses ClusterIP. To expose it externally:

#### Option 1: NodePort

```bash
# Patch Traefik service to NodePort
kubectl patch svc traefik -n kube-system -p '{"spec":{"type":"NodePort"}}'

# Get the assigned NodePort
kubectl get svc -n kube-system traefik

# Access: http://<NODE_IP>:<NODE_PORT>
```

#### Option 2: LoadBalancer (AWS)

```bash
# Patch Traefik service to LoadBalancer
kubectl patch svc traefik -n kube-system -p '{"spec":{"type":"LoadBalancer"}}'

# Get LoadBalancer hostname (takes 1-2 minutes)
kubectl get svc -n kube-system traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Access: http://<LB_HOSTNAME>
```

#### Option 3: Port Forward (Testing)

```bash
# Port forward to Traefik
kubectl port-forward -n kube-system svc/traefik 8080:80

# Access: http://localhost:8080
```

---

## Part 2: Storage Configuration

### Why Storage Matters

Kubernetes pods are ephemeral. When a pod dies, its data is lost. Persistent storage allows data to survive pod restarts and rescheduling.

### Storage Types in Kubernetes

| Type | Description | Use Case |
|------|-------------|----------|
| emptyDir | Temporary storage, deleted with pod | Cache, temp files |
| hostPath | Mount from node's filesystem | Single-node testing |
| PersistentVolume (PV) | Cluster-level storage resource | Production workloads |
| StorageClass | Dynamic provisioning | Cloud environments |

### Check Available Storage

```bash
# Check available storage classes
kubectl get storageclass

# Check persistent volumes
kubectl get pv

# Check persistent volume claims
kubectl get pvc -A
```

### Default Storage in RKE2

RKE2 **does not** install a default storage provisioner. You need to install one.

For AWS, you have several options:
1. **EBS CSI Driver** - AWS EBS volumes
2. **Longhorn** - Distributed block storage
3. **Local Path Provisioner** - Local storage

---

## Option 1: Install AWS EBS CSI Driver

### Step 1: Create IAM Policy

The EBS CSI driver needs permissions to manage EBS volumes.

```bash
# Create IAM policy document
cat > ebs-csi-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSnapshot",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:ModifyVolume",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeInstances",
        "ec2:DescribeSnapshots",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumesModifications",
        "ec2:DeleteVolume",
        "ec2:DeleteSnapshot",
        "ec2:CreateVolume",
        "ec2:ModifyInstanceAttribute"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Create IAM policy (via AWS Console or CLI)
aws iam create-policy \
    --policy-name Amazon_EBS_CSI_Driver \
    --policy-document file://ebs-csi-policy.json

# Attach to EC2 instance profile
aws iam attach-role-policy \
    --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/Amazon_EBS_CSI_Driver \
    --role-name <EC2_INSTANCE_ROLE>
```

### Step 2: Install EBS CSI Driver

```bash
# Add Helm repository
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update

# Install EBS CSI Driver
helm install aws-ebs-csi-driver \
    --namespace kube-system \
    aws-ebs-csi-driver/aws-ebs-csi-driver

# Verify installation
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
```

### Step 3: Create StorageClass

```bash
# Create default StorageClass for EBS
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  fsType: ext4
EOF

# Verify
kubectl get storageclass
```

### Step 4: Test with PersistentVolumeClaim

```bash
# Create a PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ebs-sc
  resources:
    requests:
      storage: 5Gi
EOF

# Check PVC status
kubectl get pvc

# Create a pod using the PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-storage
  namespace: default
spec:
  containers:
  - name: app
    image: nginx:1.25-alpine
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-pvc
EOF

# Verify pod is running
kubectl get pod test-storage

# Write data to verify persistence
kubectl exec test-storage -- sh -c "echo 'Hello RKE2 Storage!' > /data/test.txt"
kubectl exec test-storage -- cat /data/test.txt
```

---

## Option 2: Install Longhorn (Distributed Storage)

Longhorn is a distributed block storage system that works well on RKE2.

### Step 3: Install Longhorn

```bash
# Add Helm repository
helm repo add longhorn https://charts.longhorn.io
helm repo update

# Install Longhorn
helm install longhorn \
    --namespace longhorn-system \
    --create-namespace \
    --version 1.6.0 \
    longhorn/longhorn

# Verify installation
kubectl -n longhorn-system get pod

# Wait for all pods to be ready (takes 2-3 minutes)
kubectl -n longhorn-system wait pod --all --for=condition=ready --timeout=300s
```

### Step 4: Use Longhorn StorageClass

```bash
# Longhorn creates a default StorageClass automatically
kubectl get storageclass

# Create a PVC using Longhorn
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 5Gi
EOF
```

### Longhorn Dashboard

```bash
# Port forward to Longhorn UI
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8000:80

# Access: http://localhost:8000
```

---

## Option 3: Install Local Path Provisioner (Simplest)

For single-node labs, local path provisioner is the simplest option.

```bash
# Install local path provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml

# Set as default storage class
kubectl patch storageclass local-path \
    -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Verify
kubectl get storageclass

# Test with PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: local-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 2Gi
EOF
```

---

## Storage for Demo Application

Let's add persistent storage to the demo application.

### Update Backend with Persistent Storage

```bash
# Create PVC for backend
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backend-data
  namespace: demo-app
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path  # Change to your storage class
  resources:
    requests:
      storage: 1Gi
EOF

# Create deployment with PVC
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-with-storage
  namespace: demo-app
spec:
  replicas: 1  # Must be 1 for ReadWriteOnce PVC
  selector:
    matchLabels:
      app: demo
      tier: backend-storage
  template:
    metadata:
      labels:
        app: demo
        tier: backend-storage
    spec:
      containers:
      - name: api
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: backend-data
EOF
```

### Verify Data Persistence

```bash
# Write data
kubectl exec -n demo-app deployment/backend-with-storage -- sh -c "echo 'Persistent data' > /data/test.txt"

# Read data
kubectl exec -n demo-app deployment/backend-with-storage -- cat /data/test.txt

# Delete pod
kubectl delete pod -n demo-app -l tier=backend-storage

# Wait for new pod (data should persist)
kubectl get pods -n demo-app -l tier=backend-storage -w

# Verify data still exists
kubectl exec -n demo-app deployment/backend-with-storage -- cat /data/test.txt
```

---

## Summary

### Traefik
- **Automatically installed** with RKE2 (no manual steps needed)
- Verify: `kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik`
- Configure: Use `HelmChartConfig` resource
- Expose: Change service type to NodePort or LoadBalancer

### Storage Options
| Option | Difficulty | Best For | Cloud Support |
|--------|-----------|----------|---------------|
| Local Path | Easy | Single-node labs | No |
| Longhorn | Medium | Multi-node clusters | Yes (any) |
| EBS CSI | Medium | AWS production | AWS only |

### Recommended Path
1. **Lab**: Install Local Path Provisioner (simplest)
2. **Production on AWS**: Install EBS CSI Driver
3. **Production multi-cloud**: Install Longhorn

---

## Quick Commands

```bash
# Verify Traefik
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# Install Local Path Provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml

# Check storage classes
kubectl get storageclass

# Test storage
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
EOF
```
