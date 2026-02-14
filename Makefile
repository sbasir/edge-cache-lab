SHELL := /bin/bash
# Use Make's shell() to evaluate `go env GOPATH` when the Makefile is read
GOLANGCI := $(shell go env GOPATH)/bin/golangci-lint
OAPI_CODEGEN := $(shell go env GOPATH)/bin/oapi-codegen

K8S_NAMESPACE ?= edge-cache-api
K8S_OVERLAY_LOCAL ?= infra/k8s/overlays/local

PURGE_TOKEN ?= test-purge-token

.PHONY: help api-init api-install api-update api-run api-test api-lint api-fmt openapi openapi-validate docker-build docker-up docker-down docker-logs k8s-varnish-vcl-sync k8s-local-up k8s-local-down k8s-wait k8s-status k8s-logs k8s-port-forward k8s-port-forward-varnish validate-endpoints

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "API:"
	@echo "  api-init     - Initialize the API module"
	@echo "  api-install  - Install API dependencies"
	@echo "  api-run      - Run the API server"
	@echo "  api-test     - Run tests for the API"
	@echo "  api-lint     - Run linters for the API"
	@echo "  api-fmt      - Format the API code"
	@echo ""
	@echo "OpenAPI:"
	@echo "  openapi          - Generate Go code from OpenAPI spec"
	@echo "  openapi-validate - Validate OpenAPI spec"
	@echo ""
	@echo "Docker:"
	@echo "  docker-build - Build the Docker images"
	@echo "  docker-up    - Start the application using Docker Compose"
	@echo "  docker-down  - Stop the application and remove containers"
	@echo "  docker-logs  - Follow the logs of the application"
	@echo ""
	@echo "Kubernetes:"
	@echo "  make k8s-varnish-vcl-sync             - Generate Kubernetes VCL from template"
	@echo "  make k8s-local-up                     - Deploy to local k8s (e.g., OrbStack) or Docker environment"
	@echo "  make k8s-local-down                   - Remove local k8s resources (namespace, local image)"
	@echo "  make k8s-wait                         - Wait for deployment rollout to complete"
	@echo "  make k8s-status                       - Get status of resources"
	@echo "  make k8s-logs                         - Tail logs"
	@echo "  make k8s-port-forward                 - Port-forward the API service"
	@echo "  make k8s-port-forward-varnish         - Port-forward the Varnish service"
	@echo ""
	@echo "Testing:"
	@echo "  validate-endpoints PORT=<port>       - Validate all API endpoints (default PORT=6081)"
api-init:
	@cd apps/api && if [ ! -f go.mod ]; then go mod init edge-cache-lab/apps/api; fi && \
	go get -u github.com/go-chi/chi/v5 && \
	go get -u "github.com/stretchr/testify/require" && \
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
	@which $(OAPI_CODEGEN) > /dev/null || go install github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@latest
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

docker-build:
	@docker compose build

docker-up:
	@docker compose up -d --build

docker-down:
	@docker compose down --remove-orphans

docker-logs:
	@docker compose logs -f --tail=100

k8s-varnish-vcl-sync:
	@BACKEND_HOST=edge-cache-api PURGE_TOKEN=$(PURGE_TOKEN) ./apps/varnish/render-k8s-vcl.sh

k8s-local-up: k8s-varnish-vcl-sync
	@docker build -t edge-cache-lab-api:local apps/api
	@kubectl apply -k $(K8S_OVERLAY_LOCAL)

k8s-port-forward:
	@kubectl -n $(K8S_NAMESPACE) port-forward svc/edge-cache-api 3000:3000

k8s-local-down:
	@kubectl delete -k $(K8S_OVERLAY_LOCAL) --ignore-not-found
	@kubectl delete namespace $(K8S_NAMESPACE) --ignore-not-found
	@docker image rm -f edge-cache-lab-api:local > /dev/null 2>&1 || true

k8s-wait:
	@kubectl -n $(K8S_NAMESPACE) rollout status deployment/edge-cache-api

k8s-status:
	@kubectl -n $(K8S_NAMESPACE) get all

k8s-logs:
	@kubectl -n $(K8S_NAMESPACE) logs -l app=edge-cache-api -f --tail=100

k8s-port-forward-varnish:
	@kubectl -n $(K8S_NAMESPACE) port-forward svc/varnish 6081:80

PORT ?= 6081

validate-endpoints:
	@echo "Validating endpoints on localhost:$(PORT)..."
	@set -e; \
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

# Backwards compatibility aliases
.PHONY: k8s-test-local k8s-clean-local
k8s-test-local: k8s-local-up
k8s-clean-local: k8s-local-down