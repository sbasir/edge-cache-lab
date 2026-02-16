# Edge Cache Lab - Web Frontend

React TypeScript SPA demonstrating CDN → Varnish → App cache behavior.

## Features

- **OpenAPI-driven**: TypeScript client auto-generated from OpenAPI spec
- **Cache visualization**: Real-time display of X-Cache headers (HIT/MISS/PASS)
- **Interactive pages**:
  - Home: Featured products (cacheable)
  - Categories: Product categories (cacheable)
  - Product detail: Individual product pages (cacheable)
  - Cart: Shopping cart (non-cacheable, always PASS)
  - Account: User account (non-cacheable, always PASS)
  - Admin: Product updates with cache purge

## Development

```sh
# Install dependencies
pnpm install

# Generate TypeScript client from OpenAPI spec
pnpm run generate-client

# Run dev server (http://localhost:5173)
pnpm run dev

# Build for production
pnpm run build

# Preview production build
pnpm run preview

# Lint
pnpm run lint
```

## Environment Variables

Create `.env` file:

```
VITE_API_BASE_URL=http://localhost:6081
```

The API URL can also be changed at runtime via the UI.

## Docker

Build and run with nginx:

```sh
docker build -t edge-cache-lab-web .
docker run -p 8080:80 edge-cache-lab-web
open http://localhost:8080
```

## Architecture

- Built with Vite + React 19 + TypeScript
- Uses React Router for SPA routing
- OpenAPI TypeScript client for type-safe API calls
- Production build served by nginx:1.29-alpine-slim
- nginx config handles SPA routing (all routes → index.html)
