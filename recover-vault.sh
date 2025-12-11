#!/bin/bash
# Manual Recovery Script
# Use this to complete the setup since vault-0 is already initialized

set -e

NAMESPACE="vault"

echo "=== Vault Raft Recovery Script ==="
echo ""
echo "This will complete the Raft cluster setup."
echo ""

# Check if we have the init keys
if [ ! -f "vault-init-keys.json" ]; then
    echo "ERROR: vault-init-keys.json not found!"
    echo "This file should have been created during initialization."
    exit 1
fi

# Load keys
UNSEAL_KEY_1=$(cat vault-init-keys.json | jq -r '.unseal_keys_b64[0]')
UNSEAL_KEY_2=$(cat vault-init-keys.json | jq -r '.unseal_keys_b64[1]')
UNSEAL_KEY_3=$(cat vault-init-keys.json | jq -r '.unseal_keys_b64[2]')
ROOT_TOKEN=$(cat vault-init-keys.json | jq -r '.root_token')

export VAULT_TOKEN=$ROOT_TOKEN

echo "Step 1: Checking vault-0 status..."
kubectl exec -n $NAMESPACE vault-0 -e VAULT_TOKEN=$VAULT_TOKEN -- vault status
echo ""

echo "Step 2: Joining vault-1 to Raft cluster..."
kubectl exec -n $NAMESPACE vault-1 -- \
    vault operator raft join http://vault-0.vault-internal:8200

echo "Unsealing vault-1..."
kubectl exec -n $NAMESPACE vault-1 -- vault operator unseal "$UNSEAL_KEY_1"
kubectl exec -n $NAMESPACE vault-1 -- vault operator unseal "$UNSEAL_KEY_2"
kubectl exec -n $NAMESPACE vault-1 -- vault operator unseal "$UNSEAL_KEY_3"
echo "✓ vault-1 joined and unsealed"
echo ""

echo "Step 3: Joining vault-2 to Raft cluster..."
kubectl exec -n $NAMESPACE vault-2 -- \
    vault operator raft join http://vault-0.vault-internal:8200

echo "Unsealing vault-2..."
kubectl exec -n $NAMESPACE vault-2 -- vault operator unseal "$UNSEAL_KEY_1"
kubectl exec -n $NAMESPACE vault-2 -- vault operator unseal "$UNSEAL_KEY_2"
kubectl exec -n $NAMESPACE vault-2 -- vault operator unseal "$UNSEAL_KEY_3"
echo "✓ vault-2 joined and unsealed"
echo ""

echo "Step 4: Verifying Raft cluster..."
kubectl exec -n $NAMESPACE vault-0 -e VAULT_TOKEN=$VAULT_TOKEN -- \
    vault operator raft list-peers
echo ""

echo "Step 5: Configuring Kubernetes auth..."
kubectl exec -n $NAMESPACE vault-0 -e VAULT_TOKEN=$VAULT_TOKEN -- \
    vault auth enable kubernetes 2>/dev/null || echo "Already enabled"

kubectl exec -n $NAMESPACE vault-0 -e VAULT_TOKEN=$VAULT_TOKEN -- \
    vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token

echo "✓ Kubernetes auth configured"
echo ""

echo "Step 6: Enabling secrets engines..."
kubectl exec -n $NAMESPACE vault-0 -e VAULT_TOKEN=$VAULT_TOKEN -- \
    vault secrets enable -path=admin -version=2 kv 2>/dev/null || echo "admin kv already enabled"

kubectl exec -n $NAMESPACE vault-0 -e VAULT_TOKEN=$VAULT_TOKEN -- \
    vault secrets enable -path=api -version=2 kv 2>/dev/null || echo "api kv already enabled"

echo "✓ Secrets engines enabled"
echo ""

echo "Step 7: Creating policies..."
if [ -f "vault-policy-admin.hcl" ]; then
    cat vault-policy-admin.hcl | kubectl exec -n $NAMESPACE vault-0 -e VAULT_TOKEN=$VAULT_TOKEN -i -- \
        vault policy write admin-policy -
    echo "✓ Admin policy created"
fi

if [ -f "vault-policy-api.hcl" ]; then
    cat vault-policy-api.hcl | kubectl exec -n $NAMESPACE vault-0 -e VAULT_TOKEN=$VAULT_TOKEN -i -- \
        vault policy write api-policy -
    echo "✓ API policy created"
fi

if [ -f "vault-policy-operator.hcl" ]; then
    cat vault-policy-operator.hcl | kubectl exec -n $NAMESPACE vault-0 -e VAULT_TOKEN=$VAULT_TOKEN -i -- \
        vault policy write operator-policy -
    echo "✓ Operator policy created"
fi
echo ""

echo "Step 8: Creating Kubernetes auth roles..."
kubectl exec -n $NAMESPACE vault-0 -e VAULT_TOKEN=$VAULT_TOKEN -- \
    vault write auth/kubernetes/role/admin \
    bound_service_account_names=vault-admin \
    bound_service_account_namespaces=vault \
    policies=admin-policy \
    ttl=24h

kubectl exec -n $NAMESPACE vault-0 -e VAULT_TOKEN=$VAULT_TOKEN -- \
    vault write auth/kubernetes/role/api \
    bound_service_account_names=app-vault-access \
    bound_service_account_namespaces=default,apps,production \
    policies=api-policy \
    ttl=1h

kubectl exec -n $NAMESPACE vault-0 -e VAULT_TOKEN=$VAULT_TOKEN -- \
    vault write auth/kubernetes/role/operator \
    bound_service_account_names=vault-operator \
    bound_service_account_namespaces=vault \
    policies=operator-policy \
    ttl=12h

echo "✓ Auth roles created"
echo ""

echo "Step 9: Enabling audit logging..."
kubectl exec -n $NAMESPACE vault-0 -e VAULT_TOKEN=$VAULT_TOKEN -- \
    vault audit enable file file_path=/vault/data/vault-audit.log 2>/dev/null || echo "Already enabled"

echo ""
echo "=== Recovery Complete ==="
echo ""
echo "Final cluster status:"
for i in 0 1 2; do
    echo "--- vault-$i ---"
    kubectl exec -n $NAMESPACE vault-$i -e VAULT_TOKEN=$VAULT_TOKEN -- vault status | grep -E "(Sealed|HA Mode|Cluster Name)"
    echo ""
done

echo "✓ All nodes are part of the Raft cluster!"
echo ""
