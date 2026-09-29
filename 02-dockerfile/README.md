# 02 — Dockerfile Deep Dive

A **Dockerfile** is a declarative, plain-text configuration script that Docker interprets to build container images automatically. It contains an ordered sequence of instructions where each instruction adds a read-only layer to the image.

---

## Table of Contents

1. [Dockerfile Instructions Reference](#1-dockerfile-instructions-reference)
   - [FROM](#from)
   - [WORKDIR](#workdir)
   - [COPY](#copy)
   - [ADD](#add)
   - [RUN](#run)
   - [ENV](#env)
   - [ARG](#arg)
   - [EXPOSE](#expose)
   - [CMD](#cmd)
   - [ENTRYPOINT](#entrypoint)
   - [USER](#user)
   - [VOLUME](#volume)
   - [LABEL](#label)
   - [HEALTHCHECK](#healthcheck)
2. [Build Context & `.dockerignore`](#2-build-context--dockerignore)
3. [Key Concept Comparisons](#3-key-concept-comparisons)
   - [CMD vs ENTRYPOINT](#cmd-vs-entrypoint)
   - [COPY vs ADD](#copy-vs-add)
   - [RUN vs CMD](#run-vs-cmd)
   - [ARG vs ENV](#arg-vs-env)
4. [Layer Caching & Optimization](#4-layer-caching--optimization)
5. [Multi-Stage Dockerfiles](#5-multi-stage-dockerfiles)
6. [Minimal & Base Images](#6-minimal--base-images)
7. [Non-Root Containers & Security](#7-non-root-containers--security)
8. [Complete Production Dockerfile Example](#8-complete-production-dockerfile-example)
9. [Build & Execution Cheat Sheet](#9-build--execution-cheat-sheet)

---

## 1. Dockerfile Instructions Reference

### `FROM`
- **Purpose**: Defines the base image to build upon. Must be the first instruction in a Dockerfile (except for `ARG` instructions used before `FROM`).
- **Syntax**:
  ```dockerfile
  FROM <image>[:<tag>] [AS <stage-name>]
  ```
- **Example**:
  ```dockerfile
  FROM node:20-alpine AS builder
  ```

---

### `WORKDIR`
- **Purpose**: Sets the working directory for subsequent instructions (`RUN`, `CMD`, `ENTRYPOINT`, `COPY`, `ADD`). If the directory does not exist, Docker creates it automatically.
- **Best Practice**: Always use absolute paths. Avoid using `RUN cd /app` because `cd` does not persist across layers.
- **Example**:
  ```dockerfile
  WORKDIR /app
  ```

---

### `COPY`
- **Purpose**: Copies files/directories from the host build context into the container filesystem.
- **Syntax**:
  ```dockerfile
  COPY [--chown=<user>:<group>] <src>... <dest>
  ```
- **Example**:
  ```dockerfile
  COPY --chown=node:node package*.json ./
  COPY --from=builder /app/dist ./dist
  ```

---

### `ADD`
- **Purpose**: Similar to `COPY`, but with two additional capabilities:
  1. Automatically extracts local compressed archives (`.tar`, `.tar.gz`, `.tgz`, `.tar.bz2`, etc.) into the destination directory.
  2. Downloads files directly from a remote URL.
- **Best Practice**: Prefer `COPY` for regular files. Use `ADD` primarily for auto-extracting local tar archives. For downloading remote files, prefer `RUN curl` or `RUN wget` followed by cleanup in the same layer.
- **Example**:
  ```dockerfile
  # Auto-extracts archive into /opt/app/
  ADD application-bundle.tar.gz /opt/app/
  ```

---

### `RUN`
- **Purpose**: Executes shell commands during the **image build phase** and commits the result as a new image layer (e.g., installing packages, compiling code).
- **Forms**:
  - Shell form: `RUN apt-get update && apt-get install -y curl`
  - Exec form: `RUN ["npm", "ci"]`
- **Best Practice**: Chain related commands with `&&` and clean up caches in the same `RUN` command to reduce layer size.
- **Example**:
  ```dockerfile
  RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
   && rm -rf /var/lib/apt/lists/*
  ```

---

### `ENV`
- **Purpose**: Sets persistent environment variables available during **both build time and container runtime**.
- **Syntax**:
  ```dockerfile
  ENV <key>=<value> ...
  ```
- **Example**:
  ```dockerfile
  ENV NODE_ENV=production \
      PORT=3000
  ```

---

### `ARG`
- **Purpose**: Defines variables that users can pass at build-time using `docker build --build-arg <varname>=<value>`.
- **Scope**: Exists **only during the build phase**; it is NOT baked into the running container environment (unless explicitly assigned to an `ENV`).
- **Example**:
  ```dockerfile
  ARG APP_VERSION=1.0.0
  ARG BUILD_ENV=production
  RUN echo "Building version: ${APP_VERSION} for ${BUILD_ENV}"
  ```

---

### `EXPOSE`
- **Purpose**: Documents the network port that the application inside the container listens on. Acts as metadata/documentation; it does **not** automatically publish or bind the port to the host machine.
- **Syntax**:
  ```dockerfile
  EXPOSE <port>[/<protocol>]
  ```
- **Example**:
  ```dockerfile
  EXPOSE 8080/tcp
  ```

---

### `CMD`
- **Purpose**: Sets default arguments or commands to execute when a **container starts at runtime**.
- **Behavior**: Easily overridden by passing arguments after `docker run <image> <command>`.
- **Forms**:
  - Exec form (preferred): `CMD ["node", "dist/server.js"]`
  - Shell form: `CMD node dist/server.js` (runs inside `/bin/sh -c`)
- **Example**:
  ```dockerfile
  CMD ["npm", "start"]
  ```

---

### `ENTRYPOINT`
- **Purpose**: Configures the fixed executable that will always run when the container starts.
- **Behavior**: Not easily overridden (requires `--entrypoint` flag). Any `CMD` parameters or arguments passed to `docker run` are appended as arguments to the `ENTRYPOINT`.
- **Example**:
  ```dockerfile
  ENTRYPOINT ["python", "app.py"]
  CMD ["--port", "8000"]
  # Running `docker run myapp` -> executes: python app.py --port 8000
  # Running `docker run myapp --port 9000` -> executes: python app.py --port 9000
  ```

---

### `USER`
- **Purpose**: Sets the UID (and optionally GID) or username/group that runs all subsequent instructions (`RUN`, `CMD`, `ENTRYPOINT`) and the container runtime process.
- **Best Practice**: Always switch away from root (`USER nonroot` or `USER node`) for production workloads.
- **Example**:
  ```dockerfile
  RUN addgroup -S appgroup && adduser -S appuser -G appgroup
  USER appuser
  ```

---

### `VOLUME`
- **Purpose**: Declares a mount point with the specified path and marks it as holding externally mounted persistent storage from the host or other containers.
- **Example**:
  ```dockerfile
  VOLUME ["/var/log/app", "/data"]
  ```

---

### `LABEL`
- **Purpose**: Adds key-value metadata to the image (e.g., maintainer, version, description, OCI image specification labels).
- **Example**:
  ```dockerfile
  LABEL org.opencontainers.image.title="My Production Service" \
        org.opencontainers.image.version="1.4.0" \
        org.opencontainers.image.authors="devops@example.com"
  ```

---

### `HEALTHCHECK`
- **Purpose**: Instructs Docker how to test whether the container application is alive and healthy, allowing orchestrators (Docker Swarm, Kubernetes, Compose) to restart or route traffic away from unhealthy containers.
- **Syntax**:
  ```dockerfile
  HEALTHCHECK [--interval=30s] [--timeout=5s] [--start-period=10s] [--retries=3] \
    CMD <command>
  ```
- **Example**:
  ```dockerfile
  HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:3000/health || exit 1
  ```

---

## 2. Build Context & `.dockerignore`

### What is the Build Context?
When you run `docker build -t my-image:1.0 .`, the `.` represents the **build context directory**. The Docker client packs all files in this directory and sends them to the Docker daemon over the API before building.

If the context contains large folders like `node_modules`, `.git`, or temporary files, build performance degrades and secrets may accidentally be copied into the image.

### `.dockerignore` Best Practices
A `.dockerignore` file prevents unnecessary, large, or sensitive files from entering the Docker build context:

```
# Git & Version Control
.git
.gitignore

# Package manager cache & dependencies
node_modules
npm-debug.log
yarn-error.log

# Build outputs & test coverage
dist
build
coverage
.nyc_output

# Environment & Secrets (NEVER bake into image)
.env
.env.*
*.pem
*.key
id_rsa

# IDE & OS files
.vscode
.idea
.DS_Store
Thumbs.db
```

---

## 3. Key Concept Comparisons

### CMD vs. ENTRYPOINT

| Feature | `CMD` | `ENTRYPOINT` |
|---|---|---|
| **Purpose** | Provides default command/arguments | Configures container to run as a fixed executable |
| **Override** | Simple: `docker run myimg <new-command>` | Hard: requires `docker run --entrypoint <bin> myimg` |
| **Combination** | Appended as default arguments to `ENTRYPOINT` | Receives `CMD` values as parameters |
| **Shell Form** | `CMD npm start` (invokes `/bin/sh -c`) | `ENTRYPOINT npm start` (ignores signals) |
| **Exec Form** | `CMD ["npm", "start"]` (receives POSIX signals) | `ENTRYPOINT ["npm", "start"]` (receives POSIX signals) |

#### Combined Example:
```dockerfile
ENTRYPOINT ["node", "cli.js"]
CMD ["--help"]
```
- `docker run my-cli` &rarr; runs `node cli.js --help`
- `docker run my-cli --version` &rarr; runs `node cli.js --version`

---

### COPY vs. ADD

| Feature | `COPY` | `ADD` |
|---|---|---|
| **Local File Copy** | Yes (`COPY src dest`) | Yes (`ADD src dest`) |
| **Auto Tar Extraction** | No (copies archive as a file) | Yes (automatically unpacks `.tar`, `.tar.gz`) |
| **Remote URL Download**| No | Yes (`ADD http://example.com/file.tar.gz /tmp/`) |
| **Ownership Flag** | Supports `--chown=user:group` | Supports `--chown=user:group` |
| **Rule of Thumb** | **Use `COPY` for 99% of use cases** | Use only when unpacking local archives |

---

### RUN vs. CMD

| Feature | `RUN` | `CMD` |
|---|---|---|
| **Phase** | **Build time** (image creation) | **Runtime** (container startup) |
| **Layer Created** | Yes, commits a new image layer | No, sets image metadata only |
| **Frequency** | Runs once per build step | Runs every time a container starts |
| **Typical Use** | `RUN apt-get install`, `RUN npm ci` | `CMD ["node", "server.js"]` |

---

### ARG vs. ENV

| Feature | `ARG` | `ENV` |
|---|---|---|
| **Build Time** | Available (`--build-arg`) | Available |
| **Runtime** | **Not available** (discards after build) | **Available** in container environment |
| **`docker inspect`** | Not visible in final container env | Visible in container metadata |
| **Use Case** | Tool versions, compiler flags, build targets | `NODE_ENV`, `PORT`, `LOG_LEVEL` |

---

## 4. Layer Caching & Optimization

Docker checks its cache for each instruction during `docker build`. If the instruction and all previous instructions are unchanged, Docker reuses the cached layer.

### Golden Rules for Layer Caching:
1. **Order from least-frequently changed to most-frequently changed**:
   - OS packages & dependencies change rarely &rarr; Place near the top.
   - Application source code changes on every commit &rarr; Place near the bottom.
2. **Copy dependency manifests before copying source code**:

```dockerfile
# ❌ BAD: Invalidates dependency cache on every single code change
WORKDIR /app
COPY . .
RUN npm ci

# ✅ GOOD: Cached unless package.json / package-lock.json changes
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
```

3. **Chain commands to minimize layer count and purge temporary files in the same `RUN` step**:
```dockerfile
# ✅ GOOD: Package lists cleaned in same layer before committing
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
 && rm -rf /var/lib/apt/lists/*
```

---

## 5. Multi-Stage Dockerfiles

Multi-stage builds allow you to use intermediate containers containing compilers, SDKs, and build tools, then copy **only the compiled artifacts** into a clean, minimal runtime image.

```dockerfile
# ==========================================
# Stage 1: Build & Compilation Environment
# ==========================================
FROM node:20-alpine AS builder

WORKDIR /app

# Install dependencies
COPY package*.json tsconfig.json ./
RUN npm ci

# Build TypeScript code to JavaScript
COPY src/ ./src
RUN npm run build

# Prune devDependencies to keep production modules clean
RUN npm prune --production

# ==========================================
# Stage 2: Minimal Production Runtime
# ==========================================
FROM node:20-alpine

WORKDIR /app

ENV NODE_ENV=production

# Copy only production node_modules and compiled output from builder
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY package.json ./

USER node

EXPOSE 3000
CMD ["node", "dist/index.js"]
```

---

## 6. Minimal & Base Images

Choosing the right base image drastically reduces vulnerability surface and deployment transfer times:

| Base Image Type | Example | Size | Pros / Cons |
|---|---|---|---|
| **Full Distribution** | `ubuntu:22.04`, `node:20` | ~1 GB | Easy debugging, contains full package manager, large attack surface |
| **Alpine Linux** | `alpine:3.19`, `node:20-alpine` | ~5 MB - 50 MB | Extremely lightweight, uses `musl` instead of `glibc` |
| **Distroless** | `gcr.io/distroless/nodejs20-debian12` | ~30 MB - 60 MB | Contains only app and runtime; zero shell, zero package manager (highest security) |
| **Scratch** | `FROM scratch` | 0 MB | True empty base; used for statically compiled binaries (Go, Rust, C++) |

---

## 7. Non-Root Containers & Security

By default, Docker containers execute as `root` (UID 0). If a container breakout vulnerability occurs, the attacker gains root-level capabilities on the host kernel.

### Hardening Checklist:
1. **Never run as root**:
   ```dockerfile
   # Alpine
   RUN addgroup -S appgroup && adduser -S appuser -G appgroup
   USER appuser
   ```
2. **Explicitly assign file permissions during `COPY`**:
   ```dockerfile
   COPY --chown=appuser:appgroup . /app
   ```
3. **Use Distroless nonroot user**:
   ```dockerfile
   FROM gcr.io/distroless/static-debian12:nonroot
   USER nonroot:nonroot
   ```

---

## 8. Complete Production Dockerfile Example

Below is a production-hardened Dockerfile incorporating all modern best practices:

```dockerfile
# ----------------------------------------------------
# Global Build Arguments
# ----------------------------------------------------
ARG NODE_VERSION=20.11.1
ARG ALPINE_VERSION=3.19

# ----------------------------------------------------
# Stage 1: Dependencies & Build Stage
# ----------------------------------------------------
FROM node:${NODE_VERSION}-alpine${ALPINE_VERSION} AS builder

WORKDIR /usr/src/app

# Install dependencies first for layer caching
COPY package*.json tsconfig.json ./
RUN npm ci

# Copy source and build
COPY src/ ./src
RUN npm run build

# Install production-only dependencies
RUN npm ci --omit=dev && npm cache clean --force

# ----------------------------------------------------
# Stage 2: Hardened Production Image
# ----------------------------------------------------
FROM node:${NODE_VERSION}-alpine${ALPINE_VERSION}

LABEL maintainer="engineering@example.com" \
      version="1.0.0" \
      description="Production API Service"

WORKDIR /usr/src/app

# Set production environment variables
ENV NODE_ENV=production \
    PORT=8080

# Create dedicated non-root user and group
RUN addgroup -g 10001 -S appgroup && \
    adduser -u 10001 -S appuser -G appgroup

# Copy dependencies and compiled assets with correct permissions
COPY --chown=appuser:appgroup --from=builder /usr/src/app/node_modules ./node_modules
COPY --chown=appuser:appgroup --from=builder /usr/src/app/dist ./dist
COPY --chown=appuser:appgroup package.json ./

# Switch to non-root user
USER appuser

# Expose service port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

# Start container with exec form
CMD ["node", "dist/server.js"]
```

---

## 9. Build & Execution Cheat Sheet

```bash
# 1. Build an image with a specific tag
docker build -t my-service:1.0.0 .

# 2. Build with custom Dockerfile name
docker build -f Dockerfile.prod -t my-service:prod .

# 3. Build passing build-time arguments (ARG)
docker build --build-arg APP_VERSION=2.1.0 -t my-service:2.1.0 .

# 4. Build without using layer cache (clean build)
docker build --no-cache -t my-service:latest .

# 5. Inspect image layers and history
docker history my-service:1.0.0

# 6. Run container in background with healthcheck monitoring
docker run -d \
  --name api-server \
  -p 8080:8080 \
  --restart unless-stopped \
  my-service:1.0.0

# 7. Check container health status
docker inspect --format='{{json .State.Health.Status}}' api-server
```

---

## References

- [Official Dockerfile Reference](https://docs.docker.com/engine/reference/builder/)
- [Best Practices for Writing Dockerfiles](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [Docker Multi-Stage Builds](https://docs.docker.com/build/building/multi-stage/)
- [Open Container Initiative (OCI) Image Specification](https://github.com/opencontainers/image-spec)
