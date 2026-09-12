# Image Sync

Mirror container images from Docker Hub / GCR / GHCR / Quay.io into Aliyun ACR, so mainland China users can pull them reliably.

**Languages:** [English](README.md) · [简体中文](README.zh.md)

---

## Project Overview

`images.txt` is the only user-facing config. Each push to `master` triggers a GitHub Actions workflow that uses `skopeo` to copy every listed image into your ACR instance. Digest comparison makes the run idempotent — unchanged images are skipped.

## Problem Statement

From mainland China, pulling images from Docker Hub / GCR / GHCR / Quay.io is unreliable:

- **Timeouts** — Kubernetes and Helm pull requests frequently time out
- **Unstable throughput** — the same pull can take seconds on one day and minutes the next
- **Regional blockage** — some registries are entirely unreachable

CI/CD pipelines depend on `ghcr.io/*` and `quay.io/*` images. When those become unreachable, your entire build breaks.

## Design Decisions

**Why skopeo instead of Docker.**
`skopeo` is a small CLI (~50 MB), has no daemon, and speaks every registry protocol. It's the ideal tool for CI/CD image mirroring.

**Why digest-based sync.**
Each image carries an immutable digest (SHA256). Comparing source and destination digests tells you whether the image has actually changed. The sync is idempotent and never wastes bandwidth.

**Why `skopeo login` for credentials.**
Both ACR (target) and Docker Hub (optional source) credentials are injected by the workflow via `skopeo login`, which writes to the default authfile (`~/.config/containers/auth.json`). The `sync.sh` script itself is auth-agnostic — it just calls `skopeo copy` and lets skopeo pick up credentials automatically.

**Why no retries in this MVP.**
Retries (exponential backoff, `--retry-times`) would add resilience but also complexity. The MVP keeps the script minimal. If you need retries, add them in a future iteration — the structure allows it.

**Why push-triggered, not scheduled.**
Public repos get unlimited free GitHub Actions minutes; scheduled runs burn quota without need. You pull from the source only when you change `images.txt`, which is the actual signal that a new image should be synced.

**Why `images.txt` format stays unchanged.**
The `namespace|source` format is familiar and simple. Changes would break existing users for no clear benefit.

## Quickstart

### 1. Fork and configure

Fork this repository, then add the required secrets in **Settings → Secrets and variables → Actions**.

### 2. Edit `images.txt`

Add entries in the format `namespace|source_image`:

```
cn-infra|nginx                          # Docker Hub → registry/cn-infra/nginx
cn-infra|quay.io/jetstack/cert-manager  # Quay.io   → registry/cn-infra/cert-manager
cn-infra|gcr.io/k8s-minikube/kicbase    # GCR       → registry/cn-infra/kicbase
```

`#` starts a comment (whole-line or inline after `|`). Blank lines are ignored.

### 3. Push to `master`

```bash
git add images.txt && git commit -m "Add images" && git push
```

After pushing to `master`, GitHub Actions syncs automatically.

### 4. Run locally (optional)

```bash
skopeo login registry.cn-beijing.aliyuncs.com -u <user> -p <password>
bash sync.sh
```

## GitHub Secrets

| Secret | Required | Description |
|---|---|---|
| `ACR_USERNAME` | **Yes** | Aliyun ACR access key |
| `ACR_PASSWORD` | **Yes** | Aliyun ACR password |
| `DOCKERHUB_USERNAME` | No | Docker Hub username |
| `DOCKERHUB_TOKEN` | No | Docker Hub access token |

If `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` are both set, the workflow runs `skopeo login docker.io` and pulls from Docker Hub as an authenticated user (rate limit: 200 pulls / 6h). Otherwise, Docker Hub pulls happen anonymously (rate limit: 100 pulls / 6h per IP). GHCR, GCR, and Quay.io are always pulled anonymously.

## `images.txt` Format

One entry per line, pipe-delimited. Every entry must have a non-empty namespace and source:

```
<namespace>|<source_image>
```

- `<namespace>` — a non-empty string that maps to a subdirectory in your target registry. ACR personal edition supports a **hard limit of 3 namespaces** per instance. This limit is checked by `bash sync.sh validate` before every sync.
- `<source_image>` — a Docker reference like `nginx`, `apache/kafka`, `quay.io/jetstack/cert-manager`, or `gcr.io/k8s-minikube/kicbase:v0.0.50`. The destination image name is derived from the basename: `quay.io/jetstack/cert-manager` → `<registry>/<namespace>/cert-manager`.

Rules:

- `#` starts a comment — whole-line or inline after `|`. `sync.sh` strips inline comments via `awk` before parsing.
- Blank lines and lines with fewer than 2 pipe-separated fields are silently ignored.
- Whitespace around the pipe is trimmed automatically.
- Duplicate entries are rejected by `bash sync.sh validate` (exits non-zero, workflow fails).
- Namespaces exceeding 3 are rejected by `bash sync.sh validate`.

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `REGISTRY` | `registry.cn-beijing.aliyuncs.com` | Target ACR address |
| `CONCURRENCY` | `4` | Parallel sync jobs |
| `MAX_NAMESPACES` | `3` | Max namespace count (validation only) |

`REGISTRY` is the Beijing ACR endpoint by default. Override it before deploying to another region (e.g. `registry.cn-hangzhou.aliyuncs.com`).

## Running Locally

```bash
# 1. Install skopeo (required)
sudo apt-get install -y skopeo    # Debian/Ubuntu

# 2. Authenticate to ACR
skopeo login registry.cn-beijing.aliyuncs.com -u <user> -p <password>

# 3. (Optional) Authenticate to Docker Hub for authenticated pulls
skopeo login docker.io -u <username> -p <token>

# 4. Run
bash sync.sh

# 5. Or validate only (no network calls)
bash sync.sh validate
```

## Validate Subcommand

`bash sync.sh validate` runs an offline check of `images.txt`. It does **not** call the network or `skopeo`. It checks:

- Missing `|` delimiter
- Empty namespace or source
- Duplicate entries
- Namespace count exceeds 3 (or `$MAX_NAMESPACES`)

The workflow runs `bash sync.sh validate` as the first step. Any validation error fails the workflow before any network call is made.

## GitHub Actions Free Tier

Public repos get **unlimited free minutes** on standard GitHub-hosted runners. Cache and artifact storage are separate:

| Item | Public repo (Free plan) | Private repo (Free plan) |
|---|---|---|
| Standard runner minutes | Unlimited (free) | 2,000 / month |
| Artifact storage | 500 MB (shared with GitHub Packages) | 500 MB |
| Cache storage | 10 GB / repo | 10 GB / repo |
| Single job timeout | 6 hours | 6 hours |
| Single workflow timeout | 35 hours | 35 hours |

Source: [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)

This repo uses no artifacts or cache (skopeo pulls directly from source and pushes to ACR), so total cost is zero **as long as the repo stays public**.

**Important**: If you make the repo private, the 2,000 free minutes cover roughly 10 syncs per day (assuming 10 min each). For heavier use, keep the repo public.

## Quotas & Limitations

### Aliyun ACR Personal Edition

The default target (`registry.cn-beijing.aliyuncs.com`) is the **ACR Personal Edition**. Official [specs](https://help.aliyun.com/zh/acr/product-overview/what-is-container-registry):

| Item | Value |
|---|---|
| Namespaces | 3 (hard limit) |
| Public repos | 300 |
| Concurrent builds | 1 |
| Pull QPS | **Not guaranteed** |
| SLA | None |
| VPC access control | No |
| Version immutability | No |
| Auto cleanup | No |
| Network access control / Audit | No |

**Official warning**: ACR Personal Edition has "no SLA commitment and no SLA compensation, with usage limits. Do not use in production."

Additional note: For instances created on or after **2024-09-04**, the `aliyun-acr-credential-helper` component (免密拉取) is not available. Kubernetes deployments must use traditional `imagePullSecret` instead.

### Docker Hub Pull Rate Limits

Docker Hub [rate limits](https://docs.docker.com/docker-hub/download-rate-limit/) are enforced per rolling 6-hour window:

| User type | Pulls / 6h |
|---|---|
| Anonymous (per IP) | 100 |
| Personal (authenticated) | 200 |
| Team / Pro / Business | Unlimited |

Configure `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets to raise the limit from 100 to 200.

## Troubleshooting

**`429 Too Many Requests` from Docker Hub.**
You hit the anonymous rate limit. Configure `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets, or push again after the 6-hour window resets.

**`401 Unauthorized` when pushing to ACR.**
`ACR_USERNAME` / `ACR_PASSWORD` are missing, expired, or lack push permission. Verify the AccessKey has write access to the target namespace.

**`image not found` on source.**
The source tag doesn't exist or is unreachable. Check the exact reference in your browser first.

**`denied: unknown manifest class for application/vnd.oci.empty.v1+json` when copying a multi-arch image.**
Some source images (e.g. `gitea/gitea`) have manifest lists that include empty placeholder manifests. ACR personal edition rejects the `application/vnd.oci.empty.v1+json` media type. This repo uses `skopeo copy -a` (equivalent to `--all`) which copies the full multi-arch manifest list, so these images will fail. Workarounds:

1. Remove the problematic image from `images.txt` and sync it manually.
2. Upgrade to skopeo 1.13+ (build from source or install manually) to enable `--multi-arch=linux/amd64,linux/arm64` for platform-specific copying.

**Namespace limit reached (validate error).**
The manifest uses more than 3 distinct namespaces. Consolidate images under fewer namespaces, or upgrade to ACR Enterprise.

**Duplicate entry error (validate error).**
Two lines in `images.txt` resolve to the same `namespace|source`. Remove the duplicate.

## Production Recommendations

- **Use ACR Enterprise, not Personal**, for any workload that isn't a personal experiment. Enterprise adds VPC access control, SLA, security scanning, audit logs, and higher quotas. The default `REGISTRY` in this repo is Personal Edition — override it if you use Enterprise.
- **Keep the repo public.** Public repos get unlimited free GitHub Actions minutes; private repos are capped at 2,000/month.
- **Use authenticated Docker Hub pulls** for anything you care about. Anonymous pulls have a 100/6h limit and can be hit by CI activity from other users on shared IPs.
- **Keep `images.txt` bounded.** Each push re-syncs every entry in the manifest. A manifest with hundreds of images means each push pulls hundreds of images. Split the manifest if needed.
- **Watch ACR storage.** Personal Edition has no auto-cleanup. Old tags accumulate over time.

## License

MIT
