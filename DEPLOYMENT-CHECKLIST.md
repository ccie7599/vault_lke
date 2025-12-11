# Vault HA Production Deployment Checklist

## Pre-Deployment

### Infrastructure
- [ ] LKE-Enterprise cluster is running and accessible
- [ ] `kubectl` is configured and working
- [ ] Cluster has at least 3 nodes for pod distribution
- [ ] Persistent volume storage is available (Linode Block Storage)
- [ ] Load balancer support is available

### Prerequisites
- [ ] `kubectl` installed and configured
- [ ] `jq` installed (for init script)
- [ ] `make` installed (optional, for Makefile usage)
- [ ] Review and customize configuration in `vault-config.hcl`

### Security Planning
- [ ] Determine who will hold unseal keys (minimum 3 people)
- [ ] Plan for secure storage of root token
- [ ] Decide on TLS certificate strategy
- [ ] Review network policy requirements
- [ ] Plan backup strategy and retention policy

## Deployment Steps

### 1. Initial Deployment
- [ ] Review `vault-statefulset.yaml` configuration
- [ ] Adjust resource requests/limits if needed
- [ ] Verify storage class configuration
- [ ] Deploy: `make install` or `kubectl apply -f vault-statefulset.yaml`
- [ ] Wait for pods to be created: `kubectl -n vault get pods -w`

### 2. RBAC Configuration
- [ ] Deploy RBAC: `kubectl apply -f vault-rbac.yaml`
- [ ] Create service accounts: `kubectl apply -f vault-service-accounts.yaml`
- [ ] Verify service accounts: `kubectl -n vault get sa`

### 3. Initialization
- [ ] Run initialization script: `./vault-init.sh`
- [ ] **CRITICAL**: Secure `vault-init-keys.json` immediately
- [ ] Distribute unseal keys to designated key holders
- [ ] Document key holder contact information
- [ ] Store root token securely (password manager/vault)
- [ ] Delete local copy of keys after secure storage

### 4. Verification
- [ ] Check all pods are unsealed: `make status`
- [ ] Verify Raft cluster: `kubectl -n vault exec vault-0 -- vault operator raft list-peers`
- [ ] Test admin access: `make test-admin`
- [ ] Access Vault UI and verify login
- [ ] Check audit logs are being written

### 5. Policy and Access Setup
- [ ] Verify policies are created: `make policies`
- [ ] Verify Kubernetes auth roles: `make auth-methods`
- [ ] Test application authentication: `make test-api`
- [ ] Deploy example app: `make deploy-example`
- [ ] Verify app can read/write secrets

### 6. Security Hardening (Production)
- [ ] Enable TLS certificates
- [ ] Deploy network policies: `make install-network-policy`
- [ ] Label application namespaces for Vault access
- [ ] Configure Pod Security Policies/Standards
- [ ] Enable auto-unseal (recommended)
- [ ] Set up secret rotation policies
- [ ] Configure session timeouts

### 7. Monitoring and Alerting
- [ ] Set up Prometheus scraping of metrics
- [ ] Configure alerts for seal status
- [ ] Configure alerts for leadership changes
- [ ] Set up log aggregation for audit logs
- [ ] Configure alerts for failed authentication
- [ ] Set up uptime monitoring

### 8. Backup Configuration
- [ ] Test backup process: `make backup`
- [ ] Verify backup file is created
- [ ] Test restore process in non-production
- [ ] Set up automated backup schedule
- [ ] Configure backup retention policy
- [ ] Document restore procedure

## Post-Deployment

### Documentation
- [ ] Document unseal key distribution
- [ ] Document root token location
- [ ] Create runbook for common operations
- [ ] Document backup/restore procedures
- [ ] Document emergency contact list
- [ ] Create on-call playbook

### Team Training
- [ ] Train admins on unsealing procedures
- [ ] Train SREs on operator access
- [ ] Train developers on API access
- [ ] Conduct disaster recovery drill
- [ ] Review security policies with team

### Access Management
- [ ] Create admin tokens for customer team
- [ ] Create operator tokens for SRE team
- [ ] Set up developer onboarding process
- [ ] Document token renewal procedures
- [ ] Establish token revocation process

### Operational Readiness
- [ ] Create monitoring dashboard
- [ ] Set up alerting channels (Slack/PagerDuty)
- [ ] Establish backup verification schedule
- [ ] Create maintenance windows schedule
- [ ] Document upgrade procedures
- [ ] Create rollback plan

## Security Checklist

### Access Controls
- [ ] Admin access limited to customer only
- [ ] Operator access provides no secret visibility
- [ ] Application access restricted to specific namespaces
- [ ] Root token is revoked or securely stored
- [ ] Unseal keys distributed among multiple people
- [ ] Regular access audits scheduled

### Network Security
- [ ] Network policies are enforced
- [ ] Only necessary ports are exposed
- [ ] TLS is enabled for all connections
- [ ] Load balancer has appropriate security groups
- [ ] Internal communication is encrypted

### Data Protection
- [ ] Encryption at rest is enabled (Raft)
- [ ] Encryption in transit is enabled (TLS)
- [ ] Backups are encrypted
- [ ] Backup access is restricted
- [ ] Data retention policies defined

### Compliance
- [ ] Audit logging is enabled
- [ ] Logs are retained per policy
- [ ] Access reviews are scheduled
- [ ] Compliance reports can be generated
- [ ] Incident response plan exists

## Ongoing Maintenance

### Daily
- [ ] Check Vault seal status
- [ ] Monitor cluster health
- [ ] Review critical alerts

### Weekly
- [ ] Review audit logs for anomalies
- [ ] Verify backup completion
- [ ] Check storage utilization
- [ ] Review access patterns

### Monthly
- [ ] Test backup restoration
- [ ] Review and update policies
- [ ] Rotate operator credentials
- [ ] Update documentation
- [ ] Security audit

### Quarterly
- [ ] Plan version upgrades
- [ ] Review disaster recovery plan
- [ ] Conduct security training
- [ ] Review access lists
- [ ] Test failover procedures

## Emergency Procedures

### Vault Sealed
1. Contact unseal key holders
2. Gather minimum threshold (3) of keys
3. Unseal using: `make unseal`
4. Verify cluster health
5. Investigate cause of sealing

### Complete Cluster Failure
1. Verify backups are available
2. Deploy new cluster
3. Initialize new cluster
4. Restore from backup
5. Verify data integrity
6. Update DNS/endpoints

### Security Breach
1. Immediately seal Vault: `vault operator seal`
2. Revoke all tokens: `vault token revoke -mode=path /`
3. Investigate breach source
4. Rotate all secrets
5. Update policies
6. Unseal with new procedures

### Data Corruption
1. Stop accepting new writes
2. Identify extent of corruption
3. Restore from last known good backup
4. Verify restored data
5. Resume operations
6. Post-mortem analysis

## Success Criteria

- [ ] All 3 Vault pods are running and unsealed
- [ ] Raft cluster shows 3 healthy peers
- [ ] Admin users can manage secrets in `admin/` namespace
- [ ] Applications can read/write secrets in `api/` namespace
- [ ] Operators can manage infrastructure without seeing secrets
- [ ] Backup/restore procedures tested and working
- [ ] Monitoring and alerting configured
- [ ] Documentation complete and accessible
- [ ] Team trained on operations
- [ ] Security controls validated

## Notes and Customizations

Document any customizations or deviations from standard deployment:

```
[Add your notes here]
```

## Sign-off

Deployment completed by: _____________________ Date: _________

Verified by: _____________________ Date: _________

Production approved by: _____________________ Date: _________
