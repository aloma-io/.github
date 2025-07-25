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
