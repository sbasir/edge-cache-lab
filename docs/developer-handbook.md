# Developer Handbook

> A quick-start and context-switching guide for developers working on Edge Cache Lab.

---

## Table of Contents

1. [What This Project Does](#what-this-project-does)
2. [Architecture Overview](#architecture-overview)
3. [Tech Stack](#tech-stack)
4. [Repository Structure](#repository-structure)
5. [Prerequisites](#prerequisites)
6. [Environment Setup](#environment-setup)
7. [Developer Workflows](#developer-workflows)
   - [API Development](#api-development)
   - [Web Frontend Development](#web-frontend-development)
   - [OpenAPI Contract Changes](#openapi-contract-changes)
   - [Local Docker Compose Stack](#local-docker-compose-stack)
   - [Local Kubernetes Stack](#local-kubernetes-stack)
8. [Production Deployment](#production-deployment)
   - [Step 1 — Provision Infrastructure](#step-1--provision-infrastructure)
   - [Step 2 — Tag and Publish Container Images](#step-2--tag-and-publish-container-images)
   - [Step 3 — Deploy to Kubernetes](#step-3--deploy-to-kubernetes)
   - [Step 4 — Deploy Web Frontend](#step-4--deploy-web-frontend)
   - [Live Endpoints](#live-endpoints)
9. [Running GitHub Actions Locally with `act`](#running-github-actions-locally-with-act)
10. [Troubleshooting & Production Operations](#troubleshooting--production-operations)
    - [Authenticate with AWS](#authenticate-with-aws)
    - [Connect to the EC2 Instance](#connect-to-the-ec2-instance)
    - [Port-Forward to k3s API Server](#port-forward-to-k3s-api-server)
    - [Access the Kubernetes Cluster](#access-the-kubernetes-cluster)
    - [Inspect the Running Cluster](#inspect-the-running-cluster)
    - [Validate Endpoints in Production](#validate-endpoints-in-production)
    - [Replace a Spot Instance](#replace-a-spot-instance)
11. [Key Makefile Reference](#key-makefile-reference)

---

## What This Project Does

Edge Cache Lab is a production-like, fully automated mini e-commerce platform built to demonstrate CDN → Varnish → App caching behavior end-to-end. Its purpose is **operational learning** — not application complexity.

The system lets you observe and experiment with:

- **Cache HIT / MISS / PASS** headers propagating through Cloudflare → Varnish → Go API
- **Cache purge / invalidation** via `PURGE` requests with `X-Purge-Token`
- **Multi-layer cache** behavior (Cloudflare edge + Varnish reverse proxy)
- **Request tracing** via `X-Request-Id` across every layer
- **CI/CD automation** from code commit to live Kubernetes deployment

---

## Architecture Overview

```
Browser / Client
      ↓
  Cloudflare          ← Edge CDN (optional DNS proxy, CF-Cache-Status header)
      ↓
  Varnish             ← Reverse proxy cache (Kubernetes pod, port 80)
      ↓
  Go API              ← Origin service (Kubernetes pod, ClusterIP :3000)
      ↓
 (in-memory data)     ← No external DB yet; demo data is hardcoded
```

**Traffic routing in production (k3s on AWS):**

```
EC2 :80/443
    ↓
Traefik Ingress Controller   ← built into k3s
    ↓
Varnish Service (ClusterIP)
    ↓
API Service (ClusterIP, internal only)
```

The API is **never** directly exposed externally. All public traffic passes through Varnish.

The web frontend (React SPA) is deployed separately to **Cloudflare Workers** and fetches data through Varnish.

---

## Tech Stack

| Layer | Technology |
|---|---|
| API | Go 1.26, chi router, oapi-codegen |
| Cache / Reverse Proxy | Varnish 8 (Alpine), VCL template |
| Web Frontend | Vite + React 19 + TypeScript, pnpm |
| Web Hosting | Cloudflare Workers (production), nginx (Docker/k8s) |
| Container Runtime | Docker, Docker Compose |
| Kubernetes | k3s (single-node, ARM64 spot), Kustomize |
| Infrastructure | Pulumi (Python/uv), AWS EC2 Spot (t4g.small, arm64) |
| DNS | Cloudflare DNS API |
| CI/CD | GitHub Actions, `act` (local runner) |
| API Contract | OpenAPI 3.0, oapi-codegen (Go), openapi-typescript-codegen (TS) |

---

## Repository Structure

```
edge-cache-lab/
├── apps/
│   ├── api/               # Go API server
│   │   ├── cmd/server/    # main.go, handlers (implements ServerInterface)
│   │   └── internal/api/  # api.gen.go — DO NOT EDIT (generated from openapi/api.yaml)
│   ├── varnish/           # Varnish container image
│   │   ├── default.vcl.template  # VCL template (BACKEND_HOST, PURGE_TOKEN vars)
│   │   └── docker-entrypoint.sh  # Renders VCL at container startup
│   └── web/               # React SPA
│       ├── src/api/       # Generated TypeScript client — DO NOT EDIT
│       ├── src/pages/     # Page components
│       └── worker/        # Cloudflare Worker entry point
├── docs/                  # Documentation (you are here)
├── infra/
│   ├── k8s/               # Kubernetes manifests (Kustomize)
│   │   ├── base/          # Base manifests for api, varnish, web
│   │   └── overlays/
│   │       ├── local/     # Local k8s (OrbStack / Docker Desktop)
│   │       └── production/ # Production (k3s on AWS)
│   ├── pulumi/            # Pulumi Python IaC (VPC, EC2 spot, EIP, S3, IAM)
│   └── scripts/           # Shell helpers (deploy-k8s.sh, cloudflare-set-dns.sh)
├── openapi/
│   └── api.yaml           # Source of truth for all endpoints, models, and headers
├── .github/workflows/     # GitHub Actions CI/CD pipelines
├── .env.example           # Template for local .env (never commit .env)
├── docker-compose.yml     # Local dev stack (api + varnish + web)
└── Makefile               # All common commands (run `make help`)
```

**Important rules:**

- Never edit `apps/api/internal/api/api.gen.go` — it is auto-generated from `openapi/api.yaml`.
- Never edit `apps/web/src/api/` — it is auto-generated from `openapi/api.yaml`.
- To add or modify endpoints, edit `openapi/api.yaml` first, then regenerate.

---

## Prerequisites

Install the following tools before working on this project:

| Tool | Version | Install |
|---|---|---|
| Go | 1.26+ | https://go.dev/dl/ |
| golangci-lint | v2.9.0 | `curl -sSfL https://golangci-lint.run/install.sh \| sh -s -- -b $(go env GOPATH)/bin v2.9.0` |
| Node.js | 24+ | https://nodejs.org/ |
| pnpm | 10+ | `corepack enable && corepack prepare pnpm@10.28.1 --activate` |
| Docker | latest | https://www.docker.com/ |
| kubectl | v1.31+ | https://kubernetes.io/docs/tasks/tools/ |
| AWS CLI | v2 | https://aws.amazon.com/cli/ |
| AWS Session Manager Plugin | latest | https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html |
| Pulumi CLI | latest | https://www.pulumi.com/docs/install/ |
| uv (Python toolchain) | latest | `pip install uv` |
| act (local GitHub Actions) | latest | `brew install act` |
| jq | latest | `brew install jq` |

---

## Environment Setup

Copy the example environment file and fill in values:

```sh
cp .env.example .env
```

Required variables for cloud workflows:

```sh
# Cloudflare
CF_API_TOKEN=...       # Zone:DNS:Edit + Workers Routes + Zone:Read
CF_ZONE_ID=...         # Cloudflare dashboard → Overview → API → Zone ID
CF_API_RECORD_NAME=api.edge.example.com

# AWS
AWS_REGION=us-east-1

# Pulumi
PULUMI_ACCESS_TOKEN=... # Pulumi Cloud → Account Settings → Access Tokens

# Web
API_BASE_URL=https://api.edge.example.com
```

The Makefile automatically loads `.env` if it exists. Do **not** commit `.env`.

---

## Developer Workflows

### API Development

```sh
# First time setup
make api-init

# Install / update dependencies
make api-install

# Run the API server at http://localhost:3000
make api-run

# Run tests
make api-test

# Lint
make api-lint

# Format
make api-fmt
```

**Test a few endpoints:**

```sh
curl -i http://localhost:3000/health
curl -i http://localhost:3000/
curl -i http://localhost:3000/category
curl -i http://localhost:3000/product/prod-001   # cacheable — check Cache-Control, ETag
curl -i http://localhost:3000/cart               # non-cacheable — Cache-Control: no-store
curl -i http://localhost:3000/account

# Admin update (requires X-Purge-Token)
curl -i -X POST http://localhost:3000/admin/product/prod-001 \
  -H 'Content-Type: application/json' \
  -H 'X-Purge-Token: test-purge-token' \
  -d '{"name":"Updated Name","inStock":false}'
```

---

### Web Frontend Development

```sh
# Install dependencies
make web-install

# Generate TypeScript API client from OpenAPI spec (required after any OpenAPI change)
make web-generate-client

# Run dev server at http://localhost:5173
make web-run

# Production build
make web-build

# Preview production build at http://localhost:4173
make web-preview

# Lint
make web-lint
```

The dev server requires Varnish or the API to be running. Set the API URL in the UI header field at runtime, or via `.env`:

```sh
VITE_API_BASE_URL=http://localhost:6081   # through Varnish (Docker Compose)
# or
VITE_API_BASE_URL=http://localhost:3000   # direct API
```

---

### OpenAPI Contract Changes

The OpenAPI spec (`openapi/api.yaml`) is the **source of truth** for all endpoints, request/response models, and headers. To change the API:

1. Edit `openapi/api.yaml`
2. Validate the spec:
   ```sh
   make openapi-validate
   ```
3. Regenerate Go server interface and types:
   ```sh
   make openapi
   ```
4. Regenerate TypeScript client:
   ```sh
   make web-generate-client
   ```
5. Update handler implementations in `apps/api/cmd/server/main.go` to satisfy the new `ServerInterface`.
6. Run tests to confirm nothing broke:
   ```sh
   make api-test
   ```

CI will fail on any drift between the spec and generated code.

---

### Local Docker Compose Stack

The Docker Compose stack runs API + Varnish + Web together with a single command.

> **Note:** Varnish DNS resolution may fail in some CI or Docker Desktop environments. For reliable Varnish testing, use the local Kubernetes stack. See [docker-compose-issues.md](docker-compose-issues.md).

```sh
# Start all services
make docker-up

# Access web frontend
open http://localhost:8080

# Access API via Varnish
curl -i http://localhost:6081/health
curl -i http://localhost:6081/product/prod-001   # X-Cache: MISS first time
curl -i http://localhost:6081/product/prod-001   # X-Cache: HIT second time
curl -i http://localhost:6081/cart               # X-Cache: PASS (bypassed)

# Purge a cached object
curl -i -X PURGE http://localhost:6081/product/prod-001 \
  -H 'X-Purge-Token: test-purge-token'

# Follow logs
make docker-logs

# Stop
make docker-down
```

---

### Local Kubernetes Stack

For full fidelity testing with Ingress, run the local Kubernetes overlay (requires OrbStack, Docker Desktop Kubernetes, or similar):

```sh
# Build images and apply kustomize overlay
make k8s-local-up

# Wait for all deployments to be ready
make k8s-wait

# Check status
make k8s-status

# Port-forward Varnish (in one terminal)
make k8s-port-forward-varnish   # → http://localhost:6081

# Port-forward Web (in another terminal)
make k8s-port-forward-web       # → http://localhost:8080

# Test cache behavior
curl -i http://localhost:6081/product/prod-001   # MISS
curl -i http://localhost:6081/product/prod-001   # HIT
curl -i http://localhost:6081/cart               # PASS

# Validate all endpoints
make validate-endpoints

# Tail logs
make k8s-logs

# Clean up
make k8s-local-down
```

---

## Production Deployment

Production runs k3s on a single AWS spot instance (t4g.small, arm64). The full deployment pipeline has four stages:

### Step 1 — Provision Infrastructure

Uses Pulumi (Python) to create the VPC, EC2 spot instance, security groups, EIP, IAM roles, and S3 bootstrap bucket. k3s is installed automatically via user data on first boot.

**First-time setup only:** Create the GitHub Actions IAM role for OIDC authentication:

```sh
make infra-github-actions-oidc-role
```

Then add the required GitHub repository secrets and variables (see [README.md](../README.md#quick-start) for the full list).

**Deploy via GitHub Actions:**

1. Go to **Actions → Infra Up** in GitHub
2. Click **Run workflow**
3. Confirm deployment

The workflow runs `pulumi up` and then updates the Cloudflare DNS A record to point to the new elastic IP.

**Deploy locally (requires AWS credentials in environment):**

```sh
make infra-init       # First time: install Pulumi dependencies
make infra-preview    # Dry-run: inspect planned changes
make infra-up         # Apply: provision all resources
make infra-stack-output  # Show stack outputs (public_ip, instance_id, etc.)
```

---

### Step 2 — Tag and Publish Container Images

Container images for the API and Varnish are published to GHCR (`ghcr.io/sbasir/edge-cache-lab-api` and `ghcr.io/sbasir/edge-cache-lab-varnish`).

**Automated (on PR merge):** Merging a PR to `main` automatically creates a new patch version tag (e.g., `v1.2.4`) and triggers image builds for both API and Varnish via a matrix strategy.

**Manual tag creation via GitHub Actions:**

1. Go to **Actions → Create Release Tag**
2. Click **Run workflow**
3. Optionally provide a suffix (e.g., `testing` → `v1.2.4-testing`)

**Run locally with `act`:**

```sh
make gh-act-app-tag           # creates a tag (dry-run under act)
make gh-act-app-publish       # builds and pushes images
```

---

### Step 3 — Deploy to Kubernetes

Applies the `infra/k8s/overlays/production` Kustomize overlay to the remote k3s cluster. Uses AWS SSM port-forwarding to reach the k3s API server and retrieves the kubeconfig from SSM Parameter Store.

**Deploy via GitHub Actions:**

1. Go to **Actions → Deploy to Kubernetes**
2. Select the **tag** to deploy (e.g., `v1.2.4`) using the branch/tag selector
3. Click **Run workflow**

The workflow:
1. Validates the semver tag
2. Authenticates with AWS via OIDC
3. Retrieves Pulumi stack outputs to get the EC2 instance ID
4. SSM port-forwards to `localhost:6443` (k3s API server)
5. Fetches kubeconfig from SSM Parameter Store (`/edge-cache-lab/k3s/kubeconfig`)
6. Runs `kustomize edit set image` to update image tags
7. Applies the overlay with `kubectl apply -k`
8. Waits for rollout of API and Varnish deployments

**Run locally with `act`:**

```sh
REF_TAG=v1.2.4 make gh-act-k8s-deploy
```

---

### Step 4 — Deploy Web Frontend

The React SPA deploys to **Cloudflare Workers** via Wrangler. It is triggered automatically on any push to `main` that touches `apps/web/` files.

**Deploy via GitHub Actions:**

The `web-deploy.yaml` workflow runs automatically on push to `main` (paths: `apps/web/**`). It can also be triggered manually:

1. Go to **Actions → Deploy Web to Cloudflare**
2. Click **Run workflow**

**Run locally with `act`:**

```sh
make gh-act-web-deploy   # requires CF_API_TOKEN and API_BASE_URL in .env
```

---

### Live Endpoints

After a full production deployment:

| Endpoint | URL | Cache Behavior |
|---|---|---|
| Homepage | `https://api.edge.example.com/` | Cacheable (HIT/MISS) |
| Health check | `https://api.edge.example.com/health` | Cacheable |
| Categories | `https://api.edge.example.com/category` | Cacheable |
| Product detail | `https://api.edge.example.com/product/{id}` | Cacheable |
| Cart | `https://api.edge.example.com/cart` | Non-cacheable (PASS) |
| Account | `https://api.edge.example.com/account` | Non-cacheable (PASS) |
| Admin update | `POST https://api.edge.example.com/admin/product/{id}` | Triggers purge |

Substitute `api.edge.example.com` with the value of your `CF_API_RECORD_NAME` variable.

Inspect cache behavior headers on any response:

```sh
curl -si https://api.edge.example.com/product/prod-001 | grep -E "X-Cache|CF-Cache-Status|Cache-Control|ETag|X-Request-Id"
```

---

## Running GitHub Actions Locally with `act`

[`act`](https://github.com/nektos/act) lets you run any GitHub Actions workflow on your machine before pushing. This is the fastest way to validate workflow changes and catch CI failures locally.

**Prerequisites:**

- `act` is installed (`brew install act`)
- A `.env` file exists with required secrets and variables (see [Environment Setup](#environment-setup))

**CI workflows (no cloud credentials required):**

```sh
make gh-act-app-ci      # API lint + test + image build
make gh-act-web-ci      # Web client drift + lint + build
make gh-act-k8s-ci      # Kubernetes manifest validation
make gh-act-all-ci      # All three CI workflows in sequence
```

**Infrastructure workflows (requires AWS credentials + Pulumi token in `.env`):**

```sh
make gh-act-infra-preview             # Pulumi preview (dry-run, safe)
make gh-act-infra-up FORCE=true       # Pulumi up (runs the real deploy)
make gh-act-infra-destroy FORCE=true  # Pulumi destroy
```

**Deployment workflows:**

```sh
make gh-act-app-publish               # Build and push container images
make gh-act-web-deploy                # Deploy web to Cloudflare Workers
REF_TAG=v1.2.4 make gh-act-k8s-deploy  # Deploy to Kubernetes
```

> **Tip:** Infrastructure and deployment workflows that modify real resources are guarded by an `if: ${{ !env.ACT || env.FORCE == 'true' }}` condition — they are skipped by default under `act` unless you pass `FORCE=true`.

---

## Troubleshooting & Production Operations

### Authenticate with AWS

The CLI workflows require active AWS credentials. Use AWS SSO or temporary credentials from your provider. For the workflows that rely on long-lived credentials locally (e.g., when running `act`), export them before running `make`:

```sh
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...       # if using temporary credentials
export AWS_REGION=us-east-1
```

Or add them to your `.env` file.

---

### Connect to the EC2 Instance

There are no SSH keys. All access is via **AWS SSM Session Manager**. No inbound SSH port is opened on the security group.

```sh
make infra-ec2-connect
```

This retrieves the instance ID from Pulumi stack outputs and opens an interactive SSM shell session.

To monitor the instance bootstrap logs (useful after `infra-up` to watch k3s install):

```sh
make infra-deploy-logs
```

---

### Port-Forward to k3s API Server

To run `kubectl` commands against the remote cluster from your laptop, open an SSM port-forwarding tunnel first:

```sh
# Terminal 1 — start the tunnel (blocks while open)
make infra-ec2-port-forward
# Forwards localhost:6443 → EC2:6443 (k3s API server)
```

---

### Access the Kubernetes Cluster

With the port-forward running, fetch the kubeconfig from SSM Parameter Store and configure `kubectl`:

```sh
aws ssm get-parameter \
  --name "/edge-cache-lab/k3s/kubeconfig" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  | base64 -d > /tmp/edge-cache-lab-kubeconfig

# Point to localhost (the SSM tunnel)
sed -i 's/127.0.0.1/localhost/' /tmp/edge-cache-lab-kubeconfig

export KUBECONFIG=/tmp/edge-cache-lab-kubeconfig
kubectl get nodes
kubectl get all -n edge-cache-lab
```

---

### Inspect the Running Cluster

With `KUBECONFIG` set (see above):

```sh
# Check all resources in the namespace
kubectl get all -n edge-cache-lab

# Tail API pod logs
kubectl logs -n edge-cache-lab -l app=api -f --tail=100

# Tail Varnish logs
kubectl logs -n edge-cache-lab -l app=varnish -f --tail=100

# Describe a pod (shows events, image, env vars)
kubectl describe pod -n edge-cache-lab -l app=api

# Check Traefik ingress
kubectl get ingress -n edge-cache-lab
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# Validate k3s installation on EC2 (runs a remote health-check script)
make infra-validate-k3s
```

---

### Validate Endpoints in Production

Port-forward Varnish from the cluster, then run the endpoint validation suite:

```sh
# Terminal 1 — with KUBECONFIG set, port-forward Varnish
kubectl port-forward -n edge-cache-lab svc/varnish 6081:80

# Terminal 2
make validate-endpoints           # defaults to PORT=6081
make validate-endpoints PORT=6081 # explicit
```

The validation script checks every endpoint for correct status codes and cache headers (HIT/MISS/PASS).

---

### Replace a Spot Instance

If the spot instance is interrupted or needs replacement while preserving the Elastic IP:

```sh
make infra-replace-instance
```

This finds the spot instance resource URN in the Pulumi state and replaces it in-place, keeping the EIP allocation and DNS record intact.

---

## Key Makefile Reference

Run `make help` at any time to see all available targets. The most commonly used ones:

### API

| Target | Description |
|---|---|
| `make api-init` | Initialize Go module (first time only) |
| `make api-install` | Download Go dependencies |
| `make api-run` | Run API server on :3000 |
| `make api-test` | Run tests with coverage |
| `make api-lint` | Run golangci-lint |
| `make api-fmt` | Format code |

### Web

| Target | Description |
|---|---|
| `make web-install` | Install pnpm dependencies |
| `make web-generate-client` | Generate TypeScript client from OpenAPI |
| `make web-run` | Dev server on :5173 |
| `make web-build` | Production build |
| `make web-lint` | ESLint |

### OpenAPI

| Target | Description |
|---|---|
| `make openapi-validate` | Validate `openapi/api.yaml` |
| `make openapi` | Generate Go server code |
| `make openapi-diff` | Fail if generated code has drifted |

### Docker

| Target | Description |
|---|---|
| `make docker-up` | Build and start full stack |
| `make docker-down` | Stop and remove containers |
| `make docker-logs` | Tail all service logs |

### Kubernetes (local)

| Target | Description |
|---|---|
| `make k8s-local-up` | Build images and deploy to local k8s |
| `make k8s-local-down` | Remove local k8s resources |
| `make k8s-wait` | Wait for deployment rollout |
| `make k8s-status` | Show all resources in namespace |
| `make k8s-port-forward-varnish` | Port-forward Varnish → :6081 |
| `make k8s-port-forward-web` | Port-forward Web → :8080 |
| `make validate-endpoints` | Run endpoint validation suite |

### Infrastructure (Pulumi)

| Target | Description |
|---|---|
| `make infra-init` | Install Pulumi Python dependencies |
| `make infra-preview` | Preview infrastructure changes |
| `make infra-up` | Deploy / update infrastructure |
| `make infra-destroy` | Destroy all infrastructure |
| `make infra-stack-output` | Show Pulumi stack outputs |
| `make infra-ec2-connect` | Open SSM shell on EC2 |
| `make infra-ec2-port-forward` | SSM port-forward :6443 for kubectl |
| `make infra-deploy-logs` | Tail cloud-init bootstrap logs |
| `make infra-validate-k3s` | Run k3s health-check on EC2 |
| `make infra-replace-instance` | Replace spot instance (preserve EIP) |
| `make infra-set-dns` | Upsert Cloudflare DNS A record |

### CI / `act`

| Target | Description |
|---|---|
| `make app-ci` | Run API CI checks locally |
| `make web-ci` | Run Web CI checks locally |
| `make gh-act-app-ci` | API CI via `act` |
| `make gh-act-web-ci` | Web CI via `act` |
| `make gh-act-k8s-ci` | K8s CI via `act` |
| `make gh-act-all-ci` | All CI workflows via `act` |
| `make gh-act-infra-up` | Infra deploy via `act` |
| `make gh-act-infra-preview` | Infra preview via `act` |
| `make gh-act-web-deploy` | Web deploy to Cloudflare via `act` |
| `make gh-act-app-publish` | Build and push images via `act` |
| `REF_TAG=v1.2.4 make gh-act-k8s-deploy` | K8s deploy via `act` |
