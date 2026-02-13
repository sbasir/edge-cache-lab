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
make api-test
make api-run
curl http://localhost:3000/
```

## Local Docker dev

```sh
make docker-up
make docker-logs

curl -i http://localhost:3000/

make docker-down
```
