# Standards Audit

**Repo:** `/Users/sofy/projects/current/edge-cache-lab`  
**Stacks:** cloudflare, docker, go, node, python, shell  
**Score:** 29/29 passing · 0 warn · 0 fail

## Dev experience

| Control | Status | Detail |
|---|:---:|---|
| Makefile present | ✅ | Makefile present |
| SHELL + pipefail hardening | ✅ | SHELL=/bin/bash + pipefail set |
| .DEFAULT_GOAL := help | ✅ | .DEFAULT_GOAL := help |
| Sectioned self-documenting help | ✅ | sectioned help macro with ##! stars |
| `make ci` mirrors CI | ✅ | ci target present (should mirror CI workflow) |
| Standard targets | ✅ | all standard targets present |
| Runtime pinning (.mise.toml) | ✅ | .mise.toml present |
| Git hooks (lefthook) | ✅ | lefthook.yml present |

## CI/CD security

| Control | Status | Detail |
|---|:---:|---|
| CI workflows present | ✅ | 16 workflow(s) |
| Actions SHA-pinned | ✅ | all 68 action refs SHA-pinned |
| permissions: {} lockdown | ✅ | all workflows use `permissions: {}` lockdown |
| Concurrency control | ✅ | concurrency set on all workflows |
| Job timeouts | ✅ | timeout-minutes on all workflows |
| actionlint + pinact enforcement | ✅ | actionlint + pinact enforced in CI |
| Secret scanning (gitleaks) | ✅ | gitleaks workflow present |
| yamllint config | ✅ | .yamllint present |
| Dependency updates | ✅ | dependabot configured |
| CODEOWNERS | ✅ | CODEOWNERS present |

## Quality gates

| Control | Status | Detail |
|---|:---:|---|
| JS/TS: biome | ✅ | biome.json present |
| JS/TS: pnpm enforced | ✅ | pnpm enforced (packageManager/only-allow + pnpm-lock.yaml) |
| JS/TS: timeboxed dep-audit | ✅ | timeboxed dep-audit present |
| Python: ruff | ✅ | ruff configured |
| Python: pip-audit | ✅ | pip-audit present |
| Go: golangci-lint | ✅ | golangci-lint configured |
| Terraform: fmt/validate/tflint/checkov | — | not a Terraform repo |
| Docker: hadolint + trivy | ✅ | hadolint + trivy |
| Shell: shellcheck | ✅ | shellcheck present |

## Kubernetes/Helm

| Control | Status | Detail |
|---|:---:|---|
| Helm: chart lint | — | not a Helm repo |
| Helm: kubeconform schema validation | — | not a Helm repo |
| Helm: trivy config misconfig scan | — | not a Helm repo |

## Cloudflare

| Control | Status | Detail |
|---|:---:|---|
| wrangler config quality | ✅ | wrangler config: observability, compat_date |
| Preview environment | ✅ | preview env + PR preview workflow |
| deploy --dry-run gate | ✅ | wrangler --dry-run gate present |

## Uncovered tech (no controls yet)

The standard has no controls for the following detected tech. Run `project-standard extend <key>` to add controls + templates for it.

- `kubernetes` — Kubernetes manifests / Kustomize
- `pulumi` — Pulumi IaC
- `docker-compose` — Docker Compose
