# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Production-like mini e-commerce platform demonstrating CDN → Varnish → Go API caching. Contract-first development with OpenAPI 3.0.3 as the single source of truth. Three apps: Go API server, Varnish reverse proxy cache, React SPA frontend.

## Common Commands

```bash
# Full local stack (web :8080, varnish :6081, API :3000)
make docker-up
make docker-down
make docker-logs

# API development
make api-run              # Run API locally on :3000
make api-test             # Run tests with coverage
make api-lint             # golangci-lint
make api-fmt              # Format Go code

# OpenAPI workflow (always start here for API changes)
make openapi-validate     # Validate spec
make openapi              # Regenerate Go server code from spec
make openapi-diff         # Fail if generated code is out of sync

# Web frontend
make web-install          # Install pnpm dependencies
make web-generate-client  # Regenerate TypeScript client from spec
make web-run              # Vite dev server on :5173
make web-build            # Production build
make web-lint             # ESLint

# Integration testing (requires docker-up or k8s-local-up)
make validate-endpoints   # Test cache HIT/MISS/PASS behavior, purge, token validation

# Kubernetes local
make k8s-local-up         # Build images + apply local Kustomize overlay
make k8s-wait             # Wait for rollout
make k8s-port-forward-varnish  # Port-forward varnish to localhost

# Infrastructure
make infra-init           # Install Pulumi dependencies
make infra-up             # Apply Pulumi changes (AWS EC2 k3s)
```

## Architecture

**Request flow:** Browser → Web (nginx SPA) → Varnish (cache layer) → Go API

### Contract-First Development

All API changes follow this workflow:
1. Edit `openapi/api.yaml` (the single source of truth)
2. `make openapi` → regenerates `apps/api/internal/api/api.gen.go` (oapi-codegen v2.5.1)
3. Implement/update handlers in `apps/api/cmd/server/main.go` satisfying the `ServerInterface`
4. `make web-generate-client` → regenerates `apps/web/src/api/` (openapi-typescript-codegen)

**Never manually edit:**
- `apps/api/internal/api/api.gen.go` — generated Go types + chi-server interface
- `apps/web/src/api/` — generated TypeScript client

### Go API (`apps/api`)

- Go 1.26, chi/v5 router, oapi-codegen runtime
- Single file server: `cmd/server/main.go` implements all handlers
- Tests: `cmd/server/main_test.go` using testify (httptest-based)
- Cache headers pattern:
  - **Cacheable endpoints** (`/health`, `/`, `/category`, `/product/{id}`): call `setCacheHeaders()` which sets `Cache-Control: public`, `Surrogate-Control`, `ETag`, `X-Cache`
  - **Non-cacheable endpoints** (`/cart`, `/account`): set `Cache-Control: no-store, no-cache, must-revalidate`
- Every response includes `X-Request-Id` (chi middleware) and response meta (timestamp, instance, headersReceived)
- Admin update endpoint requires `X-Purge-Token` header, returns `X-Purge-Tags: product:{id}`
- Instance identity: `INSTANCE_NAME` env var or hostname

### Varnish Cache (`apps/varnish`)

- `default.vcl.template` uses placeholder variables (`BACKEND_HOST`, `PURGE_TOKEN`) rendered at container startup by `docker-entrypoint.sh`
- Bypass rules: `/cart`, `/account`, requests with `session` cookie → always PASS
- PURGE method validates token, bans by URL or product ID
- Adds `X-Cache: HIT/MISS/PASS` and `X-Cache-Hits` headers
- TTL: 2 minutes for 200 responses
- CORS validation against origin whitelist

### Web Frontend (`apps/web`)

- React 19, TypeScript 5.9, Vite 7.3, react-router-dom v7
- Deployable to Cloudflare Workers (Wrangler) or as Docker container (nginx)
- `CacheInfo` component displays response cache headers for debugging
- API base URL configurable at runtime via UI

### Infrastructure

- **Pulumi** (Python 3.14+) in `infra/pulumi/` — AWS EC2 Spot instance running k3s
- **Kubernetes** manifests in `infra/k8s/` — Kustomize overlays for local and production
- **Docker Compose** for local development — bridge network `varnish-net` for service discovery
- Purge token for local testing: `test-purge-token`

## CI/CD

GitHub Actions workflows with path-based triggers:
- **app-ci** (`apps/api/*`, `apps/varnish/*`, `openapi/*`): OpenAPI validate + diff, golangci-lint, tests, Docker build
- **web-ci** (`apps/web/*`, `openapi/*`): Client generation drift check, ESLint, Vite build, Docker build
- **k8s-ci**: KubeLinter validation of manifests
- **infra-preview/up/destroy**: Pulumi lifecycle (OIDC auth, no static AWS creds)
- **app-publish**: Build + push Docker images to GHCR
- **k8s-deploy**: Deploy to EC2 k3s via SSM
