# Edge Cache Lab

A production-like, fully automated mini e-commerce platform that demonstrates CDN → Varnish → App → DB behavior, including CI/CD, observability, and safe operations.

## Current Status

Phases 0-9 are implemented and validated locally and in Kubernetes (OpenAPI contract, cache headers, Varnish HIT/MISS/PASS, purge via `PURGE` with `X-Purge-Token`, CI/CD baseline, Pulumi + Cloudflare edge wiring, and frontend SPA).

## Prerequisites

* Go 1.26 (for API server and code generation)
* GoLangCI Lint (for static analysis)

```
# binary will be $(go env GOPATH)/bin/golangci-lint
curl -sSfL https://golangci-lint.run/install.sh | sh -s -- -b $(go env GOPATH)/bin v2.9.0
```

* Docker
* Node.js 24+ and pnpm (for web frontend)

## Local dev

### API

```sh
make api-init
make openapi
make api-lint
make api-test
make api-run
curl -i http://localhost:3000/
curl -i http://localhost:3000/health
curl -i http://localhost:3000/category
curl -i http://localhost:3000/product/prod-001
curl -i http://localhost:3000/cart
curl -i http://localhost:3000/account

# Admin update (triggers purge tags)
curl -i -X POST http://localhost:3000/admin/product/prod-001 \
  -H 'Content-Type: application/json' \
  -d '{"name":"Updated Name","inStock":false}'
```

### Web Frontend

```sh
make web-install
make web-generate-client  # Generate TypeScript client from OpenAPI spec
make web-run              # Dev server at http://localhost:5173
make web-build            # Production build
make web-preview          # Preview production build
```

## Local Docker dev

**Note**: Docker Compose Varnish setup may encounter DNS resolution issues in certain CI environments. See [docs/docker-compose-issues.md](docs/docker-compose-issues.md) for details. For full Varnish functionality, use the Kubernetes deployment.

```sh
make docker-up
make docker-logs

# Access web frontend (Docker host port 8080 -> web container port 80)
open http://localhost:8080

# Access via Varnish (Docker host port 6081 -> Varnish container port 80)
curl -i http://localhost:6081/
curl -i http://localhost:6081/health
curl -i http://localhost:6081/category
curl -i http://localhost:6081/product/prod-001

# Verify cache behavior (X-Cache: MISS on first request, HIT on second)
curl -i http://localhost:6081/product/prod-001
curl -i http://localhost:6081/product/prod-001

# Verify bypass for non-cacheable endpoints (X-Cache: PASS)
curl -i http://localhost:6081/cart
curl -i http://localhost:6081/account

make docker-down
```

## API Contract

The OpenAPI spec is the source of truth:

```sh
make openapi-validate
make openapi
```

Generated types live in `apps/api/internal/api/api.gen.go` and handlers in `apps/api/cmd/server`.

## CI/CD

GitHub Actions runs OpenAPI validation, codegen drift checks, lint/test, and Docker image builds for app/web workflows.

Local CI runs can be executed with:

```sh
make app-ci
make web-ci
```

Run the all the CI workflows with `act`:

```sh
make gh-act-all-ci
```

### GitHub Actions Workflows

- **App CI** - Automated linting and testing on PRs and main branch
- **Web CI** - Automated client generation, drift checks, linting, and build on PRs and main branch
- **K8s CI** - Validate Kubernetes manifests on PRs and main branch
- **Infra Preview** - Preview infrastructure changes on PRs
- **Infra Up** - Deploy infrastructure (manual trigger)
- **Infra Destroy** - Destroy all infrastructure resources (manual trigger)

### Quick Start

1. **Configure AWS OIDC** - Set up GitHub OIDC provider in AWS IAM
2. **Create IAM Role** - Create a role with trust policy for your repository
  - `make infra-github-actions-oidc-role` - creates the IAM role with trust policy for GitHub OIDC authentication
3. **Add GitHub Repository Secrets**:
  - `AWS_ROLE_ARN` - IAM role ARN for OIDC authentication
    - `gh secret set AWS_ROLE_ARN -r sbasir/edge-cache-lab --body "arn:aws:iam::<account-id>:role/<role-name>"`
  - `PULUMI_ACCESS_TOKEN` - Pulumi Cloud access token
    - Get from Pulumi Cloud dashboard → Account Settings → Access Tokens
    - `gh secret set PULUMI_ACCESS_TOKEN -r sbasir/edge-cache-lab --body "<your-pulumi-access-token>"`
  - `CF_API_TOKEN` - Cloudflare API token
    - Create a token for your zone in the Cloudflare dashboard → My Profile → API Tokens with permissions:
      - Zone:Zone:Read
      - Zone:DNS:Edit
      - Zone:Workers Routes:Edit
      - User:Membership:Read
      - User:User Details:Read
      - Account:Workers Scripts:Edit
    - `gh secret set CF_API_TOKEN -r sbasir/edge-cache-lab --body "<your-cloudflare-api-token>"`
  - `CF_ZONE_ID` - Cloudflare zone ID
    - Get from Cloudflare dashboard → Overview → API → Zone ID
    - `gh secret set CF_ZONE_ID -r sbasir/edge-cache-lab --body "<your-cloudflare-zone-id>"`
4. **Add Github Repository Variables**:
    - `CF_API_RECORD_NAME` - DNS record name
      - `gh variable set CF_API_RECORD_NAME -r sbasir/edge-cache-lab -b api.edge.example.com`
    - `AWS_REGION` - AWS region for deployment (e.g., us-east-1)
      - `gh variable set AWS_REGION -r sbasir/edge-cache-lab -b us-east-1`
    - `API_BASE_URL` - Base URL for the API (used in web frontend build)
      - `gh variable set API_BASE_URL -r sbasir/edge-cache-lab -b https://api.edge.example.com`
5. **Deploy via GitHub Actions**:
   - Go to Actions → "Pulumi Up" workflow
   - Click "Run workflow"
   - Confirm deployment

### Web (Cloudflare Workers) deployment

The `web-deploy` (production, on push to `main`) and `web-preview` (per-PR) workflows
publish the SPA Worker in `apps/web`. Both reuse the **`CF_API_TOKEN`** secret above —
its `Account:Workers Scripts:Edit` (deploy) and `Zone:Workers Routes:Edit` (custom
route on `edge.sbas.dev`) permissions already cover Workers deploys.

**Creating the `CF_API_TOKEN` for Workers deploys** (if you don't already have one):

1. Cloudflare dashboard → **My Profile → API Tokens → Create Token**.
2. Use the **"Edit Cloudflare Workers"** template (or **Create Custom Token** and add
   the six permissions listed under `CF_API_TOKEN` above).
3. Scope **Account Resources** to your account and **Zone Resources** to `sbas.dev`.
4. Create the token, copy it, then store it as a repo secret:

   ```sh
   gh secret set CF_API_TOKEN -r sbasir/edge-cache-lab --body "<your-cloudflare-api-token>"
   ```

   Verify the token before saving it:

   ```sh
   curl -s -H "Authorization: Bearer <token>" \
     https://api.cloudflare.com/client/v4/user/tokens/verify | jq .success
   ```

**Create the `preview` Environment** (required by `web-preview`): repo **Settings →
Environments → New environment → `preview`**. Per-PR builds deploy the isolated
`edge-cache-lab-preview` Worker on `*.workers.dev` and comment the URL on the PR.

## Varnish Cache

Implementation with reverse proxy caching. See [docs/varnish.md](docs/varnish.md) for details.

## Cache Purge / Invalidation

Update a product and purge cached content with a token:

```sh
# With Docker Compose (through Varnish)
curl -i -X POST http://localhost:6081/admin/product/prod-001 \
  -H 'Content-Type: application/json' \
  -H 'X-Purge-Token: test-purge-token' \
  -d '{"name":"Updated Product","inStock":false}'

# Response includes X-Purge-Tags (e.g., product:prod-001) for purge tooling.

# Purge cached product by URL (Varnish only supports PURGE here)
curl -i -X PURGE http://localhost:6081/product/prod-001 \
  -H 'X-Purge-Token: test-purge-token'

# Verify purge worked - next GET should be MISS
curl -i http://localhost:6081/product/prod-001  # X-Cache: MISS
```

Purge token is validated by both the API and Varnish. The default token is `test-purge-token`.

For non-default tokens:
- Set the `PURGE_TOKEN` environment variable in the API deployment to your desired token value.
- Configure Varnish (e.g., in the VCL) to expect the same token value.
- Ensure the token value matches in both the API environment variable and the Varnish configuration; mismatches will cause purge requests to be rejected.
- When changing the token, update all of these places and redeploy/reload both the API and Varnish.
## Endpoint Validation

Run comprehensive endpoint tests:

```sh
# Test against Docker Compose (default port 6081)
make docker-up
make validate-endpoints

# Test against Kubernetes (after port-forward)
make k8s-local-up && make k8s-wait
make k8s-port-forward-varnish  # in one terminal
make validate-endpoints        # in another
make k8s-local-down
```

## Kubernetes

Deploy to local Kubernetes:

```sh
# Deploy API, Varnish, and Web
make k8s-local-up

# Wait for rollout
make k8s-wait

# Check status
make k8s-status

# Port-forward Web (access at http://localhost:8080)
make k8s-port-forward-web

# Port-forward Varnish (access at http://localhost:6081)
make k8s-port-forward-varnish

# In another terminal, test cache behavior
curl -i http://localhost:6081/product/prod-001  # X-Cache: MISS
curl -i http://localhost:6081/product/prod-001  # X-Cache: HIT
curl -i http://localhost:6081/cart              # X-Cache: PASS

# Cleanup
make k8s-local-down
```
