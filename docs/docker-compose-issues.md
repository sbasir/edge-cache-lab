# Docker Compose Known Issues

## DNS Resolution for Varnish Backend

### Issue
In some Docker environments, the embedded DNS server (127.0.0.11) may refuse queries for service names during Varnish VCL compilation. This manifests as:

```
Backend host '"api"' could not be resolved to an IP address: Try again
```

### Why This Happens
- Varnish compiles VCL at startup and needs to resolve backend hostnames at compile time
- Docker's embedded DNS sometimes doesn't respond quickly enough or refuses queries
- This is environment-specific and may not occur in all Docker setups

### Workaround
If you encounter this issue, you can:

1. Use a fixed IP address in the VCL (requires network configuration)
2. Use host networking mode (loses container isolation)
3. Deploy to Kubernetes where DNS resolution works reliably

### Kubernetes
The Kubernetes deployment does not have this issue as it uses CoreDNS which reliably resolves service names.

### Status
This is a known limitation of the Docker Compose setup in certain environments. The Kubernetes deployment (Phase 4) works correctly.
