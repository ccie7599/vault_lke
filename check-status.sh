#!/bin/bash
# Quick status check and token helper

NAMESPACE="vault"

echo "=== Vault Status Check ==="
echo ""

# Check if init keys exist
if [ ! -f "vault-init-keys.json" ]; then
    echo "ERROR: vault-init-keys.json not found!"
    echo "This file should have been created during initialization."
    exit 1
fi

# Extract root token
ROOT_TOKEN=$(cat vault-init-keys.json | jq -r '.root_token')

echo "Root token loaded from vault-init-keys.json"
echo ""
echo "To use Vault CLI commands, set this environment variable:"
echo ""
echo "export VAULT_TOKEN=$ROOT_TOKEN"
echo ""
echo "Then you can run commands like:"
echo "  kubectl -n vault exec vault-0 -- env VAULT_TOKEN=\$VAULT_TOKEN vault operator raft list-peers"
echo "  kubectl -n vault exec vault-0 -- env VAULT_TOKEN=\$VAULT_TOKEN vault status"
echo ""

# Check pod status
echo "=== Pod Status ==="
kubectl -n $NAMESPACE get pods
echo ""

# Check each pod's seal status (doesn't require auth)
echo "=== Seal Status (no auth required) ==="
for i in 0 1 2; do
    echo "--- vault-$i ---"
    kubectl -n $NAMESPACE exec vault-$i -- vault status 2>&1 | grep -E "(Sealed|Initialized|HA Enabled|HA Mode)" || echo "Could not get status"
    echo ""
done

echo "=== Quick Commands ==="
echo ""
echo "Export the token in your shell:"
echo "  export VAULT_TOKEN=$ROOT_TOKEN"
echo ""
echo "Then run recovery script:"
echo "  ./recover-vault-fixed.sh"
echo ""
