SHELL := /bin/bash
# Use Make's shell() to evaluate `go env GOPATH` when the Makefile is read
GOLANGCI := $(shell go env GOPATH)/bin/golangci-lint
OAPI_CODEGEN := $(shell go env GOPATH)/bin/oapi-codegen

.PHONY: help api-init api-install api-update api-run api-test openapi openapi-validate docker-build docker-up docker-down docker-logs

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
