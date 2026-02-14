# Documentation

## API

The API is generated from the OpenAPI contract (`openapi/api.yaml`). Handlers live in `apps/api/cmd/server` and implement the generated `ServerInterface`.

### Behavioral contracts

* Cacheable endpoints (`/`, `/category`, `/product/{id}`) return:
  * `Cache-Control`, `Surrogate-Control`, `ETag`, `X-Cache`, `X-Request-Id`
* Non-cacheable endpoints (`/cart`, `/account`) return:
  * `Cache-Control: no-store, no-cache, must-revalidate`
* Every response includes a request id and response meta with timestamp + instance name.

### Local verification

```sh
make api-test
make api-run
curl -i http://localhost:3000/product/prod-001
```
