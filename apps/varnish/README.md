# Varnish Cache

Reverse proxy cache layer for the Edge Cache Lab API.

## Files

- `Dockerfile` - Container image with Varnish 8-alpine
- `default.vcl.template` - Reference VCL configuration (Docker Compose dynamically updates backend resolution)
- `../infra/k8s/base/varnish/default.vcl` - Deployed VCL for Kubernetes (generated into ConfigMap), manually copied from template with backend set to `edge-cache-api`
- `docker-entrypoint.sh` - Startup script for Docker Compose


## Configuration

### Kubernetes

Uses `infra/k8s/base/varnish/default.vcl` (generated into ConfigMap via kustomize configMapGenerator), manually copied from `default.vcl.template` with backend set to `edge-cache-api` (Kubernetes service name).

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
