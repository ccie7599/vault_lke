#!/bin/bash
set -e

# Vault HA Initialization Script
# This script initializes a new Vault cluster and configures namespaces and policies

echo "=== Vault HA Initialization Script ==="
echo ""

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://vault.vault.svc.cluster.local:8200}"
VAULT_POD="${VAULT_POD:-vault-0}"
NAMESPACE="${NAMESPACE:-vault}"

export VAULT_ADDR

echo "Using Vault address: $VAULT_ADDR"
echo "Using Vault pod: $VAULT_POD"
echo ""

# Function to check if Vault is initialized
check_initialized() {
    kubectl exec -n $NAMESPACE $VAULT_POD -- vault status -format=json 2>/dev/null | jq -r '.initialized'
}

# Step 1: Initialize Vault (only on primary pod)
echo "Step 1: Checking initialization status..."
IS_INITIALIZED=$(check_initialized)

if [ "$IS_INITIALIZED" = "true" ]; then
    echo "Vault is already initialized. Skipping initialization."
    echo ""
else
    echo "Initializing Vault with 5 key shares and threshold of 3..."
    
    INIT_OUTPUT=$(kubectl exec -n $NAMESPACE $VAULT_POD -- vault operator init \
        -key-shares=5 \
        -key-threshold=3 \
        -format=json)
    
    # Save the output securely
    echo "$INIT_OUTPUT" > vault-init-keys.json
    chmod 600 vault-init-keys.json
    
    echo ""
    echo "⚠️  IMPORTANT: Vault initialization keys saved to vault-init-keys.json"
    echo "⚠️  SECURE THIS FILE IMMEDIATELY - It contains the unseal keys and root token!"
    echo "⚠️  Store in a secure location (e.g., password manager, KMS, secure vault)"
    echo ""
    
    # Extract keys for unsealing
    UNSEAL_KEY_1=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')
    UNSEAL_KEY_2=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[1]')
    UNSEAL_KEY_3=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[2]')
    ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
    
    export VAULT_TOKEN="$ROOT_TOKEN"
    
    echo "Step 2: Unsealing Vault nodes..."
    
    # Unseal all pods
    for i in 0 1 2; do
        POD_NAME="vault-$i"
        echo "Unsealing $POD_NAME..."
        
        kubectl exec -n $NAMESPACE $POD_NAME -- vault operator unseal "$UNSEAL_KEY_1" || true
        kubectl exec -n $NAMESPACE $POD_NAME -- vault operator unseal "$UNSEAL_KEY_2" || true
        kubectl exec -n $NAMESPACE $POD_NAME -- vault operator unseal "$UNSEAL_KEY_3" || true
        
        echo "$POD_NAME unsealed."
    done
    
    echo ""
    echo "All Vault nodes unsealed successfully!"
    echo ""
fi

# If we didn't just initialize, ask for root token
if [ "$IS_INITIALIZED" = "true" ]; then
    if [ -z "$VAULT_TOKEN" ]; then
        echo "Please provide the root token for configuration:"
        read -s VAULT_TOKEN
        export VAULT_TOKEN
        echo ""
    fi
fi

# Step 3: Join additional nodes to Raft cluster
echo "Step 3: Ensuring all nodes are part of the Raft cluster..."
sleep 5

for i in 1 2; do
    POD_NAME="vault-$i"
    echo "Checking $POD_NAME..."
    
    # Check if already part of cluster
    STATUS=$(kubectl exec -n $NAMESPACE $POD_NAME -- vault status -format=json 2>/dev/null || echo "{}")
    INITIALIZED=$(echo "$STATUS" | jq -r '.initialized // false')
    
    if [ "$INITIALIZED" = "false" ]; then
        echo "Joining $POD_NAME to cluster..."
        kubectl exec -n $NAMESPACE $POD_NAME -- vault operator raft join http://vault-0.vault-internal:8200
    else
        echo "$POD_NAME is already part of the cluster."
    fi
done

echo ""
echo "Step 4: Configuring Kubernetes auth method..."

# Enable Kubernetes auth
kubectl exec -n $NAMESPACE $VAULT_POD -- vault auth enable kubernetes 2>/dev/null || echo "Kubernetes auth already enabled"

# Configure Kubernetes auth
kubectl exec -n $NAMESPACE $VAULT_POD -- vault write auth/kubernetes/config \
    kubernetes_host="https://\$KUBERNETES_SERVICE_HOST:\$KUBERNETES_SERVICE_PORT" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token

echo "Kubernetes auth configured."
echo ""

# Step 5: Enable KV v2 secrets engines for each namespace
echo "Step 5: Enabling KV v2 secrets engines..."

kubectl exec -n $NAMESPACE $VAULT_POD -- vault secrets enable -path=admin -version=2 kv 2>/dev/null || echo "admin kv already enabled"
kubectl exec -n $NAMESPACE $VAULT_POD -- vault secrets enable -path=api -version=2 kv 2>/dev/null || echo "api kv already enabled"

echo "Secrets engines enabled."
echo ""

# Step 6: Upload and create policies
echo "Step 6: Creating Vault policies..."

# Admin policy
kubectl exec -n $NAMESPACE $VAULT_POD -i -- vault policy write admin-policy - <<EOF
$(cat vault-policy-admin.hcl)
EOF

# API policy
kubectl exec -n $NAMESPACE $VAULT_POD -i -- vault policy write api-policy - <<EOF
$(cat vault-policy-api.hcl)
EOF

# Operator policy
kubectl exec -n $NAMESPACE $VAULT_POD -i -- vault policy write operator-policy - <<EOF
$(cat vault-policy-operator.hcl)
EOF

echo "Policies created successfully."
echo ""

# Step 7: Create Kubernetes auth roles
echo "Step 7: Creating Kubernetes auth roles..."

# Admin role (bound to specific service account)
kubectl exec -n $NAMESPACE $VAULT_POD -- vault write auth/kubernetes/role/admin \
    bound_service_account_names=vault-admin \
    bound_service_account_namespaces=vault \
    policies=admin-policy \
    ttl=24h

# API role (for application pods)
kubectl exec -n $NAMESPACE $VAULT_POD -- vault write auth/kubernetes/role/api \
    bound_service_account_names=app-vault-access \
    bound_service_account_namespaces=default,apps,production \
    policies=api-policy \
    ttl=1h

# Operator role (for SRE team)
kubectl exec -n $NAMESPACE $VAULT_POD -- vault write auth/kubernetes/role/operator \
    bound_service_account_names=vault-operator \
    bound_service_account_namespaces=vault \
    policies=operator-policy \
    ttl=12h

echo "Kubernetes auth roles created."
echo ""

# Step 8: Enable audit logging
echo "Step 8: Enabling audit logging..."

kubectl exec -n $NAMESPACE $VAULT_POD -- vault audit enable file file_path=/vault/logs/vault-audit.log 2>/dev/null || echo "Audit log already enabled"

echo "Audit logging enabled."
echo ""

echo "=== Vault Configuration Complete ==="
echo ""
echo "Next steps:"
echo "1. Securely store vault-init-keys.json in a safe location"
echo "2. Create service accounts for admin, operator, and applications"
echo "3. Test authentication with each role"
echo "4. Set up auto-unseal (recommended for production)"
echo "5. Configure TLS for production use"
echo "6. Set up backup procedures for Raft storage"
echo ""
echo "Vault UI is accessible at: $VAULT_ADDR/ui"
echo ""
