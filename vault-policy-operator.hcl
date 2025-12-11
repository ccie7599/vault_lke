# Operator Namespace Policy
# This policy grants SRE teams operational access without viewing secrets
# Operators can monitor, manage infrastructure, but cannot read secret data

# Read-only access to health and metrics
path "sys/health" {
  capabilities = ["read"]
}

path "sys/metrics" {
  capabilities = ["read"]
}

# Read seal status but cannot unseal/seal
path "sys/seal-status" {
  capabilities = ["read"]
}

# Manage audit devices
path "sys/audit" {
  capabilities = ["read", "list"]
}

path "sys/audit/*" {
  capabilities = ["create", "update", "delete"]
}

# View mounts and configurations (but not secret data)
path "sys/mounts" {
  capabilities = ["read", "list"]
}

path "sys/mounts/*" {
  capabilities = ["read"]
}

# Manage auth methods
path "sys/auth" {
  capabilities = ["read", "list"]
}

path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete"]
}

# View and manage policies (necessary for onboarding apps)
path "sys/policies/acl" {
  capabilities = ["list"]
}

path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete"]
}

# Manage Kubernetes auth roles
path "auth/kubernetes/role/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/kubernetes/config" {
  capabilities = ["read", "update"]
}

# View namespace structure (Enterprise)
path "sys/namespaces" {
  capabilities = ["read", "list"]
}

path "sys/namespaces/*" {
  capabilities = ["read"]
}

# Manage leases
path "sys/leases/lookup/*" {
  capabilities = ["update"]
}

path "sys/leases/revoke/*" {
  capabilities = ["update"]
}

# View replication status
path "sys/replication/status" {
  capabilities = ["read"]
}

# Manage plugins
path "sys/plugins/catalog" {
  capabilities = ["read", "list"]
}

path "sys/plugins/catalog/*" {
  capabilities = ["read", "update"]
}

# Rotate encryption keys
path "sys/rotate" {
  capabilities = ["update"]
}

# View capabilities
path "sys/capabilities-self" {
  capabilities = ["update"]
}

# Token management for operator sessions
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# DENY access to all secret data
path "admin/data/*" {
  capabilities = ["deny"]
}

path "api/data/*" {
  capabilities = ["deny"]
}

path "secret/data/*" {
  capabilities = ["deny"]
}

path "+/data/*" {
  capabilities = ["deny"]
}

# DENY seal/unseal operations
path "sys/unseal" {
  capabilities = ["deny"]
}

path "sys/seal" {
  capabilities = ["deny"]
}

# DENY root token generation
path "sys/generate-root/*" {
  capabilities = ["deny"]
}

# Can view metadata but not secret content
path "*/metadata/*" {
  capabilities = ["read", "list"]
}
