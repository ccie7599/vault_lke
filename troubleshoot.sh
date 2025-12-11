#!/bin/bash
set -e

echo "=== Vault Startup Troubleshooting Script ==="
echo ""

NAMESPACE="vault"

# Check pod status
echo "1. Checking pod status..."
kubectl -n $NAMESPACE get pods
echo ""

# Count running pods
RUNNING_PODS=$(kubectl -n $NAMESPACE get pods -l app=vault --no-headers 2>/dev/null | grep -c "Running" || echo "0")
TOTAL_PODS=$(kubectl -n $NAMESPACE get pods -l app=vault --no-headers 2>/dev/null | wc -l || echo "0")

echo "Running pods: $RUNNING_PODS / Expected: 3"
echo ""

if [ "$RUNNING_PODS" -lt 3 ]; then
    echo "⚠️  Not all pods are running yet. StatefulSets create pods sequentially."
    echo "This is normal. The DNS errors you see are because vault-1 and vault-2"
    echo "don't exist yet while vault-0 is trying to join them."
    echo ""
    echo "Wait for all 3 pods to be in Running state before proceeding."
    echo "You can watch with: kubectl -n vault get pods -w"
    echo ""
fi

# Check RBAC issue
echo "2. Checking for RBAC permission issues..."
RBAC_ERRORS=$(kubectl -n $NAMESPACE logs vault-0 2>/dev/null | grep -c "403" || echo "0")

if [ "$RBAC_ERRORS" -gt 0 ]; then
    echo "⚠️  RBAC permission issue detected!"
    echo ""
    echo "The Vault service account needs permission to update pods."
    echo "This is required for Kubernetes service registration."
    echo ""
    echo "Fix: Apply the corrected RBAC configuration:"
    echo "  kubectl apply -f vault-rbac-fixed.yaml"
    echo ""
    
    if [ -f "vault-rbac-fixed.yaml" ]; then
        read -p "Apply the fix now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl apply -f vault-rbac-fixed.yaml
            echo "✓ RBAC permissions updated!"
            echo ""
            echo "Restarting vault-0 to apply the fix..."
            kubectl -n $NAMESPACE delete pod vault-0
            echo "Waiting for vault-0 to restart..."
            sleep 5
            kubectl -n $NAMESPACE wait --for=condition=Ready pod/vault-0 --timeout=120s || true
            echo ""
        fi
    fi
else
    echo "✓ No RBAC issues detected"
    echo ""
fi

# Check if pods are sealed (expected)
echo "3. Checking Vault seal status..."
if [ "$RUNNING_PODS" -gt 0 ]; then
    for i in $(seq 0 $((RUNNING_PODS-1))); do
        POD_NAME="vault-$i"
        echo "Checking $POD_NAME..."
        
        SEALED=$(kubectl -n $NAMESPACE exec $POD_NAME -- vault status -format=json 2>/dev/null | jq -r '.sealed // "unknown"' || echo "unknown")
        INITIALIZED=$(kubectl -n $NAMESPACE exec $POD_NAME -- vault status -format=json 2>/dev/null | jq -r '.initialized // "unknown"' || echo "unknown")
        
        echo "  Initialized: $INITIALIZED"
        echo "  Sealed: $SEALED"
    done
    echo ""
    
    if [ "$INITIALIZED" = "false" ]; then
        echo "Vault is not initialized yet. This is expected on first deployment."
        echo ""
    fi
fi

# Check DNS resolution from pod
echo "4. Checking DNS resolution from vault-0..."
if kubectl -n $NAMESPACE get pod vault-0 >/dev/null 2>&1; then
    echo "Testing DNS resolution for vault-internal service..."
    
    for i in 0 1 2; do
        HOST="vault-$i.vault-internal"
        RESULT=$(kubectl -n $NAMESPACE exec vault-0 -- nslookup $HOST 2>&1 | grep -c "can't resolve" || echo "0")
        if [ "$RESULT" -eq 0 ]; then
            echo "  ✓ $HOST resolves"
        else
            echo "  ✗ $HOST does not resolve (pod may not exist yet)"
        fi
    done
    echo ""
fi

# Check headless service
echo "5. Checking headless service configuration..."
kubectl -n $NAMESPACE get svc vault-internal -o yaml | grep -A 3 "clusterIP:"
echo ""

# Next steps
echo "=== Summary and Next Steps ==="
echo ""

if [ "$RUNNING_PODS" -lt 3 ]; then
    echo "1. Wait for all 3 pods to reach Running state"
    echo "   Command: kubectl -n vault get pods -w"
    echo ""
elif [ "$RBAC_ERRORS" -gt 0 ]; then
    echo "1. Apply RBAC fix if not already done"
    echo "   Command: kubectl apply -f vault-rbac-fixed.yaml"
    echo "2. Restart pods to apply changes"
    echo "   Command: kubectl -n vault delete pod --all"
    echo ""
else
    echo "✓ All pods are running and RBAC looks good!"
    echo ""
    echo "Next step: Initialize Vault"
    echo "  Run: ./vault-init.sh"
    echo ""
    echo "Or manually initialize vault-0:"
    echo "  kubectl -n vault exec vault-0 -- vault operator init"
    echo ""
fi

echo "You can check logs with:"
echo "  kubectl -n vault logs vault-0"
echo "  kubectl -n vault logs vault-0 -f  # follow mode"
echo ""
