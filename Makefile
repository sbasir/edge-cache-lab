SHELL := /bin/bash

.PHONY: help api-init api-install api-update api-run api-test docker-build docker-up docker-down docker-logs

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "API:"
	@echo "  api-init     - Initialize the API module"
	@echo "  api-install  - Install API dependencies"
	@echo "  api-run      - Run the API server"
	@echo "  api-test     - Run tests for the API"
	@echo ""
	@echo "Docker:"
	@echo "  docker-build - Build the Docker images"
	@echo "  docker-up    - Start the application using Docker Compose"
	@echo "  docker-down  - Stop the application and remove containers"
	@echo "  docker-logs  - Follow the logs of the application"

api-init:
	@cd apps/api && go mod init edge-cache-lab/apps/api

api-install:
	@cd apps/api && \
	go get -u github.com/go-chi/chi/v5 && \
	go get -u "github.com/stretchr/testify/require" && \
	go mod tidy

api-update:
	@cd apps/api && go get -u ./... && go mod tidy

api-run: api-install
	@echo "Starting API server on http://localhost:3000" && \
	cd apps/api && go run ./...

api-test: api-install
	@cd apps/api && go test ./... -v -cover

docker-build:
	@docker compose build

docker-up:
	@docker compose up -d --build

docker-down:
	@docker compose down --remove-orphans

docker-logs:
	@docker compose logs -f --tail=100
