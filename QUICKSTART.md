# RKE2 Lab Quick Start Guide

This is a quick reference guide for setting up RKE2 on AWS EC2. For detailed explanations, see the full documentation in the `docs/` folder.

## Prerequisites

- AWS account with EC2 access
- SSH client
- kubectl installed locally (optional)

## Quick Setup (15-20 minutes)

### Step 1: Launch EC2 Instance

**Via AWS Console:**
1. EC2 → Launch Instance
2. Name: `rke2-lab-server`
3. AMI: Amazon Linux 2023
4. Instance type: `t3.medium`
5. Key pair: Create new `rke2-lab-key`
6. Security group: Allow ports 22, 80, 443, 6443, 9345
7. Launch

**Via AWS CLI:**
```bash
# Create security group
aws ec2 create-security-group --group-name rke2-lab-sg --description "RKE2 Lab"

# Add rules
for PORT in 22 80 443 6443 9345; do
  aws ec2 authorize-security-group-ingress --group-name rke2-lab-sg --protocol tcp --port $PORT --cidr 0.0.0.0/0
done

# Launch instance
aws ec2 run-instances \
  --image-id ami-0abcdef1234567890 \
  --instance-type t3.medium \
  --key-name rke2-lab-key \
  --security-groups rke2-lab-sg \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=rke2-lab-server}]"
```

### Step 2: Install RKE2

SSH into the instance:

```bash
ssh -i rke2-lab-key.pem ec2-user@<PUBLIC_IP>
```

Run the installation script:

```bash
# Download and run
curl -sfL https://get.rke2.io | sudo sh -

# Configure
sudo mkdir -p /etc/rancher/rke2
sudo tee /etc/rancher/rke2/config.yaml <<EOF
tls-san:
  - "$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
write-kubeconfig-mode: "0644"
EOF

# Start RKE2
sudo systemctl enable rke2-server
sudo systemctl start rke2-server

# Wait for startup (2-3 minutes)
sudo journalctl -u rke2-server -f
```

### Step 3: Configure kubectl

```bash
# On EC2 instance
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# Verify
kubectl get nodes
```

**From local machine:**
```bash
# Copy kubeconfig
ssh -i rke2-lab-key.pem ec2-user@<PUBLIC_IP> "sudo cat /etc/rancher/rke2/rke2.yaml" > ~/.kube/rke2-lab

# Edit server IP
sed -i 's/127.0.0.1/<PUBLIC_IP>/g' ~/.kube/rke2-lab

# Use
export KUBECONFIG=~/.kube/rke2-lab
kubectl get nodes
```

### Step 4: Deploy Demo App

```bash
# Clone or download manifests
git clone <repo> rke2
cd rke2

# Deploy
kubectl apply -f manifests/deploy-all.yaml

# Verify
kubectl get all -n demo-app
```

### Step 5: Access the App

**Option 1: Port Forward**
```bash
kubectl port-forward -n kube-system svc/traefik 8888:80
# Open: http://localhost:8888/demo/
```

**Option 2: NodePort**
```bash
kubectl patch svc traefik -n kube-system -p '{"spec":{"type":"NodePort"}}'
NODE_PORT=$(kubectl get svc -n kube-system traefik -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}')
# Open: http://<PUBLIC_IP>:$NODE_PORT/demo/
```

**Option 3: LoadBalancer (AWS)**
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: traefik-lb
  namespace: kube-system
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: traefik
  ports:
  - name: web
    port: 80
    targetPort: web
EOF

# Get LoadBalancer hostname
kubectl get svc -n kube-system traefik-lb
# Open: http://<LB_HOSTNAME>/demo/
```

## Quick Commands Reference

### Cluster Management

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A
kubectl cluster-info

# View logs
sudo journalctl -u rke2-server -f

# Restart RKE2
sudo systemctl restart rke2-server
```

### Application Management

```bash
# Deploy
kubectl apply -f manifests/deploy-all.yaml

# Check status
kubectl get all -n demo-app

# Scale
kubectl scale deployment frontend -n demo-app --replicas=5

# View logs
kubectl logs -n demo-app -l app=demo -f

# Delete
kubectl delete namespace demo-app
```

### Networking

```bash
# Test DNS
kubectl run -it --rm --restart=Never test --image=busybox -- nslookup kubernetes.default

# Test service
kubectl run -it --rm --restart=Never test --image=curlimages/curl -- curl http://frontend.demo-app

# Port forward
kubectl port-forward -n demo-app svc/frontend 8080:80
```

### Troubleshooting

```bash
# Describe resources
kubectl describe pod <POD_NAME> -n demo-app
kubectl describe ingress -n demo-app

# Check events
kubectl get events -A --sort-by='.lastTimestamp'

# Check logs
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik
```

## Cleanup

**Quick cleanup:**
```bash
# Terminate instance via AWS Console
# OR
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>
```

**Full cleanup:**
```bash
# Run cleanup script
./scripts/cleanup-aws.sh
```

## Estimated Costs

| Resource | Cost |
|----------|------|
| t3.medium instance | ~$0.04/hr |
| 30GB gp3 volume | ~$0.01/hr |
| **Total** | ~$1.15/day |

**Always terminate instances when not in use!**

## Documentation

- [Full Guide](README.md) - Complete documentation
- [AWS EC2 Setup](docs/01-aws-ec2-setup.md) - Detailed EC2 setup
- [RKE2 Installation](docs/02-rke2-installation.md) - Installation details
- [Demo Application](docs/03-demo-application.md) - App deployment guide
- [Testing Guide](docs/04-testing-verification.md) - Verification procedures
- [Cleanup Guide](docs/05-cleanup.md) - Resource cleanup

## Common Issues

| Issue | Solution |
|-------|----------|
| Node NotReady | Wait 2-3 minutes, check `kubectl get pods -n kube-system` |
| Cannot connect to API | Verify security group allows port 6443 |
| Ingress not working | Check Traefik: `kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik` |
| Image pull errors | Check internet connectivity, verify image names |

## Support

- [RKE2 Documentation](https://docs.rke2.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
