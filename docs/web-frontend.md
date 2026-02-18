# Web Frontend Documentation

## Overview

The Edge Cache Lab web frontend is a React TypeScript SPA that demonstrates CDN → Varnish → App cache behavior through an interactive e-commerce interface.

## Architecture

- **Framework**: Vite + React 19 + TypeScript
- **Routing**: React Router for SPA navigation
- **API Client**: Auto-generated from OpenAPI spec (type-safe)
- **Production Server**: nginx:1.29-alpine-slim
- **Build Size**: ~242KB (76KB gzipped)

## Key Features

### Cache Behavior Visualization

Every page displays:
- **X-Cache Status**: HIT/MISS/PASS from Varnish
- **Cache-Control**: Browser and CDN cache directives
- **ETag**: Cache validation tags
- **Request ID**: End-to-end request tracing
- **Response Metadata**: Timestamp, instance, headers

### Page Types

**Cacheable Pages** (expect HIT after first request):
- `/` - Homepage with featured products
- `/categories` - Product categories
- `/product/:id` - Individual product details

**Non-Cacheable Pages** (always PASS):
- `/cart` - Shopping cart (session-specific)
- `/account` - User account (private data)

**Admin Pages**:
- `/admin` - Product updates and cache purge operations

### Admin Functions

1. **Update Product**: Modify product details
2. **Purge Cache**: Manually trigger cache invalidation
3. **View Purge Headers**: See X-Purge-Tags returned by API

## Development

### Local Development

```sh
# Install dependencies
make web-install

# Generate API client (required after OpenAPI changes)
make web-generate-client

# Run dev server (http://localhost:5173)
make web-run

# Build for production
make web-build

# Preview production build
make web-preview

# Lint
make web-lint
```

### Environment Configuration

The API base URL can be configured via:
1. `.env` file: `VITE_API_BASE_URL=http://localhost:6081`
2. Runtime UI: Input field in header (dynamic configuration)

## Deployment

### Docker Compose

```sh
make docker-up
# Web available at http://localhost:8080
```

The compose setup:
- Builds web from Dockerfile
- Serves on port 8080
- Connects to Varnish backend
- Auto-reloads on API changes

### Kubernetes

```sh
make k8s-local-up
make k8s-port-forward-web
# Web available at http://localhost:8080
```

The K8s deployment:
- Single replica (can scale)
- Read-only root filesystem
- nginx cache and run volumes
- Health check on port 80

## CI/CD

GitHub Actions workflow (`.github/workflows/web-ci.yaml`):
1. Setup Node.js 24 + pnpm
2. Install dependencies
3. Generate OpenAPI client
4. Fail on generated client drift (`git diff -- apps/web/src/api`)
5. Lint code
6. Build production bundle
7. Build Docker image

## Best Practices

### Type Safety

Use generated OpenAPI models and service artifacts for contract safety:
```typescript
import type { Product } from '../api';
const product: Product = await someProductCall();
```

### Current Data-Access Pattern

The current frontend keeps manual response-header capture for cache diagnostics (`X-Cache`, `ETag`, `X-Request-Id`) while using generated OpenAPI types/client artifacts.

This is intentional for the cache lab UX and is being iteratively reduced toward centralized typed request helpers.

### Error Handling

```typescript
try {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const data = await response.json();
} catch (err) {
  setError(err instanceof Error ? err.message : 'Failed to fetch');
}
```

### Header Capture

To visualize cache behavior, manually capture headers:
```typescript
const response = await fetch(url);
const headers: Record<string, string> = {};
response.headers.forEach((value, key) => {
  headers[key] = value;
});
```

## Testing Cache Behavior

### Test Cacheable Endpoint

1. Visit product page: http://localhost:8080/product/prod-001
2. Note X-Cache: MISS on first load
3. Refresh page
4. Note X-Cache: HIT on subsequent loads
5. ETag remains consistent

### Test Non-Cacheable Endpoint

1. Visit cart page: http://localhost:8080/cart
2. Note X-Cache: PASS (always bypasses cache)
3. Refresh page
4. Still X-Cache: PASS (never cached)

### Test Cache Purge

1. Visit product page (ensure it's cached - X-Cache: HIT)
2. Go to Admin: http://localhost:8080/admin
3. Update product with valid purge token
4. Note X-Purge-Tags in response
5. Return to product page
6. Note X-Cache: MISS (cache was invalidated)
7. Refresh again
8. Note X-Cache: HIT (re-cached)

## Troubleshooting

### Build Fails

```sh
# Regenerate lockfile
cd apps/web && pnpm install --no-frozen-lockfile

# Regenerate API client
make web-generate-client

# Clean and rebuild
rm -rf apps/web/dist apps/web/node_modules
make web-install
make web-build
```

### Runtime API Errors

Check:
1. API base URL is correct (visible in header)
2. Varnish is running and accessible
3. Browser console for network errors
4. Response headers for X-Cache status

### Linting Errors

```sh
# Auto-fix what's possible
cd apps/web && pnpm run lint --fix

# Check specific files
cd apps/web && pnpm run lint src/pages/HomePage.tsx
```

## Performance

- **Initial bundle**: 242KB (~76KB gzipped)
- **First Contentful Paint**: < 1s (local)
- **Time to Interactive**: < 1.5s (local)
- **nginx memory**: ~32-64MB
- **nginx CPU**: < 50m (0.05 cores)

## Security

- nginx runs as non-root user (101)
- Read-only root filesystem in K8s
- Security headers in nginx config:
  - X-Frame-Options: SAMEORIGIN
  - X-Content-Type-Options: nosniff
  - X-XSS-Protection: 1; mode=block
- No sensitive data in client-side code
- API calls use configured base URL (no hardcoded endpoints)

## Future Enhancements

Potential improvements (not in current scope):
- Real-time cache metrics dashboard
- WebSocket for live cache events
- Service worker for offline capability
- Progressive Web App (PWA) features
- Performance monitoring integration
- A/B testing for cache strategies
