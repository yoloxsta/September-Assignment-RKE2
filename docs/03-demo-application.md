# Demo Application Deployment Guide

This guide walks you through deploying a demo application on RKE2. We'll deploy a simple web application with ClusterIP services and expose it via Ingress.

## Table of Contents
- [Application Architecture](#application-architecture)
- [What is ClusterIP?](#what-is-clusterip)
- [What is Ingress?](#what-is-ingress)
- [Deploy Frontend Application](#deploy-frontend-application)
- [Deploy Backend API](#deploy-backend-api)
- [Create ClusterIP Services](#create-clusterip-services)
- [Configure Ingress](#configure-ingress)
- [Test the Application](#test-the-application)
- [Understanding the Flow](#understanding-the-flow)

---

## Application Architecture

We'll deploy a simple 2-tier application:

```
                    Internet
                        |
                        v
                +---------------+
                |    Ingress    |
                |  (Traefik)    |
                |   demo.local  |
                +-------+-------+
                        |
                        v
            +-----------------------+
            |  Service: frontend    |
            |  Type: ClusterIP      |
            |  Port: 80 -> 8080     |
            +-----------+-----------+
                        |
                        v
            +-----------------------+
            |  Deployment: frontend |
            |  Pod: nginx           |
            |  Container Port: 8080 |
            +-----------+-----------+
                        |
            +-----------+-----------+
            |                       |
            v                       v
    +---------------+       +---------------+
    | Service: api |       | Service: api  |
    | (backend-v1) |       | (backend-v2)  |
    | ClusterIP    |       | ClusterIP     |
    +------+-------+       +-------+-------+
           |                       |
           v                       v
    +---------------+       +---------------+
    | Deployment:   |       | Deployment:   |
    | api-v1        |       | api-v2        |
    +---------------+       +---------------+
```

### Components

1. **Frontend**: Simple web page served by nginx
2. **Backend API (v1)**: Returns JSON response with version info
3. **Backend API (v2)**: Alternative version for demonstrating service discovery

---

## What is ClusterIP?

**ClusterIP** is the default Kubernetes service type. It provides:

- **Internal Load Balancing**: Distributes traffic across pods
- **Stable IP Address**: Pods can come and go, but the service IP stays the same
- **DNS Name**: Services get a DNS name: `<service-name>.<namespace>.svc.cluster.local`
- **Internal Access Only**: Not accessible from outside the cluster

### When to Use ClusterIP?

- Services that don't need external access
- Internal microservices communication
- Databases, caches, internal APIs
- When you want to control access via Ingress

### Service Types Comparison

| Type | Access | Use Case |
|------|--------|----------|
| ClusterIP | Internal only | Internal services, databases |
| NodePort | Internal + Node port | Dev/test, simple external access |
| LoadBalancer | External via cloud LB | Production external services |
| ExternalName | External DNS alias | External service integration |

---

## What is Ingress?

**Ingress** is a Kubernetes resource that manages external access to services:

- **HTTP/HTTPS Routing**: Routes requests based on host/path
- **SSL/TLS Termination**: Handles HTTPS certificates
- **Load Balancing**: Distributes traffic to services
- **Virtual Hosting**: Multiple domains on one IP

### How Ingress Works

```
External Traffic
      |
      v
+--------------+     +------------------+
|   Ingress    | --> | Ingress Class    |
|  Resource    |     | (Traefik/NGINX)  |
+--------------+     +------------------+
                            |
                            v
                     +-------------+
                     |  Service    |
                     | (ClusterIP) |
                     +-------------+
                            |
                            v
                     +-------------+
                     |    Pods     |
                     +-------------+
```

### Ingress vs LoadBalancer

| Feature | Ingress | LoadBalancer |
|---------|---------|--------------|
| Cost | 1 LB for many services | 1 LB per service |
| SSL/TLS | Built-in | Manual |
| Path routing | Yes | No |
| Host routing | Yes | No |
| Cloud required | No | Yes |

---

## Deploy Frontend Application

### Step 1: Create Namespace

Create a namespace to organize our demo resources:

```bash
# Create namespace
kubectl create namespace demo-app

# Set as default for current context
kubectl config set-context --current --namespace=demo-app
```

### Step 2: Create Frontend Deployment

Create `frontend-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: demo-app
  labels:
    app: demo
    tier: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo
      tier: frontend
  template:
    metadata:
      labels:
        app: demo
        tier: frontend
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
          name: http
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 100m
            memory: 64Mi
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        configMap:
          name: frontend-html
```

### Step 3: Create Frontend HTML

Create `frontend-html-configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: frontend-html
  namespace: demo-app
data:
  index.html: |
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>RKE2 Demo Application</title>
        <style>
            body {
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                max-width: 800px;
                margin: 50px auto;
                padding: 20px;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh;
            }
            .container {
                background: white;
                border-radius: 10px;
                padding: 40px;
                box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            }
            h1 {
                color: #333;
                border-bottom: 3px solid #667eea;
                padding-bottom: 10px;
            }
            .success {
                background: #d4edda;
                color: #155724;
                padding: 15px;
                border-radius: 5px;
                margin: 20px 0;
            }
            .info {
                background: #e7f3ff;
                padding: 20px;
                border-radius: 5px;
                margin: 20px 0;
            }
            .api-status {
                margin-top: 20px;
                padding: 15px;
                background: #f8f9fa;
                border-radius: 5px;
            }
            .label {
                font-weight: bold;
                color: #555;
            }
            code {
                background: #f4f4f4;
                padding: 2px 6px;
                border-radius: 3px;
                font-family: 'Courier New', monospace;
            }
            button {
                background: #667eea;
                color: white;
                border: none;
                padding: 10px 20px;
                border-radius: 5px;
                cursor: pointer;
                font-size: 16px;
                margin-top: 10px;
            }
            button:hover {
                background: #5568d3;
            }
            #api-response {
                margin-top: 15px;
                padding: 10px;
                background: #f0f0f0;
                border-radius: 5px;
                display: none;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 RKE2 Demo Application</h1>
            
            <div class="success">
                ✅ <strong>Success!</strong> Your RKE2 cluster is working correctly!
            </div>
            
            <div class="info">
                <h2>How the Traffic Flows:</h2>
                <ol>
                    <li><strong>User Request</strong> → Ingress (Traefik)</li>
                    <li><strong>Ingress</strong> → Frontend Service (ClusterIP)</li>
                    <li><strong>Service</strong> → Frontend Pods (nginx)</li>
                </ol>
                
                <h3>Key Concepts Demonstrated:</h3>
                <ul>
                    <li><code>ClusterIP</code> - Internal service discovery</li>
                    <li><code>Ingress</code> - External HTTP routing</li>
                    <li><code>Deployment</code> - Pod management</li>
                    <li><code>ConfigMap</code> - Configuration injection</li>
                </ul>
            </div>
            
            <div class="api-status">
                <h2>API Status Check</h2>
                <p>Test the backend API service:</p>
                <button onclick="checkAPI()">Check API Status</button>
                <div id="api-response"></div>
            </div>
            
            <div class="api-status">
                <p class="label">Pod Name:</p>
                <p id="pod-name">Loading...</p>
                
                <p class="label">Node:</p>
                <p id="node-name">Loading...</p>
            </div>
        </div>
        
        <script>
        function checkAPI() {
            const responseDiv = document.getElementById('api-response');
            responseDiv.style.display = 'block';
            responseDiv.innerHTML = 'Checking...';
            
            fetch('/api/status')
                .then(response => response.json())
                .then(data => {
                    responseDiv.innerHTML = '<strong>API Response:</strong><br><pre>' + 
                        JSON.stringify(data, null, 2) + '</pre>';
                })
                .catch(error => {
                    responseDiv.innerHTML = '<strong>API Status:</strong> Not reachable via this demo. ' +
                        'In a real setup, the backend API would respond here.';
                });
        }
        
        // Display pod info (simulated - in real apps, this comes from the backend)
        document.getElementById('pod-name').textContent = 'frontend-' + Math.random().toString(36).substr(2, 9);
        document.getElementById('node-name').textContent = window.location.hostname;
        </script>
    </body>
    </html>
```

### Step 4: Apply Frontend Resources

```bash
# Apply all frontend resources
kubectl apply -f frontend-html-configmap.yaml
kubectl apply -f frontend-deployment.yaml

# Verify deployment
kubectl get deployments -n demo-app
kubectl get pods -n demo-app
```

---

## Deploy Backend API

### Step 1: Create Backend Deployment (v1)

Create `backend-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-v1
  namespace: demo-app
  labels:
    app: demo
    tier: backend
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo
      tier: backend
      version: v1
  template:
    metadata:
      labels:
        app: demo
        tier: backend
        version: v1
    spec:
      containers:
      - name: api
        image: hashicorp/http-echo:1.0
        args:
        - -text={"status":"healthy","version":"v1","message":"Hello from Backend API v1!","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
        - -listen=:8080
        ports:
        - containerPort: 8080
          name: http
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 50m
            memory: 32Mi
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
```

### Step 2: Apply Backend Resources

```bash
# Apply backend deployment
kubectl apply -f backend-deployment.yaml

# Verify
kubectl get deployments -n demo-app
kubectl get pods -n demo-app -l tier=backend
```

---

## Create ClusterIP Services

### Step 1: Create Frontend Service

Create `frontend-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: demo-app
  labels:
    app: demo
    tier: frontend
spec:
  type: ClusterIP
  selector:
    app: demo
    tier: frontend
  ports:
  - name: http
    port: 80        # Service port
    targetPort: 80  # Container port
    protocol: TCP
```

### Step 2: Create Backend Service

Create `backend-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: demo-app
  labels:
    app: demo
    tier: backend
spec:
  type: ClusterIP
  selector:
    app: demo
    tier: backend
  ports:
  - name: http
    port: 8080        # Service port
    targetPort: 8080  # Container port
    protocol: TCP
```

### Step 3: Apply Services

```bash
# Apply services
kubectl apply -f frontend-service.yaml
kubectl apply -f backend-service.yaml

# Verify services
kubectl get svc -n demo-app

# Describe service (see endpoints)
kubectl describe svc frontend -n demo-app
kubectl describe svc backend -n demo-app
```

### Step 4: Test Service Discovery

```bash
# Create a test pod to test internal DNS
kubectl run -it --rm --restart=Never test-dns --image=busybox:1.36 -- nslookup frontend.demo-app.svc.cluster.local

# Test service connectivity from inside cluster
kubectl run -it --rm --restart=Never test-curl --image=curlimages/curl:8.5.0 -- curl http://frontend.demo-app

# Test backend service
kubectl run -it --rm --restart=Never test-curl --image=curlimages/curl:8.5.0 -- curl http://backend.demo-app:8080
```

---

## Configure Ingress

### Step 1: Understand Traefik Ingress

RKE2 comes with Traefik as the default Ingress Controller. Traefik:
- Listens on ports 80 and 443
- Routes traffic based on Ingress rules
- Supports path-based and host-based routing

### Step 2: Check Ingress Class

```bash
# List ingress classes
kubectl get ingressclass

# Should show 'traefik' as default
```

### Step 3: Create Ingress Resource

Create `demo-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-ingress
  namespace: demo-app
  annotations:
    # Traefik specific annotations (optional)
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  # Host-based routing (recommended for production)
  - host: demo.local
    http:
      paths:
      # Route / to frontend service
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
      # Route /api to backend service
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: backend
            port:
              number: 8080
---
# Alternative: Path-based routing without specific host
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-ingress-path
  namespace: demo-app
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - http:
      paths:
      # Route /demo/ to frontend
      - path: /demo
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
      # Route /api to backend
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: backend
            port:
              number: 8080
```

### Step 4: Apply Ingress

```bash
# Apply ingress
kubectl apply -f demo-ingress.yaml

# Verify ingress
kubectl get ingress -n demo-app

# Describe ingress
kubectl describe ingress demo-ingress -n demo-app
```

### Step 5: Check Traefik Service

```bash
# Check Traefik service
kubectl get svc -n kube-system traefik

# Check Traefik pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# Check Traefik logs
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik
```

---

## Test the Application

### Method 1: Port Forward (Easiest)

Port forwarding allows you to access services locally without exposing them:

```bash
# Port forward to Traefik (ingress controller)
kubectl port-forward -n kube-system svc/traefik 8080:80

# In another terminal, test:
curl http://localhost:8080/demo/

# Or open in browser:
# http://localhost:8080/demo/
```

### Method 2: NodePort

Create a NodePort service to expose Traefik:

```bash
# Check if Traefik is already exposed via NodePort
kubectl get svc -n kube-system traefik -o jsonpath='{.spec.type}'

# If not, patch it:
kubectl patch svc traefik -n kube-system -p '{"spec":{"type":"NodePort"}}'

# Get the NodePort
NODE_PORT=$(kubectl get svc -n kube-system traefik -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}')
echo "NodePort: $NODE_PORT"

# Access via:
curl http://<PUBLIC_IP>:$NODE_PORT/demo/
```

### Method 3: LoadBalancer (AWS)

For AWS, you can create a LoadBalancer service:

```yaml
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
```

```bash
kubectl apply -f traefik-lb.yaml

# Get LoadBalancer hostname
kubectl get svc -n kube-system traefik-lb

# Wait for AWS to provision the load balancer (1-2 minutes)
# Then access:
# http://<LB-HOSTNAME>/demo/
```

### Method 4: Add /etc/hosts Entry

For host-based routing (`demo.local`):

```bash
# On your local machine, add to /etc/hosts (Linux/Mac) or C:\Windows\System32\drivers\etc\hosts (Windows)

# Get EC2 public IP
PUBLIC_IP=<YOUR_EC2_PUBLIC_IP>

# Add entry
echo "$PUBLIC_IP demo.local" | sudo tee -a /etc/hosts

# Now access:
# http://demo.local/
```

---

## Understanding the Flow

### Complete Traffic Flow

```
1. User opens browser to http://demo.local/
   |
2. DNS resolves demo.local to EC2 public IP (via /etc/hosts)
   |
3. Request hits AWS Security Group on port 80
   |
4. Request reaches EC2 instance
   |
5. Traefik Ingress Controller receives request on port 80
   |
6. Traefik checks Ingress rules for host=demo.local, path=/
   |
7. Rule matches! Route to service "frontend" in namespace "demo-app"
   |
8. Kubernetes DNS resolves "frontend.demo-app.svc.cluster.local" to ClusterIP
   |
9. Service "frontend" load balances to one of the frontend pods
   |
10. Pod returns HTML page
   |
11. Response travels back through the chain
   |
12. User sees "RKE2 Demo Application" page
```

### Verify Each Step

```bash
# Step 6: Check ingress rules
kubectl get ingress -n demo-app -o yaml

# Step 8: Check service DNS
kubectl run -it --rm --restart=Never test --image=busybox:1.36 -- nslookup frontend.demo-app.svc.cluster.local

# Step 9: Check service endpoints (pods)
kubectl get endpoints frontend -n demo-app

# Step 10: Check pod logs
kubectl logs -n demo-app -l tier=frontend
```

---

## Troubleshooting

### Ingress Not Working

```bash
# 1. Check Traefik is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# 2. Check Traefik service
kubectl get svc -n kube-system traefik

# 3. Check ingress resource
kubectl describe ingress -n demo-app

# 4. Check ingress controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik

# 5. Check if port 80 is accessible
curl -I http://<PUBLIC_IP>/
```

### Service Not Accessible

```bash
# 1. Check service exists
kubectl get svc -n demo-app

# 2. Check service has endpoints
kubectl get endpoints -n demo-app

# 3. Check pods are running
kubectl get pods -n demo-app

# 4. Test service from inside cluster
kubectl run -it --rm --restart=Never test --image=curlimages/curl:8.5.0 -- curl -v http://frontend.demo-app
```

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n demo-app -o wide

# Describe pod for events
kubectl describe pod -n demo-app <POD_NAME>

# Check pod logs
kubectl logs -n demo-app <POD_NAME>

# Check events in namespace
kubectl get events -n demo-app --sort-by='.lastTimestamp'
```

---

## Clean Up

```bash
# Delete all resources
kubectl delete -f demo-ingress.yaml
kubectl delete -f backend-service.yaml
kubectl delete -f frontend-service.yaml
kubectl delete -f backend-deployment.yaml
kubectl delete -f frontend-deployment.yaml
kubectl delete -f frontend-html-configmap.yaml

# Or delete entire namespace
kubectl delete namespace demo-app
```

---

## Next Steps

After successfully deploying this demo:
1. **Scale the application**: `kubectl scale deployment frontend --replicas=5 -n demo-app`
2. **Add TLS**: Configure HTTPS with cert-manager
3. **Add more backends**: Deploy backend-v2 and implement traffic splitting
4. **Add monitoring**: Deploy Prometheus/Grafana to monitor the application

---

## Summary

What we learned:

| Concept | What it does | Example |
|---------|--------------|---------|
| Deployment | Manages pods | `kubectl get deployments` |
| ClusterIP Service | Internal load balancing | `kubectl get svc` |
| Ingress | External routing | `kubectl get ingress` |
| ConfigMap | Configuration data | `kubectl get configmap` |
| Labels | Resource identification | `app: demo, tier: frontend` |

The key takeaway: **ClusterIP provides internal service discovery, Ingress provides external routing**.

Continue to: **[04-testing-verification.md](04-testing-verification.md)** for comprehensive testing procedures.
