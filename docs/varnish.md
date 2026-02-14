# Varnish Configuration

## Overview

Varnish is configured as a reverse proxy cache in front of the API service.

## VCL Configuration

The VCL (Varnish Configuration Language) file defines caching behavior:

### Backend Configuration

```vcl
backend default {
    .host = "edge-cache-api";  # Kubernetes service name
    .port = "3000";
    .connect_timeout = 5s;
    .first_byte_timeout = 10s;
    .between_bytes_timeout = 2s;
}
```

### Caching Rules

1. **Cache GET and HEAD requests** - Standard HTTP caching for read operations
2. **Bypass /cart and /account** - These endpoints contain user-specific data
3. **Bypass if session cookie present** - Personalized content should not be cached
4. **TTL: 2 minutes** - Cache entries expire after 120 seconds

### Headers

- **X-Cache**: Indicates cache status (HIT, MISS, or PASS)
- **X-Cache-Hits**: Number of times this cached object has been served

## Deployment

### Kubernetes

Varnish is deployed as a separate pod with:
- ConfigMap containing VCL configuration
- Deployment with varnish:8-alpine image (internal port 80)
- ClusterIP Service exposing external port 6081

Access via:
```bash
make k8s-test-local
make k8s-port-forward-varnish
curl -i http://localhost:6081/product/prod-001
```

### Docker Compose

Varnish container configuration with health checks:
```bash
make docker-up
```

**Note**: Some Docker environments may experience DNS resolution issues. See docs/docker-compose-issues.md.

## Testing Cache Behavior

### Verify HIT/MISS

```bash
# First request - cache MISS
curl -i http://localhost:6081/product/prod-001 | grep X-Cache
# X-Cache: MISS

# Second request - cache HIT
curl -i http://localhost:6081/product/prod-001 | grep X-Cache
# X-Cache: HIT
```

### Verify Bypass

```bash
# Non-cacheable endpoint - always PASS
curl -i http://localhost:6081/cart | grep X-Cache
# X-Cache: PASS

# With session cookie
curl -i -H "Cookie: session=abc123" http://localhost:6081/product/prod-001 | grep X-Cache
# X-Cache: PASS
```

## Troubleshooting

### VCL Compilation Errors

If Varnish fails to start, check:
1. Backend host is resolvable
2. VCL syntax is valid
3. Container logs: `kubectl logs -n edge-cache-api -l app=varnish`

### No Cache HITs

If all requests show MISS:
1. Check TTL is set correctly
2. Verify request method is GET or HEAD
3. Confirm no session cookies are present
4. Check `X-Cache-Hits` header value

## Next Steps (Phase 5)

- Implement BAN/PURGE for cache invalidation
- Secure purge with token authentication
- Connect admin endpoints to trigger cache purges
