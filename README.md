# Edge Cache Lab

A production-like, fully automated mini e-commerce platform that demonstrates CDN → Varnish → App → DB behavior, including CI/CD, observability, and safe operations.

## Prerequisites

* Go 1.26 (for API server and code generation)
* GoLangCI Lint (for static analysis)

```
# binary will be $(go env GOPATH)/bin/golangci-lint
curl -sSfL https://golangci-lint.run/install.sh | sh -s -- -b $(go env GOPATH)/bin v2.9.0
```

* Docker

## Local dev

```sh
make api-init
make openapi
make api-lint
make api-test
make api-run
curl -i http://localhost:3000/
curl -i http://localhost:3000/health
curl -i http://localhost:3000/category
curl -i http://localhost:3000/product/prod-001
curl -i http://localhost:3000/cart
curl -i http://localhost:3000/account

# Admin update (triggers purge tags)
curl -i -X POST http://localhost:3000/admin/product/prod-001 \
  -H 'Content-Type: application/json' \
  -d '{"name":"Updated Name","inStock":false}'
```

## Local Docker dev

**Note**: Docker Compose Varnish setup may encounter DNS resolution issues in certain CI environments. See [docs/docker-compose-issues.md](docs/docker-compose-issues.md) for details. For full Varnish functionality, use the Kubernetes deployment.

```sh
make docker-up
make docker-logs

# Access via Varnish (port 8080) - may not work in all Docker environments
curl -i http://localhost:8080/
curl -i http://localhost:8080/health
curl -i http://localhost:8080/category
curl -i http://localhost:8080/product/prod-001

# Verify cache behavior (X-Cache: MISS on first request, HIT on second)
curl -i http://localhost:8080/product/prod-001
curl -i http://localhost:8080/product/prod-001

# Verify bypass for non-cacheable endpoints (X-Cache: PASS)
curl -i http://localhost:8080/cart
curl -i http://localhost:8080/account

make docker-down
```

## API Contract

The OpenAPI spec is the source of truth:

```sh
make openapi-validate
make openapi
```

Generated types live in `apps/api/internal/api/api.gen.go` and handlers in `apps/api/cmd/server`.

## Varnish Cache

Implementation with reverse proxy caching. See [docs/varnish.md](docs/varnish.md) for details.

## Kubernetes

Deploy to local Kubernetes:

```sh
# Deploy API and Varnish
make k8s-test-local

# Wait for rollout
make k8s-wait

# Check status
make k8s-status

# Port-forward Varnish (access at http://localhost:8080)
make k8s-port-forward-varnish

# In another terminal, test cache behavior
curl -i http://localhost:8080/product/prod-001  # X-Cache: MISS
curl -i http://localhost:8080/product/prod-001  # X-Cache: HIT
curl -i http://localhost:8080/cart              # X-Cache: PASS

# Cleanup
make k8s-clean-local
```
