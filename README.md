# Edge Cache Lab

A production-like, fully automated mini e-commerce platform that demonstrates CDN → Varnish → App → DB behavior, including CI/CD, observability, and safe operations.

## Current Status

Phases 0-5 are implemented and validated locally and in Kubernetes (OpenAPI contract, cache headers, Varnish HIT/MISS/PASS, and purge via `PURGE` with `X-Purge-Token`).

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

# Access via Varnish (Docker host port 6081 -> Varnish container port 80)
curl -i http://localhost:6081/
curl -i http://localhost:6081/health
curl -i http://localhost:6081/category
curl -i http://localhost:6081/product/prod-001

# Verify cache behavior (X-Cache: MISS on first request, HIT on second)
curl -i http://localhost:6081/product/prod-001
curl -i http://localhost:6081/product/prod-001

# Verify bypass for non-cacheable endpoints (X-Cache: PASS)
curl -i http://localhost:6081/cart
curl -i http://localhost:6081/account

make docker-down
```

## API Contract

The OpenAPI spec is the source of truth:

```sh
make openapi-validate
make openapi
```

Generated types live in `apps/api/internal/api/api.gen.go` and handlers in `apps/api/cmd/server`.

## CI/CD Baseline

GitHub Actions runs OpenAPI validation, codegen drift checks, lint/test, and a Docker image build for the API.

Local CI run:

```sh
make app-ci
```

Run the workflow with `act`:

```sh
make gh-act-app-ci
```

## Varnish Cache

Implementation with reverse proxy caching. See [docs/varnish.md](docs/varnish.md) for details.

## Cache Purge / Invalidation

Update a product and purge cached content with a token:

```sh
# With Docker Compose (through Varnish)
curl -i -X POST http://localhost:6081/admin/product/prod-001 \
  -H 'Content-Type: application/json' \
  -H 'X-Purge-Token: test-purge-token' \
  -d '{"name":"Updated Product","inStock":false}'

# Response includes X-Purge-Tags (e.g., product:prod-001) for purge tooling.

# Purge cached product by URL (Varnish only supports PURGE here)
curl -i -X PURGE http://localhost:6081/product/prod-001 \
  -H 'X-Purge-Token: test-purge-token'

# Verify purge worked - next GET should be MISS
curl -i http://localhost:6081/product/prod-001  # X-Cache: MISS
```

Purge token is validated by both the API and Varnish. The default token is `test-purge-token`.

For non-default tokens:
- Set the `PURGE_TOKEN` environment variable in the API deployment to your desired token value.
- Configure Varnish (e.g., in the VCL) to expect the same token value.
- Ensure the token value matches in both the API environment variable and the Varnish configuration; mismatches will cause purge requests to be rejected.
- When changing the token, update all of these places and redeploy/reload both the API and Varnish.
## Endpoint Validation

Run comprehensive endpoint tests:

```sh
# Test against Docker Compose (default port 6081)
make docker-up
make validate-endpoints

# Test against Kubernetes (after port-forward)
make k8s-local-up && make k8s-wait
make k8s-port-forward-varnish  # in one terminal
make validate-endpoints        # in another
make k8s-local-down
```

## Kubernetes

Deploy to local Kubernetes:

```sh
# Deploy API and Varnish
make k8s-local-up

# Wait for rollout
make k8s-wait

# Check status
make k8s-status

# Port-forward Varnish (access at http://localhost:6081)
make k8s-port-forward-varnish

# In another terminal, test cache behavior
curl -i http://localhost:6081/product/prod-001  # X-Cache: MISS
curl -i http://localhost:6081/product/prod-001  # X-Cache: HIT
curl -i http://localhost:6081/cart              # X-Cache: PASS

# Cleanup
make k8s-local-down
```

## Infrastructure as Code (Pulumi)

Deploy k3s cluster on AWS spot instance with automated edge-cache-lab deployment:

```sh
# Initialize (first time)
cd infra/pulumi
npm install
pulumi stack init dev
pulumi config set aws:region us-east-1

# Deploy infrastructure
make infra-up

# View outputs (public IP, SSM command, etc.)
make infra-status

# Access via SSM Session Manager
make infra-ssm-connect

# Configure kubectl for remote k3s cluster
make infra-kubeconfig
kubectl get nodes

# Access Varnish endpoint (get URL from outputs)
curl $(cd infra/pulumi && pulumi stack output varnishEndpoint)/health

# Teardown
make infra-down
```

See [infra/pulumi/README.md](infra/pulumi/README.md) for details.

