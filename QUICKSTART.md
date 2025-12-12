# Vault HA Deployment - Quick Start Guide

## Fresh Cluster Deployment Order

Follow these steps in order for a successful deployment.

---

## Step 1: Deploy Core Infrastructure

```bash
# Deploy Vault StatefulSet (with all fixes: parallel pods, correct probes)
kubectl apply -f vault-statefulset.yaml

# Deploy RBAC (with all permissions: pod updates, tokenreviews)
kubectl apply -f vault-rbac.yaml

# Deploy Service Accounts (for admin, operator, and apps)
kubectl apply -f vault-service-accounts.yaml
```

**Wait for all 3 pods to be Running:**
```bash
kubectl -n vault get pods -w
# Press Ctrl+C when you see:
# vault-0   1/1   Running
# vault-1   1/1   Running
# vault-2   1/1   Running
```

---

## Step 2: Initialize Vault Cluster

```bash
# Make script executable
chmod +x vault-init.sh

# Run initialization (this handles Raft cluster setup correctly)
./vault-init.sh
```

**⚠️ CRITICAL**: This creates `vault-init-keys.json` - **SECURE THIS FILE IMMEDIATELY!**

Expected output:
```
✓ vault-0 unsealed and active as Raft leader
✓ vault-1 joined the cluster
✓ vault-1 unsealed
✓ vault-2 joined the cluster
✓ vault-2 unsealed
✓ Kubernetes auth configured
✓ Policies created
✓ Kubernetes auth roles created
✓ Audit logging enabled
```

---

## Step 3: Verify Deployment

```bash
# Quick verification
make status

# Or manually:
kubectl -n vault get pods
export VAULT_TOKEN=$(cat vault-init-keys.json | jq -r '.root_token')
kubectl -n vault exec vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN vault operator raft list-peers
```

Expected output:
```
Node       Address                        State       Voter
----       -------                        -----       -----
vault-0    vault-0.vault-internal:8201    leader      true
vault-1    vault-1.vault-internal:8201    follower    true
vault-2    vault-2.vault-internal:8201    follower    true
```

---

## Step 4: Deploy Example Application

```bash
# Deploy sample app that uses Vault
kubectl apply -f example-app.yaml

# Wait for pods
kubectl get pods -l app=example-app -w
# Press Ctrl+C when both pods show 2/2 Running
```

---

## Step 5: Run Demo

```bash
# Make demo script executable
chmod +x demo-app.sh

# Run full demo
./demo-app.sh
```

Expected output:
```
✓ Secret written to api/myapp/config
✓ Retrieved Kubernetes service account token
✓ Received Vault token
✓ Successfully read secret!

Demo Complete!
```

---

## Troubleshooting Quick Reference

### If Pods Are Sealed After Restart

```bash
make unseal
# Or manually with vault-init-keys.json
```

### If Authentication Fails

```bash
# Check and fix auth configuration
chmod +x fix-auth.sh
./fix-auth.sh

# Test authentication
chmod +x test-auth-direct.sh
./test-auth-direct.sh
```

### If You Need to Start Over

```bash
# Complete cleanup
make clean
make clean-pvcs  # Type 'yes' to confirm

# Redeploy from Step 1
```

---

## Essential Files Checklist

### Core Deployment (Required)
- ✅ `vault-statefulset.yaml` - Vault pods with HA configuration
- ✅ `vault-rbac.yaml` - All necessary permissions
- ✅ `vault-service-accounts.yaml` - Service accounts for all roles
- ✅ `vault-init.sh` - Initialization script
- ✅ `vault-policy-admin.hcl` - Admin namespace policy
- ✅ `vault-policy-api.hcl` - API namespace policy
- ✅ `vault-policy-operator.hcl` - Operator namespace policy

### Demo & Testing (Optional but Recommended)
- ✅ `example-app.yaml` - Sample application
- ✅ `demo-app.sh` - Automated demo script
- ✅ `Makefile` - Convenient commands

### Helper Scripts (Optional)
- `fix-auth.sh` - Fix authentication issues
- `test-auth-direct.sh` - Test authentication
- `check-status.sh` - Quick status check
- `recover-vault-fixed.sh` - Recover partial deployments

### Documentation
- `README.md` - Complete documentation
- `QUICKREF.md` - Quick reference commands
- `DEPLOYMENT-NOTES.md` - Lessons learned and troubleshooting
- `HA-REDIRECT-GUIDE.md` - Understanding HA redirects

---

## Time Estimate

- **Steps 1-2**: 5-10 minutes (pods starting + initialization)
- **Step 3**: 1 minute (verification)
- **Steps 4-5**: 2-3 minutes (app deployment + demo)

**Total**: ~10-15 minutes for complete deployment and demo

---

## Success Criteria

After Step 5, you should have:

✅ 3 Vault pods running and unsealed  
✅ Raft cluster with 1 leader, 2 followers  
✅ All policies created (admin, api, operator)  
✅ Kubernetes auth working  
✅ Example app authenticating successfully  
✅ Secrets being read from application pods  

---

## Next Steps After Demo

1. **Secure the keys**: Store `vault-init-keys.json` in a password manager
2. **Enable TLS**: Configure TLS certificates for production
3. **Set up monitoring**: Configure Prometheus metrics scraping
4. **Configure backups**: Schedule Raft snapshots
5. **Test failover**: Verify HA behavior by killing the leader pod

---

## Quick Commands

```bash
# Status check
make status

# View logs
make logs

# Access Vault UI
kubectl -n vault get svc vault  # Get external IP
# Open http://<EXTERNAL-IP>:8200/ui

# Backup
make backup

# Clean up demo
make clean-example
```

---

## Support

If you encounter issues:

1. Check `DEPLOYMENT-NOTES.md` for common problems
2. Run `./check-status.sh` for diagnostics
3. Check pod logs: `kubectl -n vault logs vault-0`
4. Verify RBAC: `kubectl get clusterrole vault -o yaml`

---

**Ready to deploy? Start with Step 1!** 🚀
