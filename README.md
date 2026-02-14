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

```sh
make docker-up
make docker-logs

curl -i http://localhost:3000/
curl -i http://localhost:3000/health
curl -i http://localhost:3000/category
curl -i http://localhost:3000/product/prod-001

make docker-down
```

## API Contract

The OpenAPI spec is the source of truth:

```sh
make openapi-validate
make openapi
```

Generated types live in `apps/api/internal/api/api.gen.go` and handlers in `apps/api/cmd/server`.
