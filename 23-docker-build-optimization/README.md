# 23 — Docker Build Optimization Deep Dive

Optimizing Docker builds accelerates CI/CD pipelines, minimizes container image transfer times across registries, and significantly reduces the security attack surface in production environments.

---

## The Build Optimization Pipeline

The core pattern of build optimization is isolating build-time tools, compiler toolchains, and dev dependencies in early build stages, producing a lean, production-only minimal runtime artifact:

```
┌────────────────────────────────────────────────────────┐
│               Development Dependencies                 │
│         (TypeScript, Webpack, GCC, PyTest, etc.)       │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│                      Build Stage                       │
│               (Compile, Lint, Transpile)               │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│                  Compiled Application                  │
│               (dist/, bin/, static assets)             │
└───────────────────────────┬────────────────────────────┘
                            │ copied into
                            ▼
┌────────────────────────────────────────────────────────┐
│               Minimal Production Image                 │
│         (Alpine / Distroless / Scratch runtime)        │
└────────────────────────────────────────────────────────┘
```

---

## Table of Contents

1. [Key Optimization Pillars](#1-key-optimization-pillars)
2. [Layer Caching & Instruction Ordering](#2-layer-caching--instruction-ordering)
3. [Dependency Caching Strategies](#3-dependency-caching-strategies)
4. [Build Context Optimization with `.dockerignore`](#4-build-context-optimization-with-dockerignore)
5. [Multi-Stage Builds (Build vs. Runtime Separation)](#5-multi-stage-builds-build-vs-runtime-separation)
6. [Minimal Base Images (Alpine, Distroless, Scratch)](#6-minimal-base-images-alpine-distroless-scratch)
7. [Docker BuildKit & Advanced Build Cache](#7-docker-buildkit--advanced-build-cache)
   - [Enabling BuildKit](#enabling-buildkit)
   - [Cache Mounts (`--mount=type=cache`)](#cache-mounts---mounttypecache)
   - [Secret Mounts (`--mount=type=secret`)](#secret-mounts---mounttypesecret)
   - [Remote Build Cache (`--cache-from` / `--cache-to`)](#remote-build-cache---cache-from---cache-to)
8. [Real-World Language Optimization Examples](#8-real-world-language-optimization-examples)
   - [Node.js / TypeScript Example](#nodejs--typescript-example)
   - [Go Binary Example (Distroless / Scratch)](#go-binary-example-distroless--scratch)
   - [Python Example](#python-example)
9. [Docker Build Optimization Checklist](#9-docker-build-optimization-checklist)

---

## 1. Key Optimization Pillars

| Optimization Technique | Benefit | Impact |
|---|---|---|
| **Layer Ordering** | Reuses cached layers between builds when source code changes | Fast local and CI build times |
| **`.dockerignore`** | Prevents transferring bloated/secret files to Docker daemon | Faster context upload, avoids cache busting |
| **Dependency Caching** | Separates package install step from source code copy | Skips slow `npm install` / `pip install` on logic edits |
| **Multi-Stage Builds** | Excludes compilers, linters, and header files from final image | Dramatically smaller image size (e.g. 1.2GB &rarr; 60MB) |
| **Minimal Base Images** | Uses Alpine or Distroless instead of full Linux distributions | Reduced CVE count, faster pull times |
| **BuildKit Cache Mounts** | Preserves package manager caches across builds without creating layers | 10x faster build cycles |

---

## 2. Layer Caching & Instruction Ordering

Docker caches the result of each instruction (`RUN`, `COPY`, `ADD`). During a build:
1. Docker checks if the instruction and the files being copied have changed.
2. If unchanged, Docker uses the cached layer.
3. **If any layer is invalidated, ALL subsequent layers must be rebuilt from scratch.**

### The Golden Rule of Layer Ordering:
Order instructions from **least-frequently changing** to **most-frequently changing**:

```
Least Frequently Changed:
1. Base image (FROM)
2. System packages (RUN apt-get install / apk add)
3. Package manifests (COPY package.json, requirements.txt, go.mod)
4. Dependency installation (RUN npm ci, pip install, go download)
5. Application source code (COPY src/ .)
6. Build command (RUN npm run build)
Most Frequently Changed:
```

---

## 3. Dependency Caching Strategies

### ❌ Anti-Pattern (Invalidates Cache on Every Single Code Edit):
```dockerfile
WORKDIR /app
# Copies entire project (including source code)
COPY . .
# Every single change in src/ forces npm install to run from scratch!
RUN npm ci
```

### ✅ Best Practice (Cached Dependencies):
```dockerfile
WORKDIR /app
# 1. Copy only dependency manifest files
COPY package*.json ./
# 2. Install dependencies (cached until package.json changes)
RUN npm ci
# 3. Copy source code (invalidates only subsequent steps)
COPY . .
RUN npm run build
```

---

## 4. Build Context Optimization with `.dockerignore`

When `docker build` runs, the CLI compresses the entire directory and sends it to the Docker daemon. A missing or inadequate `.dockerignore` file:
- Uploads massive files (`node_modules`, `.git`, `.venv`) slowing down build initialization.
- Accidentally bakes sensitive secrets (`.env`, private keys) into image layers.
- Inadvertently invalidates layer caches due to timestamp changes on temporary files.

### Production `.dockerignore` Template:
```
# Version Control & CI
.git
.gitignore
.github

# Dependencies & Package Manager caches
node_modules
.npm
.yarn
.venv
__pycache__
*.pyc

# Build outputs & artifacts
dist
build
coverage
*.log

# Secrets & Environment variables
.env
.env.*
*.pem
*.key

# IDE and OS metadata
.vscode
.idea
.DS_Store
Thumbs.db
```

---

## 5. Multi-Stage Builds (Build vs. Runtime Separation)

A multi-stage build uses multiple `FROM` instructions in a single `Dockerfile`. Each stage can use a different base image, and you selectively copy only the generated artifacts from earlier stages into the final runtime image.

```
Stage 1: builder (node:20)                  Stage 2: production (node:20-alpine)
┌──────────────────────────────────────┐     ┌──────────────────────────────────────┐
│ • TypeScript Compiler                │     │ • Node.js Runtime                    │
│ • DevDependencies (Jest, Webpack)    │     │ • Production node_modules ONLY       │
│ • Full Source Code (.ts files)       │ ──► │ • Compiled JS (dist/ only)           │
│ • Size: ~1.2 GB                      │     │ • Size: ~80 MB                       │
└──────────────────────────────────────┘     └──────────────────────────────────────┘
```

---

## 6. Minimal Base Images (Alpine, Distroless, Scratch)

| Image Type | Example | Size | Pros | Cons |
|---|---|---|---|---|
| **Standard / Debian** | `node:20`, `python:3.11` | ~1 GB | Includes all debugging tools, libraries | Heavy, large attack surface, slower pull times |
| **Alpine Linux** | `node:20-alpine`, `python:3.11-alpine` | ~50 MB | Very small, lightweight | Uses `musl` libc (can cause issues with C-extensions) |
| **Distroless** | `gcr.io/distroless/nodejs20-debian12` | ~40 MB | No shell, no package manager, highly secure | Debugging requires ephemeral debug containers |
| **Scratch** | `FROM scratch` | 0 MB | True empty layer, zero CVEs | Only for self-contained, statically compiled binaries (Go, Rust) |

---

## 7. Docker BuildKit & Advanced Build Cache

**BuildKit** is Docker's next-generation build engine offering parallel stage execution, cache mounts, secret mounts, and remote cache backends.

### Enabling BuildKit:
BuildKit is enabled by default in modern Docker, but can be forced via environment variable:
```bash
export DOCKER_BUILDKIT=1
docker build -t myapp .
```

---

### Cache Mounts (`--mount=type=cache`)
Cache mounts persist package manager caches (e.g. `npm`, `pip`, `apt`, `go-build`) **outside the image layers** across builds. Package downloads are cached on the host without increasing the final image size!

```dockerfile
# syntax=docker/dockerfile:1.4
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./

# Cache the npm cache directory across builds
RUN --mount=type=cache,target=/root/.npm \
    npm ci --prefer-offline
```

#### Python / pip cache mount:
```dockerfile
# syntax=docker/dockerfile:1.4
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt
```

#### Go compiler cache mount:
```dockerfile
# syntax=docker/dockerfile:1.4
FROM golang:1.22-alpine
WORKDIR /app
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build -o /app/server .
```

---

### Secret Mounts (`--mount=type=secret`)
Mounts private tokens (e.g. `.npmrc`, GitHub tokens) during the build without baking them into layer metadata or history:

```dockerfile
# syntax=docker/dockerfile:1.4
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm ci
```
Build command:
```bash
docker build --secret id=npmrc,src=.npmrc -t myapp .
```

---

### Remote Build Cache (`--cache-from` / `--cache-to`)
In CI/CD environments (GitHub Actions, GitLab CI), every runner starts with an empty local cache. BuildKit can push and pull build caches directly to/from a container registry:

```bash
# Build and push inline cache to registry
docker buildx build \
  --cache-to type=registry,ref=myregistry.com/app:buildcache,mode=max \
  --cache-from type=registry,ref=myregistry.com/app:buildcache \
  -t myregistry.com/app:1.0 \
  --push .
```

---

## 8. Real-World Language Optimization Examples

### Node.js / TypeScript Example
```dockerfile
# syntax=docker/dockerfile:1.4

# ==========================================
# Stage 1: Dependencies & Compilation Stage
# ==========================================
FROM node:20-alpine AS builder

WORKDIR /app

# Cache package manifests
COPY package*.json tsconfig.json ./

# Use BuildKit cache mount for npm
RUN --mount=type=cache,target=/root/.npm \
    npm ci

# Copy source and compile
COPY src/ ./src
RUN npm run build

# Install production-only dependencies
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev

# ==========================================
# Stage 2: Minimal Production Runtime
# ==========================================
FROM node:20-alpine

WORKDIR /app
ENV NODE_ENV=production

# Security: Non-root user
USER node

# Copy only production dependencies and compiled artifacts
COPY --chown=node:node --from=builder /app/node_modules ./node_modules
COPY --chown=node:node --from=builder /app/dist ./dist
COPY --chown=node:node package.json ./

EXPOSE 3000
CMD ["node", "dist/server.js"]
```

---

### Go Binary Example (Distroless / Scratch)
```dockerfile
# syntax=docker/dockerfile:1.4

# ==========================================
# Stage 1: Compilation Stage
# ==========================================
FROM golang:1.22-alpine AS builder

WORKDIR /src

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .

# Compile static binary with zero external C dependencies
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /bin/server .

# ==========================================
# Stage 2: Distroless Static Minimal Image
# ==========================================
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /
COPY --from=builder /bin/server /bin/server

# Uses non-root user (UID 65532)
USER nonroot:nonroot

EXPOSE 8080
ENTRYPOINT ["/bin/server"]
```
*Result: Image size is under **15 MB** with zero system packages or CVEs!*

---

### Python Example
```dockerfile
# syntax=docker/dockerfile:1.4

# ==========================================
# Stage 1: Build Wheels Stage
# ==========================================
FROM python:3.11-slim AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends gcc build-essential

COPY requirements.txt .

# Build wheels using pip cache mount
RUN --mount=type=cache,target=/root/.cache/pip \
    pip wheel --no-cache-dir --wheel-dir /app/wheels -r requirements.txt

# ==========================================
# Stage 2: Clean Runtime Stage
# ==========================================
FROM python:3.11-slim

WORKDIR /app

# Create unprivileged user
RUN useradd -u 10001 -m appuser

# Copy and install pre-built wheels
COPY --from=builder /app/wheels /wheels
RUN pip install --no-cache /wheels/* && rm -rf /wheels

# Copy application source code
COPY --chown=appuser:appuser . .

USER appuser
EXPOSE 8000
CMD ["python", "main.py"]
```

---

## 9. Docker Build Optimization Checklist

- [ ] **`.dockerignore` populated**: Excludes `.git`, `node_modules`, test files, and secrets.
- [ ] **Dependency manifests copied first**: `package.json` / `requirements.txt` copied before source code.
- [ ] **Multi-stage build utilized**: Compilers, SDKs, and build dependencies excluded from final stage.
- [ ] **Minimal base image selected**: Alpine, Distroless, or Scratch used for production runtime.
- [ ] **BuildKit cache mounts enabled**: `--mount=type=cache` configured for package manager directories.
- [ ] **Chained `RUN` commands**: Cleaned package manager lists (`rm -rf /var/lib/apt/lists/*`) in the same layer.
- [ ] **Non-root user in runtime**: `USER` directive applied in final image stage.
- [ ] **Remote caching configured in CI**: `--cache-from` and `--cache-to` active for fast pipeline execution.

---

## References

- [Docker BuildKit Documentation](https://docs.docker.com/build/buildkit/)
- [Best Practices for Writing Dockerfiles](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [Multi-Stage Builds Documentation](https://docs.docker.com/build/building/multi-stage/)
- [GoogleContainerTools Distroless Images](https://github.com/GoogleContainerTools/distroless)
