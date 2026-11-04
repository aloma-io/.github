# Reusable Workflows

This repository contains reusable GitHub workflows that can be used across all Aloma repositories.

## Docker Build and Push Workflow

### Location
`.github/workflows/docker-build-push.yml`

### Description
A comprehensive workflow that builds Docker images with caching and pushes them to both Azure Container Registry and Google Artifact Registry in parallel.

### Status: ✅ FULLY OPERATIONAL
**Latest Test Results (t1.13.7-basic-caching):**
- ✅ Build time: 34s (with caching)
- ✅ Azure push: 28s
- ✅ Google push: 35s  
- ✅ Total workflow time: ~1m18s
- ✅ Parallel execution confirmed

### Features
- ✅ **Docker Buildx** with GitHub Actions caching
- ✅ **Parallel pushes** to Azure and Google registries
- ✅ **Automatic tag derivation** (SHA, branch-based tags)
- ✅ **Artifact sharing** between jobs for efficiency
- ✅ **Configurable registry targets** (can disable Azure or Google)
- ✅ **Flexible input parameters**
- ✅ **Conditional execution** (skips push jobs when disabled)

### Usage

#### Basic Usage
```yaml
name: Build and Deploy

on:
  push:
    branches: [ main ]
    tags: [ 't*', 'p*' ]
  pull_request:
    branches: [ main ]

jobs:
  docker:
    uses: aloma-io/.github/.github/workflows/docker-build-push.yml@main
    with:
      image_name: 'my-service'
    secrets:
      AZURE_USER: ${{ secrets.AZURE_USER }}
      AZURE_PASS: ${{ secrets.AZURE_PASS }}
      GOOGLE_CLOUD_KEY: ${{ secrets.GOOGLE_CLOUD_KEY }}
```

#### Advanced Usage
```yaml
jobs:
  docker:
    uses: aloma-io/.github/.github/workflows/docker-build-push.yml@main
    with:
      image_name: 'my-service'
      dockerfile: 'build/Dockerfile'
      context: './src'
      tags: ${{ github.ref_type == 'tag' && github.ref_name || 'latest' }}
      cache-scope: 'my-custom-scope'
      enable-azure: true
      enable-google: false  # Only push to Azure
    secrets:
      AZURE_USER: ${{ secrets.AZURE_USER }}
      AZURE_PASS: ${{ secrets.AZURE_PASS }}
      PAT: ${{ secrets.PAT }}  # For private submodules
```

### Inputs

| Input | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `image_name` | ✅ | string | - | Name of the Docker image (without registry prefix) |
| `dockerfile` | ❌ | string | `Dockerfile` | Path to Dockerfile |
| `context` | ❌ | string | `.` | Build context path |
| `tags` | ❌ | string | `latest` | Tags to apply (comma or space separated) |
| `cache-scope` | ❌ | string | `github.repository` | Cache scope for Docker buildx |
| `enable-azure` | ❌ | boolean | `true` | Enable push to Azure Container Registry |
| `enable-google` | ❌ | boolean | `true` | Enable push to Google Artifact Registry |

### Secrets

| Secret | Required | Description |
|--------|----------|-------------|
| `AZURE_USER` | ❌* | Azure Container Registry username |
| `AZURE_PASS` | ❌* | Azure Container Registry password |
| `GOOGLE_CLOUD_KEY` | ❌* | Google Cloud service account key (base64) |
| `PAT` | ❌ | Personal Access Token for private repositories |

*Required if the corresponding registry is enabled

### Outputs

The workflow provides the following outputs from the build job:

| Output | Description |
|--------|-------------|
| `primary-tag` | The primary tag assigned to the image |
| `all-tags` | All tags applied to the image (space-separated) |
| `image-digest` | SHA256 digest of the built image |

### Tag Generation

The workflow automatically generates additional tags:
- **SHA tag**: 8-character commit SHA (e.g., `sha-abc12345`)
- **Branch tag**: Branch name (for non-main branches, e.g., `feat-new-feature`)
- **User-provided tags**: As specified in the `tags` input

### Registry URLs

Images are pushed to:
- **Azure**: `aloma.azurecr.io/{image_name}:{tag}`
- **Google**: `us-central1-docker.pkg.dev/aloma-site/{image_name}/{image_name}:{tag}`

### Error Handling

- If Azure credentials are missing, the Azure push job is skipped
- If Google credentials are missing, the Google push job is skipped
- Build failures stop the entire workflow
- Individual push failures don't affect other push jobs

### Examples for Different Repository Types

#### Frontend Application
```yaml
# .github/workflows/deploy.yml
jobs:
  docker:
    uses: aloma-io/.github/.github/workflows/docker-build-push.yml@main
    with:
      image_name: 'frontend-app'
      context: '.'
      dockerfile: 'Dockerfile'
    secrets: inherit
```

#### Microservice
```yaml
# .github/workflows/build.yml
jobs:
  docker:
    uses: aloma-io/.github/.github/workflows/docker-build-push.yml@main
    with:
      image_name: 'user-service'
      context: './services/user'
      dockerfile: './services/user/Dockerfile'
      tags: ${{ github.ref_type == 'tag' && github.ref_name || 'dev' }}
    secrets: inherit
```

#### Multi-service Repository
```yaml
# .github/workflows/build-all.yml
jobs:
  api:
    uses: aloma-io/.github/.github/workflows/docker-build-push.yml@main
    with:
      image_name: 'api'
      context: './api'
      cache-scope: 'api-cache'
    secrets: inherit
  
  worker:
    uses: aloma-io/.github/.github/workflows/docker-build-push.yml@main
    with:
      image_name: 'worker'
      context: './worker'
      cache-scope: 'worker-cache'
    secrets: inherit
```

## Migration Guide

### From Local Actions to Reusable Workflow

If you're currently using the local composite actions, replace your workflow with:

**Before:**
```yaml
jobs:
  docker-build:
    # ... build job
  push-azure:
    # ... azure push job  
  push-google:
    # ... google push job
```

**After:**
```yaml
jobs:
  docker:
    uses: aloma-io/.github/.github/workflows/docker-build-push.yml@main
    with:
      image_name: 'your-service-name'
    secrets: inherit
```

### Required Organization Secrets

Ensure these secrets are set at the organization level:
- `AZURE_USER`
- `AZURE_PASS`  
- `GOOGLE_CLOUD_KEY`

### Optional Repository Secrets
- `PAT` - Only needed for repositories with private submodules

## Connector CI Workflow (test only)

`.github/workflows/connector-ci.yml` installs, builds and tests an ALOMA connector:
`yarn install --frozen-lockfile`, `yarn build`, `yarn test`, once per Node version. The exit code is the result.
It never tags, publishes, pushes an image or calls the deploy webhook, takes no secrets and runs with a read-only
token. Releases stay in each connector's `build.yml` (tag push) and the release bot.

Each connector copies `workflow-templates/connector-ci.yml` to `.github/workflows/connector-ci.yml` and deletes its own
`test.yml` in the same pull request, so nothing runs twice. It runs on push to `main`, on pull requests and on demand.

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `node-versions` | string (JSON list) | `'["22"]'` | Node versions; add `"20"` when package.json `engines` allow it |
| `timeout-minutes` | number | `15` | Job timeout (the suite must finish in under 10 minutes) |
| `working-directory` | string | `.` | Folder holding package.json and yarn.lock |
| `run-mutants` | boolean | `false` | Run `test/mutants/run.mjs` (or `test/recorded/mutants.sh`) after the suite; honoured on `workflow_dispatch` and `schedule` only, never on push or pull request |

Tests: `.github/workflows/test-connector-ci.yml` (actionlint, `tests/test_connector_ci.py`, `tests/connector-ci-local.sh`
against `tests/fixtures/`, `tests/connector-ci-mutants.sh`, and a real call on the green fixture).

## Image CI Workflow (test, then build once)

`.github/workflows/image-ci.yml` runs the repo's own test command, and only if it passes builds the image ONCE with
`docker build`, tagged `<registry>/<image>:sha-<full commit>`. On a push to `main`, when the caller passes
`push: true`, it logs in with the registry secret the caller passes by name, refuses to overwrite a tag that already
exists, pushes, and outputs the registry digest. Pull requests test and build but never push. It never tags the repo,
never adds or moves a version or `latest` tag and deploys nothing: releases stay in each repo's `build.yml` (tag
push), the release bot and promotion by flux PR. A `sha-` tag matches no Flux image policy filter.

Each repo copies `workflow-templates/image-ci.yml` over its own test workflow (keeping the file name), fills in
`image-name` and `test-command`, and passes only its existing registry secret.

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `image-name` | string | required | Repository name in the registry |
| `test-command` | string | required | Run with `bash -e` from the repo root |
| `registry` | string | `aloma.azurecr.io` | Registry host |
| `context` / `dockerfile` | string | `.` / `Dockerfile` | Build context, and the Dockerfile inside it |
| `prepare-command` | string | `''` | Run in the build job before the image build (e.g. `./build.sh`) |
| `node-version` | string | `''` | Set up Node for the test job |
| `push` | boolean | `false` | Push; honoured only on a push to `main` |
| `registry-login` | string | `password` | `password` (`REGISTRY_USERNAME`/`REGISTRY_PASSWORD`) or `azure` (`AZURE_CREDENTIALS`, then `az acr login`) |
| `timeout-minutes` | number | `20` | Timeout of each job |

Outputs: `image`, `tag` (`sha-<commit>`), `digest` (`sha256:<64 hex>`), `ref` (`image:tag@digest`, the line a
promotion PR writes). The promotion-PR job is designed but not built (it needs a new credential that can write to
aloma-io/flux): claude-code `knowledge/proposals/devops/PROPOSAL-IMAGE-CI-TEMPLATE-20261104.md`.

Tests: `.github/workflows/test-image-ci.yml` (actionlint, `tests/test_image_ci.py`, `tests/image-ci-local.sh` running
the workflow's own steps through `tests/image-ci-run.py` against a throwaway local registry, `tests/image-ci-mutants.sh`,
and a real call on the green fixture with push off).
