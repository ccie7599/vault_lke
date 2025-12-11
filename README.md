# HashiCorp Vault HA Deployment on LKE-Enterprise

This repository contains a production-ready HashiCorp Vault High Availability (HA) deployment for Linode Kubernetes Engine Enterprise (LKE-Enterprise) with three-tier namespace separation.

## Architecture Overview

### High Availability Setup
- **3-node Raft cluster** for data replication and consensus
- **Integrated Storage (Raft)** for built-in HA without external dependencies
- **Pod anti-affinity** to ensure nodes are distributed across different hosts
- **Headless service** for internal cluster communication
- **LoadBalancer service** for external access

### Namespace Separation

This deployment implements three distinct access levels:

1. **Admin Namespace** (`admin/`)
   - **Purpose**: Customer-controlled secret management and unsealing operations
   - **Access**: Full control over secrets, unsealing, and core Vault operations
   - **Use Cases**: Root key management, initial configuration, critical infrastructure secrets
   - **Kubernetes SA**: `vault-admin`

2. **API Namespace** (`api/`)
   - **Purpose**: Application access to secrets
   - **Access**: Read/write secrets, cannot manage infrastructure
   - **Use Cases**: Application configuration, database credentials, API keys
   - **Kubernetes SA**: `app-vault-access`

3. **Operator Namespace** (operational access only)
   - **Purpose**: SRE team operational access
   - **Access**: Monitor, manage auth methods and policies, **cannot view secrets**
   - **Use Cases**: Onboarding apps, managing authentication, monitoring, audit logs
   - **Kubernetes SA**: `vault-operator`

## Prerequisites

- Linode Kubernetes Engine Enterprise (LKE-Enterprise) cluster
- `kubectl` configured to access your cluster
- `jq` for JSON processing (for init script)
- Persistent volume support (Linode Block Storage)

**📖 Important:** Review [DEPLOYMENT-NOTES.md](DEPLOYMENT-NOTES.md) for detailed configuration explanations, common issues, and lessons learned from real-world deployments.

## Deployment Steps

### 1. Deploy Vault Infrastructure

```bash
# Create the Vault namespace and deploy StatefulSet
kubectl apply -f vault-statefulset.yaml

# Create RBAC resources (includes pod update/patch permissions)
kubectl apply -f vault-rbac.yaml

# Create service accounts for different access levels
kubectl apply -f vault-service-accounts.yaml

# Wait for all 3 pods to be running (may take 1-2 minutes)
kubectl -n vault get pods -w

# Expected output (all 3 pods should start together):
# NAME      READY   STATUS    RESTARTS   AGE
# vault-0   1/1     Running   0          60s
# vault-1   1/1     Running   0          60s
# vault-2   1/1     Running   0          60s
```

**Note:** With `podManagementPolicy: Parallel`, all 3 pods start simultaneously. They will show as Running even when sealed/uninitialized - this is expected behavior.

### 2. Initialize and Configure Vault

```bash
# Make the init script executable
chmod +x vault-init.sh

# Run initialization (this will initialize vault-0, join vault-1 and vault-2 to Raft cluster)
./vault-init.sh

# IMPORTANT: The script creates vault-init-keys.json
# Store this file securely immediately!
```

**Important Notes:**
- Only vault-0 (the Raft leader) is initialized
- vault-1 and vault-2 automatically join the Raft cluster
- All commands require authentication with the root token
- Use `env VAULT_TOKEN=$VAULT_TOKEN` when running kubectl exec commands

**⚠️ CRITICAL SECURITY NOTICE:**
- The `vault-init-keys.json` file contains unseal keys and the root token
- Store this in a secure vault or password manager
- Never commit this file to version control
- Consider splitting unseal keys among trusted individuals
- Delete the local copy after secure storage

### 3. Verify Deployment

```bash
# Check cluster status
kubectl -n vault exec vault-0 -- vault status

# List Raft peers
kubectl -n vault exec vault-0 -- vault operator raft list-peers

# Verify policies
kubectl -n vault exec vault-0 -- vault policy list

# Check auth methods
kubectl -n vault exec vault-0 -- vault auth list
```

### 4. Access Vault UI

```bash
# Get the external IP
kubectl -n vault get svc vault

# Access UI at http://<EXTERNAL-IP>:8200/ui
# Login with root token from vault-init-keys.json
```

## Usage Examples

### Admin Access (Customer)

Admin users have full control and can unseal Vault:

```bash
# Set up admin context
export VAULT_ADDR=http://<vault-external-ip>:8200
export VAULT_TOKEN=<admin-token>

# Store critical secrets
vault kv put admin/infrastructure/root-ca \
  certificate=@ca.crt \
  private-key=@ca.key

# Unseal Vault nodes
vault operator unseal <key1>
vault operator unseal <key2>
vault operator unseal <key3>
```

### API Access (Applications)

Applications authenticate via Kubernetes service accounts:

```bash
# Example: Write secret from a pod
kubectl apply -f example-app.yaml

# The app will automatically:
# 1. Authenticate using its service account
# 2. Get a Vault token
# 3. Access secrets from api/ path
```

### Operator Access (SRE)

SREs can manage infrastructure without seeing secrets:

```bash
# Authenticate as operator
VAULT_TOKEN=$(kubectl -n vault exec vault-0 -- vault write -field=token \
  auth/kubernetes/login \
  role=operator \
  jwt=$(kubectl -n vault get secret vault-operator-token -o jsonpath='{.data.token}' | base64 -d))

export VAULT_TOKEN

# Onboard a new application
vault write auth/kubernetes/role/new-app \
  bound_service_account_names=new-app \
  bound_service_account_namespaces=production \
  policies=api-policy \
  ttl=1h

# View metrics and health
vault read sys/metrics
vault read sys/health

# CANNOT read secrets (will be denied)
vault kv get admin/infrastructure/root-ca  # DENIED
vault kv get api/myapp/config              # DENIED
```

## Auto-Unsealing (Recommended for Production)

For production environments, configure auto-unseal using a cloud KMS:

### Option 1: Linode Object Storage + Transit Seal

```hcl
seal "transit" {
  address         = "https://vault-primary.example.com:8200"
  token           = "<token>"
  disable_renewal = false
  key_name        = "autounseal"
  mount_path      = "transit/"
}
```

### Option 2: Cloud KMS Integration

Update `vault-config.hcl` to include seal configuration for AWS KMS, GCP KMS, or Azure Key Vault.

## TLS Configuration (Production)

For production, enable TLS:

1. Create TLS certificates:
```bash
# Using cert-manager or your PKI
kubectl create secret tls vault-tls \
  --cert=vault.crt \
  --key=vault.key \
  -n vault
```

2. Update ConfigMap to enable TLS:
```hcl
listener "tcp" {
  address       = "[::]:8200"
  tls_cert_file = "/vault/tls/tls.crt"
  tls_key_file  = "/vault/tls/tls.key"
}
```

3. Mount TLS secret in StatefulSet:
```yaml
volumeMounts:
  - name: tls
    mountPath: /vault/tls
volumes:
  - name: tls
    secret:
      secretName: vault-tls
```

## Backup and Recovery

### Backup Raft Data

```bash
# Take a snapshot
kubectl -n vault exec vault-0 -- vault operator raft snapshot save backup.snap

# Copy from pod
kubectl -n vault cp vault-0:/vault/backup.snap ./vault-backup-$(date +%Y%m%d).snap
```

### Restore from Backup

```bash
# Copy to pod
kubectl -n vault cp ./vault-backup.snap vault-0:/vault/backup.snap

# Restore
kubectl -n vault exec vault-0 -- vault operator raft snapshot restore -force backup.snap
```

## Monitoring and Alerts

### Health Checks

```bash
# Check seal status
curl http://<vault-ip>:8200/v1/sys/seal-status

# Check leader
curl http://<vault-ip>:8200/v1/sys/leader
```

### Metrics Export

Vault exposes Prometheus metrics at `/v1/sys/metrics?format=prometheus`:

```yaml
# ServiceMonitor for Prometheus Operator
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vault
  namespace: vault
spec:
  selector:
    matchLabels:
      app: vault
  endpoints:
    - port: http
      path: /v1/sys/metrics
      params:
        format: ['prometheus']
```

## Security Best Practices

1. **Unseal Keys**: Distribute among multiple trusted individuals
2. **Root Token**: Revoke after initial setup, use regular tokens
3. **TLS**: Always enable TLS in production
4. **Network Policies**: Restrict pod-to-pod communication
5. **Audit Logging**: Enable and monitor audit logs
6. **Auto-Unseal**: Implement for production environments
7. **Rotation**: Regularly rotate encryption keys and credentials
8. **Least Privilege**: Use minimal required policies for each role
9. **Pod Security**: Enable Pod Security Standards
10. **Backup**: Regular automated backups of Raft snapshots

## Troubleshooting

### Only vault-0 Pod Exists

If only vault-0 is created and you don't see vault-1 and vault-2:

**Cause:** Old StatefulSet without `podManagementPolicy: Parallel`

**Fix:**
```bash
# Delete and recreate with the correct configuration
kubectl delete statefulset vault -n vault
kubectl delete pvc -l app=vault -n vault
kubectl apply -f vault-statefulset.yaml
```

### RBAC Permission Errors (403)

If you see errors like "PATCH pods giving up after 1 attempt(s): bad status code: 403":

**Cause:** Vault service account lacks pod update permissions

**Fix:**
```bash
# Apply updated RBAC
kubectl apply -f vault-rbac.yaml

# Restart pods
kubectl -n vault delete pod --all
```

### Vault Won't Unseal After Initialization

If vault-1 and vault-2 show "Vault is not initialized" errors during unseal:

**Cause:** In Raft mode, only the leader (vault-0) is initialized. Follower nodes must join the cluster.

**Fix:**
```bash
# Use the recovery script
chmod +x check-status.sh recover-vault-fixed.sh
./check-status.sh  # View current status
./recover-vault-fixed.sh  # Complete the setup
```

### Authentication Required Errors

All vault commands (except unseal) require authentication:

```bash
# Export the root token
export VAULT_TOKEN=$(cat vault-init-keys.json | jq -r '.root_token')

# Use env VAULT_TOKEN in kubectl exec
kubectl -n vault exec vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN vault status
```

### DNS Lookup Failures During Startup

Errors like "lookup vault-1.vault-internal: no such host" during initial startup are **normal** and can be ignored. They occur while pods are being created.

### Vault Won't Unseal

```bash
# Check seal status
kubectl -n vault exec vault-0 -- vault status

# Unseal manually
kubectl -n vault exec vault-0 -- vault operator unseal <key>
```

### Pod Crashes or Won't Start

```bash
# Check logs
kubectl -n vault logs vault-0

# Check persistent volume
kubectl -n vault get pvc

# Check configuration
kubectl -n vault get cm vault-config -o yaml
```

### Cannot Join Raft Cluster

```bash
# Check leader
kubectl -n vault exec vault-0 -- vault operator raft list-peers

# Force remove a node
kubectl -n vault exec vault-0 -- vault operator raft remove-peer vault-2

# Re-join
kubectl -n vault exec vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
```

### Authentication Issues

```bash
# List auth methods
kubectl -n vault exec vault-0 -- vault auth list

# Check role configuration
kubectl -n vault exec vault-0 -- vault read auth/kubernetes/role/api

# Test authentication from pod
kubectl run test -it --rm --image=hashicorp/vault:1.15.4 \
  --serviceaccount=app-vault-access \
  -- sh
```

## Scaling Considerations

### Horizontal Scaling
- Raft supports 3-5 nodes (odd number recommended)
- More nodes = higher read throughput but slower writes
- 3 nodes is optimal for most use cases

### Vertical Scaling
Adjust resource requests/limits in StatefulSet:
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"
  limits:
    memory: "1Gi"
    cpu: "1000m"
```

### Storage Scaling
Expand PVC size:
```bash
kubectl -n vault patch pvc data-vault-0 -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

## Maintenance

### Upgrading Vault

1. Take a backup
2. Update image version in StatefulSet
3. Roll out one pod at a time:
```bash
kubectl -n vault delete pod vault-2
# Wait for healthy
kubectl -n vault delete pod vault-1
# Wait for healthy
kubectl -n vault delete pod vault-0
```

### Rotating Encryption Keys

```bash
vault operator rotate
```

### Revoking Leases

```bash
# Revoke all leases under a path
vault lease revoke -prefix api/
```

## Support and Resources

- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Vault on Kubernetes Guide](https://learn.hashicorp.com/tutorials/vault/kubernetes-raft-deployment-guide)
- [Raft Storage Backend](https://www.vaultproject.io/docs/configuration/storage/raft)
- [Linode Kubernetes Engine](https://www.linode.com/products/kubernetes/)

## License

This configuration is provided as-is for use with HashiCorp Vault.
