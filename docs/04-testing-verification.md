# Testing and Verification Guide

This comprehensive guide covers testing and verifying every aspect of your RKE2 cluster and demo application.

## Table of Contents
- [RKE2 Cluster Health Checks](#rke2-cluster-health-checks)
- [Node Verification](#node-verification)
- [System Component Checks](#system-component-checks)
- [Network Verification](#network-verification)
- [Application Testing](#application-testing)
- [Ingress Testing](#ingress-testing)
- [Performance Testing](#performance-testing)
- [Troubleshooting Commands](#troubleshooting-commands)

---

## RKE2 Cluster Health Checks

### Quick Health Check Script

Create a health check script:

```bash
#!/bin/bash
# save as: health-check.sh

echo "=========================================="
echo "RKE2 Cluster Health Check"
echo "=========================================="
echo ""

# Check RKE2 service
echo "1. RKE2 Service Status:"
systemctl is-active rke2-server
echo ""

# Check node status
echo "2. Node Status:"
kubectl get nodes -o wide
echo ""

# Check system pods
echo "3. System Pods:"
kubectl get pods -n kube-system
echo ""

# Check component statuses
echo "4. Component Health:"
kubectl get --raw='/readyz?verbose'
echo ""

# Check etcd health
echo "5. Etcd Health:"
kubectl get endpoints -n kube-system kube-controller-manager-api -o yaml | grep -A 5 "addresses"
echo ""

# Check API server
echo "6. API Server:"
kubectl cluster-info
echo ""

echo "=========================================="
echo "Health check complete!"
echo "=========================================="
```

### Expected Output

```
==========================================
RKE2 Cluster Health Check
==========================================

1. RKE2 Service Status:
active

2. Node Status:
NAME            STATUS   ROLES                       AGE   VERSION        INTERNAL-IP   OS-IMAGE
rke2-server-1   Ready    control-plane,etcd,master   1h    v1.34.6+rke2r3 10.0.1.100    Amazon Linux 2023

3. System Pods:
NAMESPACE     NAME                                    READY   STATUS      RESTARTS   AGE
kube-system   etcd-rke2-server-1                      1/1     Running     0          1h
kube-system   kube-apiserver-rke2-server-1            1/1     Running     0          1h
kube-system   kube-controller-manager-rke2-server-1  1/1     Running     0          1h
kube-system   kube-proxy-rke2-server-1                1/1     Running     0          1h
kube-system   kube-scheduler-rke2-server-1            1/1     Running     0          1h
kube-system   rke2-canal-xxxxx                        2/2     Running     0          1h
kube-system   rke2-coredns-xxxxx                      1/1     Running     0          1h
kube-system   traefik-xxxxx                           1/1     Running     0          1h

4. Component Health:
[+]ping ok
[+]log ok
[+]etcd ok
[+]informer-sync ok
[+]poststarthook/start-kube-apiserver-admission-initializer ok
...
healthz check passed

5. Etcd Health:
- address: 10.0.1.100

6. API Server:
Kubernetes control plane is running at https://127.0.0.1:6443
CoreDNS is running at https://127.0.0.1:6443/api/v1/namespaces/kube-system/services/rke2-coredns-rke2-coredns:udp-53/proxy

==========================================
Health check complete!
==========================================
```

---

## Node Verification

### Check Node Details

```bash
# Get detailed node information
kubectl describe node <NODE_NAME>

# Check node conditions
kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,REASON:.status.conditions[-1].reason

# Check node resources
kubectl describe node <NODE_NAME> | grep -A 5 "Allocated resources"

# Check node capacity
kubectl get node -o json | jq '.items[] | {name: .metadata.name, capacity: .status.capacity}'
```

### Check Node Labels and Taints

```bash
# List node labels
kubectl get nodes --show-labels

# Check for taints
kubectl describe node <NODE_NAME> | grep -A 3 "Taints"

# Add a label (example)
kubectl label node <NODE_NAME> environment=lab

# Remove a label (example)
kubectl label node <NODE_NAME> environment-
```

### Check System Information

```bash
# Get node system info
kubectl get node -o json | jq '.items[].status.nodeInfo'

# Check kernel version
uname -r

# Check OS version
cat /etc/os-release

# Check container runtime
kubectl get node -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}'
```

---

## System Component Checks

### CoreDNS

```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS service
kubectl get svc -n kube-system -l k8s-app=kube-dns

# Test DNS resolution from a pod
kubectl run -it --rm --restart=Never dns-test --image=busybox:1.36 -- nslookup kubernetes.default

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# Test external DNS resolution
kubectl run -it --rm --restart=Never dns-test --image=busybox:1.36 -- nslookup google.com
```

### Etcd

```bash
# Check etcd pod
kubectl get pods -n kube-system -l component=etcd

# Check etcd health (on server node)
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key \
  endpoint health

# Check etcd members
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key \
  member list

# Check etcd data size
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key \
  endpoint status --write-out=table
```

### API Server

```bash
# Check API server pod
kubectl get pods -n kube-system -l component=kube-apiserver

# Check API server logs
kubectl logs -n kube-system kube-apiserver-$(hostname)

# Check API server metrics
kubectl get --raw /metrics | grep apiserver_request_duration_seconds

# Test API server connectivity
kubectl get --raw /healthz
```

### Controller Manager

```bash
# Check controller manager pod
kubectl get pods -n kube-system -l component=kube-controller-manager

# Check controller manager logs
kubectl logs -n kube-system kube-controller-manager-$(hostname)
```

### Scheduler

```bash
# Check scheduler pod
kubectl get pods -n kube-system -l component=kube-scheduler

# Check scheduler logs
kubectl logs -n kube-system kube-scheduler-$(hostname)
```

---

## Network Verification

### CNI (Canal/Calico)

```bash
# Check CNI pods
kubectl get pods -n kube-system -l k8s-app=canal

# Check CNI config on node
ls -la /etc/cni/net.d/

# Check CNI logs
kubectl logs -n kube-system -l k8s-app=canal -c calico-node

# Check pod network
kubectl get pods -A -o wide

# Test pod-to-pod connectivity
kubectl run -it --rm --restart=Never ping-test --image=busybox:1.36 -- ping -c 3 <POD_IP>
```

### Service Discovery (DNS)

```bash
# Test DNS resolution
kubectl run -it --rm --restart=Never dns-test --image=busybox:1.36 -- sh -c "nslookup kubernetes.default && nslookup kubernetes.default.svc.cluster.local"

# Test service DNS
kubectl run -it --rm --restart=Never dns-test --image=busybox:1.36 -- nslookup frontend.demo-app.svc.cluster.local

# Check DNS service
kubectl get svc -n kube-system kube-dns
```

### Service Endpoints

```bash
# Check service endpoints
kubectl get endpoints -n demo-app

# Describe endpoints
kubectl describe endpoints frontend -n demo-app

# Check endpoint slices (newer API)
kubectl get endpointslices -n demo-app
```

### Network Policies

```bash
# Check if network policies are supported
kubectl get networkpolicies -A

# Check Canal/Calico network policy CRDs
kubectl get crd | grep -i network

# Test default deny policy (optional)
# kubectl apply -f - <<EOF
# apiVersion: networking.k8s.io/v1
# kind: NetworkPolicy
# metadata:
#   name: default-deny
#   namespace: demo-app
# spec:
#   podSelector: {}
#   policyTypes:
#   - Ingress
# EOF
```

### Port Connectivity Test

```bash
# Test connectivity between services
kubectl run -it --rm --restart=Never curl-test \
  --image=curlimages/curl:8.5.0 \
  -- curl -v http://frontend.demo-app

# Test backend service
kubectl run -it --rm --restart=Never curl-test \
  --image=curlimages/curl:8.5.0 \
  -- curl -v http://backend.demo-app:8080
```

---

## Application Testing

### Check Application Status

```bash
# Check all resources in demo-app namespace
kubectl get all -n demo-app

# Check deployments
kubectl get deployments -n demo-app

# Check pods
kubectl get pods -n demo-app -o wide

# Check services
kubectl get svc -n demo-app

# Check ingress
kubectl get ingress -n demo-app

# Check configmaps
kubectl get configmap -n demo-app
```

### Pod Health Checks

```bash
# Check pod status and events
kubectl describe pod -n demo-app <POD_NAME>

# Check pod logs
kubectl logs -n demo-app <POD_NAME>

# Check pod logs with follow
kubectl logs -n demo-app -l app=demo -f

# Check pod resource usage
kubectl top pods -n demo-app

# Check pod events
kubectl get events -n demo-app --sort-by='.lastTimestamp'
```

### Test Service Discovery

```bash
# Test frontend service
kubectl run -it --rm --restart=Never test \
  --image=curlimages/curl:8.5.0 \
  -- curl -s http://frontend.demo-app | head -20

# Test backend service
kubectl run -it --rm --restart=Never test \
  --image=curlimages/curl:8.5.0 \
  -- curl -s http://backend.demo-app:8080

# Test service from another pod
kubectl run -it --rm --restart=Never test \
  --image=busybox:1.36 \
  -- wget -qO- http://frontend.demo-app
```

### Port Forwarding Test

```bash
# Port forward frontend service
kubectl port-forward -n demo-app svc/frontend 8080:80 &

# Test
curl http://localhost:8080

# Port forward backend service
kubectl port-forward -n demo-app svc/backend 8081:8080 &

# Test
curl http://localhost:8081
```

### Pod Scaling Test

```bash
# Scale frontend to 5 replicas
kubectl scale deployment frontend -n demo-app --replicas=5

# Watch pods scale up
kubectl get pods -n demo-app -l tier=frontend -w

# Check HPA (if configured)
kubectl get hpa -n demo-app

# Scale back down
kubectl scale deployment frontend -n demo-app --replicas=2
```

### Rolling Update Test

```bash
# Update frontend image
kubectl set image deployment/frontend nginx=nginx:1.26-alpine -n demo-app

# Watch rollout
kubectl rollout status deployment/frontend -n demo-app

# Check rollout history
kubectl rollout history deployment/frontend -n demo-app

# Rollback if needed
kubectl rollout undo deployment/frontend -n demo-app
```

---

## Ingress Testing

### Check Ingress Controller

```bash
# Check Traefik pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# Check Traefik service
kubectl get svc -n kube-system traefik

# Check Traefik logs
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik

# Check ingress classes
kubectl get ingressclass

# Describe ingress class
kubectl describe ingressclass traefik
```

### Check Ingress Resources

```bash
# List ingress resources
kubectl get ingress -A

# Describe ingress
kubectl describe ingress -n demo-app demo-ingress

# Check ingress rules
kubectl get ingress -n demo-app demo-ingress -o yaml
```

### Test Ingress Routing

#### Method 1: Port Forward

```bash
# Port forward Traefik service
kubectl port-forward -n kube-system svc/traefik 8888:80 &

# Test frontend route
curl -H "Host: demo.local" http://localhost:8888/

# Test backend route
curl -H "Host: demo.local" http://localhost:8888/api/status
```

#### Method 2: NodePort

```bash
# Check if Traefik has NodePort
kubectl get svc -n kube-system traefik -o jsonpath='{.spec.type}'

# If LoadBalancer, patch to NodePort
kubectl patch svc traefik -n kube-system -p '{"spec":{"type":"NodePort"}}'

# Get NodePort
NODE_PORT=$(kubectl get svc -n kube-system traefik -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}')
echo "NodePort: $NODE_PORT"

# Test from outside (replace with your EC2 public IP)
curl http://<PUBLIC_IP>:$NODE_PORT/demo/
```

#### Method 3: Host-based Routing

```bash
# Add entry to /etc/hosts
echo "<EC2_PUBLIC_IP> demo.local" | sudo tee -a /etc/hosts

# Test
curl http://demo.local/
curl http://demo.local/api/status
```

### Verify Load Balancing

```bash
# Run multiple requests and check which pod responds
for i in {1..10}; do
  curl -s http://demo.local/api/status | jq -r '.pod_name // .service'
  sleep 0.5
done

# Or check nginx logs
kubectl logs -n demo-app -l tier=frontend -f --max-log-requests=5
```

---

## Performance Testing

### Resource Usage

```bash
# Check node resource usage
kubectl top nodes

# Check pod resource usage
kubectl top pods -A

# Check pod resource requests/limits
kubectl get pods -n demo-app -o json | jq '.items[] | {name: .metadata.name, containers: .spec.containers[].resources}'
```

### Benchmark DNS

```bash
# DNS performance test
kubectl run -it --rm --restart=Never dnsperf \
  --image=infoblox/dnstools \
  -- dnstest -s 10.43.0.10 -q 100 kubernetes.default.svc.cluster.local
```

### Benchmark Application

```bash
# Install hey (HTTP load generator)
# On your local machine or a test pod

# Test frontend
hey -n 1000 -c 10 http://demo.local/

# Test backend
hey -n 1000 -c 10 http://demo.local/api/status
```

### Network Latency Test

```bash
# Test latency between pods
kubectl run -it --rm --restart=Never latency-test \
  --image=alpine:3.19 \
  -- sh -c "apk add --no-cache iputils && ping -c 10 <POD_IP>"
```

---

## Troubleshooting Commands

### General Debugging

```bash
# Get cluster events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Get events for specific namespace
kubectl get events -n demo-app --sort-by='.lastTimestamp'

# Get events for specific resource
kubectl describe pod -n demo-app <POD_NAME>

# Check all resources
kubectl get all -A

# Check failed pods
kubectl get pods -A --field-selector=status.phase=Failed
```

### Logs Collection

```bash
# Get RKE2 service logs
sudo journalctl -u rke2-server -n 100

# Get kernel logs
dmesg | tail -50

# Get system logs
sudo journalctl -n 100

# Export pod logs
kubectl logs -n demo-app <POD_NAME> > pod-logs.txt

# Export all logs from namespace
for pod in $(kubectl get pods -n demo-app -o jsonpath='{.items[*].metadata.name}'); do
  kubectl logs -n demo-app $pod > ${pod}.log
done
```

### Network Debugging

```bash
# Check iptables rules
sudo iptables -L -n -v

# Check network interfaces
ip addr show

# Check routes
ip route show

# Check open ports
sudo netstat -tulpn | grep -E "6443|9345|8472|10250"

# Check connectivity
ping -c 3 8.8.8.8
curl -I https://registry.k8s.io
```

### Common Issues and Fixes

#### Issue: Node Not Ready

```bash
# Check CNI
kubectl get pods -n kube-system -l k8s-app=canal

# Check kubelet
sudo journalctl -u rke2-server | grep -i kubelet

# Fix: Restart RKE2
sudo systemctl restart rke2-server
```

#### Issue: Pod Stuck in Pending

```bash
# Check events
kubectl describe pod <POD_NAME> -n demo-app

# Check node resources
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check taints
kubectl describe nodes | grep -A 3 "Taints"
```

#### Issue: Image Pull BackOff

```bash
# Check image name
kubectl describe pod <POD_NAME> -n demo-app | grep -i image

# Check if image exists
crictl pull <IMAGE_NAME>

# Check registry connectivity
curl -I https://registry.k8s.io/v2/
```

#### Issue: Service Not Accessible

```bash
# Check endpoints
kubectl get endpoints <SERVICE_NAME> -n demo-app

# Check pod labels match service selector
kubectl get pods -n demo-app --show-labels
kubectl get svc <SERVICE_NAME> -n demo-app -o jsonpath='{.spec.selector}'

# Test from inside cluster
kubectl run -it --rm --restart=Never test --image=curlimages/curl:8.5.0 -- curl http://<SERVICE_NAME>.<NAMESPACE>
```

#### Issue: Ingress Not Working

```bash
# Check Traefik
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik

# Check ingress resource
kubectl describe ingress -n demo-app

# Check ingress class
kubectl get ingressclass

# Test Traefik directly
kubectl port-forward -n kube-system svc/traefik 8888:80
curl http://localhost:8888/demo/
```

---

## Verification Checklist

Use this checklist to verify your complete setup:

### RKE2 Cluster
- [ ] RKE2 service is running: `systemctl status rke2-server`
- [ ] Node is Ready: `kubectl get nodes`
- [ ] All system pods are Running: `kubectl get pods -n kube-system`
- [ ] API server is healthy: `kubectl get --raw='/healthz'`
- [ ] etcd is healthy: `etcdctl endpoint health`

### Networking
- [ ] CNI pods are running: `kubectl get pods -n kube-system -l k8s-app=canal`
- [ ] DNS is working: `kubectl run -it --rm --restart=Never test --image=busybox -- nslookup kubernetes.default`
- [ ] Pod-to-pod connectivity works
- [ ] Service DNS resolution works

### Application
- [ ] All pods are Running: `kubectl get pods -n demo-app`
- [ ] Services have endpoints: `kubectl get endpoints -n demo-app`
- [ ] Port forwarding works: `kubectl port-forward ...`
- [ ] Service discovery works from inside cluster

### Ingress
- [ ] Traefik is running: `kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik`
- [ ] Ingress resource is created: `kubectl get ingress -n demo-app`
- [ ] Ingress routing works (port-forward or NodePort)
- [ ] Load balancing works across pods

### Security
- [ ] Security groups allow required traffic
- [ ] RBAC is working (if configured)
- [ ] Network policies work (if configured)
- [ ] TLS is configured (if required)

---

## Summary

After completing all tests:

1. **Cluster is healthy**: All components running, API server responding
2. **Networking is working**: DNS, CNI, pod-to-pod communication
3. **Application is running**: Pods up, services accessible, ingress routing
4. **Performance is acceptable**: Reasonable response times, no resource bottlenecks

Continue to: **[04-cleanup.md](04-cleanup.md)** for cleanup instructions.

---

## Additional Resources

- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug/)
- [RKE2 Troubleshooting](https://docs.rke2.io/troubleshooting/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
