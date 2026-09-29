# 24 — Docker CI/CD: Automated Pipelines, Security & Deployment

Continuous Integration and Continuous Deployment (CI/CD) with Docker automates the complete journey of code from a developer's local commit to production deployment.

---

## The End-to-End Docker CI/CD Pipeline

```
┌────────────────────────────────────────────────────────┐
│                       Developer                        │
│                   (Write Code & Test)                  │
└───────────────────────────┬────────────────────────────┘
                            │ git push origin main
                            ▼
┌────────────────────────────────────────────────────────┐
│                    Git / GitHub                        │
│                 (Pull Request / Push)                  │
└───────────────────────────┬────────────────────────────┘
                            │ triggers workflow
                            ▼
┌────────────────────────────────────────────────────────┐
│                   GitHub Actions                       │
│  ┌──────────────────────────────────────────────────┐  │
│  │ 1. Run Unit & Integration Tests                  │  │
│  ├──────────────────────────────────────────────────┤  │
│  │ 2. Setup Docker Buildx & Remote Caching          │  │
│  ├──────────────────────────────────────────────────┤  │
│  │ 3. Docker Build Multi-Stage Image                │  │
│  ├──────────────────────────────────────────────────┤  │
│  │ 4. Security & Vulnerability Scan (Trivy / Snyk)  │  │
│  ├──────────────────────────────────────────────────┤  │
│  │ 5. Tag Image (Git SHA, Semantic Version)         │  │
│  ├──────────────────────────────────────────────────┤  │
│  │ 6. Docker Push to Registry (ECR / GHCR / Hub)    │  │
│  └────────────────────────┬─────────────────────────┘  │
└───────────────────────────┼────────────────────────────┘
                            │ pulls verified image
                            ▼
┌────────────────────────────────────────────────────────┐
│                   Docker Registry                      │
│            (Docker Hub, GitHub Packages, ECR)          │
└───────────────────────────┬────────────────────────────┘
                            │ deploys
                            ▼
┌────────────────────────────────────────────────────────┐
│                 Production Deployment                  │
│       (Kubernetes, AWS ECS, Docker Swarm, Compose)     │
└────────────────────────────────────────────────────────┘
```

---

## Table of Contents

1. [Key Concepts in Container CI/CD](#1-key-concepts-in-container-cicd)
2. [Automated Testing in the Pipeline](#2-automated-testing-in-the-pipeline)
3. [Image Tagging & Versioning Strategy](#3-image-tagging--versioning-strategy)
4. [Security Scanning in CI (Trivy / Snyk)](#4-security-scanning-in-ci-trivy--snyk)
5. [Complete Production GitHub Actions Workflow](#5-complete-production-github-actions-workflow)
6. [CI/CD Remote Layer & Cache Optimization](#6-cicd-remote-layer--cache-optimization)
7. [Automated Deployment Strategies](#7-automated-deployment-strategies)
   - [Rolling Updates with Docker Compose](#rolling-updates-with-docker-compose)
   - [Kubernetes Continuous Delivery](#kubernetes-continuous-delivery)
   - [AWS ECS / Cloud Run Deployment](#aws-ecs--cloud-run-deployment)
8. [Production CI/CD Security Best Practices](#8-production-cicd-security-best-practices)

---

## 1. Key Concepts in Container CI/CD

| Stage | Responsibility | Tooling |
|---|---|---|
| **Continuous Integration (CI)** | Code checkout, dependency install, unit tests, Docker build, and vulnerability analysis. | GitHub Actions, GitLab CI, Jenkins |
| **Artifact Publishing** | Pushing immutable, version-tagged container images to a secure registry. | GitHub Container Registry (GHCR), AWS ECR, Docker Hub |
| **Continuous Delivery / Deployment (CD)** | Promoting verified images into staging and production clusters automatically. | ArgoCD, Flux, GitHub Actions, AWS CodeDeploy |
| **Pipeline Immutability** | Build the container image **once** in CI, and promote that **exact same binary image** across Test, Staging, and Production environments. | OCI Image Manifests, SHA digests |

---

## 2. Automated Testing in the Pipeline

Tests should run **before** pushing the image to a registry:

1. **Pre-build Unit Tests**: Run tests on the host runner to fail fast before invoking heavy Docker builds.
2. **Containerized Integration Tests**: Run tests inside an ephemeral Docker container or using Docker Compose to spin up real dependency services (e.g. PostgreSQL, Redis):

```yaml
# Example: Run tests against a real Postgres container in CI
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_PASSWORD: testpassword
          POSTGRES_DB: testdb
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: npm ci
      - run: npm test
        env:
          DATABASE_URL: postgres://postgres:testpassword@localhost:5432/testdb
```

---

## 3. Image Tagging & Versioning Strategy

A robust tagging strategy enables safe rollbacks, traceability, and environment separation:

```
┌────────────────────────────────────────────────────────┐
│                   Tagging Hierarchy                    │
├────────────────────┬───────────────────────────────────┤
│ Production Release │ `myapp:v1.4.2` (Semantic Version) │
│ Git Commit SHA     │ `myapp:sha-7f3b89a` (Traceable)   │
│ Pull Request / Dev │ `myapp:pr-142` (Ephemeral test)   │
│ Branch Build       │ `myapp:main` (Latest branch head) │
└────────────────────┴───────────────────────────────────┘
```

### GitHub Actions Metadata Action (`docker/metadata-action`):
Automatically extracts tags based on Git events:
- On Git Tag `v1.2.3` &rarr; Generates `myapp:1.2.3`, `myapp:1.2`, `myapp:1`, `myapp:latest`
- On `push` to `main` &rarr; Generates `myapp:main`, `myapp:sha-<commit_sha>`
- On Pull Request `#42` &rarr; Generates `myapp:pr-42`

---

## 4. Security Scanning in CI (Trivy / Snyk)

Integrate vulnerability scanning directly into the pipeline to prevent shipping critical CVEs:

```yaml
- name: Run Trivy Vulnerability Scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
    format: 'table'
    exit-code: '1' # Fails the build if vulnerabilities exceed threshold
    ignore-unfixed: true
    vuln-type: 'os,library'
    severity: 'CRITICAL,HIGH'
```

---

## 5. Complete Production GitHub Actions Workflow

Below is a production-grade workflow (`.github/workflows/docker-ci-cd.yml`):

```yaml
name: Docker CI/CD Pipeline

on:
  push:
    branches: [ "main" ]
    tags: [ "v*.*.*" ]
  pull_request:
    branches: [ "main" ]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  # ----------------------------------------------------
  # 1. Test Stage
  # ----------------------------------------------------
  test:
    name: Run Unit & Integration Tests
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Source Code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'

      - name: Install Dependencies
        run: npm ci

      - name: Run Tests
        run: npm test

  # ----------------------------------------------------
  # 2. Build, Scan & Push Stage
  # ----------------------------------------------------
  build-and-push:
    name: Build, Scan & Push Docker Image
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      security-events: write

    steps:
      - name: Checkout Source Code
        uses: actions/checkout@v4

      - name: Set up QEMU (Multi-platform support)
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GitHub Container Registry
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract Docker Metadata (Tags & Labels)
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha,prefix=sha-,format=short
            type=ref,event=branch
            type=ref,event=pr

      # Build image locally to allow security scanning before push
      - name: Build Docker Image for Scanning
        uses: docker/build-push-action@v5
        with:
          context: .
          load: true
          tags: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      # Security Vulnerability Scan
      - name: Scan Image with Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'

      # Upload scan results to GitHub Security Tab
      - name: Upload Trivy Scan Results
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: 'trivy-results.sarif'

      # Push verified image to Container Registry
      - name: Push Docker Image to Registry
        if: github.event_name != 'pull_request'
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  # ----------------------------------------------------
  # 3. Continuous Deployment Stage
  # ----------------------------------------------------
  deploy:
    name: Deploy to Production
    needs: build-and-push
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    steps:
      - name: Trigger Remote Deployment via SSH
        uses: appleboy/ssh-action@master
        with:
          host: ${{ secrets.PROD_SERVER_IP }}
          username: ${{ secrets.PROD_SERVER_USER }}
          key: ${{ secrets.PROD_SSH_PRIVATE_KEY }}
          script: |
            echo "Pulling latest production image..."
            docker pull ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-${{ github.sha }}
            
            echo "Performing rolling update..."
            export IMAGE_TAG=sha-${{ github.sha }}
            docker compose -f /opt/app/compose.yaml up -d --no-deps api
            
            echo "Pruning dangling images..."
            docker image prune -f
```

---

## 6. CI/CD Remote Layer & Cache Optimization

In GitHub Actions, default runners are ephemeral virtual machines that start with empty local Docker caches. Without remote caching, every CI run rebuilds all layers from scratch.

### GitHub Actions Cache (`type=gha`):
Docker Buildx integrates natively with GitHub Actions cache storage:

```yaml
- name: Build and push with GHA cache
  uses: docker/build-push-action@v5
  with:
    context: .
    push: true
    tags: ${{ steps.meta.outputs.tags }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```
*`mode=max` caches intermediate build layers (including multi-stage builder stages), drastically accelerating builds.*

---

## 7. Automated Deployment Strategies

### Rolling Updates with Docker Compose
```bash
# Set new image tag
export IMAGE_TAG=v1.4.2

# Pull new image
docker compose pull api

# Recreate container with zero downtime (service stays up until new one is healthy)
docker compose up -d --no-deps --remove-orphans api
```

### Kubernetes Continuous Delivery (GitOps / ArgoCD)
CI builds and pushes the image, then updates the GitOps repository manifest:
```bash
# Update image tag in deployment.yaml
kubectl set image deployment/api-server api=ghcr.io/myorg/myapp:v1.4.2
```

---

## 8. Production CI/CD Security Best Practices

1. **Use Minimal Pipeline Permissions**: Restrict GitHub Actions token permissions (`contents: read`, `packages: write`).
2. **Never Hardcode Secrets**: Store passwords, tokens, and SSH keys in GitHub Repository Secrets.
3. **Scan Before Pushing**: Run Trivy or Docker Scout **before** `docker push` so contaminated images never enter registries.
4. **Enforce Semantic Releases & Commit SHAs**: Deploy explicit tags (`sha-abc1234` or `v1.2.3`), never untraceable `latest`.
5. **Pin Action Versions**: Pin third-party GitHub Actions to exact commit SHAs (e.g. `docker/build-push-action@v5`) to prevent supply chain tampering.

---

## References

- [GitHub Actions Docker Build and Push Action](https://github.com/docker/build-push-action)
- [Docker Metadata Action](https://github.com/docker/metadata-action)
- [Aquasecurity Trivy GitHub Action](https://github.com/aquasecurity/trivy-action)
- [Docker Buildx Cache Backends](https://docs.docker.com/build/cache/backends/)
