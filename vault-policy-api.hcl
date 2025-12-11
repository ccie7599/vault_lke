# API Namespace Policy
# This policy grants read/write access to secrets for applications
# Applications can store and retrieve their own secrets but not manage infrastructure

# Read/write access to KV v2 secrets in api namespace
path "api/data/*" {
  capabilities = ["create", "read", "update", "list"]
}

path "api/metadata/*" {
  capabilities = ["read", "list"]
}

# Allow applications to delete their own secret versions
path "api/delete/*" {
  capabilities = ["update"]
}

# Read-only access to database credentials (if using dynamic secrets)
path "database/creds/*" {
  capabilities = ["read"]
}

# PKI certificate issuance for applications
path "pki/issue/*" {
  capabilities = ["create", "update"]
}

# Transit encryption operations for applications
path "transit/encrypt/*" {
  capabilities = ["update"]
}

path "transit/decrypt/*" {
  capabilities = ["update"]
}

# Token management for applications
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Kubernetes auth for pods
path "auth/kubernetes/login" {
  capabilities = ["create", "update"]
}

# Read-only access to API namespace configuration
path "sys/mounts/api" {
  capabilities = ["read"]
}

# Deny access to sensitive operations
path "sys/unseal" {
  capabilities = ["deny"]
}

path "sys/seal" {
  capabilities = ["deny"]
}

path "sys/namespaces/*" {
  capabilities = ["deny"]
}

path "sys/policies/*" {
  capabilities = ["deny"]
}
