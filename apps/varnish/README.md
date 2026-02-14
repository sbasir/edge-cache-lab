# Varnish Cache

Reverse proxy cache layer for the Edge Cache Lab API.

## Files

- `Dockerfile` - Container image with Varnish 8-alpine
- `default.vcl.template` - Source VCL (backend set via `BACKEND_HOST`)
- `render-k8s-vcl.sh` - Generates the Kubernetes VCL from the template
- `../infra/k8s/base/varnish/default.vcl` - Generated VCL for Kubernetes (used by kustomize)
- `docker-entrypoint.sh` - Startup script for Docker Compose


## Configuration

### Kubernetes

Uses `infra/k8s/base/varnish/default.vcl` generated from `default.vcl.template` via `make k8s-varnish-vcl-sync`.

Backend host: `edge-cache-api` (service name)

### Docker Compose

Uses `default.vcl.template` with `BACKEND_HOST` environment variable substitution.

Backend host: `api` (service name)

## Cache Behavior

- **Cacheable**: GET/HEAD requests to `/`, `/health`, `/category`, `/product/*`
- **Bypass**: `/cart`, `/account`, requests with `session` cookie
- **TTL**: 2 minutes
- **Headers**: `X-Cache` (HIT/MISS/PASS), `X-Cache-Hits`

## See Also

- [Varnish Documentation](../../docs/varnish.md)
- [Docker Compose Issues](../../docs/docker-compose-issues.md)
