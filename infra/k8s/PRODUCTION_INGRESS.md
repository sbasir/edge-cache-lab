# Production Ingress Setup Guide

## Overview
Your k3s cluster now has Traefik Ingress configured for **Varnish only**. The API remains an internal ClusterIP service, never exposed directly.

## Current Setup
- **Traefik** (built into k3s) routes external traffic → **Varnish**
- **Varnish** (Ingress resource) caches and proxies → **API**
- **API** remains private (ClusterIP only)

## Deployment Steps

### 1. Basic Setup (HTTP only, any hostname)
Just deploy with the base configuration. Traefik will expose Varnish on port 80:
```bash
kubectl apply -k infra/k8s/overlays/production
```

This works immediately if your EC2 instance's security group allows inbound traffic on port 80.

### 2. Hostname-Based Routing (Recommended)
Edit [`infra/k8s/overlays/production/varnish-ingress.yaml`](infra/k8s/overlays/production/varnish-ingress.yaml):
- Replace `api.example.com` with your actual domain
- Uncomment the patch in `kustomization.yaml`
- Redeploy

```bash
# Edit varnish-ingress.yaml with your domain
kubectl apply -k infra/k8s/overlays/production
```

### 3. HTTPS/TLS Setup (Production recommended)
Requires **cert-manager**:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

# Create a production Let's Encrypt ClusterIssuer
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: traefik
EOF
```

Then uncomment and enable TLS in `varnish-ingress.yaml`:
```yaml
  tls:
    - hosts:
        - api.example.com
      secretName: varnish-tls
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
```

## Verification

```bash
# Check Ingress is created
kubectl get ingress -n edge-cache-lab

# Check Traefik is routing traffic
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik

# Port-forward to test (if not exposing port 80 on EC2)
kubectl port-forward -n edge-cache-lab svc/varnish 8000:80
# Then curl http://localhost:8000/health
```

## Troubleshooting

**Varnish not reachable from EC2 public IP?**
- Check EC2 security group allows inbound on port 80 (and 443 for HTTPS)
- Verify Traefik is running: `kubectl get pods -n kube-system`
- Check Ingress status: `kubectl describe ingress varnish -n edge-cache-lab`

**Can internal clients (EC2 services) still reach the API?**
- Yes! They use the ClusterIP service directly: `http://api.edge-cache-lab:3000`
- Only external traffic goes through Varnish

## Architecture at a Glance
```
External Traffic (EC2:80/443)
    ↓
Traefik Ingress Controller
    ↓
Varnish Service (ClusterIP)
    ↓
API Service (ClusterIP) - PRIVATE
```

## Files Modified
- `infra/k8s/base/varnish/ingress.yaml` - New Ingress resource
- `infra/k8s/base/varnish/kustomization.yaml` - Added ingress.yaml
- `infra/k8s/overlays/production/kustomization.yaml` - Added guidance
- `infra/k8s/overlays/production/varnish-ingress.yaml` - Hostname/TLS patch (optional)
