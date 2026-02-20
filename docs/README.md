# Documentation

## Developer Handbook

For onboarding and day-to-day development, start with the [Developer Handbook](developer-handbook.md). It covers architecture, local workflows, production deployment, and production troubleshooting.

## API

The API is generated from the OpenAPI contract (`openapi/api.yaml`). Handlers live in `apps/api/cmd/server` and implement the generated `ServerInterface`.

### Behavioral contracts

* Cacheable endpoints (`/`, `/category`, `/product/{id}`) return:
  * `Cache-Control`, `Surrogate-Control`, `ETag`, `X-Cache`, `X-Request-Id`
* Non-cacheable endpoints (`/cart`, `/account`) return:
  * `Cache-Control: no-store, no-cache, must-revalidate`
* Every response includes a request id and response meta with timestamp + instance name.
* Admin updates (`POST /admin/product/{id}`) require `X-Purge-Token` and return `X-Purge-Tags`.

### Purge / invalidation

Varnish supports URL-based purge with `PURGE` and a shared token header.

```sh
curl -i -X PURGE http://localhost:6081/product/prod-001 \
  -H 'X-Purge-Token: test-purge-token'
```

See [varnish.md](varnish.md) for VCL details.

### Local verification

```sh
make api-test
make api-run
curl -i http://localhost:3000/product/prod-001
```
