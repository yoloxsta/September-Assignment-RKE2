# RKE2 Learning Lab - Complete Guide

## Table of Contents
1. [What is RKE2?](#what-is-rke2)
2. [Why Use RKE2?](#why-use-rke2)
3. [Architecture Overview](#architecture-overview)
4. [Lab Prerequisites](#lab-prerequisites)
5. [Step-by-Step Setup](#step-by-step-setup)
6. [Demo Application](#demo-application)
7. [Testing & Verification](#testing--verification)
8. [Troubleshooting](#troubleshooting)
9. [Cleanup](#cleanup)

---

## What is RKE2?

**RKE2** (Rancher Kubernetes Engine 2), also known as **RKE Government**, is a fully conformant Kubernetes distribution developed by Rancher/SUSE. It combines the best of both worlds from its predecessors:

### Key Characteristics

- **Security-First Design**: CIS Kubernetes Benchmark compliant out of the box
- **FIPS 140-2 Validated**: Uses validated cryptography modules (important for government/enterprise)
- **Lightweight**: Single binary installation, minimal dependencies
- **Production-Ready**: Uses etcd (not SQLite like K3s) for production-grade data store
- **All-in-One**: Bundles CNI (Canal/Cilium), Ingress (Traefik), and storage drivers

### RKE2 vs Other Kubernetes Distributions

| Feature | RKE2 | K3s | EKS | kubeadm |
|---------|------|-----|-----|---------|
| Security Hardened | ✓ (CIS) | Partial | ✓ | Manual |
| FIPS Validated Crypto | ✓ | ✗ | ✗ | ✗ |
| Single Binary | ✓ | ✓ | ✗ | ✗ |
| etcd Production Ready | ✓ | SQLite | ✓ | ✓ |
| Rancher Integration | ✓ Native | ✓ | ✓ | ✓ |
| Air-Gap Support | ✓ | ✓ | Complex | Complex |
| Managed Service | ✗ | ✗ | ✓ | ✗ |

---

## Why Use RKE2?

### 1. **Security & Compliance**
```
- CIS Kubernetes Benchmark compliant by default
- SELinux/AppArmor support
- FIPS 140-2 validated cryptography
- Regular security audits
- DISA STIG ready
```

### 2. **Simplicity**
```
- Single command installation
- No external dependencies
- Automatic TLS certificate management
- Built-in ingress controller (Traefik)
- Integrated CNI (Canal with network policies)
```

### 3. **Enterprise Features**
```
- High availability with embedded etcd
- Automated upgrades via Rancher
- Multi-cluster management ready
- Windows node support
- GPU operator support
```
### 4. **Perfect For**
- **Government & Defense**: FIPS compliance, DISA STIG
- **Financial Services**: Security hardening, audit trails
- **Healthcare**: HIPAA compliance requirements
- **Air-Gapped Environments**: Complete offline installation
- **Edge Computing**: Lightweight, runs on minimal resources
- **Dev/Test Labs**: Easy setup and teardown

### Why Not Just Use EKS?

| Consideration | EKS | RKE2 on EC2 |
|----------------|-----|-------------|
| Cost | Higher (managed service premium) | Lower (just EC2 costs) |
| Control | AWS managed | Full control |
| Upgrades | AWS schedule | Your schedule |
| Air-Gap | Not possible | Fully supported |
| Customization | Limited | Complete control |
| Learning | Abstracts complexity | Learn Kubernetes deeply |

---

## Architecture Overview

### RKE2 Components

```
┌─────────────────────────────────────────────────────────────┐
│                        RKE2 Server Node                      │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ kube-apiserver│  │   etcd       │  │kube-scheduler│      │
│  │   :6443      │  │  :2379-2381  │  │              │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │kube-controller│  │ rke2-server  │  │ cloud-       │      │
│  │   manager    │  │   :9345      │  │ controller   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Traefik    │  │  Canal CNI   │  │   CoreDNS    │      │
│  │  (Ingress)   │  │  :8472/UDP   │  │              │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### Networking Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                       Internet / Users                        │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       ▼
              ┌────────────────┐
              │  AWS Security  │  Inbound: 80, 443, 6443, 9345
              │     Group      │  8472/UDP (VXLAN internal)
              └────────┬───────┘
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
   ┌─────────┐    ┌─────────┐    ┌─────────┐
   │ Server  │    │ Server  │    │ Agent   │
   │ Node 1  │    │ Node 2  │    │ Node 1  │
   │(Control)│    │(Control)│    │(Worker) │
   └─────────┘    └─────────┘    └─────────┘
        │              │              │
        └──────────────┴──────────────┘
                       │
              Overlay Network (VXLAN)
              Pod CIDR: 10.42.0.0/16
              Service CIDR: 10.43.0.0/16
```

### Traffic Flow to Application

```
User Request → AWS Security Group
            → Node (EC2 Instance)
            → Traefik Ingress Controller (LoadBalancer/NodePort)
            → Kubernetes Service (ClusterIP)
            → Pod (Application Container)
```

---

## Lab Prerequisites

### AWS Account Requirements
- Active AWS account with EC2 access
- IAM user with permissions:
  - `ec2:*` (launch, manage instances)
  - `iam:PassRole` (if using IAM roles)
  - `elasticloadbalancing:*` (optional, for LoadBalancer services)

### Local Machine Requirements
- **kubectl** installed (for cluster management)
- **SSH client** (for connecting to EC2 instances)
- **AWS CLI** (optional, for resource management)

### Recommended Instance Types

| Role | Instance Type | vCPU | RAM | Cost/hr (us-east-1) |
|------|--------------|------|-----|---------------------|
| Single Node Lab | t3.medium | 2 | 4GB | ~$0.04 |
| Single Node Prod | m5.large | 2 | 8GB | ~$0.10 |
| HA Control Plane | m5.xlarge | 4 | 16GB | ~$0.20 |
| Worker Node | m5.large | 2 | 8GB | ~$0.10 |

### Estimated Lab Costs
```
Single node (t3.medium): ~$1/day
Three node cluster (1 server + 2 workers): ~$3/day
Always terminate instances when not in use!
```

---

## Step-by-Step Setup

### Overview

This lab will guide you through:

1. **Phase 1**: Launch EC2 instance on AWS
2. **Phase 2**: Install RKE2 (single node)
3. **Phase 3**: Configure kubectl access
4. **Phase 4**: Deploy demo application
5. **Phase 5**: Expose application with ClusterIP + Ingress
6. **Phase 6**: Test and verify

### Detailed Instructions

See individual guides:
- [`docs/01-aws-ec2-setup.md`](docs/01-aws-ec2-setup.md) - Launch and configure EC2
- [`docs/02-rke2-installation.md`](docs/02-rke2-installation.md) - Install RKE2
- [`docs/traefik-storage.md`](docs/traefik-storage.md) - **Traefik ingress & Storage configuration**
- [`docs/03-demo-application.md`](docs/03-demo-application.md) - Deploy and test app

---

## Demo Application

We'll deploy a **3-tier demo application** to demonstrate:

1. **Frontend**: Nginx web server
2. **Backend**: Simple API server
3. **Database**: Redis (optional, for state)

### Architecture

```
                    ┌─────────────────────┐
                    │   Ingress (Traefik) │
                    │   demo.local /*     │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │  Service: frontend  │
                    │   Type: ClusterIP   │
                    │   Port: 80          │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │   Pods: Frontend    │
                    │   (Nginx)           │
                    └──────────┬──────────┘
                               │
            ┌──────────────────┼──────────────────┐
            │                  │                  │
    ┌───────▼───────┐  ┌──────▼──────┐  ┌───────▼───────┐
    │ Service: API  │  │ Service: DB │  │ Service: ...  │
    │ ClusterIP     │  │ ClusterIP   │  │               │
    └───────────────┘  └─────────────┘  └───────────────┘
```

### What We'll Learn

- Creating Kubernetes Deployments
- Exposing services with ClusterIP (internal only)
- Configuring Ingress for external access
- Understanding service discovery
- Testing with port-forwarding and Ingress

---

## Testing & Verification

At each step, we'll verify:

1. **Cluster Health**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

2. **Component Status**
   ```bash
   kubectl get svc -A
   kubectl get ingress
   ```

3. **Application Functionality**
   ```bash
   curl http://<node-ip>/app
   ```

4. **Logs & Events**
   ```bash
   kubectl logs -f deployment/<name>
   kubectl describe ingress <name>
   ```

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Node NotReady | CNI not ready | Check Canal pods: `kubectl get pods -n kube-system -l k8s-app=canal` |
| Ingress not working | Traefik not deployed | Verify Traefik: `kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik` |
| Cannot pull images | Network/registry issue | Check security groups, verify internet access |
| API server unreachable | Security group | Verify port 6443 is open |

### Debug Commands

```bash
# Check RKE2 service status
sudo journalctl -u rke2-server -f

# Check cluster info
kubectl cluster-info

# View all resources
kubectl get all -A

# Check events
kubectl get events --sort-by='.lastTimestamp' -A
```

---

## Cleanup

### Important: Avoid AWS Charges!

After completing the lab:

1. **Terminate EC2 instances**
   - AWS Console → EC2 → Instances → Terminate
   
2. **Delete Security Groups** (if created specifically for lab)

3. **Release Elastic IPs** (if allocated)

4. **Verify no running resources**
   - Check EC2 dashboard
   - Check VPC dashboard for orphaned resources

See [`docs/04-cleanup.md`](docs/04-cleanup.md) for detailed cleanup instructions.

---

## Next Steps

After completing this lab:

1. **High Availability Setup**: Deploy 3 control plane nodes
2. **Rancher Integration**: Install Rancher for multi-cluster management
3. **GitOps**: Deploy ArgoCD for GitOps workflows
4. **Monitoring**: Install Prometheus/Grafana stack
5. **CI/CD**: Integrate with Jenkins/GitLab CI

---

## Resources

- [Official RKE2 Documentation](https://docs.rke2.io/)
- [Rancher Documentation](https://rancher.com/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)

## Additional Guides

- **Traefik & Storage**: See [`docs/traefik-storage.md`](docs/traefik-storage.md) for:
  - Traefik installation and configuration (automatic with RKE2)
  - Storage options: Local Path, Longhorn, AWS EBS CSI
  - Persistent Volume configuration

---

## License

This lab guide is provided for educational purposes. RKE2 is open source under the Apache 2.0 license.

---

**Let's begin!** Continue to [`docs/01-aws-ec2-setup.md`](docs/01-aws-ec2-setup.md) to launch your first EC2 instance.
