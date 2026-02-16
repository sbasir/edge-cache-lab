SHELL := /bin/bash
# Use Make's shell() to evaluate `go env GOPATH` when the Makefile is read
GOLANGCI := $(shell go env GOPATH)/bin/golangci-lint
OAPI_CODEGEN := $(shell go env GOPATH)/bin/oapi-codegen
ACT ?= act
ACT_FLAGS ?= --platform ubuntu-latest=ghcr.io/catthehacker/ubuntu:act-latest \
	--container-architecture linux/amd64 \
	--pull=false

ACT_INFRA_FLAGS = -s PULUMI_ACCESS_TOKEN=$(PULUMI_ACCESS_TOKEN) \
	-s CF_API_TOKEN=$(CF_API_TOKEN) \
	-s CF_ZONE_ID=$(CF_ZONE_ID) \
	--var CF_RECORD_NAME=$(CF_RECORD_NAME) \
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
include .env
# Export variables loaded from .env to shell recipes
export $(filter-out MAKEFILE_LIST, $(.VARIABLES))
endif

IMAGE_TAG ?= local

K8S_NAMESPACE ?= edge-cache-lab
K8S_OVERLAY_LOCAL ?= infra/k8s/overlays/local

PURGE_TOKEN ?= test-purge-token

.PHONY: help 
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "API:"
	@echo "  api-init            - Initialize the API module"
	@echo "  api-install         - Install API dependencies"
	@echo "  api-run             - Run the API server"
	@echo "  api-test            - Run tests for the API"
	@echo "  api-lint            - Run linters for the API"
	@echo "  api-fmt             - Format the API code"
	@echo "  api-docker-build    - Build the API Docker image"
	@echo ""
	@echo "Web:"
	@echo "  web-install         - Install web dependencies"
	@echo "  web-generate-client - Generate OpenAPI TypeScript client"
	@echo "  web-run             - Run the web dev server"
	@echo "  web-build           - Build web for production"
	@echo "  web-preview         - Preview production build"
	@echo "  web-lint            - Lint web code"
	@echo "  web-docker-build    - Build web Docker image"
	@echo ""
	@echo "OpenAPI:"
	@echo "  openapi             - Generate Go code from OpenAPI spec"
	@echo "  openapi-validate    - Validate OpenAPI spec"
	@echo "  openapi-diff        - Fail if generated OpenAPI code differs"
	@echo ""
	@echo "Docker:"
	@echo "  docker-build        - Build the Docker images"
	@echo "  docker-up           - Start the application using Docker Compose"
	@echo "  docker-down         - Stop the application and remove containers"
	@echo "  docker-logs         - Follow the logs of the application"
	@echo ""
	@echo "Kubernetes:"
	@echo "  make k8s-varnish-vcl-sync      - Generate Kubernetes VCL from template"
	@echo "  make k8s-local-up              - Deploy to local k8s (e.g., OrbStack) or Docker environment"
	@echo "  make k8s-local-down            - Remove local k8s resources (namespace, local image)"
	@echo "  make k8s-wait                  - Wait for deployment rollout to complete"
	@echo "  make k8s-status                - Get status of resources"
	@echo "  make k8s-logs                  - Tail logs"
	@echo "  make k8s-port-forward-api      - Port-forward the API service"
	@echo "  make k8s-port-forward-varnish  - Port-forward the Varnish service"
	@echo "  make k8s-port-forward-web      - Port-forward the Web service"
	@echo ""
	@echo "Pulumi / Stack Commands:"
	@echo "  infra-init                     - Initialize Pulumi stack (defaults to 'dev')"
	@echo "  infra-preview                  - Run 'pulumi preview' to inspect changes"
	@echo "  infra-up                       - Deploy the stack (interactive)"
	@echo "  infra-destroy                  - Destroy the Pulumi stack"
	@echo "  infra-stack-output             - Show stack outputs (plain)"
	@echo "  infra-stack-output-json        - Show stack outputs as JSON"
	@echo "  infra-replace-instance         - Replace the Spot instance resource with a fresh instance (preserves EIP)"
	@echo "  infra-up-and-sync              - Run 'make infra-up --yes' then 'make infra-set-dns' (convenience)"
	@echo "  infra-github-actions-oidc-role - Create GitHub Actions IAM Role"
	@echo ""
	@echo "Cloudflare DNS helpers:"
	@echo "  infra-set-dns                  - Upsert A record for $(CF_RECORD_NAME) to the stack public IP (requires CF_API_TOKEN + CF_ZONE_ID)"
	@echo "  infra-set-dns-dry              - Dry-run: show what would be updated but do not modify DNS (useful to preview)"
	@echo "  infra-remove-dns               - Remove A record for $(CF_RECORD_NAME) from Cloudflare"
	@echo ""	
	@echo "CI:"
	@echo "  app-ci                         - Run API CI checks locally"
	@echo "  web-ci                         - Run Web CI checks locally"
	@echo "  gh-act-app-ci                  - Run GitHub Actions workflow with act"
	@echo "  gh-act-k8s-ci                  - Run Kubernetes CI workflow with act"
	@echo "  gh-act-web-ci                  - Run Web CI workflow with act"
	@echo "  gh-act-all-ci                  - Run all GitHub Actions workflows with act"
	@echo "  gh-dependencies                - Check for act and .env before running GitHub Actions locally"
	@echo "  gh-act-infra-up                - Run the 'infra-up.yaml' GitHub Actions workflow locally using 'act'"
	@echo "  gh-act-infra-preview           - Run the 'infra-preview.yaml' GitHub Actions workflow locally using 'act'"
	@echo "  gh-act-infra-destroy FORCE     - Run the 'infra-destroy.yaml' GitHub Actions workflow locally using 'act'. Use FORCE=true to skip confirmation prompt in destroy workflow."

	@echo ""
	@echo "Testing:"
	@echo "  validate-endpoints PORT        - Validate all API endpoints (default PORT=6081)"

.PHONY: api-init api-install api-update api-run api-test api-lint api-fmt openapi openapi-validate openapi-diff api-docker-build app-ci

api-init:
	@cd apps/api && if [ ! -f go.mod ]; then go mod init edge-cache-lab/apps/api; fi && \
	go get -u github.com/go-chi/chi/v5 && \
	go get -u github.com/stretchr/testify/require && \
	go mod tidy

api-install:
	@cd apps/api && \
	go mod download && \
	go mod tidy

api-update:
	@cd apps/api && go get -u ./... && go mod tidy

api-run: api-install
	@echo "Starting API server on http://localhost:3000" && \
	cd apps/api && go run ./...

api-test: api-install
	@cd apps/api && go test ./... -v -cover

api-lint:
	@cd apps/api && $(GOLANGCI) run

api-fmt:
	@cd apps/api && $(GOLANGCI) fmt

openapi:
	@echo "Installing oapi-codegen if needed..."
	@which $(OAPI_CODEGEN) > /dev/null || go install github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@v2.5.1
	@echo "Generating Go code from OpenAPI spec..."
	@mkdir -p apps/api/internal/api
	@$(OAPI_CODEGEN) -generate types,chi-server \
		-package api \
		openapi/api.yaml > apps/api/internal/api/api.gen.go
	@echo "✓ Generated apps/api/internal/api/api.gen.go"

openapi-validate:
	@echo "Validating OpenAPI spec..."
	@$(OAPI_CODEGEN) -generate types \
		-package api \
		openapi/api.yaml > /dev/null 2>&1 && echo "✓ OpenAPI spec is valid" || (echo "✗ OpenAPI spec validation failed" && exit 1)

openapi-diff: openapi
	@echo "Checking for OpenAPI codegen drift..."
	@git diff --exit-code -- apps/api/internal/api/api.gen.go
	@echo "✓ OpenAPI codegen is in sync"

api-docker-build:
	@docker build -t edge-cache-lab-api:$(IMAGE_TAG) apps/api

app-ci: openapi-validate openapi-diff api-lint api-test api-docker-build

.PHONY: web-install web-generate-client web-run web-build web-preview web-lint web-docker-build

web-install:
	@echo "Installing web dependencies..."
	@cd apps/web && corepack enable && corepack prepare pnpm@10.28.1 --activate && pnpm install

web-generate-client:
	@echo "Generating OpenAPI TypeScript client..."
	@cd apps/web && pnpm run generate-client
	@echo "✓ Generated TypeScript client in apps/web/src/api"

web-run: web-install web-generate-client
	@echo "Starting web dev server on http://localhost:5173" && \
	cd apps/web && pnpm run dev

web-build: web-install web-generate-client
	@echo "Building web for production..." && \
	cd apps/web && pnpm run build

web-preview: web-build
	@echo "Previewing production build on http://localhost:4173" && \
	cd apps/web && pnpm run preview

web-lint:
	@cd apps/web && pnpm run lint

web-docker-build:
	@docker build -t edge-cache-lab-web:$(IMAGE_TAG) apps/web

web-ci: web-build web-lint web-docker-build

.PHONY: docker-build docker-up docker-down docker-logs

docker-build:
	@docker compose build

docker-up:
	@docker compose up -d --build

docker-down:
	@docker compose down --remove-orphans

docker-logs:
	@docker compose logs -f --tail=100

.PHONY: k8s-varnish-vcl-sync k8s-local-up k8s-local-down k8s-wait k8s-status k8s-logs k8s-port-forward-api k8s-port-forward-varnish k8s-lint

k8s-varnish-vcl-sync:
	@BACKEND_HOST=api PURGE_TOKEN=$(PURGE_TOKEN) ./apps/varnish/render-k8s-vcl.sh

k8s-local-up: k8s-varnish-vcl-sync
	@docker build -t edge-cache-lab-api:k8s apps/api
	@docker build -t edge-cache-lab-web:k8s apps/web
	@kubectl apply -k $(K8S_OVERLAY_LOCAL)

k8s-local-down:
	@kubectl delete -k $(K8S_OVERLAY_LOCAL) --ignore-not-found
	@kubectl delete namespace $(K8S_NAMESPACE) --ignore-not-found
	@docker image rm -f edge-cache-lab-api:k8s > /dev/null 2>&1 || true
	@docker image rm -f edge-cache-lab-web:k8s > /dev/null 2>&1 || true

k8s-wait:
	@kubectl -n $(K8S_NAMESPACE) rollout status deployment/api

k8s-status:
	@kubectl -n $(K8S_NAMESPACE) get all

k8s-logs:
	@kubectl -n $(K8S_NAMESPACE) logs -l app=api -f --tail=100

k8s-port-forward-api:
	@kubectl -n $(K8S_NAMESPACE) port-forward svc/api 3000:3000

k8s-port-forward-varnish:
	@kubectl -n $(K8S_NAMESPACE) port-forward svc/varnish 6081:80

k8s-port-forward-web:
	@kubectl -n $(K8S_NAMESPACE) port-forward svc/web 8080:80

k8s-lint:
	@echo "Linting Kubernetes manifests with KubeLinter..."
	@command -v kube-linter > /dev/null || (echo "KubeLinter not found, please install it (https://docs.kubelinter.io/)" && exit 1)
	@kube-linter lint infra/k8s

# Pulumi and stack management targets

.PHONY: infra-init infra-preview infra-up infra-destroy infra-stack-output infra-stack-output-json infra-github-actions-oidc-role

infra-init:
	@cd infra/pulumi && \
	$(PULUMI) install

infra-preview:
	@cd infra/pulumi && \
	$(PULUMI) preview

infra-up:
	@cd infra/pulumi && \
	$(PULUMI) up

infra-destroy:
	@cd infra/pulumi && \
	$(PULUMI) destroy --yes

infra-stack-output:
	@cd infra/pulumi && \
	$(PULUMI) stack output

infra-stack-output-json:
	@cd infra/pulumi && \
	$(PULUMI) stack output --json

infra-replace-instance:
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

infra-set-dns:
	@cd infra/pulumi && DRY_RUN=0 ../scripts/cloudflare-set-dns.sh

infra-set-dns-dry:
	@cd infra/pulumi && DRY_RUN=1 ../scripts/cloudflare-set-dns.sh

infra-remove-dns:
	@cd infra/pulumi && ../scripts/cloudflare-remove-dns.sh

infra-up-set-dns:
	@cd infra/pulumi && $(PULUMI) up --yes
	@$(MAKE) infra-set-dns

infra-github-actions-oidc-role:
	@cd infra && \
	aws cloudformation deploy \
		--template-file github-actions-oidc-role.yaml \
		--stack-name EdgeCacheLabGitHubActionsOIDC \
		--color on \
		--capabilities CAPABILITY_NAMED_IAM && \
	aws cloudformation describe-stacks \
		--stack-name=EdgeCacheLabGitHubActionsOIDC \
		--query 'Stacks[0].Outputs[?OutputKey == `GitHubActionsRoleArn`].OutputValue' \
		--output text \
		--no-cli-pager

# Instance and SSM helper targets

.PHONY: infra-deploy-logs infra-ec2-connect

infra-deploy-logs:
	@echo "📊 Monitoring bootstrap progress:"
	@cd infra/pulumi && id=$$($(PULUMI) stack output instance_id 2>/dev/null); \
	if [ -z "$$id" ]; then echo "No instance_id in stack outputs. See 'make infra-stack-output'"; exit 1; fi; \
	$(AWS) ssm start-session --target $$id --document-name AWS-StartInteractiveCommand --parameters 'command=["sudo su -c \"tail -n 50 -f /var/log/cloud-init-output.log\""]' --region $(REGION)

infra-ec2-connect:
	@cd infra/pulumi && id=$$($(PULUMI) stack output instance_id 2>/dev/null); \
	if [ -z "$$id" ]; then echo "No instance_id in stack outputs. See 'make infra-stack-output'"; exit 1; fi; \
	$(AWS) ssm start-session --target $$id --region $(REGION)

infra-validate-k3s:
	@echo "🔍 Validating k3s installation..."
	@echo ""
	@cd infra/pulumi && id=$$($(PULUMI) stack output instance_id 2>/dev/null); \
	if [ -z "$$id" ]; then echo "No instance_id in stack outputs. See 'make infra-stack-output'"; exit 1; fi; \
	$(AWS) ssm start-session --target $$id --document-name AWS-StartInteractiveCommand --parameters 'command=["sudo su -c /usr/local/bin/validate-k3s.sh"]'

.PHONY: validate-endpoints
PORT ?= 6081

validate-endpoints:
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

.PHONY: gh-act-app-ci gh-act-k8s-ci gh-act-web-ci gh-act-all-ci gh-dependencies gh-act-infra-up gh-act-infra-preview gh-act-infra-destroy

gh-act-app-ci:
	@$(ACT) -W .github/workflows/app-ci.yaml $(ACT_FLAGS)

gh-act-k8s-ci:
	@$(ACT) -W .github/workflows/k8s-ci.yaml $(ACT_FLAGS)

gh-act-web-ci:
	@$(ACT) -W .github/workflows/web-ci.yaml $(ACT_FLAGS)

gh-act-all-ci:
	@$(MAKE) gh-act-app-ci
	@$(MAKE) gh-act-k8s-ci
	@$(MAKE) gh-act-web-ci

gh-dependencies:
	@command -v act >/dev/null 2>&1 || { \
		echo "act is required to run GitHub Actions locally. Install act (e.g., 'brew install act')"; \
		exit 1; \
	};
	@if [ ! -f .env ]; then \
		echo "No .env file found. Create a .env file with required environment variables (see .env.example)"; \
		exit 1; \
	fi

FORCE ?= false

gh-act-infra-up: gh-dependencies
	@$(ACT) -W .github/workflows/infra-up.yaml \
		$(ACT_FLAGS) $(ACT_INFRA_FLAGS) \
		--env FORCE=$(FORCE)

gh-act-infra-preview: gh-dependencies
	@$(ACT) -W .github/workflows/infra-preview.yaml \
		$(ACT_FLAGS) $(ACT_INFRA_FLAGS)

gh-act-infra-destroy: gh-dependencies 
	@$(ACT) -W .github/workflows/infra-destroy.yaml \
		$(ACT_FLAGS) \
		$(ACT_INFRA_FLAGS) \
		--env FORCE=$(FORCE)