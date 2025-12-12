#!/bin/bash
# Fresh Cluster Deployment Script
# This script deploys Vault HA to a fresh LKE cluster

set -e

echo "=========================================="
echo "Vault HA Fresh Deployment"
echo "=========================================="
echo ""

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Prerequisites Check${NC}"
echo ""

# Check for kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} kubectl found"

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}✗ jq not found${NC}"
    echo "Install with: brew install jq  (Mac) or apt-get install jq (Linux)"
    exit 1
fi
echo -e "${GREEN}✓${NC} jq found"

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Connected to Kubernetes cluster"

echo ""
echo -e "${YELLOW}Step 1: Deploying Vault Infrastructure${NC}"
echo ""

# Check if files exist
for file in vault-statefulset.yaml vault-rbac.yaml vault-service-accounts.yaml; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}✗ Missing file: $file${NC}"
        exit 1
    fi
done

kubectl apply -f vault-statefulset.yaml
kubectl apply -f vault-rbac.yaml
kubectl apply -f vault-service-accounts.yaml

echo ""
echo -e "${GREEN}✓${NC} Infrastructure deployed"
echo ""
echo "Waiting for pods to start..."

# Wait for pods to be created
sleep 5

# Wait for all 3 pods to be running
echo "Waiting for 3 Vault pods to reach Running state..."
for i in {1..60}; do
    RUNNING=$(kubectl -n vault get pods -l app=vault 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$RUNNING" -eq 3 ]; then
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

if [ "$RUNNING" -ne 3 ]; then
    echo -e "${RED}✗ Not all pods are running after 2 minutes${NC}"
    echo "Check status with: kubectl -n vault get pods"
    exit 1
fi

echo -e "${GREEN}✓${NC} All 3 Vault pods are running"
echo ""

# Show pod status
kubectl -n vault get pods

echo ""
echo -e "${YELLOW}Step 2: Initializing Vault Cluster${NC}"
echo ""

# Check for init script and policies
if [ ! -f "vault-init.sh" ]; then
    echo -e "${RED}✗ vault-init.sh not found${NC}"
    exit 1
fi

for file in vault-policy-admin.hcl vault-policy-api.hcl vault-policy-operator.hcl; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}✗ Missing policy file: $file${NC}"
        exit 1
    fi
done

chmod +x vault-init.sh
./vault-init.sh

echo ""
echo -e "${GREEN}✓${NC} Vault initialized and configured"
echo ""

# Check if init keys were created
if [ ! -f "vault-init-keys.json" ]; then
    echo -e "${RED}✗ vault-init-keys.json was not created${NC}"
    exit 1
fi

echo -e "${YELLOW}⚠️  IMPORTANT: vault-init-keys.json contains your unseal keys and root token!${NC}"
echo "Store this file securely and delete the local copy after backing up."
echo ""

echo -e "${YELLOW}Step 3: Verifying Deployment${NC}"
echo ""

# Load root token
VAULT_TOKEN=$(cat vault-init-keys.json | jq -r '.root_token')

# Check Raft cluster
echo "Raft Cluster Status:"
kubectl -n vault exec vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN \
    vault operator raft list-peers

echo ""

# Check all pods are unsealed
echo "Seal Status:"
for i in 0 1 2; do
    SEALED=$(kubectl -n vault exec vault-$i -- vault status -format=json 2>/dev/null | jq -r '.sealed')
    if [ "$SEALED" = "false" ]; then
        echo -e "vault-$i: ${GREEN}Unsealed${NC}"
    else
        echo -e "vault-$i: ${RED}Sealed${NC}"
    fi
done

echo ""
echo -e "${GREEN}=========================================="
echo "✓ Vault HA Deployment Complete!"
echo "==========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Secure vault-init-keys.json"
echo "2. Deploy example app: kubectl apply -f example-app.yaml"
echo "3. Run demo: ./demo-app.sh"
echo ""
echo "Access Vault UI:"
echo "kubectl -n vault get svc vault"
echo ""
echo "Useful commands:"
echo "  make status     - Check cluster status"
echo "  make backup     - Create backup"
echo "  make logs       - View logs"
echo ""
