SHELL := /bin/bash
# Use Make's shell() to evaluate `go env GOPATH` when the Makefile is read
GOLANGCI := $(shell go env GOPATH)/bin/golangci-lint
OAPI_CODEGEN := $(shell go env GOPATH)/bin/oapi-codegen
ACT ?= act
ACT_FLAGS ?= --platform ubuntu-latest=ghcr.io/catthehacker/ubuntu:act-24.04-20260215 \
	--container-architecture linux/amd64 \
	--pull=false

ACT_WEB_FLAGS = -s CF_API_TOKEN=$(CF_API_TOKEN) \
	--var API_BASE_URL=$(API_BASE_URL)

ACT_INFRA_FLAGS = -s PULUMI_ACCESS_TOKEN=$(PULUMI_ACCESS_TOKEN) \
	-s CF_API_TOKEN=$(CF_API_TOKEN) \
	-s CF_ZONE_ID=$(CF_ZONE_ID) \
	--var CF_API_RECORD_NAME=$(CF_API_RECORD_NAME) \
	-s AWS_ACCESS_KEY_ID=$$AWS_ACCESS_KEY_ID \
	-s AWS_SECRET_ACCESS_KEY=$$AWS_SECRET_ACCESS_KEY \
	-s AWS_SESSION_TOKEN=$$AWS_SESSION_TOKEN \
	--var AWS_REGION=$(AWS_REGION) \
	--input stack=$(STACK)

AWS ?= aws
PULUMI ?= pulumi
REGION ?= $(AWS_REGION)
STACK ?= dev
DRY_RUN ?= true # Set to true by default for safety; override with DRY_RUN=false to execute actions

# Auto-load a local .env file if present (convenience). `.env` should NOT be committed.
ifneq (,$(wildcard .env))
# Capture variables defined before loading .env
ENV_PRE_VARS := $(.VARIABLES)
include .env
# Export only variables newly introduced by .env (avoid exporting all Make internals)
ENV_NEW_VARS := $(filter-out $(ENV_PRE_VARS) MAKEFILE_LIST,$(.VARIABLES))
export $(ENV_NEW_VARS)
endif

IMAGE_TAG ?= local

K8S_NAMESPACE ?= edge-cache-lab
K8S_OVERLAY_LOCAL ?= infra/k8s/overlays/local
K8S_OVERLAY_PRODUCTION ?= infra/k8s/overlays/production

PURGE_TOKEN ?= test-purge-token

# Colors for output
GREEN  := \033[0;32m
YELLOW := \033[1;33m
NC     := \033[0m

define print_help_section
	@printf "$(YELLOW)%s$(NC)\n" "$(1)"
	@grep -h -E '^[a-zA-Z0-9_.-]+:.*## $(2): .*$$' $(MAKEFILE_LIST) | \
	awk -F '## ' \
	'{ \
		cmd=$$1; \
		gsub(/:.*/,"",cmd); \
		desc=$$2; \
		sub(/^$(2): /,"",desc); \
		printf "  $(GREEN)%-30s$(NC)  %s\n", cmd, desc \
	}'
	@echo ""
endef

.PHONY: help
help: ## Meta: Show this help message
	@printf "$(GREEN)%s$(NC)\n" "Edge Cache Lab - Commands"
	@echo ""
	$(call print_help_section,API Commands,API)
	$(call print_help_section,Web Commands,Web)
	$(call print_help_section,OpenAPI Commands,OpenAPI)
	$(call print_help_section,Docker Commands,Docker)
	$(call print_help_section,Kubernetes Commands,Kubernetes)
	$(call print_help_section,Infrastructure Commands,Infra)
	$(call print_help_section,Cloudflare DNS Commands,Cloudflare)
	$(call print_help_section,CI Commands,CI)
	$(call print_help_section,Testing Commands,Testing)

.PHONY: api-init api-install api-update api-run api-test api-lint api-fmt openapi openapi-validate openapi-diff api-docker-build app-ci varnish-docker-build

##@ API

api-init: ## API: Initialize the API module and dependencies
	@cd apps/api && if [ ! -f go.mod ]; then go mod init edge-cache-lab/apps/api; fi && \
	go get -u github.com/go-chi/chi/v5 && \
	go get -u github.com/stretchr/testify/require && \
	go mod tidy

api-install: ## API: Download and tidy API Go dependencies
	@cd apps/api && \
	go mod download && \
	go mod tidy

api-update: ## API: Update API Go dependencies
	@cd apps/api && go get -u ./... && go mod tidy

api-run: api-install ## API: Run the API server on localhost:3000
	@echo "Starting API server on http://localhost:3000" && \
	cd apps/api && go run ./...

api-test: api-install ## API: Run API tests with coverage
	@cd apps/api && go test ./... -v -cover

api-lint: ## API: Run golangci-lint checks for API
	@cd apps/api && $(GOLANGCI) run

api-fmt: ## API: Format API code using golangci-lint formatters
	@cd apps/api && $(GOLANGCI) fmt

##@ OpenAPI

openapi: ## OpenAPI: Generate Go server/types from openapi/api.yaml
	@echo "Installing oapi-codegen if needed..."
	@which $(OAPI_CODEGEN) > /dev/null || go install github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@v2.5.1
	@echo "Generating Go code from OpenAPI spec..."
	@mkdir -p apps/api/internal/api
	@$(OAPI_CODEGEN) -generate types,chi-server \
		-package api \
		openapi/api.yaml > apps/api/internal/api/api.gen.go
	@echo "✓ Generated apps/api/internal/api/api.gen.go"

openapi-validate: ## OpenAPI: Validate OpenAPI specification
	@echo "Validating OpenAPI spec..."
	@$(OAPI_CODEGEN) -generate types \
		-package api \
		openapi/api.yaml > /dev/null 2>&1 && echo "✓ OpenAPI spec is valid" || (echo "✗ OpenAPI spec validation failed" && exit 1)

openapi-diff: openapi ## OpenAPI: Fail if generated Go code is out of sync
	@echo "Checking for OpenAPI codegen drift..."
	@git diff --exit-code -- apps/api/internal/api/api.gen.go
	@echo "✓ OpenAPI codegen is in sync"

api-docker-build: ## API: Build API Docker image
	@docker build -t edge-cache-lab-api:$(IMAGE_TAG) apps/api

varnish-docker-build: ## API: Build Varnish Docker image
	@docker build -t edge-cache-lab-varnish:$(IMAGE_TAG) apps/varnish

app-ci: openapi-validate openapi-diff api-lint api-test api-docker-build varnish-docker-build ## CI: Run API-side CI checks locally

.PHONY: web-install web-generate-client web-openapi-diff web-run web-build web-preview web-lint web-docker-build web-cf-typegen web-ci

##@ Web

web-install: ## Web: Install web dependencies with pnpm
	@echo "Installing web dependencies..."
	@cd apps/web && corepack enable && corepack prepare pnpm@10.28.1 --activate && pnpm install

web-generate-client: ## Web: Generate OpenAPI TypeScript client
	@echo "Generating OpenAPI TypeScript client..."
	@cd apps/web && pnpm run generate-client
	@echo "✓ Generated TypeScript client in apps/web/src/api"

web-openapi-diff: web-generate-client ## Web: Fail if generated TypeScript client is out of sync
	@echo "Checking for OpenAPI TypeScript client drift..."
	@git diff --exit-code -- apps/web/src/api
	@echo "✓ OpenAPI TypeScript client is in sync"

web-cf-typegen: ## Web: Generate Cloudflare Wrangler type definitions
	@echo "Generating Cloudflare Types for Wrangler..."
	@cd apps/web && pnpm run cf-typegen
	@echo "✓ Generated Cloudflare types in apps/web/worker-configuration.d.ts"

web-run: web-install web-generate-client web-cf-typegen ## Web: Run web development server
	@echo "Starting web dev server on http://localhost:5173" && \
	cd apps/web && pnpm run dev

web-build: web-install web-generate-client web-cf-typegen ## Web: Build web application for production
	@echo "Building web for production..." && \
	cd apps/web && pnpm run build

web-preview: web-build ## Web: Preview production web build locally
	@echo "Previewing production build on http://localhost:4173" && \
	cd apps/web && pnpm run preview

web-lint: ## Web: Run web lint checks
	@cd apps/web && pnpm run lint

web-docker-build: ## Web: Build web Docker image
	@docker build -t edge-cache-lab-web:$(IMAGE_TAG) apps/web

web-ci: web-openapi-diff web-build web-lint web-docker-build ## CI: Run web-side CI checks locally

.PHONY: docker-build docker-up docker-down docker-logs

##@ Docker

docker-build: ## Docker: Build all Docker Compose services
	@docker compose build

docker-up: ## Docker: Start local stack with Docker Compose
	@docker compose up -d --build

docker-down: ## Docker: Stop local stack and remove orphan containers
	@docker compose down --remove-orphans

docker-logs: ## Docker: Follow Docker Compose logs
	@docker compose logs -f --tail=100

.PHONY: k8s-local-up k8s-local-down k8s-wait k8s-status k8s-logs k8s-port-forward-api k8s-port-forward-varnish k8s-port-forward-web k8s-lint k8s-remote-up

##@ Kubernetes

k8s-local-up: ## Kubernetes: Build local images and apply local kustomize overlay
	@docker build -t edge-cache-lab-api:k8s apps/api
	@docker build -t edge-cache-lab-varnish:k8s apps/varnish
	@docker build -t edge-cache-lab-web:k8s apps/web
	@kubectl apply -k $(K8S_OVERLAY_LOCAL)

k8s-local-down: ## Kubernetes: Delete local kustomize resources and local images
	@kubectl delete -k $(K8S_OVERLAY_LOCAL) --ignore-not-found
	@kubectl delete namespace $(K8S_NAMESPACE) --ignore-not-found
	@docker image rm -f edge-cache-lab-api:k8s > /dev/null 2>&1 || true
	@docker image rm -f edge-cache-lab-varnish:k8s > /dev/null 2>&1 || true
	@docker image rm -f edge-cache-lab-web:k8s > /dev/null 2>&1 || true

k8s-wait: ## Kubernetes: Wait for API deployment rollout
	@kubectl -n $(K8S_NAMESPACE) rollout status deployment/api

k8s-status: ## Kubernetes: Show Kubernetes resource status for namespace
	@kubectl -n $(K8S_NAMESPACE) get all

k8s-logs: ## Kubernetes: Tail API pod logs
	@kubectl -n $(K8S_NAMESPACE) logs -l app=api -f --tail=100

k8s-port-forward-api: ## Kubernetes: Port-forward API service to localhost:3000
	@kubectl -n $(K8S_NAMESPACE) port-forward svc/api 3000:3000

k8s-port-forward-varnish: ## Kubernetes: Port-forward Varnish service to localhost:6081
	@kubectl -n $(K8S_NAMESPACE) port-forward svc/varnish 6081:80

k8s-port-forward-web: ## Kubernetes: Port-forward web service to localhost:8080
	@kubectl -n $(K8S_NAMESPACE) port-forward svc/web 8080:80

k8s-lint: ## Kubernetes: Lint manifests with KubeLinter
	@echo "Linting Kubernetes manifests with KubeLinter..."
	@command -v kube-linter > /dev/null || (echo "KubeLinter not found, please install it (https://docs.kubelinter.io/)" && exit 1)
	@kube-linter lint infra/k8s

INSTANCE_ID ?=

k8s-remote-up: ## Kubernetes: Deploy production overlay remotely via EC2 helper script
	@if [ $(IMAGE_TAG) = "local" ]; then \
		echo "Error: IMAGE_TAG cannot be 'local' for remote deployment. Please specify a valid image tag (e.g., 'make k8s-remote-up IMAGE_TAG=v1.0.0')"; \
		exit 1; \
	fi;
	if [ -n "$(INSTANCE_ID)" ]; then \
		echo "Using provided INSTANCE_ID: $(INSTANCE_ID)"; \
		id=$(INSTANCE_ID); \
	else \
		cd infra/pulumi && id=$$($(PULUMI) stack output instance_id 2>/dev/null); \
		cd ../../ && echo "Using instance_id from Pulumi stack output: $$id"; \
	fi; \
	if [ -z "$$id" ]; then echo "No instance_id in stack outputs. See 'make pulumi-stack-output'"; exit 1; fi; \
	bash infra/scripts/deploy-k8s.sh \
		--instance-id $$id \
		--overlay-path $(K8S_OVERLAY_PRODUCTION) \
		--api-image-uri ghcr.io/sbasir/edge-cache-lab-api \
		--varnish-image-uri ghcr.io/sbasir/edge-cache-lab-varnish \
		--image-tag $(IMAGE_TAG)

# Pulumi and stack management targets

.PHONY: infra-init infra-preview infra-up infra-destroy infra-stack-output infra-stack-output-json infra-replace-instance infra-set-dns infra-set-dns-dry infra-remove-dns infra-up-set-dns infra-up-and-set-dns infra-github-actions-oidc-role

##@ Infrastructure

infra-init: ## Infra: Install Pulumi dependencies for infra project
	@cd infra/pulumi && \
	$(PULUMI) install

infra-preview: ## Infra: Preview infrastructure changes
	@cd infra/pulumi && \
	$(PULUMI) preview

infra-up: ## Infra: Apply infrastructure changes
	@cd infra/pulumi && \
	$(PULUMI) up

infra-destroy: ## Infra: Destroy infrastructure stack
	@cd infra/pulumi && \
	$(PULUMI) destroy --yes

infra-stack-output: ## Infra: Show Pulumi stack outputs
	@cd infra/pulumi && \
	$(PULUMI) stack output

infra-stack-output-json: ## Infra: Show Pulumi stack outputs as JSON
	@cd infra/pulumi && \
	$(PULUMI) stack output --json

infra-replace-instance: ## Infra: Replace Spot instance resources while preserving EIP
	@command -v jq >/dev/null 2>&1 || { echo "jq is required to find resource URNs. Install jq (e.g., 'brew install jq')"; exit 1; } ;
	@tmp=$$(mktemp); \
	cd infra/pulumi && \
	$(PULUMI) stack export > $$tmp; \
	spot_urn=$$(jq -r '.deployment.resources[] | select(.urn | contains("edge-cache-lab-spot")) | .urn' $$tmp | head -n1); \
	tag_urn=$$(jq -r '.deployment.resources[] | select(.urn | contains("edge-cache-lab-spot-name-tag")) | .urn' $$tmp | head -n1); \
	rm -f $$tmp; \
	if [ -z "$$spot_urn" ]; then echo "Could not find resource URN for 'edge-cache-lab-spot'. Run 'make infra-stack-output' or 'pulumi stack export' to inspect."; exit 1; fi; \
	if [ -z "$$tag_urn" ]; then echo "Could not find resource URN for 'edge-cache-lab-spot-name-tag'. Run 'make infra-stack-output' or 'pulumi stack export' to inspect."; exit 1; fi; \
	echo "Replacing resource $$spot_urn with $$tag_urn ..."; \
	$(PULUMI) up --yes --target-replace "$$spot_urn" --target-replace "$$tag_urn"

##@ Cloudflare

infra-set-dns: ## Cloudflare: Upsert API DNS A record to current stack public IP
	@cd infra/pulumi && DRY_RUN=0 ../scripts/cloudflare-set-dns.sh

infra-set-dns-dry: ## Cloudflare: Preview DNS changes without applying
	@cd infra/pulumi && DRY_RUN=1 ../scripts/cloudflare-set-dns.sh

infra-remove-dns: ## Cloudflare: Remove API DNS A record
	@cd infra/pulumi && ../scripts/cloudflare-remove-dns.sh

infra-up-set-dns: ## Infra: Apply infra changes and then update DNS
	@cd infra/pulumi && $(PULUMI) up --yes
	@$(MAKE) infra-set-dns

infra-up-and-set-dns: infra-up-set-dns ## Infra: Alias for infra-up-set-dns

infra-github-actions-oidc-role: ## Infra: Deploy GitHub Actions OIDC IAM role stack
	@command -v rain >/dev/null 2>&1 || { echo "`rain` is required to deploy GitHub Actions OIDC Role. Install rain (brew install rain)"; exit 1; } ;
	@command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required to retrieve OIDC Role ARN after deployment. Install AWS CLI (https://aws.amazon.com/cli/)"; exit 1; } ;
	@cd infra && \
	rain deploy github-actions-oidc-role.yaml \
		EdgeCacheLabGitHubActionsOIDC \
		--yes && \
	aws cloudformation describe-stacks \
		--stack-name=EdgeCacheLabGitHubActionsOIDC \
		--query 'Stacks[0].Outputs[?OutputKey == `GitHubActionsRoleArn`].OutputValue' \
		--output text \
		--no-cli-pager

# Instance and SSM helper targets

.PHONY: infra-deploy-logs infra-ec2-connect infra-ec2-port-forward infra-validate-k3s

infra-deploy-logs: ## Infra: Tail EC2 cloud-init bootstrap logs via SSM
	@echo "📊 Monitoring bootstrap progress:"
	@cd infra/pulumi && id=$$($(PULUMI) stack output instance_id 2>/dev/null); \
	if [ -z "$$id" ]; then echo "No instance_id in stack outputs. See 'make infra-stack-output'"; exit 1; fi; \
	$(AWS) ssm start-session --target $$id --document-name AWS-StartInteractiveCommand --parameters 'command=["sudo su -c \"tail -n 50 -f /var/log/cloud-init-output.log\""]' --region $(REGION)

infra-ec2-port-forward: ## Infra: Start SSM port-forward session to EC2 (local 6443)
	@cd infra/pulumi && id=$$($(PULUMI) stack output instance_id 2>/dev/null); \
	if [ -z "$$id" ]; then echo "No instance_id in stack outputs. See 'make infra-stack-output'"; exit 1; fi; \
	$(AWS) ssm start-session --target $$id --region $(REGION) --document-name AWS-StartPortForwardingSession \
    --parameters 'localPortNumber=6443,portNumber=6443'

infra-ec2-connect: ## Infra: Connect to EC2 instance via SSM Session Manager
	@cd infra/pulumi && id=$$($(PULUMI) stack output instance_id 2>/dev/null); \
	if [ -z "$$id" ]; then echo "No instance_id in stack outputs. See 'make pulumi-stack-output'"; exit 1; fi; \
	$(AWS) ssm start-session --target $$id --region $(REGION)

infra-validate-k3s: ## Testing: Validate k3s installation script on EC2 via SSM
	@echo "🔍 Validating k3s installation..."
	@echo ""
	@cd infra/pulumi && id=$$($(PULUMI) stack output instance_id 2>/dev/null); \
	if [ -z "$$id" ]; then echo "No instance_id in stack outputs. See 'make infra-stack-output'"; exit 1; fi; \
	$(AWS) ssm start-session --target $$id --document-name AWS-StartInteractiveCommand --parameters 'command=["sudo su -c /usr/local/bin/validate-k3s.sh"]'

.PHONY: validate-endpoints
PORT ?= 6081

##@ Testing

validate-endpoints: ## Testing: Validate API endpoints and cache behavior against localhost:PORT
	@if kubectl -n $(K8S_NAMESPACE) get svc/varnish > /dev/null 2>&1; then \
		echo "Detected Varnish service in Kubernetes..."; \
		if ! lsof -i :$(PORT) > /dev/null 2>&1; then \
			echo "✗ No process is listening on port $(PORT). Please ensure port-forwarding is set up correctly (e.g., 'make k8s-port-forward-varnish') and try again." >&2; \
			exit 1; \
		else \
			echo "Port-forwarding to localhost:$(PORT) is active..."; \
		fi; \
	fi;
	@set -e; \
	echo ""; \
	echo "✓ Validating API endpoints on http://localhost:$(PORT)"; \
	echo "Purging cache..."; \
	curl -s -f -X PURGE http://localhost:$(PORT)/ -H "X-Purge-Token: test-purge-token" > /dev/null 2>&1 || (echo "✗ Cache purge failed" >&2; exit 1); \
	echo ""; \
	echo "✓ GET /health"; \
	curl -s -f -i http://localhost:$(PORT)/health | grep -q "200 OK" || (echo "✗ /health failed" && exit 1); \
	echo "✓ GET / (homepage)"; \
	curl -s -f -i http://localhost:$(PORT)/ | grep -q "200 OK" || (echo "✗ / failed" && exit 1); \
	echo "✓ GET /category"; \
	curl -s -f -i http://localhost:$(PORT)/category | grep -q "200 OK" || (echo "✗ /category failed" && exit 1); \
	echo "✓ GET /product/prod-001 (cacheable)"; \
	curl -s -f -i http://localhost:$(PORT)/product/prod-001 | grep -q "X-Cache: MISS\|X-Cache: HIT" || (echo "✗ /product/prod-001 caching failed" && exit 1); \
	echo "✓ GET /cart (non-cacheable)"; \
	curl -s -f -i http://localhost:$(PORT)/cart | grep -q "X-Cache: PASS" || (echo "✗ /cart failed" && exit 1); \
	echo "✓ GET /account (non-cacheable)"; \
	curl -s -f -i http://localhost:$(PORT)/account | grep -q "X-Cache: PASS" || (echo "✗ /account failed" && exit 1); \
	echo "✓ POST /admin/product/prod-001 (with purge token)"; \
	curl -s -f -i -X POST http://localhost:$(PORT)/admin/product/prod-001 \
		-H "Content-Type: application/json" \
		-H "X-Purge-Token: test-purge-token" \
		-d '{"name":"Updated","inStock":false}' | grep -q "200 OK" || (echo "✗ /admin/product/prod-001 update failed" && exit 1); \
	echo "✓ POST /admin/product/prod-001 (invalid token - 401)"; \
	curl -s -i -X POST http://localhost:$(PORT)/admin/product/prod-001 \
		-H "Content-Type: application/json" \
		-H "X-Purge-Token: wrong-token" \
		-d '{"name":"Test"}' | grep -q "401 Unauthorized" || (echo "✗ /admin/product/prod-001 token validation failed" && exit 1); \
	echo ""; \
	echo "✓ All endpoints validated successfully on localhost:$(PORT)"

.PHONY: gh-act-app-ci gh-act-k8s-ci gh-act-web-ci gh-act-all-ci gh-dependencies gh-act-infra-up gh-act-infra-preview gh-act-infra-destroy gh-act-web-deploy gh-act-app-publish gh-act-app-tag gh-act-k8s-deploy

##@ CI

gh-act-app-ci: ## CI: Run app-ci GitHub Actions workflow locally with act
	@$(ACT) -W .github/workflows/app-ci.yaml $(ACT_FLAGS)

gh-act-k8s-ci: ## CI: Run k8s-ci GitHub Actions workflow locally with act
	@$(ACT) -W .github/workflows/k8s-ci.yaml $(ACT_FLAGS)

gh-act-web-ci: ## CI: Run web-ci GitHub Actions workflow locally with act
	@$(ACT) -W .github/workflows/web-ci.yaml $(ACT_FLAGS)

gh-act-all-ci: ## CI: Run app-ci, k8s-ci, and web-ci workflows locally
	@$(MAKE) gh-act-app-ci
	@$(MAKE) gh-act-k8s-ci
	@$(MAKE) gh-act-web-ci

gh-dependencies: ## CI: Verify local prerequisites for running act workflows
	@command -v act >/dev/null 2>&1 || { \
		echo "act is required to run GitHub Actions locally. Install act (e.g., 'brew install act')"; \
		exit 1; \
	};
	@if [ ! -f .env ]; then \
		echo "No .env file found. Create a .env file with required environment variables (see .env.example)"; \
		exit 1; \
	fi

FORCE ?= false

gh-act-infra-up: gh-dependencies ## CI: Run infra-up workflow locally using act
	@$(ACT) -W .github/workflows/infra-up.yaml \
		$(ACT_FLAGS) $(ACT_INFRA_FLAGS) \
		--env FORCE=$(FORCE)

gh-act-infra-preview: gh-dependencies ## CI: Run infra-preview workflow locally using act
	@$(ACT) -W .github/workflows/infra-preview.yaml \
		$(ACT_FLAGS) $(ACT_INFRA_FLAGS)

gh-act-infra-destroy: gh-dependencies ## CI: Run infra-destroy workflow locally using act
	@$(ACT) -W .github/workflows/infra-destroy.yaml \
		$(ACT_FLAGS) \
		$(ACT_INFRA_FLAGS) \
		--env FORCE=$(FORCE)

gh-act-web-deploy: gh-dependencies ## CI: Run web-deploy workflow locally using act
	@if [ -z "$(API_BASE_URL)" ]; then \
		echo "Error: API_BASE_URL environment variable is required for web deployment. Please set API_BASE_URL in your .env file or export it in your shell."; \
		exit 1; \
	fi;
	@$(ACT) -W .github/workflows/web-deploy.yaml \
		$(ACT_FLAGS) \
		$(ACT_WEB_FLAGS)

gh-act-app-publish: gh-dependencies ## CI: Run app-publish workflow locally using act
	@$(ACT) -W .github/workflows/app-publish.yaml \
		$(ACT_FLAGS) \
		-s GITHUB_TOKEN=$(gh auth token)

gh-act-app-tag: gh-dependencies ## CI: Run app-tag workflow locally using act
	@$(ACT) workflow_dispatch -W .github/workflows/app-tag.yaml \
		$(ACT_FLAGS) \
		--input suffix=act

gh-act-k8s-deploy: gh-dependencies ## CI: Run k8s-deploy workflow locally with tag event simulation
	@if [ -z "$(REF_TAG)" ]; then \
		echo "Error: REF_TAG environment variable is required (e.g., REF_TAG=v1.2.3)."; \
		exit 1; \
	fi;
	@tmp=$$(mktemp -d) && \
	echo "Simulating GitHub Actions workflow_dispatch for ref: refs/tags/$(REF_TAG)" && \
	printf '{\n  "ref": "refs/tags/$(REF_TAG)",\n  "ref_name": "$(REF_TAG)",\n  "ref_type": "tag"\n}\n' > "$$tmp/event.json" && \
	echo "Event payload:" && \
	cat "$$tmp/event.json" && \
	$(ACT) workflow_dispatch \
		-W .github/workflows/k8s-deploy.yaml \
		$(ACT_FLAGS) \
		$(ACT_INFRA_FLAGS) \
		-e "$$tmp/event.json" && \
	rm -rf "$$tmp"