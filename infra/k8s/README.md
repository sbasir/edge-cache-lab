# Kubernetes Manifests

This directory contains Kubernetes manifests for applications deployed to the k8s cluster.

## Directory Structure
```
infra/k8s/
  base/
    api/
      namespace.yaml
      deployment.yaml
      service.yaml
      kustomization.yaml
  overlays/
    local/
      kustomization.yaml
  README.md
```

## Design Principles

### Separation of Applications
Each application has its own directory under `base/`:
- **Self-contained**: All resources for an app in one place
- **Independent**: Can be deployed/removed without affecting others
- **Versioned**: Each app can have its own release cycle

### Kustomize-Based
All manifests use Kustomize for:
- Base configuration management
- Environment-specific overlays
- Image tag management
- Configuration variants

### Namespace Isolation
Each application gets its own namespace:
- Resource isolation
- RBAC boundaries
- Easier management and debugging

## Current Applications
### API
- Namespace: `edge-cache-api`
- Base manifests: `infra/k8s/base/api`
- Local overlay: `infra/k8s/overlays/local`
- Service: `edge-cache-api` on port 3000 (ClusterIP)

## Working with Manifests
- Local apply: `make k8s-test-local`
- Port-forward API: `make k8s-port-forward-api`
- Port-forward Varnish: `make k8s-port-forward-varnish`
- Port-forward Web: `make k8s-port-forward-web`
- Wait for rollout: `make k8s-wait`
- Check status: `make k8s-status`
- Tail logs: `make k8s-logs`
- Cleanup: `make k8s-clean-local`
