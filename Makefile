SHELL := /bin/bash
# Use Make's shell() to evaluate `go env GOPATH` when the Makefile is read
GOLANGCI := $(shell go env GOPATH)/bin/golangci-lint
OAPI_CODEGEN := $(shell go env GOPATH)/bin/oapi-codegen

K8S_NAMESPACE ?= edge-cache-api
K8S_OVERLAY_LOCAL ?= infra/k8s/overlays/local

.PHONY: help api-init api-install api-update api-run api-test api-lint api-fmt openapi openapi-validate docker-build docker-up docker-down docker-logs k8s-test-local k8s-clean-local k8s-wait k8s-status k8s-logs k8s-port-forward k8s-port-forward-varnish

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
	@echo "  make k8s-test-local                   - Run manifests against a local k8s (e.g., OrbStack) or Docker environment"
	@echo "  make k8s-clean-local                  - Remove local test resources (namespace, local image)"
	@echo "  make k8s-wait                         - Wait for deployment rollout to complete"
	@echo "  make k8s-status                       - Get status of resources"
	@echo "  make k8s-logs                         - Tail logs"
	@echo "  make k8s-port-forward                 - Port-forward the API service"
	@echo "  make k8s-port-forward-varnish         - Port-forward the Varnish service"
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

k8s-test-local:
	@docker build -t edge-cache-lab-api:local apps/api
	@kubectl apply -k $(K8S_OVERLAY_LOCAL)

k8s-port-forward:
	@kubectl -n $(K8S_NAMESPACE) port-forward svc/edge-cache-api 3000:3000

k8s-clean-local:
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
	@kubectl -n $(K8S_NAMESPACE) port-forward svc/varnish 8080:80
