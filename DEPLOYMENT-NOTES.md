# Vault HA Deployment Notes and Lessons Learned

## Overview

This document captures important deployment details, common issues, and fixes discovered during real-world deployment of HashiCorp Vault in HA mode on Kubernetes.

## Key Configuration Changes

### 1. StatefulSet Pod Management

**Issue:** With default `podManagementPolicy: OrderedReady`, Kubernetes creates pods sequentially. It won't create vault-1 until vault-0 is "Ready", but vault-0 can't be Ready until it's unsealed, creating a deadlock.

**Fix:** Set `podManagementPolicy: Parallel` in the StatefulSet spec:

```yaml
spec:
  serviceName: vault-internal
  replicas: 3
  podManagementPolicy: Parallel  # Creates all pods simultaneously
```

**Impact:** All 3 pods start at the same time, allowing proper Raft cluster formation.

---

### 2. Readiness Probe Configuration

**Issue:** The default readiness probe fails for sealed/uninitialized Vault, preventing pods from becoming Ready.

**Fix:** Configure health check to accept sealed and uninitialized states:

```yaml
readinessProbe:
  httpGet:
    path: /v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204
    port: 8200
    scheme: HTTP
```

**Parameters:**
- `standbyok=true` - Standby nodes are considered healthy
- `sealedcode=204` - Sealed Vault returns 204 (success) instead of 503
- `uninitcode=204` - Uninitialized Vault returns 204 instead of 501

---

### 3. RBAC Permissions

**Issue:** Vault's Kubernetes service registration requires updating pod labels, but the service account lacked permission.

**Error Message:**
```
unable to set initial state due to PATCH https://10.128.0.1:443/api/v1/namespaces/vault/pods/vault-0 
giving up after 1 attempt(s): bad status code: 403
```

**Fix:** Add `update` and `patch` verbs to the ClusterRole:

```yaml
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "watch", "list", "update", "patch"]  # Added update and patch
```

---

### 4. Raft Cluster Initialization

**Issue:** Original init script tried to initialize all 3 nodes independently, but Raft HA works differently:
- Only the leader (vault-0) is initialized
- Follower nodes (vault-1, vault-2) must **join** the existing cluster
- Attempting to initialize followers causes "Vault is not initialized" errors

**Fix:** Proper Raft cluster formation sequence:

```bash
# 1. Initialize only vault-0 (becomes Raft leader)
kubectl exec -n vault vault-0 -- vault operator init

# 2. Unseal vault-0
kubectl exec -n vault vault-0 -- vault operator unseal <key1>
kubectl exec -n vault vault-0 -- vault operator unseal <key2>
kubectl exec -n vault vault-0 -- vault operator unseal <key3>

# 3. Join vault-1 to cluster
kubectl exec -n vault vault-1 -- vault operator raft join http://vault-0.vault-internal:8200

# 4. Unseal vault-1
kubectl exec -n vault vault-1 -- vault operator unseal <key1>
kubectl exec -n vault vault-1 -- vault operator unseal <key2>
kubectl exec -n vault vault-1 -- vault operator unseal <key3>

# 5. Repeat for vault-2
kubectl exec -n vault vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -n vault vault-2 -- vault operator unseal <key1>
kubectl exec -n vault vault-2 -- vault operator unseal <key2>
kubectl exec -n vault vault-2 -- vault operator unseal <key3>
```

---

### 5. Kubectl Environment Variable Syntax

**Issue:** Using incorrect flag `-e` for environment variables in kubectl exec.

**Incorrect:**
```bash
kubectl exec vault-0 -e VAULT_TOKEN=$VAULT_TOKEN -- vault status
# Error: unknown shorthand flag: 'e' in -e
```

**Correct:**
```bash
kubectl exec vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN vault status
```

---

### 6. Kubernetes Auth Configuration

**Issue:** Original configuration used shell variables that weren't expanded correctly inside the pod.

**Incorrect:**
```bash
kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"
```

**Correct:**
```bash
kubernetes_host="https://kubernetes.default.svc"
```

---

## Common Error Messages and Solutions

### Error: "lookup vault-1.vault-internal: no such host"

**When:** During initial pod startup

**Cause:** Normal behavior while pods are being created. vault-0 tries to join vault-1 and vault-2 before they exist.

**Action:** **Ignore** - These errors resolve once all pods are Running.

---

### Error: "Vault is not initialized" (on vault-1 or vault-2)

**When:** Attempting to unseal vault-1 or vault-2 before joining the cluster

**Cause:** Follower nodes must join the Raft cluster before being unsealed.

**Action:** Run `vault operator raft join` first, then unseal.

---

### Error: "permission denied" (403)

**When:** Running authenticated vault commands

**Cause:** Missing VAULT_TOKEN in the command.

**Action:** Always include token for authenticated commands:
```bash
kubectl exec vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN vault <command>
```

---

### Error: PATCH pods giving up (403)

**When:** Pod startup

**Cause:** Service account lacks pod update permissions.

**Action:** Apply updated RBAC configuration with update/patch permissions.

---

## Deployment Checklist

- [ ] StatefulSet has `podManagementPolicy: Parallel`
- [ ] Readiness probe accepts sealed state (`sealedcode=204&uninitcode=204`)
- [ ] RBAC includes pod `update` and `patch` permissions
- [ ] All 3 pods are Running before initialization
- [ ] Only vault-0 is initialized (not vault-1 or vault-2)
- [ ] vault-1 and vault-2 join via `raft join` command
- [ ] vault-init-keys.json is securely stored
- [ ] Root token is available for authenticated commands
- [ ] Kubernetes auth uses `kubernetes.default.svc` endpoint
- [ ] All commands use `env VAULT_TOKEN=$VAULT_TOKEN` syntax

---

## Verification Commands

### Check All Pods Are Running
```bash
kubectl -n vault get pods
# All should show 1/1 Running (even when sealed)
```

### Check Raft Cluster Status
```bash
export VAULT_TOKEN=$(cat vault-init-keys.json | jq -r '.root_token')
kubectl -n vault exec vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN vault operator raft list-peers

# Expected output:
# Node       Address                        State       Voter
# ----       -------                        -----       -----
# vault-0    vault-0.vault-internal:8201    leader      true
# vault-1    vault-1.vault-internal:8201    follower    true
# vault-2    vault-2.vault-internal:8201    follower    true
```

### Check Seal Status
```bash
# No authentication required
for i in 0 1 2; do
  echo "=== vault-$i ==="
  kubectl -n vault exec vault-$i -- vault status | grep Sealed
done

# All should show: Sealed    false
```

---

## Recovery Procedures

### If Deployment Fails Midway

1. Check which pods exist:
   ```bash
   kubectl -n vault get pods
   ```

2. If only vault-0 exists, delete and redeploy with fixed StatefulSet:
   ```bash
   kubectl delete statefulset vault -n vault
   kubectl delete pvc -l app=vault -n vault
   kubectl apply -f vault-statefulset.yaml
   ```

3. If vault-0 is initialized but others aren't joined:
   ```bash
   ./recover-vault-fixed.sh
   ```

### If You Need to Start Over Completely

```bash
# Delete everything
kubectl delete statefulset vault -n vault
kubectl delete pvc -l app=vault -n vault
kubectl delete svc vault vault-internal -n vault

# Redeploy
kubectl apply -f vault-statefulset.yaml
kubectl apply -f vault-rbac.yaml
kubectl apply -f vault-service-accounts.yaml

# Wait for all pods
kubectl -n vault get pods -w

# Initialize
./vault-init.sh
```

---

## Production Recommendations

1. **Auto-Unseal**: Configure cloud KMS auto-unseal to avoid manual unsealing
2. **TLS**: Enable TLS for all connections in production
3. **Monitoring**: Set up Prometheus metrics scraping and alerting
4. **Backups**: Schedule automated Raft snapshots
5. **High Availability**: Ensure pods are distributed across availability zones
6. **Security**: Revoke root token after setup, use role-based tokens
7. **Audit Logs**: Enable and monitor audit logging
8. **Network Policies**: Restrict pod-to-pod communication

---

## File Versions

All scripts and manifests have been updated with these fixes:

- `vault-statefulset.yaml` - Includes parallel pod management and correct probes
- `vault-rbac.yaml` - Includes pod update/patch permissions
- `vault-init.sh` - Properly handles Raft cluster formation
- `Makefile` - Uses correct kubectl env syntax
- `QUICKREF.md` - Updated with correct command syntax
- `README.md` - Updated deployment instructions and troubleshooting

Additional helper scripts:
- `check-status.sh` - Quick status check and token helper
- `recover-vault-fixed.sh` - Recovery script for partial deployments

---

## References

- [HashiCorp Vault on Kubernetes](https://learn.hashicorp.com/tutorials/vault/kubernetes-raft-deployment-guide)
- [Raft Storage Backend](https://www.vaultproject.io/docs/configuration/storage/raft)
- [Vault Health Endpoint](https://www.vaultproject.io/api-docs/system/health)
- [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)

---

## Support

For issues or questions:
1. Check this document first
2. Run `./check-status.sh` to verify current state
3. Check pod logs: `kubectl -n vault logs vault-0`
4. Verify RBAC: `kubectl get clusterrole vault -o yaml`
5. Check Raft peers: `kubectl -n vault exec vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN vault operator raft list-peers`

Last updated: December 2025
