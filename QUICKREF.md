# Vault Quick Reference Guide

## Daily Operations

### Check Vault Status
```bash
# Overall status (requires token for full details)
kubectl -n vault exec vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN vault status

# Check all pods
for i in 0 1 2; do 
  echo "=== vault-$i ===" 
  kubectl -n vault exec vault-$i -- vault status
done
```

### Unseal Vault (Manual)
```bash
# Unseal all nodes (requires 3 of 5 keys)
for i in 0 1 2; do
  kubectl -n vault exec vault-$i -- vault operator unseal <KEY1>
  kubectl -n vault exec vault-$i -- vault operator unseal <KEY2>
  kubectl -n vault exec vault-$i -- vault operator unseal <KEY3>
done
```

### Access Logs
```bash
# Container logs
kubectl -n vault logs vault-0
kubectl -n vault logs -f vault-0  # Follow

# Audit logs (from within pod)
kubectl -n vault exec vault-0 -- cat /vault/logs/vault-audit.log
```

## Authentication

### Admin Login
```bash
export VAULT_ADDR=http://<vault-ip>:8200
export VAULT_TOKEN=<admin-token>
# For kubectl exec commands, pass token explicitly:
kubectl -n vault exec vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN vault <command>
```

### Kubernetes Auth (from pod)
```bash
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
VAULT_TOKEN=$(vault write -field=token auth/kubernetes/login \
  role=api \
  jwt=$KUBE_TOKEN)
```

### Create New Token
```bash
# Admin token
vault token create -policy=admin-policy -ttl=24h

# API token
vault token create -policy=api-policy -ttl=1h

# Operator token
vault token create -policy=operator-policy -ttl=12h
```

## Secret Management

### Admin Namespace Operations
```bash
# Write secret
vault kv put admin/database/root \
  username=root \
  password=supersecret

# Read secret
vault kv get admin/database/root

# List secrets
vault kv list admin/

# Delete secret
vault kv delete admin/database/root

# Destroy all versions
vault kv destroy -versions=1,2,3 admin/database/root
```

### API Namespace Operations
```bash
# Write application config
vault kv put api/myapp/config \
  database_url=postgres://host/db \
  api_key=key123

# Read secret
vault kv get api/myapp/config

# Get specific field
vault kv get -field=api_key api/myapp/config

# Create secret with metadata
vault kv put api/myapp/config \
  database_url=postgres://host/db \
  api_key=key123
vault kv metadata put -custom-metadata=owner=team-a api/myapp/config
```

## Policy Management

### List Policies
```bash
vault policy list
```

### Read Policy
```bash
vault policy read admin-policy
vault policy read api-policy
vault policy read operator-policy
```

### Update Policy
```bash
vault policy write admin-policy /path/to/admin-policy.hcl
```

### Test Policy
```bash
# Check capabilities
vault token capabilities admin/data/test
vault token capabilities api/data/myapp/config
```

## Auth Method Management (Operator Tasks)

### List Auth Methods
```bash
vault auth list
```

### Create New Kubernetes Role
```bash
vault write auth/kubernetes/role/new-app \
  bound_service_account_names=new-app-sa \
  bound_service_account_namespaces=production \
  policies=api-policy \
  ttl=1h \
  max_ttl=24h
```

### Update Existing Role
```bash
vault write auth/kubernetes/role/api \
  bound_service_account_names=app-vault-access \
  bound_service_account_namespaces=default,apps,production \
  policies=api-policy \
  ttl=2h
```

### Delete Role
```bash
vault delete auth/kubernetes/role/old-app
```

## Monitoring and Health

### Check Leader
```bash
vault operator raft list-peers
vault read sys/leader
```

### View Metrics
```bash
# JSON format
vault read sys/metrics

# Prometheus format
curl http://vault:8200/v1/sys/metrics?format=prometheus
```

### Check Seal Status
```bash
vault read sys/seal-status
```

### Audit Logs
```bash
vault audit list
vault audit enable file file_path=/vault/logs/audit.log
vault audit disable file/
```

## Backup and Recovery

### Create Snapshot
```bash
# Take snapshot
kubectl -n vault exec vault-0 -- vault operator raft snapshot save /tmp/backup.snap

# Download snapshot
kubectl -n vault cp vault-0:/tmp/backup.snap ./backup-$(date +%Y%m%d-%H%M%S).snap
```

### Restore Snapshot
```bash
# Upload snapshot
kubectl -n vault cp backup.snap vault-0:/tmp/backup.snap

# Restore (requires Vault to be sealed or no leader)
kubectl -n vault exec vault-0 -- vault operator raft snapshot restore -force /tmp/backup.snap
```

## Troubleshooting Commands

### Seal/Unseal Status
```bash
# Check if sealed
kubectl -n vault exec vault-0 -- vault status | grep Sealed

# Get unseal progress
kubectl -n vault exec vault-0 -- vault status | grep Progress
```

### Force Leader Election
```bash
# Step down as leader (force new election)
kubectl -n vault exec vault-0 -- vault operator step-down
```

### Remove Dead Node
```bash
# List peers
kubectl -n vault exec vault-0 -- vault operator raft list-peers

# Remove peer
kubectl -n vault exec vault-0 -- vault operator raft remove-peer vault-2
```

### Rejoin Node
```bash
# Join cluster
kubectl -n vault exec vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
```

### Token Lookup
```bash
# Look up current token
vault token lookup

# Look up specific token
vault token lookup <token>

# Revoke token
vault token revoke <token>
```

### Lease Management
```bash
# List leases
vault list sys/leases/lookup/api/data/

# Revoke lease
vault lease revoke <lease-id>

# Revoke all leases under path
vault lease revoke -prefix api/
```

## Performance Tuning

### Increase Cache Size
```bash
# Read current cache
kubectl -n vault exec vault-0 -- vault read sys/config/ui

# Update (requires restart)
# Edit ConfigMap and add to HCL:
# default_lease_ttl = "768h"
# max_lease_ttl = "8760h"
```

### Check Performance Stats
```bash
vault read sys/metrics
vault read sys/internal/counters/requests
```

## Security Operations

### Rotate Encryption Key
```bash
vault operator rotate
```

### Rekey Vault
```bash
# Start rekey
vault operator rekey -init -key-shares=5 -key-threshold=3

# Provide old keys and receive new keys
vault operator rekey -target=barrier <old-key>
```

### Seal Vault (Emergency)
```bash
# Seal immediately (requires unseal to use again)
kubectl -n vault exec vault-0 -- vault operator seal
```

## Common Error Resolutions

### "permission denied" errors
```bash
# Check token capabilities
vault token capabilities <path>

# Verify policy is attached
vault token lookup | grep policies

# Check policy definition
vault policy read <policy-name>
```

### "no leader" errors
```bash
# Check Raft peers
vault operator raft list-peers

# Check pod connectivity
kubectl -n vault exec vault-0 -- nc -zv vault-1.vault-internal 8201
```

### Storage issues
```bash
# Check PVC status
kubectl -n vault get pvc

# Check disk usage in pod
kubectl -n vault exec vault-0 -- df -h /vault/data
```

## Useful Aliases

Add to your `.bashrc` or `.zshrc`:

```bash
alias vl='kubectl -n vault logs'
alias ve='kubectl -n vault exec'
alias vp='kubectl -n vault get pods'
alias vs='kubectl -n vault exec vault-0 -- vault status'
alias vt='kubectl -n vault exec vault-0 -- vault operator raft list-peers'

# Vault CLI with automatic port-forward
vault-local() {
  kubectl -n vault port-forward vault-0 8200:8200 &
  export VAULT_ADDR=http://localhost:8200
  echo "Vault available at $VAULT_ADDR"
}
```

## Emergency Contacts

When things go wrong:

1. **Sealed Vault**: Contact key holders for unseal keys
2. **Lost Root Token**: Use recovery procedure with unseal keys
3. **Data Corruption**: Restore from latest Raft snapshot
4. **Total Cluster Failure**: Restore from backup and re-initialize
5. **Security Breach**: Immediately seal Vault and revoke all tokens
