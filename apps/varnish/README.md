# Varnish Cache

Reverse proxy cache layer for the Edge Cache Lab API.

## Files

- `Dockerfile` - Container image with Varnish 8-alpine
- `default.vcl.template` - Source VCL (backend set via `BACKEND_HOST`, `PURGE_TOKEN` for cache invalidation)
- `docker-entrypoint.sh` - Startup script for Docker Compose


## Configuration

### Kubernetes

Uses the same container image and startup flow as Docker Compose:
- `docker-entrypoint.sh` renders `/tmp/default.vcl` from `default.vcl.template`
- `BACKEND_HOST` and `PURGE_TOKEN` are provided via pod environment variables

Backend host: `api` (service name)

### Docker Compose

Uses `default.vcl.template` with `BACKEND_HOST` and `PURGE_TOKEN` environment variable substitution.

Backend host: `api` (service name)

## Cache Behavior

- **Cacheable**: GET/HEAD requests to `/`, `/health`, `/category`, `/product/*`
- **Bypass**: `/cart`, `/account`, requests with `session` cookie
- **TTL**: 2 minutes
- **Headers**: `X-Cache` (HIT/MISS/PASS), `X-Cache-Hits`

## See Also

- [Varnish Documentation](../../docs/varnish.md)
- [Docker Compose Issues](../../docs/docker-compose-issues.md)
