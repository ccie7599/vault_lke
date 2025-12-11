# Admin Namespace Policy
# This policy grants full control over secrets in the admin namespace
# Intended for customer administrators who manage unsealing and core secrets

# Full access to KV v2 secrets engine in admin namespace
path "admin/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "admin/metadata/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "admin/delete/*" {
  capabilities = ["update"]
}

path "admin/undelete/*" {
  capabilities = ["update"]
}

path "admin/destroy/*" {
  capabilities = ["update"]
}

# Access to mount configuration
path "sys/mounts/admin/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage policies in admin namespace
path "sys/policies/acl/admin-*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage auth methods
path "auth/kubernetes/role/admin-*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Access to unseal operations (critical for HA)
path "sys/unseal" {
  capabilities = ["update"]
}

path "sys/seal" {
  capabilities = ["update"]
}

# View seal status
path "sys/seal-status" {
  capabilities = ["read"]
}

# Manage namespaces (Enterprise feature)
path "sys/namespaces/admin" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/namespaces/admin/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Access to manage tokens in admin context
path "auth/token/create" {
  capabilities = ["create", "update"]
}

path "auth/token/renew" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Audit log access for compliance
path "sys/audit" {
  capabilities = ["read", "list"]
}
