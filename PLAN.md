# Edge Cache Lab – Implementation Plan

> Goal: build a production-like, fully automated mini e-commerce platform that demonstrates CDN → Varnish → App → DB behavior, including CI/CD, observability, and safe operations.

This project optimizes for **operability, repeatability, and debuggability**, not application complexity.

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

Endpoints, request/response formats, and error models are defined in OpenAPI.
Both backend and frontend code are generated or validated against this spec.

Breaking the contract must fail CI.

---

# Phase 0 – Repository & Tooling Foundation

### Objective

Create the skeleton and developer ergonomics.

### Deliverables

* Repo structure
* Makefile
* basic CI pipeline stub

### Suggested Structure

```
/app                → demo store
/infra              → Pulumi
/k8s                → manifests / helm
/varnish            → VCL
/docs
Makefile
```

### Make targets (example)

```
make build
make test
make deploy
make destroy
make port-forward
```

### CI (initial)

* lint
* build containers

No infra yet.

---

# Phase 1 – Define the API Contract

### Objective

Describe the system before implementing it.

### Technology

OpenAPI

### Tasks

Create:

```
/api/openapi.yaml
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

### Deliverables

* versioned spec in Git
* reviewed like code
* baseline for generation

### Definition of Done

If the spec changes → backend or frontend should fail build until regenerated.

---

# Phase 2 – Build the Backend From the Contract

### Objective

Simulate Magento-like caching behavior with minimal code.
Implement API described in OpenAPI.

### Tasks

* generate Go types/server interfaces
* implement handlers
* responses must match spec
* compilation ensures alignment

### Important Rule

Do not invent routes manually.
If it’s not in the spec → it doesn’t exist.

### Response behavior

Return:

* timestamps
* instance name
* headers received

This helps you visually debug cache layers.

### Deliverables

* Dockerfile
* health endpoint
* simple tests

---

# Phase 3 – Run App in Kubernetes (no Varnish yet)

### Objective

Origin service works.

### Tasks

* Deployment
* Service
* Ingress or ClusterIP
* scaling replicas

### Validate

* curl works
* multiple pods respond

### Deliverables

* manifests or Helm
* ability to redeploy

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
curl → MISS
curl again → HIT
```

Check headers.

### Deliverables

* working HIT/MISS
* ability to tweak TTL
* VCL in Git

---

# Phase 5 – Add Purge / Invalidation

### Objective

Reproduce Magento-style invalidation.

### Tasks

* implement BAN or URL purge endpoint in Varnish
* connect `/admin/product/{id}` to purge

### Test

1. load product → HIT
2. change product
3. verify MISS → HIT again

### Deliverables

* documented purge flow
* runbook notes

---

# Phase 6 – Cloudflare in Front

### Objective

Experience multi-layer cache confusion

### Tasks

* domain
* proxy through Cloudflare
* configure basic rules

### Learn

* which headers survive
* double HIT/MISS logic
* where SSL terminates
* real client IP handling

### Deliverables

* diagram
* explanation of responsibility split

---

# Phase 7 – Observability

### Objective

Make system behavior visible.

### Minimum

* request rate
* hit/miss ratio
* backend latency
* errors
* confirm headers & cacheability align with API design
* * e.g. if endpoint marked private → verify PASS.

If metrics stack is heavy, even logs + parsing is fine.

### Questions you must answer from dashboards

* what is hit ratio?
* what is bypass rate?
* what happens when app is slow?

---

# Phase 8 – Failure & Incident Simulations

### Objective

Build instincts.

Break things intentionally.

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

---

# Phase 9 – CI/CD Maturity

### Objective

Move from “it runs” → “it’s safe”.

### Add

* openapi validation
```
validate openapi
generate clients
fail if git diff exists
```
* PR validation
* image tagging
* automatic deployment
* rollback method

### Stretch goals

* ephemeral env per branch
* smoke tests
* config validation

---

# Phase 10 – Infrastructure as Code (Pulumi)

### Objective

Automate everything outside the cluster.

### Provision

* VPC
* instance
* security groups
* DNS
* maybe load balancer

### Deliverables

```
make infra-up
make infra-down
```

---

# Phase 11 – Documentation Like a Production System

### Objective

Prove maintainability.

### Write

* architecture
* request flow
* purge design
* how to deploy
* how to debug MISS
* common failures
* api evolution
* * how to change API
* * versioning strategy
* * deprecation example

---

# Phase 12 - Frontend (Optional)

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

