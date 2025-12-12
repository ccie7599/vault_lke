# Essential Files for Fresh Deployment

## Required Files (Use These)

These are the ONLY files you need for a complete deployment from scratch.

### 1. Core Deployment Files

| File | Purpose | When to Use |
|------|---------|-------------|
| `vault-statefulset.yaml` | Vault pods, services, ConfigMap | Step 1 |
| `vault-rbac.yaml` | All Kubernetes permissions | Step 1 |
| `vault-service-accounts.yaml` | Service accounts for admin/api/operator | Step 1 |
| `vault-init.sh` | Initialize and configure Vault | Step 2 |

### 2. Policy Files (Used by vault-init.sh)

| File | Purpose |
|------|---------|
| `vault-policy-admin.hcl` | Admin namespace policy |
| `vault-policy-api.hcl` | API namespace policy |
| `vault-policy-operator.hcl` | Operator namespace policy |

### 3. Demo & Testing Files

| File | Purpose | When to Use |
|------|---------|-------------|
| `example-app.yaml` | Sample application | Step 4 |
| `demo-app.sh` | Automated demo | Step 5 |

### 4. Optional Helper Scripts

| File | Purpose |
|------|---------|
| `Makefile` | Convenient commands (make status, make unseal, etc) |
| `fix-auth.sh` | Fix authentication if needed |
| `test-auth-direct.sh` | Test authentication directly |
| `check-status.sh` | Quick status diagnostics |

---

## Files to IGNORE

These are old/deprecated versions that have been merged into the main files:

❌ `vault-statefulset-fixed.yaml` - **Use `vault-statefulset.yaml` instead**
❌ `vault-rbac-fixed.yaml` - **Use `vault-rbac.yaml` instead**
❌ `vault-init-raft.sh` - **Use `vault-init.sh` instead**
❌ `recover-vault.sh` - **Use `recover-vault-fixed.sh` instead**
❌ `troubleshoot.sh` - **Use `check-status.sh` instead**

---

## Complete File Manifest

Here's every file in the repository and whether you need it:

### ✅ REQUIRED - Core Deployment
```
vault-statefulset.yaml          ← Deploy this
vault-rbac.yaml                 ← Deploy this
vault-service-accounts.yaml     ← Deploy this
vault-init.sh                   ← Run this
vault-policy-admin.hcl          ← Used by vault-init.sh
vault-policy-api.hcl            ← Used by vault-init.sh
vault-policy-operator.hcl       ← Used by vault-init.sh
```

### ✅ REQUIRED - Demo
```
example-app.yaml                ← Deploy this for demo
demo-app.sh                     ← Run this for demo
```

### 📚 DOCUMENTATION (Reference)
```
README.md                       ← Full documentation
QUICKSTART.md                   ← This deployment guide
QUICKREF.md                     ← Command reference
DEPLOYMENT-NOTES.md             ← Lessons learned
DEPLOYMENT-CHECKLIST.md         ← Production checklist
HA-REDIRECT-GUIDE.md           ← Understanding HA redirects
UPDATE-SUMMARY.md               ← What changed in fixes
APP-VERIFICATION.md             ← App testing commands
```

### 🔧 HELPER SCRIPTS (Optional)
```
Makefile                        ← Convenient shortcuts
fix-auth.sh                     ← Fix auth issues
test-auth-direct.sh             ← Test authentication
check-status.sh                 ← Status diagnostics
recover-vault-fixed.sh          ← Recover partial deployments
fix-vault-rbac.sh               ← Fix RBAC permissions
troubleshoot-auth.sh            ← Debug authentication
```

### 🗑️ DEPRECATED (Don't Use)
```
vault-statefulset-fixed.yaml    ← OLD, merged into vault-statefulset.yaml
vault-rbac-fixed.yaml           ← OLD, merged into vault-rbac.yaml
vault-init-raft.sh              ← OLD, merged into vault-init.sh
recover-vault.sh                ← OLD, use recover-vault-fixed.sh
troubleshoot.sh                 ← OLD, use check-status.sh
```

### 🌐 NETWORK SECURITY (Optional)
```
vault-network-policy.yaml       ← Optional network policies
```

---

## Minimal Deployment (5 Files)

If you want the absolute minimum to get Vault running:

```bash
# 1. Deploy infrastructure
kubectl apply -f vault-statefulset.yaml
kubectl apply -f vault-rbac.yaml
kubectl apply -f vault-service-accounts.yaml

# 2. Initialize (needs the 3 policy files in same directory)
chmod +x vault-init.sh
./vault-init.sh
```

That's it! These 5 files + 3 policy files = working Vault HA cluster.

---

## Full Deployment with Demo (7 Files)

For a complete deployment with demo:

```bash
# 1-3. Core deployment (as above)
kubectl apply -f vault-statefulset.yaml
kubectl apply -f vault-rbac.yaml
kubectl apply -f vault-service-accounts.yaml

# 4. Initialize
chmod +x vault-init.sh
./vault-init.sh

# 5. Deploy demo app
kubectl apply -f example-app.yaml

# 6. Run demo
chmod +x demo-app.sh
./demo-app.sh
```

---

## Download All Essential Files

If downloading from this repository, grab these files:

### Core (8 files)
- vault-statefulset.yaml
- vault-rbac.yaml
- vault-service-accounts.yaml
- vault-init.sh
- vault-policy-admin.hcl
- vault-policy-api.hcl
- vault-policy-operator.hcl
- Makefile (optional but recommended)

### Demo (2 files)
- example-app.yaml
- demo-app.sh

### Documentation (2 files for quick reference)
- QUICKSTART.md (this file)
- QUICKREF.md

**Total: 12 files** for a complete setup with documentation.

---

## What Each File Contains

### vault-statefulset.yaml
- Namespace definition
- ConfigMap with Vault configuration
- Services (LoadBalancer and headless)
- StatefulSet with:
  - ✅ Parallel pod management
  - ✅ Correct health probes
  - ✅ Raft storage configuration
  - ✅ Anti-affinity rules

### vault-rbac.yaml
- ClusterRole with all permissions:
  - ✅ Pod updates
  - ✅ TokenReview creation (critical for auth!)
  - ✅ ServiceAccount access
- ClusterRoleBinding
- Default service accounts

### vault-init.sh
- Initializes vault-0 (Raft leader)
- Joins vault-1 and vault-2 to cluster
- Unseals all nodes
- Configures Kubernetes auth
- Creates all policies
- Creates auth roles
- Enables audit logging
- ✅ Handles Raft HA correctly
- ✅ Uses proper kubectl syntax

### demo-app.sh
- Deploys example app (if needed)
- Writes test secret
- Demonstrates authentication
- Shows secret reading
- Tests namespace isolation
- ✅ Uses curl -L for HA redirects

---

## Quick Deployment Checklist

- [ ] Have `kubectl` configured for your cluster
- [ ] Have `jq` installed
- [ ] Download the 8 core files listed above
- [ ] Run: `kubectl apply -f vault-statefulset.yaml`
- [ ] Run: `kubectl apply -f vault-rbac.yaml`
- [ ] Run: `kubectl apply -f vault-service-accounts.yaml`
- [ ] Wait for 3 pods running
- [ ] Run: `chmod +x vault-init.sh && ./vault-init.sh`
- [ ] Secure `vault-init-keys.json`
- [ ] Run: `kubectl apply -f example-app.yaml`
- [ ] Run: `chmod +x demo-app.sh && ./demo-app.sh`
- [ ] ✅ Success!

---

Last Updated: December 11, 2025
