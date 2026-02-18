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

## Current Status (As Of 2026-02-18)

Phases 0-9 are implemented and validated across local workflows and CI/CD:

* OpenAPI-driven handlers and tests are in place.
* Cache headers, request id, and response meta are returned for cacheable endpoints.
* Varnish is deployed in Compose and Kubernetes with HIT/MISS/PASS behavior.
* Purge is supported via Varnish `PURGE` with `X-Purge-Token`.
* Admin updates validate `X-Purge-Token` and return `X-Purge-Tags` for invalidation workflows.
* CI validates OpenAPI, codegen drift, lint/test, and image builds.
* Pulumi + GitHub Actions workflows provision/teardown infrastructure and support DNS updates.
* Cloudflare Worker deployment and route wiring are in place for edge proxying.
* Frontend SPA is implemented with generated OpenAPI models/client artifacts and cache observability UI.

## Post-Phase-9 Reflection & Cleanup (2026-02-18)

This is a stability and maintainability checkpoint before starting Phases 10-12.

### What is working well

* Contract-first flow is established across backend and frontend.
* Cache behavior is inspectable end-to-end (headers + request id + response meta).
* Local, k8s, and CI paths are all reproducible.
* Purge flows are secured and testable.

### Cleanup and refactor focus areas

1. **Frontend contract guardrails**
    * Keep generated TypeScript client in sync with OpenAPI via CI drift checks.
    * Continue reducing endpoint-specific request duplication in page components while preserving header visibility required for cache diagnostics.

2. **Documentation normalization**
    * Keep status references consistent across `README.md`, `PLAN.md`, and `docs/*`.
    * Clarify Cloudflare ownership boundaries and expected header behavior in one place.

3. **Phase 10 readiness**
    * Standardize the minimal observability queries now (hit ratio, bypass rate, backend latency, errors).
    * Define retention/rotation expectations before adding more signal sources.

### Next milestone

Phases 10-12 now become the active implementation track:

* Phase 10: observability expansion with concrete dashboard/log queries.
* Phase 11: incident simulations with short runbooks and rollbacks.
* Phase 12: production-grade operational documentation and API evolution policy.

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
* No CI/CD until local flows are repeatable.
* No Pulumi until CI/CD baselines exist and local + k8s flows are repeatable.
* No Cloudflare until Varnish HIT/MISS and purge are deterministic and infra exists.

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
    /pulumi (Python)    → IaC for k8s and cloud resources
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

* implement `PURGE` + BAN in Varnish
* secure purge with a shared header token
* validate `X-Purge-Token` on `/admin/product/{id}` and return `X-Purge-Tags`
* document why tag-based purge wiring is deferred

### Test

1. load product → HIT
2. update product (admin endpoint)
3. send `PURGE /product/{id}` with `X-Purge-Token`
4. verify MISS → HIT again

### Definition of Done

* purge flow documented with curl examples
* unauthorized purge requests are rejected

### Deferred: tag-based purge wiring (future)

Wire `X-Purge-Tags` into Varnish BAN rules after the URL-based flow is stable. This matters because:

* Tag-based invalidation lets you purge related objects (product detail + category + homepage) in one action.
* It avoids brittle URL coupling when routes or query strings evolve.
* It matches common CDN cache workflows used by larger platforms.

---

# Phase 6 – CI/CD Baseline

### Objective

Make API and spec changes safe before provisioning cloud infrastructure.
From this phase onward, CI/CD improvements are applied as needed in each phase.

### Add

* OpenAPI validation on PRs
* codegen drift detection (fail on git diff)
* API lint + test
* image build + tag (no deploy yet)
* local GitHub Actions validation with `act`

### Acceptance checks

* `act` runs the main workflow locally
* PR workflow fails on OpenAPI drift and lint/test failures

### Definition of Done

* pipeline fails on spec drift
* rollback or teardown step documented for pipeline artifacts

---

# Phase 7 – Infrastructure as Code (Pulumi)

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

# Phase 8 – Cloudflare in Front

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

# Phase 9 – Frontend

### Objective

Build a simple SPA that consumes the API.

### Tasks

* SPA Must Use Generated Client

### Frontend must:

* consume generated API client
* no handwritten fetch logic

If backend changes contract → frontend build fails.

---

# Phase 10 – Observability (Expansion)

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

# Phase 11 – Failure & Incident Simulations

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

# Phase 12 – Documentation Like a Production System

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

