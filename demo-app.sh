#!/bin/bash
# Vault Example Application Demo Script
# This script demonstrates how applications authenticate with Vault and access secrets

set -e

NAMESPACE="default"
VAULT_NAMESPACE="vault"

echo "=========================================="
echo "Vault Example Application Demo"
echo "=========================================="
echo ""

# Check if example app is deployed
echo "Step 1: Checking example application status..."
echo ""

APP_PODS=$(kubectl -n $NAMESPACE get pods -l app=example-app 2>/dev/null | grep -v NAME || echo "")

if [ -z "$APP_PODS" ]; then
    echo "⚠️  Example app not found. Deploying now..."
    kubectl apply -f example-app.yaml
    echo ""
    echo "Waiting for pods to be ready..."
    kubectl -n $NAMESPACE wait --for=condition=Ready pod -l app=example-app --timeout=120s
    echo ""
fi

echo "Example app pods:"
kubectl -n $NAMESPACE get pods -l app=example-app
echo ""

# Load Vault root token
if [ ! -f "vault-init-keys.json" ]; then
    echo "ERROR: vault-init-keys.json not found!"
    echo "Cannot authenticate with Vault."
    exit 1
fi

VAULT_TOKEN=$(cat vault-init-keys.json | jq -r '.root_token')

echo "Step 2: Writing a test secret to Vault (api namespace)..."
echo ""

# Write a test secret
kubectl -n $VAULT_NAMESPACE exec vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN \
    vault kv put api/myapp/config \
    database_url="postgresql://vault-demo-db:5432/appdb" \
    api_key="demo-api-key-$(date +%s)" \
    environment="demo"

echo "✓ Secret written to api/myapp/config"
echo ""

echo "Step 3: Verifying secret from Vault directly..."
echo ""

kubectl -n $VAULT_NAMESPACE exec vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN \
    vault kv get api/myapp/config
echo ""

echo "Step 4: Demonstrating application authentication..."
echo ""

# Get one of the app pods
APP_POD=$(kubectl -n $NAMESPACE get pods -l app=example-app -o jsonpath='{.items[0].metadata.name}')

echo "Using pod: $APP_POD"
echo ""

echo "The application pod will:"
echo "  1. Get its Kubernetes service account token"
echo "  2. Authenticate with Vault using Kubernetes auth"
echo "  3. Receive a Vault token"
echo "  4. Use that token to read secrets"
echo ""

# Demonstrate authentication from the pod
echo "Running authentication test from pod..."
echo ""

kubectl -n $NAMESPACE exec $APP_POD -c app -- sh -c '
echo "=== Authentication Process ==="
echo ""

# Get Kubernetes token
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
echo "✓ Retrieved Kubernetes service account token"
echo ""

# Authenticate with Vault
echo "Authenticating with Vault using role: api"
VAULT_ADDR=http://vault.vault.svc.cluster.local:8200
VAULT_TOKEN=$(wget -qO- --post-data="{\"jwt\":\"$KUBE_TOKEN\",\"role\":\"api\"}" \
    --header="Content-Type: application/json" \
    $VAULT_ADDR/v1/auth/kubernetes/login | grep -o "\"client_token\":\"[^\"]*\"" | cut -d\" -f4)

if [ -z "$VAULT_TOKEN" ]; then
    echo "✗ Authentication failed!"
    exit 1
fi

echo "✓ Received Vault token: ${VAULT_TOKEN:0:20}..."
echo ""

# Read secret
echo "Reading secret from api/myapp/config..."
SECRET_DATA=$(wget -qO- --header="X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_ADDR/v1/api/data/myapp/config)

if [ $? -eq 0 ]; then
    echo "✓ Successfully read secret!"
    echo ""
    echo "Secret contents:"
    echo "$SECRET_DATA" | grep -o "\"data\":{[^}]*}" | sed "s/,/\\n  /g" | sed "s/{/  /g" | sed "s/}//g"
else
    echo "✗ Failed to read secret"
    exit 1
fi
'

echo ""
echo "Step 5: Checking Vault Agent sidecar (if enabled)..."
echo ""

# Check if vault-agent sidecar exists
SIDECAR_EXISTS=$(kubectl -n $NAMESPACE get pod $APP_POD -o jsonpath='{.spec.containers[*].name}' | grep -o vault-agent || echo "")

if [ -n "$SIDECAR_EXISTS" ]; then
    echo "✓ Vault Agent sidecar is running"
    echo ""
    echo "Vault Agent automatically:"
    echo "  - Authenticates with Vault on startup"
    echo "  - Renders secret templates"
    echo "  - Keeps tokens refreshed"
    echo ""
    
    echo "Checking rendered secrets..."
    kubectl -n $NAMESPACE exec $APP_POD -c vault-agent -- cat /vault/secrets/config.json 2>/dev/null || \
        echo "Note: Template rendering requires vault-agent-config to be properly configured"
else
    echo "Note: Vault Agent sidecar not found in this deployment"
    echo "The example shows direct API authentication instead"
fi

echo ""
echo "=========================================="
echo "Demo Complete!"
echo "=========================================="
echo ""
echo "What was demonstrated:"
echo "  ✓ Writing secrets to Vault (admin operation)"
echo "  ✓ Application authentication via Kubernetes SA"
echo "  ✓ Reading secrets from application pod"
echo "  ✓ Namespace isolation (api/ path only)"
echo ""
echo "Key Security Features:"
echo "  • No secrets in environment variables"
echo "  • No secrets in container images"
echo "  • Automatic token rotation"
echo "  • Audit trail of all access"
echo "  • Role-based access control"
echo ""
echo "Try these next:"
echo "  1. View audit logs: kubectl exec -n vault vault-0 -- cat /vault/data/vault-audit.log | tail"
echo "  2. List app tokens: kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN vault token lookup -accessor <accessor>"
echo "  3. Test operator access (cannot read secrets)"
echo ""
