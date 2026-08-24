#!/bin/bash
#
# RKE2 Cluster Health Check Script
# Run this on the RKE2 server node to verify cluster health
#
# Usage:
#   chmod +x health-check.sh
#   ./health-check.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
WARN=0

# Test functions
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASS++))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAIL++))
}

warn() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
    ((WARN++))
}

info() {
    echo -e "${BLUE}ℹ INFO${NC}: $1"
}

# Set environment
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

echo "=========================================="
echo "    RKE2 Cluster Health Check"
echo "    $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo ""

# ============================================
# 1. RKE2 Service Status
# ============================================
echo -e "${BLUE}1. RKE2 Service Status${NC}"
echo "----------------------------------------"

if systemctl is-active --quiet rke2-server; then
    pass "RKE2 server service is running"
else
    fail "RKE2 server service is not running"
fi

if systemctl is-enabled --quiet rke2-server; then
    pass "RKE2 server service is enabled"
else
    warn "RKE2 server service is not enabled"
fi

echo ""

# ============================================
# 2. Node Status
# ============================================
echo -e "${BLUE}2. Node Status${NC}"
echo "----------------------------------------"

NODE_STATUS=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

if [[ "$NODE_STATUS" == "True" ]]; then
    pass "Node is Ready"
    kubectl get nodes -o wide
else
    fail "Node is not Ready (Status: $NODE_STATUS)"
fi

echo ""

# ============================================
# 3. System Pods
# ============================================
echo -e "${BLUE}3. System Pods${NC}"
echo "----------------------------------------"

SYSTEM_PODS=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l)
READY_PODS=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep "Running" | grep -v "0/" | wc -l)

if [[ $SYSTEM_PODS -eq $READY_PODS ]]; then
    pass "All system pods are running ($READY_PODS/$SYSTEM_PODS)"
else
    warn "Some system pods are not running ($READY_PODS/$SYSTEM_PODS)"
fi

kubectl get pods -n kube-system --no-headers | while read line; do
    POD_NAME=$(echo $line | awk '{print $1}')
    POD_STATUS=$(echo $line | awk '{print $3}')
    POD_READY=$(echo $line | awk '{print $2}')
    
    if [[ "$POD_STATUS" == "Running" && "$POD_READY" != *"0/"* ]]; then
        echo -e "  ${GREEN}✓${NC} $POD_NAME ($POD_STATUS - $POD_READY)"
    else
        echo -e "  ${RED}✗${NC} $POD_NAME ($POD_STATUS - $POD_READY)"
    fi
done

echo ""

# ============================================
# 4. Component Health
# ============================================
echo -e "${BLUE}4. Component Health${NC}"
echo "----------------------------------------"

# Check API server health
if kubectl get --raw='/healthz' > /dev/null 2>&1; then
    pass "API server is healthy"
else
    fail "API server is not healthy"
fi

# Check etcd health
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$ETCD_POD" ]]; then
    ETCD_STATUS=$(kubectl get pod -n kube-system $ETCD_POD -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "$ETCD_STATUS" == "Running" ]]; then
        pass "etcd pod is running"
    else
        fail "etcd pod is not running ($ETCD_STATUS)"
    fi
else
    warn "Could not find etcd pod"
fi

# Check scheduler
SCHEDULER_POD=$(kubectl get pods -n kube-system -l component=kube-scheduler -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$SCHEDULER_POD" ]]; then
    pass "Scheduler pod is running"
else
    warn "Could not find scheduler pod"
fi

# Check controller manager
CONTROLLER_POD=$(kubectl get pods -n kube-system -l component=kube-controller-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$CONTROLLER_POD" ]]; then
    pass "Controller manager pod is running"
else
    warn "Could not find controller manager pod"
fi

echo ""

# ============================================
# 5. Networking
# ============================================
echo -e "${BLUE}5. Networking${NC}"
echo "----------------------------------------"

# Check CNI pods
CNI_PODS=$(kubectl get pods -n kube-system -l k8s-app=canal --no-headers 2>/dev/null | wc -l)
CNI_READY=$(kubectl get pods -n kube-system -l k8s-app=canal --no-headers 2>/dev/null | grep "Running" | grep -v "0/" | wc -l)

if [[ $CNI_PODS -gt 0 && $CNI_PODS -eq $CNI_READY ]]; then
    pass "CNI (Canal) pods are running ($CNI_READY/$CNI_PODS)"
else
    fail "CNI (Canal) pods are not healthy ($CNI_READY/$CNI_PODS)"
fi

# Check CoreDNS
DNS_PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | wc -l)
DNS_READY=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep "Running" | grep -v "0/" | wc -l)

if [[ $DNS_PODS -gt 0 && $DNS_PODS -eq $DNS_READY ]]; then
    pass "CoreDNS pods are running ($DNS_READY/$DNS_PODS)"
else
    fail "CoreDNS pods are not healthy ($DNS_READY/$DNS_PODS)"
fi

# Test DNS resolution
DNS_TEST=$(kubectl run -it --rm --restart=Never dns-test-$$ --image=busybox:1.36 -- nslookup kubernetes.default 2>&1 | grep -c "Server:" || echo "0")

if [[ $DNS_TEST -gt 0 ]]; then
    pass "DNS resolution is working"
else
    warn "DNS resolution test skipped (or failed)"
fi

echo ""

# ============================================
# 6. Ingress Controller
# ============================================
echo -e "${BLUE}6. Ingress Controller${NC}"
echo "----------------------------------------"

# Check Traefik pods
TRAEFIK_PODS=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik --no-headers 2>/dev/null | wc -l)
TRAEFIK_READY=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik --no-headers 2>/dev/null | grep "Running" | grep -v "0/" | wc -l)

if [[ $TRAEFIK_PODS -gt 0 && $TRAEFIK_PODS -eq $TRAEFIK_READY ]]; then
    pass "Traefik ingress controller is running ($TRAEFIK_READY/$TRAEFIK_PODS)"
else
    warn "Traefik ingress controller is not running ($TRAEFIK_READY/$TRAEFIK_PODS)"
fi

# Check Traefik service
TRAEFIK_SVC=$(kubectl get svc -n kube-system traefik -o jsonpath='{.spec.type}' 2>/dev/null || echo "")

if [[ -n "$TRAEFIK_SVC" ]]; then
    info "Traefik service type: $TRAEFIK_SVC"
    
    if [[ "$TRAEFIK_SVC" == "LoadBalancer" ]]; then
        LB_HOSTNAME=$(kubectl get svc -n kube-system traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        if [[ -n "$LB_HOSTNAME" ]]; then
            info "LoadBalancer hostname: $LB_HOSTNAME"
        else
            warn "LoadBalancer hostname not yet assigned"
        fi
    fi
else
    warn "Traefik service not found"
fi

# Check ingress class
INGRESS_CLASS=$(kubectl get ingressclass traefik -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")

if [[ -n "$INGRESS_CLASS" ]]; then
    pass "Ingress class 'traefik' exists"
else
    warn "Ingress class 'traefik' not found"
fi

echo ""

# ============================================
# 7. Demo Application (if exists)
# ============================================
echo -e "${BLUE}7. Demo Application${NC}"
echo "----------------------------------------"

DEMO_NS=$(kubectl get namespace demo-app -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")

if [[ -n "$DEMO_NS" ]]; then
    pass "demo-app namespace exists"
    
    # Check frontend
    FRONTEND_PODS=$(kubectl get pods -n demo-app -l tier=frontend --no-headers 2>/dev/null | wc -l)
    FRONTEND_READY=$(kubectl get pods -n demo-app -l tier=frontend --no-headers 2>/dev/null | grep "Running" | grep -v "0/" | wc -l)
    
    if [[ $FRONTEND_PODS -gt 0 ]]; then
        info "Frontend pods: $FRONTEND_READY/$FRONTEND_PODS ready"
    fi
    
    # Check backend
    BACKEND_PODS=$(kubectl get pods -n demo-app -l tier=backend --no-headers 2>/dev/null | wc -l)
    BACKEND_READY=$(kubectl get pods -n demo-app -l tier=backend --no-headers 2>/dev/null | grep "Running" | grep -v "0/" | wc -l)
    
    if [[ $BACKEND_PODS -gt 0 ]]; then
        info "Backend pods: $BACKEND_READY/$BACKEND_PODS ready"
    fi
    
    # Check services
    SERVICES=$(kubectl get svc -n demo-app --no-headers 2>/dev/null | wc -l)
    if [[ $SERVICES -gt 0 ]]; then
        info "Services found: $SERVICES"
    fi
    
    # Check ingress
    INGRESSES=$(kubectl get ingress -n demo-app --no-headers 2>/dev/null | wc -l)
    if [[ $INGRESSES -gt 0 ]]; then
        info "Ingress resources found: $INGRESSES"
    fi
else
    info "demo-app namespace not found (not deployed yet)"
fi

echo ""

# ============================================
# 8. Resource Usage
# ============================================
echo -e "${BLUE}8. Resource Usage${NC}"
echo "----------------------------------------"

# Check if metrics server is available
if kubectl top nodes > /dev/null 2>&1; then
    echo "Node Resources:"
    kubectl top nodes
    echo ""
    echo "Top Pods:"
    kubectl top pods -A --sort-by=memory | head -6
else
    info "Metrics server not available (kubectl top commands won't work)"
fi

# Check disk usage
echo ""
echo "Disk Usage (node):"
df -h /var/lib/rancher | tail -1

echo ""

# ============================================
# 9. Summary
# ============================================
echo "=========================================="
echo "               SUMMARY"
echo "=========================================="
echo ""
echo -e "  ${GREEN}Passed:${NC}   $PASS"
echo -e "  ${RED}Failed:${NC}   $FAIL"
echo -e "  ${YELLOW}Warnings:${NC} $WARN"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}✓ Cluster is healthy!${NC}"
    exit 0
else
    echo -e "${RED}✗ Cluster has issues. Check the failed tests above.${NC}"
    exit 1
fi
