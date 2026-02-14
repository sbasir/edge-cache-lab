# Varnish Cache

Reverse proxy cache layer for the Edge Cache Lab API.

## Files

- `Dockerfile` - Container image with Varnish 7.6-alpine
- `default.vcl` - Varnish configuration for Kubernetes (static)
- `default.vcl.template` - Template for dynamic backend resolution (Docker Compose)
- `docker-entrypoint.sh` - Startup script for Docker Compose

## Configuration

### Kubernetes

Uses `default.vcl` mounted from ConfigMap in `infra/k8s/base/varnish/configmap.yaml`.

Backend host: `edge-cache-api` (service name)

### Docker Compose

Uses template-based VCL generation with `BACKEND_HOST` environment variable.

Backend host: `api` (service name)

## Cache Behavior

- **Cacheable**: GET/HEAD requests to `/`, `/health`, `/category`, `/product/*`
- **Bypass**: `/cart`, `/account`, requests with `session` cookie
- **TTL**: 2 minutes
- **Headers**: `X-Cache` (HIT/MISS/PASS), `X-Cache-Hits`

## See Also

- [Varnish Documentation](../../docs/varnish.md)
- [Docker Compose Issues](../../docs/docker-compose-issues.md)
