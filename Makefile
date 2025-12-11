# Makefile for Vault HA Deployment on LKE-Enterprise

.PHONY: help install init unseal status clean backup restore

# Variables
NAMESPACE := vault
VAULT_POD := vault-0

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

check-prereqs: ## Check prerequisites
	@echo "Checking prerequisites..."
	@command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed."; exit 1; }
	@command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed."; exit 1; }
	@kubectl cluster-info >/dev/null 2>&1 || { echo "Cannot connect to Kubernetes cluster."; exit 1; }
	@echo "All prerequisites met!"

install: check-prereqs ## Deploy Vault to Kubernetes
	@echo "Deploying Vault to Kubernetes..."
	kubectl apply -f vault-statefulset.yaml
	kubectl apply -f vault-rbac.yaml
	kubectl apply -f vault-service-accounts.yaml
	@echo ""
	@echo "Waiting for pods to be created..."
	kubectl -n $(NAMESPACE) wait --for=condition=Ready pod/vault-0 --timeout=300s || true
	@echo ""
	@echo "Vault deployed! Pods are sealed and waiting for initialization."
	@echo "Run 'make init' to initialize and configure Vault."

install-network-policy: ## Install network policies for additional security
	kubectl apply -f vault-network-policy.yaml
	kubectl label namespace default vault-access=enabled --overwrite
	@echo "Network policies installed. Label other namespaces with 'vault-access=enabled' as needed."

init: ## Initialize and configure Vault
	@echo "Initializing Vault..."
	@chmod +x vault-init.sh
	./vault-init.sh
	@echo ""
	@echo "⚠️  IMPORTANT: Secure vault-init-keys.json immediately!"

unseal: ## Unseal all Vault pods (requires unseal keys)
	@echo "This will unseal all Vault pods."
	@echo "You will need to provide 3 unseal keys."
	@echo ""
	@read -p "Enter unseal key 1: " KEY1; \
	read -p "Enter unseal key 2: " KEY2; \
	read -p "Enter unseal key 3: " KEY3; \
	for i in 0 1 2; do \
		echo "Unsealing vault-$$i..."; \
		kubectl -n $(NAMESPACE) exec vault-$$i -- vault operator unseal $$KEY1 || true; \
		kubectl -n $(NAMESPACE) exec vault-$$i -- vault operator unseal $$KEY2 || true; \
		kubectl -n $(NAMESPACE) exec vault-$$i -- vault operator unseal $$KEY3 || true; \
	done
	@echo ""
	@echo "All pods unsealed!"

status: ## Check Vault cluster status
	@echo "=== Vault Cluster Status ==="
	@for i in 0 1 2; do \
		echo ""; \
		echo "--- vault-$$i ---"; \
		kubectl -n $(NAMESPACE) exec vault-$$i -- vault status || true; \
	done
	@echo ""
	@echo "=== Raft Peers ==="
	@kubectl -n $(NAMESPACE) exec $(VAULT_POD) -- vault operator raft list-peers || echo "Vault may be sealed"

logs: ## View logs from vault-0
	kubectl -n $(NAMESPACE) logs -f $(VAULT_POD)

logs-all: ## View logs from all Vault pods
	@for i in 0 1 2; do \
		echo "=== vault-$$i logs ==="; \
		kubectl -n $(NAMESPACE) logs vault-$$i --tail=50; \
		echo ""; \
	done

shell: ## Open shell in vault-0 pod
	kubectl -n $(NAMESPACE) exec -it $(VAULT_POD) -- sh

deploy-example: ## Deploy example application
	kubectl apply -f example-app.yaml
	@echo "Example app deployed. Check logs with: kubectl logs -l app=example-app"

backup: ## Create a Raft snapshot backup
	@echo "Creating Raft snapshot..."
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	kubectl -n $(NAMESPACE) exec $(VAULT_POD) -- vault operator raft snapshot save /tmp/backup.snap && \
	kubectl -n $(NAMESPACE) cp $(VAULT_POD):/tmp/backup.snap ./vault-backup-$$TIMESTAMP.snap && \
	echo "Backup saved to vault-backup-$$TIMESTAMP.snap"

restore: ## Restore from a Raft snapshot (requires backup file)
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "Error: BACKUP_FILE not specified."; \
		echo "Usage: make restore BACKUP_FILE=vault-backup-YYYYMMDD-HHMMSS.snap"; \
		exit 1; \
	fi
	@echo "Restoring from $(BACKUP_FILE)..."
	@kubectl -n $(NAMESPACE) cp $(BACKUP_FILE) $(VAULT_POD):/tmp/restore.snap
	@kubectl -n $(NAMESPACE) exec $(VAULT_POD) -- vault operator raft snapshot restore -force /tmp/restore.snap
	@echo "Restore complete. Restart pods if necessary."

port-forward: ## Port forward Vault to localhost:8200
	@echo "Port forwarding Vault to localhost:8200..."
	@echo "Press Ctrl+C to stop"
	@kubectl -n $(NAMESPACE) port-forward svc/vault 8200:8200

ui: ## Open Vault UI (requires port-forward in another terminal)
	@echo "Opening Vault UI..."
	@echo "Make sure port-forward is running in another terminal (make port-forward)"
	@open http://localhost:8200/ui || xdg-open http://localhost:8200/ui || echo "Open http://localhost:8200/ui in your browser"

get-ip: ## Get Vault LoadBalancer external IP
	@kubectl -n $(NAMESPACE) get svc vault -o jsonpath='{.status.loadBalancer.ingress[0].ip}' && echo ""

policies: ## List all Vault policies
	@kubectl -n $(NAMESPACE) exec $(VAULT_POD) -- vault policy list

auth-methods: ## List all auth methods
	@kubectl -n $(NAMESPACE) exec $(VAULT_POD) -- vault auth list

secrets-engines: ## List all secrets engines
	@kubectl -n $(NAMESPACE) exec $(VAULT_POD) -- vault secrets list

clean: ## Delete Vault deployment (WARNING: This will delete all data!)
	@echo "⚠️  WARNING: This will delete the Vault deployment and ALL data!"
	@read -p "Are you sure? Type 'yes' to continue: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		kubectl delete -f vault-statefulset.yaml || true; \
		kubectl delete -f vault-rbac.yaml || true; \
		kubectl delete -f vault-service-accounts.yaml || true; \
		kubectl delete -f vault-network-policy.yaml || true; \
		kubectl delete -f example-app.yaml || true; \
		echo "Vault deployment deleted."; \
	else \
		echo "Cancelled."; \
	fi

clean-pvcs: ## Delete persistent volume claims (WARNING: This deletes all stored data!)
	@echo "⚠️  WARNING: This will delete all Vault data stored in PVCs!"
	@read -p "Are you sure? Type 'yes' to continue: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		kubectl -n $(NAMESPACE) delete pvc -l app=vault; \
		echo "PVCs deleted."; \
	else \
		echo "Cancelled."; \
	fi

test-admin: ## Test admin access
	@echo "Testing admin access..."
	@kubectl -n $(NAMESPACE) exec $(VAULT_POD) -- vault kv put admin/test value=test123 && \
	kubectl -n $(NAMESPACE) exec $(VAULT_POD) -- vault kv get admin/test && \
	echo "Admin access OK!"

test-api: ## Test API access from example pod
	@echo "Testing API access..."
	@kubectl run vault-test --rm -it --image=hashicorp/vault:1.15.4 \
		--serviceaccount=app-vault-access \
		-- sh -c 'KUBE_TOKEN=$$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); \
		export VAULT_ADDR=http://vault.vault.svc.cluster.local:8200; \
		VAULT_TOKEN=$$(vault write -field=token auth/kubernetes/login role=api jwt=$$KUBE_TOKEN); \
		export VAULT_TOKEN; \
		vault kv put api/test value=test123; \
		vault kv get api/test'

upgrade: ## Upgrade Vault version (set VERSION=x.x.x)
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION not specified."; \
		echo "Usage: make upgrade VERSION=1.15.4"; \
		exit 1; \
	fi
	@echo "Upgrading Vault to version $(VERSION)..."
	@kubectl -n $(NAMESPACE) set image statefulset/vault vault=hashicorp/vault:$(VERSION)
	@echo "Upgrade initiated. Monitor with: make status"

scale-down: ## Scale Vault to 1 replica (for maintenance)
	kubectl -n $(NAMESPACE) scale statefulset vault --replicas=1
	@echo "Scaled down to 1 replica"

scale-up: ## Scale Vault back to 3 replicas
	kubectl -n $(NAMESPACE) scale statefulset vault --replicas=3
	@echo "Scaled up to 3 replicas"

watch: ## Watch Vault pods
	watch kubectl -n $(NAMESPACE) get pods

describe: ## Describe Vault pods
	kubectl -n $(NAMESPACE) describe pods -l app=vault
