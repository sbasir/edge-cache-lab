# Edge Cache Lab – Implementation Plan

> Goal: build a production-like, fully automated mini e-commerce platform that demonstrates CDN → Varnish → App → DB behavior, including CI/CD, observability, and safe operations.

This project optimizes for operability, repeatability, and debuggability, not application complexity.

## Final Target Architecture

```
User
 ↓
Cloudflare
 ↓
Varnish (Kubernetes)
 ↓
Store App (Kubernetes)
 ↓
Database / Redis
```

Managed by:

* GitHub
* GitHub Actions
* Docker
* k3s
* Pulumi

## Guiding Principles

* Everything in Git.
* Immutable deployments.
* Reproducible environments.
* Observable behavior.
* Safe to break, easy to fix.
* Learn by simulating real incidents.

## API First

The API contract is the source of truth.

Endpoints, request/response formats, headers, and error models are defined in OpenAPI.
Both backend and frontend code are generated or validated against this spec.

Breaking the contract must fail CI.

## Ownership Boundaries (Explicit)

* OpenAPI is the source of truth for endpoints and cache policy intent.
* App is the source of truth for response headers.
* VCL is the source of truth for cache decisioning and purge mechanics.
* Cloudflare rules must not override origin cache policy unless documented.

---

## Global Guardrails (Non-Negotiable)

* Pin versions for toolchains and container images.
* Every phase includes a rollback or teardown step.
* Every cacheable endpoint must have explicit cache headers.
* Every phase has concrete curl-based acceptance checks.

## Scope Deferrals (Intentional)

* No database or Redis until cache behavior is stable.
* No ingress or Helm in the first k8s phase.
* No Cloudflare until Varnish HIT/MISS and purge are deterministic.
* No Pulumi until local and k8s flows are repeatable.

## Brutal MVP Path (If Time Is Short)

* Day 1: Compose app with `GET /health`, request-id, and structured logs.
* Day 2: OpenAPI spec for core endpoints + CI validation.
* Day 3: Varnish in Compose with HIT/MISS headers.
* Day 4: Purge flow with token + curl verification.
* Day 5: Minimal observability proving hit ratio and bypass rate.

---

# Phase 0 – Walking Skeleton (Fast Path)

### Objective

Prove the request path end-to-end with one endpoint.

### Deliverables

* Repo structure
* Makefile
* Docker Compose dev loop
* One working endpoint

### Suggested Structure

```
/apps
    /web                → frontend (optional / vite react)
    /api (Go)           → demo store
    /varnish            → VCL
/infra
    /pulumi (TS)        → IaC for k8s and cloud resources
    /k8s                → manifests
/openapi                → OpenAPI spec
    /api.yaml           → use `oapi-codegen` for Go types and server stubs
/docs
Makefile
```

### Make targets (initial)

```
make up
make down
make build
make test
make logs
```

### Tasks

* implement a single endpoint (`GET /health`)
* return request-id, instance name, and timestamp
* add structured logs with request-id

### Definition of Done

* `make up` starts app locally
* `curl /health` returns 200 with headers and body fields
* log includes request-id and latency
* README shows the local curl commands

---

# Phase 1 – Define the API Contract

### Objective

Describe the system before implementing it.

### Technology

OpenAPI

### Tasks

Create:

```
/openapi/api.yaml
```

Suggested Makefile target:

```
openapi:
    oapi-codegen -generate types,chi-server \
    -package api \
    openapi/api.yaml > apps/api/internal/api.gen.go
```

Define:

#### Public endpoints

* `GET /`
* `GET /category`
* `GET /product/{id}`

#### Non-cacheable

* `GET /cart`
* `GET /account`

#### Admin

* `POST /admin/product/{id}` → triggers purge

### Define models

Example:
* Product
* Category
* Error
* Health

### Required headers in the contract

* `Cache-Control`
* `Surrogate-Control`
* `ETag`
* `X-Request-Id`
* `X-Cache` (from Varnish)

### Definition of Done

* OpenAPI validates in CI
* Generated code matches spec with no git diff
* Spec changes cause CI failure until regenerated

---

# Phase 2 – Build the Backend From the Contract

### Objective

Simulate Magento-like caching behavior with minimal code.

### Tasks

* generate Go types/server interfaces
* implement handlers from the spec
* responses must match spec and headers
* compilation ensures alignment

### Important Rule

Do not invent routes manually.
If it is not in the spec, it does not exist.

### Response behavior

Return:

* timestamps
* instance name
* headers received

This enables cache debugging.

### Definition of Done

* `make test` includes API contract tests
* `GET /product/{id}` includes cache headers
* `GET /cart` is explicitly non-cacheable
* structured logs include request-id and latency

---

# Phase 3 – Run App in Kubernetes (No Varnish Yet)

### Objective

Origin service works in k8s.

### Tasks

* Deployment
* Service (ClusterIP)
* scaling replicas
* port-forward script or Make target
* no ingress and no Helm in this phase

### Validate

* `curl` works via port-forward
* multiple pods respond with different instance names

### Definition of Done

* `make port-forward` works
* `kubectl get pods` shows desired replicas

---

# Phase 4 – Introduce Varnish

### Objective

Add reverse proxy cache in front of the app.

### Tasks

* deploy Varnish pod
* mount VCL from ConfigMap
* backend = app service

### VCL behavior (initial)

* cache GET/HEAD
* bypass `/cart`, `/account`
* bypass if `session` cookie
* set TTL (e.g., 2 min)

### Validation tests

```
curl /product/1 → MISS
curl /product/1 → HIT
curl /cart → PASS
```

### Definition of Done

* `X-Cache` headers show HIT/MISS
* VCL is versioned in Git
* TTL can be changed in one place
* cache bypass behavior is covered by curl checks

---

# Phase 5 – Add Purge / Invalidation

### Objective

Reproduce Magento-style invalidation.

### Tasks

* implement BAN in Varnish
* secure purge with a shared header token
* connect `/admin/product/{id}` to BAN

### Test

1. load product → HIT
2. change product
3. verify MISS → HIT again

### Definition of Done

* purge flow documented with curl examples
* unauthorized purge requests are rejected

---

# Phase 6 – Cloudflare in Front

### Objective

Experience multi-layer cache behavior.

### Tasks

* domain
* proxy through Cloudflare
* configure minimal ruleset
* document which headers are stripped or transformed

### Learn

* which headers survive
* double HIT/MISS logic
* where SSL terminates
* real client IP handling

### Definition of Done

* `CF-Cache-Status` and `X-Cache` both visible
* request-id remains consistent end-to-end

---

# Phase 7 – Observability (Expansion)

### Objective

Expand visibility beyond the baseline logs and headers added earlier.

### Minimum

* request rate
* hit/miss ratio
* backend latency
* errors
* confirm headers and cacheability align with API design

If metrics stack is heavy, logs + parsing is fine.

### Questions you must answer

* what is hit ratio?
* what is bypass rate?
* what happens when app is slow?

### Definition of Done

* a single dashboard or log query answers all questions
* log retention and rotation are defined

---

# Phase 8 – Failure & Incident Simulations

### Objective

Build instincts.

### Exercises

* bad cookie rule → private content cached
* purge not working
* backend down → enable grace
* remove cache headers → watch MISS spike
* Cloudflare caching API

### Document

* symptoms
* detection
* resolution

### Definition of Done

* each exercise has a short runbook and rollback

---

# Phase 9 – CI/CD Maturity

### Objective

Move from it runs to it is safe.

### Add

* OpenAPI validation
```
validate openapi
generate clients
fail if git diff exists
```
* PR validation
* image tagging
* automated deployment
* rollback method

### Stretch goals

* ephemeral env per branch
* smoke tests
* config validation

### Definition of Done

* pipeline fails on spec drift
* rollback command is documented and tested

---

# Phase 10 – Infrastructure as Code (Pulumi)

### Objective

Automate everything outside the cluster.

### Provision

* VPC
* instance
* security groups
* DNS
* optional load balancer

### Deliverables

```
make infra-up
make infra-down
```

### Definition of Done

* infra creates a reachable k3s node
* infra teardown removes all resources

---

# Phase 11 – Documentation Like a Production System

### Objective

Prove maintainability.

### Write

* architecture
* request flow
* purge design
* config ownership and source of truth
* how to deploy
* how to debug MISS
* common failures
* api evolution
	* how to change API
	* versioning strategy
	* deprecation example

---

# Phase 12 – Frontend (Optional)

### Objective

Build a simple SPA that consumes the API.

### Tasks

* SPA Must Use Generated Client

### Frontend must:

* consume generated API client
* no handwritten fetch logic

If backend changes contract → frontend build fails.

---

# Definition of Done (Project Success)

* environment recreated from zero
* visible hit ratio
* safe purge
* known bypass rules
* versioned config
* failures understandable

---

# Skills Gain

* reverse proxy mastery
* multi-layer caching
* safe change patterns
* infra automation
* debugging methodology
* communicating tradeoffs

