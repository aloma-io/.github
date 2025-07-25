# Modular Docker Actions

This directory contains modular GitHub Actions for building and pushing Docker images to multiple registries with better retry capabilities.

## Available Actions

### 1. `build/` - Docker Build Action
**Purpose**: Build Docker images with automatic tag generation

**Inputs**:
- `image_name` (required): Name of the Docker image (without registry prefix)
- `tags` (required): Comma-separated list of tags to apply to the image
- `context` (optional): Build context path (default: '.')
- `dockerfile` (optional): Path to Dockerfile (default: 'Containerfile')
- `platforms` (optional): Target platforms for build (default: 'linux/amd64,linux/arm64')

**Outputs**:
- `primary-tag`: Primary tag derived from input
- `all-tags`: All tags including derived ones (SHA, branch-based)
- `image-digest`: Image digest from build

**Example**:
```yaml
- name: Build Docker image
  id: build
  uses: ./actions/build
  with:
    image_name: my-app
    tags: v1.2.3,latest
    context: .
    dockerfile: Containerfile
```

### 2. `push-azure/` - Azure Container Registry Push Action
**Purpose**: Tag and push Docker images to Azure Container Registry

**Inputs**:
- `image_name` (required): Name of the Docker image (without registry prefix)
- `source_tag` (required): Source tag of the built image
- `all_tags` (required): Newline-separated list of all tags to push
- `registry` (optional): Azure Container Registry URL (default: 'aloma.azurecr.io')

**Environment Variables**:
- `AZURE_USER`: Azure Container Registry username
- `AZURE_PASS`: Azure Container Registry password

**Outputs**:
- `pushed_images`: List of pushed image URLs

**Example**:
```yaml
- name: Push to Azure Container Registry
  uses: ./actions/push-azure
  with:
    image_name: my-app
    source_tag: ${{ needs.build.outputs.primary-tag }}
    all_tags: ${{ needs.build.outputs.all-tags }}
  env:
    AZURE_USER: ${{ secrets.AZURE_USER }}
    AZURE_PASS: ${{ secrets.AZURE_PASS }}
```

### 3. `push-google/` - Google Artifact Registry Push Action
**Purpose**: Tag and push Docker images to Google Artifact Registry

**Inputs**:
- `image_name` (required): Name of the Docker image (without registry prefix)
- `source_tag` (required): Source tag of the built image
- `all_tags` (required): Newline-separated list of all tags to push
- `project_id` (optional): Google Cloud Project ID (default: 'aloma-459317')
- `registry_location` (optional): Google Artifact Registry location (default: 'us-central1')
- `repository_name` (optional): Google Artifact Registry repository name (default: 'aloma-docker')

**Environment Variables**:
- `GOOGLE_CLOUD_KEY`: Base64-encoded service account JSON key with Artifact Registry Writer permissions

**Outputs**:
- `pushed_images`: List of pushed image URLs

**Example**:
```yaml
- name: Push to Google Artifact Registry
  uses: ./actions/push-google
  with:
    image_name: my-app
    source_tag: ${{ needs.build.outputs.primary-tag }}
    all_tags: ${{ needs.build.outputs.all-tags }}
  env:
    GOOGLE_CLOUD_KEY: ${{ secrets.GOOGLE_CLOUD_KEY }}
```

## Usage Patterns

### Pattern 1: Sequential Workflow (Simple)
Build → Push to Azure → Push to Google

```yaml
jobs:
  docker-pipeline:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build
        id: build
        uses: ./actions/build
        with:
          image_name: my-app
          tags: latest
      
      - name: Push to Azure
        uses: ./actions/push-azure
        with:
          image_name: my-app
          source_tag: ${{ steps.build.outputs.primary-tag }}
          all_tags: ${{ steps.build.outputs.all-tags }}
        env:
          AZURE_USER: ${{ secrets.AZURE_USER }}
          AZURE_PASS: ${{ secrets.AZURE_PASS }}
      
      - name: Push to Google
        uses: ./actions/push-google
        with:
          image_name: my-app
          source_tag: ${{ steps.build.outputs.primary-tag }}
          all_tags: ${{ steps.build.outputs.all-tags }}
        env:
          GOOGLE_CLOUD_KEY: ${{ secrets.GOOGLE_CLOUD_KEY }}
```

### Pattern 2: Parallel Workflow (Faster + Better Retry)
Build → (Push to Azure || Push to Google)

```yaml
jobs:
  docker-build:
    runs-on: ubuntu-latest
    outputs:
      primary-tag: ${{ steps.build.outputs.primary-tag }}
      all-tags: ${{ steps.build.outputs.all-tags }}
    steps:
      - uses: actions/checkout@v4
      - name: Build
        id: build
        uses: ./actions/build
        with:
          image_name: my-app
          tags: latest

  push-azure:
    needs: docker-build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./actions/push-azure
        with:
          image_name: my-app
          source_tag: ${{ needs.docker-build.outputs.primary-tag }}
          all_tags: ${{ needs.docker-build.outputs.all-tags }}
        env:
          AZURE_USER: ${{ secrets.AZURE_USER }}
          AZURE_PASS: ${{ secrets.AZURE_PASS }}

  push-google:
    needs: docker-build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./actions/push-google
        with:
          image_name: my-app
          source_tag: ${{ needs.docker-build.outputs.primary-tag }}
          all_tags: ${{ needs.docker-build.outputs.all-tags }}
        env:
          GOOGLE_CLOUD_KEY: ${{ secrets.GOOGLE_CLOUD_KEY }}
```

## Benefits of Modular Approach

1. **Independent Retry**: If Azure push fails, you can retry just that step without rebuilding or re-pushing to Google
2. **Parallel Execution**: Push to both registries simultaneously to reduce total workflow time
3. **Selective Deployment**: Deploy to only one registry if needed (e.g., Azure for staging, both for production)
4. **Better Debugging**: Each step has focused logs and outputs
5. **Resource Optimization**: Build once, push to multiple registries

## Migration from Unified Action

The root `action.yml` file now acts as a wrapper that calls these modular actions, so existing workflows continue to work without changes. However, for new workflows, consider using the modular approach for better reliability.

## External Repository Usage

Other repositories can reference these actions directly:

```yaml
# Use specific action
- uses: aloma-io/site/actions/build@main
  with:
    image_name: my-external-app
    tags: v1.0.0

# Or use the unified wrapper
- uses: aloma-io/site@main
  with:
    image_name: my-external-app
    tags: v1.0.0
  env:
    AZURE_USER: ${{ secrets.AZURE_USER }}
    AZURE_PASS: ${{ secrets.AZURE_PASS }}
    GOOGLE_CLOUD_KEY: ${{ secrets.GOOGLE_CLOUD_KEY }}
```
