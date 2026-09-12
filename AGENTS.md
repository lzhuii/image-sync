# AGENTS.md

Repo purpose: one-shot tool that mirrors container images from Docker Hub / GCR / GHCR / Quay.io into Aliyun ACR via GitHub Actions. No app code — just `sync.sh`, `images.txt`, and `.github/workflows/sync.yml`.

## Toolchain

- Only dependency is `skopeo` (installed by the workflow; locally you must install + `skopeo login` before running).
- No build, test, formatter, codegen. Don't look for them — they don't exist.
- `shellcheck` runs on every push as a step inside `.github/workflows/sync.yml` (installed together with skopeo). Run it locally before pushing if you have it installed.
- Do not add a package manager, CI matrix, or new toolchain.

## Triggers

- Only push to `master` (`.github/workflows/sync.yml`). No schedule, no manual dispatch.
- `concurrency.group: sync-images` prevents overlapping runs, but `cancel-in-progress` is NOT set — later pushes wait for the current one to finish rather than cancelling it.
- Secrets `ACR_USERNAME` / `ACR_PASSWORD` must exist in repo Settings. `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` are optional; if both are set, workflow runs `skopeo login docker.io` and pulls as authenticated user (200/6h). Otherwise anonymous (100/6h per IP).

## `sync.sh` subcommands

```bash
bash sync.sh            # run the sync (digest comparison + copy)
bash sync.sh validate   # offline manifest check, no network, no skopeo
```

- `validate` is the workflow's first step. It rejects: missing `|` delimiter, empty namespace or source, duplicate entries, namespace count > 3 (ACR personal hard limit, override with `MAX_NAMESPACES`).
- Both subcommands use `awk` + `xargs -P`; don't reformat without checking POSIX sh compatibility.

## `images.txt` format (easy to get wrong)

- One entry per line, delimiter is a **pipe**: `<namespace>|<source_image>` (e.g. `cn-infra|quay.io/jetstack/cert-manager`). Every entry needs a namespace — a blank one is silently dropped by the awk filter in `sync.sh`.
- `#` starts a comment (both whole-line and inline after `|`, stripped by `sync.sh`); blank lines and lines with `< 2` fields are ignored.
- Whitespace around the pipe is trimmed automatically — no need to strip it in the file.
- Missing entries are silently not synced; typos in the source image produce a workflow failure with the skopeo error, not a validate warning.

## Running locally

```bash
skopeo login registry.cn-beijing.aliyuncs.com -u <user> -p <password>
bash sync.sh
```

- Env vars: `REGISTRY` (default `registry.cn-beijing.aliyuncs.com`, Beijing region — override before pushing elsewhere), `CONCURRENCY` (default `4`), `MAX_NAMESPACES` (default `3`), `PLATFORMS` (default `linux/amd64,linux/arm64` — use `--multi-arch` instead of `--all` because ACR personal edition rejects `application/vnd.oci.empty.v1+json` empty manifest entries that some upstream manifest lists include).
- `sync.sh` uses digest comparison; unchanged images are skipped. There is no `--force` flag — altering the source digest is the only way to re-push.

## Conventions

- Commit messages and docs are in Chinese; keep that style when editing `images.txt` comments. The README is split into `README.md` (English) and `README.zh.md` (Chinese) — both must be kept in sync when behavior changes.
- Push to `master` directly; there is no branch-protection / PR-flow expectation.
- Don't add `.env` files or example env files — the repo is expected to stay public, and any config sample risks leaking credentials patterns.

## What's intentionally NOT here

- No retries / backoff (MVP scope).
- No `--force` / forced resync flag.
- No schedule or cron trigger.
- No auth for GHCR / GCR / Quay.io sources — only Docker Hub is authenticated when configured.
