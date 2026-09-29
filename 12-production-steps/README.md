# 12 — Deploying Docker in Production: End-to-End Steps & Storage Architectures

This guide details the step-by-step lifecycle of deploying Docker applications to production environments, focusing on operational workflows and real-world production usage of **Images**, **Containers**, **Volumes**, and **Bind Mounts**.

---

## Table of Contents

1. [High-Level Production Deployment Lifecycle](#1-high-level-production-deployment-lifecycle)
2. [Step-by-Step Production Deployment Workflow](#2-step-by-step-production-deployment-workflow)
3. [Images in Production](#3-images-in-production)
4. [Containers in Production](#4-containers-in-production)
5. [Volumes in Production](#5-volumes-in-production)
6. [Bind Mounts in Production](#6-bind-mounts-in-production)
7. [Storage Decision Matrix: Volume vs. Bind Mount vs. tmpfs](#7-storage-decision-matrix-volume-vs-bind-mount-vs-tmpfs)
8. [Complete Production Example: Docker Compose Deployment](#8-complete-production-example-docker-compose-deployment)
9. [Production Deployment Checklist](#9-production-deployment-checklist)

---

## 1. High-Level Production Deployment Lifecycle

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Source Code   │ ───► │  CI / CD Build  │ ───► │ Secure Registry │
│  (Git / Branch) │      │  & Vulnerability│      │   (ECR/GHCR/    │
│                 │      │      Scan       │      │   Docker Hub)   │
└─────────────────┘      └─────────────────┘      └────────┬────────┘
                                                           │
                                                           ▼
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Health Check  │ ◄─── │  Run Container  │ ◄─── │ Production Host │
│  & Verification │      │ (Volumes, Limits│      │ (Pull Tagged    │
│                 │      │  Restart Policy)│      │  Immutable Img) │
└─────────────────┘      └─────────────────┘      └─────────────────┘
```

---

## 2. Step-by-Step Production Deployment Workflow

Deploying a containerised application to production follows a structured 7-step process:

### Step 1: Write an Optimized, Multi-Stage `Dockerfile`
- Separate the build environment from the runtime environment to eliminate compiler tools, package managers, and source code from the final artifact.
- Define a non-root user and include an integrated `HEALTHCHECK`.

### Step 2: Establish a Secure Tagging & Versioning Strategy
- Avoid `latest` in production.
- Use immutable semantic versions (e.g., `v1.4.2`) or Git commit SHAs (e.g., `sha-8f3e2b1`).

### Step 3: CI/CD Pipeline Build, Test & Security Scan
- Build images in automated CI pipelines.
- Scan for Common Vulnerabilities and Exposures (CVEs) using tools like **Trivy**, **Snyk**, or **Docker Scout** before pushing to registry.

```bash
# Example CI image scan
trivy image --exit-code 1 --severity CRITICAL,HIGH myregistry.com/app:v1.4.2
```

### Step 4: Push to an Authenticated Private Registry
- Push immutable image tags to secure registries (AWS ECR, GCP Artifact Registry, GitHub Packages, Azure ACR, or self-hosted Harbor).

### Step 5: Provision Production Storage (Volumes & Bind Mounts)
- Create and configure named volumes for persistent data (databases, stateful files).
- Pre-stage read-only configuration files or host certificates for bind mounting.

### Step 6: Deploy with Orchestration & Safe Rolling Update
- Deploy using Docker Compose, Docker Swarm, AWS ECS, or Kubernetes.
- Apply resource constraints (CPU/Memory), restart policies, and logging drivers.
- Use zero-downtime rolling update or blue-green strategy.

### Step 7: Continuous Monitoring, Logging & Pruning
- Forward container logs (`stdout`/`stderr`) to centralized aggregation tools (CloudWatch, Datadog, ELK/Promtail).
- Set up automated cleanup policies (`docker system prune`) via cron jobs to avoid disk exhaustion on host servers.

---

## 3. Images in Production

Images in production are immutable, self-contained artifacts. Once built and tested in staging, the **exact same image binary** must be promoted to production without rebuilding.

### Best Practices for Production Images

| Aspect | Development | Production |
|---|---|---|
| **Base Image** | Full SDK / standard OS (`node:20`, `python:3.11`) | Minimal / Distroless / Alpine (`node:20-alpine`, `gcr.io/distroless/nodejs20`) |
| **Image Size** | 800 MB - 1.5 GB | 50 MB - 200 MB |
| **Tagging** | `latest` or `dev` | Semantic version `v1.2.3` or commit SHA `sha-a1b2c3d` |
| **Layers** | Many unoptimised layers | Chained `RUN` commands and multi-stage builds |
| **Security** | Root user, dev tools included | Non-root `USER`, zero build tools/test frameworks |

### Production Multi-Stage Dockerfile Pattern

```dockerfile
# Stage 1: Build & Dependencies
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production && cp -R node_modules prod_node_modules
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Hardened Runtime
FROM node:20-alpine
WORKDIR /app

# Create a restricted user & group
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy only compiled assets and production dependencies
COPY --from=builder --chown=appuser:appgroup /app/prod_node_modules ./node_modules
COPY --from=builder --chown=appuser:appgroup /app/dist ./dist

# Drop root privileges
USER appuser

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "dist/server.js"]
```

---

## 4. Containers in Production

In production, containers must be **stateless**, **isolated**, **resource-governed**, and **self-healing**.

### Key Production Container Principles

1. **Self-Healing & Restart Policies**:
   - `restart: unless-stopped` or `restart: always` ensures crashed containers or restarted hosts automatically bring services back up.
2. **Resource Boundaries (Guardrails)**:
   - Prevent noisy neighbor issues or memory leaks from crashing the host by setting memory and CPU limits.
3. **Read-Only Root Filesystem**:
   - Running `--read-only` prevents malware or exploit payloads from modifying container binaries at runtime.
4. **Structured Logging**:
   - Log strictly to `stdout` and `stderr` using JSON format. Set up log rotation to prevent Docker host disk filling.

### Production Execution Command

```bash
docker run -d \
  --name web-app \
  --restart unless-stopped \
  --cpus="1.5" \
  --memory="512m" \
  --memory-reservation="256m" \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  -v app-storage:/app/storage \
  -v /etc/ssl/certs/prod-bundle.crt:/etc/ssl/certs/app.crt:ro \
  --log-driver json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  -p 3000:3000 \
  myregistry.com/my-app:v1.4.2
```

---

## 5. Volumes in Production

**Docker Volumes** are the standard mechanism for persisting data generated by stateful production workloads (databases, message queues, uploads). Volumes are fully managed by Docker and stored in `/var/lib/docker/volumes/` on Linux hosts.

### How Volumes Are Used in Production

- **Database Persistence**: PostgreSQL, MySQL, MongoDB, Redis storage engines.
- **Shared Cluster Storage**: Cloud volume drivers (e.g., AWS EBS/EFS plugins, Azure File Storage, Ceph) that attach persistent volumes across instances.
- **Lifecycle Independence**: Volumes exist independently of container lifecycles. Containers can be destroyed, upgraded, and recreated without data loss.

### Production Volume Strategies

#### 1. Named Volumes with Explicit Storage Drivers
```yaml
volumes:
  db_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/fast-ssd/postgres-data
```

#### 2. Backup & Disaster Recovery Pipeline
Perform automated backups without taking down containers by mounting volumes into lightweight backup containers:

```bash
# Automated database volume backup to host / S3
docker run --rm \
  --volumes-from postgres_db_container \
  -v /var/backups:/backup \
  alpine \
  tar czf /backup/db_data_$(date +%Y%m%d).tar.gz /var/lib/postgresql/data
```

#### 3. Restore Strategy
```bash
# Restore to a fresh volume
docker run --rm \
  -v db_data:/target \
  -v /var/backups:/backup \
  alpine \
  tar xzf /backup/db_data_20250101.tar.gz -C /target --strip 1
```

---

## 6. Bind Mounts in Production

**Bind Mounts** map an exact file or directory on the host machine to a container path. 

### Development vs. Production Usage of Bind Mounts

> ⚠️ **Key Rule:** While bind mounts are used in development for **live source code hot-reloading**, hot-reloading code via bind mounts is **strictly forbidden in production**.

### Legitimate Production Use Cases for Bind Mounts

1. **Mounting Host Configuration Files (Read-Only `:ro`)**:
   - NGINX configuration files (`/etc/nginx/nginx.conf`).
   - Custom daemon or database configuration (`/etc/my.cnf`).
2. **Mounting TLS/SSL Certificates**:
   - Injecting server SSL certificates managed by Let's Encrypt / Certbot on the host into proxy containers.
3. **Mounting Host Timezone & System Time**:
   - Synchronizing container time: `-v /etc/localtime:/etc/localtime:ro`.
4. **Mounting Docker Socket (Admin / CI Agents Only)**:
   - For monitoring or deployment agents (e.g., Portainer, Datadog agent, Jenkins CI agent) using `-v /var/run/docker.sock:/var/run/docker.sock`.

### Production Rule: Always Mount Bind Mounts as Read-Only (`:ro`)

```bash
# Production NGINX reverse proxy with read-only bind mounts
docker run -d \
  --name production-proxy \
  -p 80:80 \
  -p 443:443 \
  -v /opt/nginx/conf/nginx.conf:/etc/nginx/nginx.conf:ro \
  -v /etc/letsencrypt/live/example.com:/etc/ssl/certs/example.com:ro \
  nginx:1.25-alpine
```

---

## 7. Storage Decision Matrix: Volume vs. Bind Mount vs. tmpfs

| Feature | Docker Named Volume | Bind Mount | tmpfs Mount |
|---|---|---|---|
| **Location** | Docker managed (`/var/lib/docker/volumes`) | Explicit host path (`/etc/ssl`, `/opt/conf`) | Host RAM memory only |
| **Production Use Case** | Databases, file uploads, persistent app state | Host configuration files, SSL certs, socket files | Ephemeral caches, secrets, session storage |
| **Host System Independence** | High (portable across cloud VMs) | Low (requires specific host directory structure) | High |
| **Write Permissions** | Read-Write (`:rw`) | Almost always Read-Only (`:ro`) in production | Read-Write (RAM only) |
| **Performance** | High native I/O | Host filesystem performance | Maximum (memory bus speed) |
| **Backup Ease** | Simple via volume backup containers | Relies on host-level backup scripts | None (cleared on container exit) |

---

## 8. Complete Production Example: Docker Compose Deployment

Below is a production-ready `compose.yaml` demonstrating how images, containers, named volumes, bind mounts, and security constraints work together.

```yaml
services:
  # 1. Reverse Proxy (Using Bind Mounts for Config & SSL)
  proxy:
    image: nginx:1.25-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      # Read-only bind mount for NGINX config
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      # Read-only bind mount for SSL certs
      - /etc/letsencrypt:/etc/letsencrypt:ro
    depends_on:
      api:
        condition: service_healthy
    networks:
      - frontend_net
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # 2. Application API (Stateless Container with Hardening & tmpfs)
  api:
    image: myregistry.com/my-api:v1.4.2
    restart: unless-stopped
    read_only: true
    tmpfs:
      - /tmp:size=64M,uid=1000,gid=1000
    environment:
      NODE_ENV: production
      DATABASE_URL: postgres://dbuser:${DB_PASSWORD}@db:5432/production_db
    deploy:
      resources:
        limits:
          cpus: "1.5"
          memory: 512M
        reservations:
          cpus: "0.5"
          memory: 128M
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    volumes:
      # Persistent named volume for user-uploaded assets
      - app_uploads:/app/uploads
    networks:
      - frontend_net
      - backend_net

  # 3. Database (Stateful Service Using Named Volumes)
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: production_db
      POSTGRES_USER: dbuser
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 1024M
    volumes:
      # Dedicated named volume for DB data persistence
      - pgdata:/var/lib/postgresql/data
    networks:
      - backend_net

networks:
  frontend_net:
    driver: bridge
  backend_net:
    driver: bridge

volumes:
  pgdata:
    driver: local
  app_uploads:
    driver: local
```

---

## 9. Production Deployment Checklist

### Images
- [ ] Multi-stage build configured; zero build/test tools in final layer.
- [ ] Minimal/distroless/alpine base image used.
- [ ] Tagged with semantic version or Git SHA (no `latest`).
- [ ] Vulnerability scan (CVE check) passed in CI/CD pipeline.
- [ ] `.dockerignore` file prevents `.env`, `.git`, and node_modules from being baked into the build context.

### Containers
- [ ] Non-root user specified (`USER` in Dockerfile or `user:` in compose).
- [ ] `restart: unless-stopped` or `restart: always` configured.
- [ ] CPU and memory limits (`limits`, `reservations`) defined.
- [ ] `HEALTHCHECK` defined and verified.
- [ ] Read-only root filesystem applied where possible (`read_only: true`).
- [ ] Log rotation enabled (`max-size`, `max-file`).

### Volumes & Bind Mounts
- [ ] All database/persistent state mapped to **named volumes**, not container root layers.
- [ ] Automated backup job configured for all persistent volumes.
- [ ] All production **bind mounts** set to **read-only** (`:ro`).
- [ ] Source code hot-reloading bind mounts removed from production configs.
- [ ] Ephemeral temporary writes configured to use `tmpfs`.
