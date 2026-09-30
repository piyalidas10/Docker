# Docker Security Best Practices

A comprehensive guide to securing Docker containers, images, hosts, and networks
in development and production environments.

---

## The Docker Security Attack Surface

```
┌─────────────────────────────────────────────────────────────┐
│                        Host Machine                         │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                   Docker Daemon                      │  │
│  │                                                      │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │  │
│  │  │ Container A │  │ Container B │  │ Container C │  │  │
│  │  │             │  │             │  │             │  │  │
│  │  │  Image      │  │  Image      │  │  Image      │  │  │
│  │  │  Process    │  │  Process    │  │  Process    │  │  │
│  │  │  Network    │  │  Network    │  │  Network    │  │  │
│  │  │  Volumes    │  │  Volumes    │  │  Volumes    │  │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  Registry ──► Images ──► Containers ──► Networks/Volumes   │
└─────────────────────────────────────────────────────────────┘
```

**Attack vectors to defend:**
1. Vulnerable base images
2. Secrets leaked in images or environment variables
3. Root processes inside containers
4. Excessive container privileges
5. Exposed Docker daemon socket
6. Unrestricted inter-container network traffic
7. Unpatched host kernel (container escape)
8. Unverified images from public registries

---

## 1. Image Security

### Use Minimal Base Images

Large base images have a larger attack surface — more packages, more CVEs.

```dockerfile
# ❌ Full OS image — hundreds of unnecessary packages
FROM ubuntu:22.04

# ✅ Minimal base
FROM node:20-alpine          # Alpine: ~5MB, minimal attack surface
FROM python:3.12-slim        # Slim variant: no build tools, smaller
FROM gcr.io/distroless/nodejs20  # Distroless: no shell, no package manager
```

**Distroless images** contain only the application runtime and its dependencies.
There is no shell, no `apt`, no `curl` — so even if an attacker gets code execution,
they have almost nothing to work with.

---

### Pin Exact Image Versions (Never Use `latest`)

```dockerfile
# ❌ Unpredictable — could pull a vulnerable version tomorrow
FROM node:latest
FROM postgres:latest

# ✅ Pinned to a specific version
FROM node:20.14.0-alpine3.20
FROM postgres:16.3-alpine3.20

# ✅ Even better — pin by digest (immutable, cannot be altered)
FROM node@sha256:a1b2c3d4e5f6...
```

`latest` is not a version — it is the most recently pushed tag.
A supply chain attack on a base image won't affect you if you're pinned to a digest.

---

### Scan Images for Vulnerabilities

```bash
# Trivy — scan an image before pushing
trivy image myapp:latest

# Docker Scout (built into Docker Desktop)
docker scout cves myapp:latest

# Snyk
snyk container test myapp:latest
```

Integrate scanning into CI/CD so vulnerable images never reach production:

```yaml
# GitHub Actions: fail the build if critical CVEs found
- name: Scan image
  run: |
    trivy image --exit-code 1 --severity CRITICAL myapp:${{ github.sha }}
```

---

### Multi-Stage Builds — Keep Build Tools Out of Production Images

```dockerfile
# Stage 1: Build (includes compiler, dev dependencies)
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci                        # installs devDependencies too
COPY . .
RUN npm run build                 # compiles TypeScript, bundles, etc.

# Stage 2: Production (only the compiled output + runtime deps)
FROM node:20-alpine AS production
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
# ← no source code, no compiler, no devDependencies in this image
CMD ["node", "dist/server.js"]
```

The production image has no build tools, no source code, and no test dependencies.
An attacker who gains code execution inside it cannot recompile or exfiltrate source.

---

### Do Not Store Secrets in Images

```dockerfile
# ❌ Secret baked into the image layer — visible in docker history
ENV DB_PASSWORD=mysecretpassword
RUN curl -H "Authorization: Bearer hardcodedtoken" https://api.example.com

# ✅ Pass secrets at runtime via environment or mounted files
# (never in the Dockerfile)
```

Even if you delete the `ENV` line in a later layer, the secret remains in the image
history and can be extracted with `docker history --no-trunc`.

---

## 2. Container Runtime Security

### Never Run as Root

By default, processes inside containers run as `root` (UID 0). If a container is
compromised, root inside the container maps to root on the host — catastrophic.

```dockerfile
# ❌ Default — runs as root
FROM node:20-alpine
CMD ["node", "server.js"]

# ✅ Create and use a non-root user
FROM node:20-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
CMD ["node", "server.js"]
```

In Docker Compose:
```yaml
services:
  app:
    image: myapp:latest
    user: "1000:1000"   # UID:GID — must exist in the image
```

In Kubernetes:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
```

---

### Drop All Linux Capabilities

Linux capabilities are fine-grained root privileges. Containers start with a default
set that includes several dangerous ones. Drop all of them and add back only what is needed.

```yaml
services:
  app:
    image: myapp:latest
    cap_drop:
      - ALL                   # drop every capability
    cap_add:
      - NET_BIND_SERVICE      # only re-add what the app actually needs
                              # (bind to port < 1024)
```

Common capabilities and when you actually need them:

| Capability | What It Allows | Need It? |
|---|---|---|
| `NET_BIND_SERVICE` | Bind to ports < 1024 | Only if app binds to port 80/443 |
| `SYS_PTRACE` | Attach debugger to processes | Dev only, never production |
| `SYS_ADMIN` | Mount filesystems, modify kernel params | Almost never |
| `NET_ADMIN` | Configure network interfaces | Only network tools |
| `CHOWN` | Change file ownership | Only if app manages file permissions |

---

### Use Read-Only Root Filesystems

A compromised container cannot install malware or modify its own binaries if the
root filesystem is read-only.

```yaml
services:
  app:
    image: myapp:latest
    read_only: true
    tmpfs:
      - /tmp                  # in-memory scratch space (not persisted)
    volumes:
      - app_data:/data        # explicit writable volume only where needed
```

In Kubernetes:
```yaml
securityContext:
  readOnlyRootFilesystem: true
```

---

### Prevent Privilege Escalation

```yaml
services:
  app:
    image: myapp:latest
    security_opt:
      - no-new-privileges:true   # process cannot gain more privileges than its parent
```

This prevents a compromised process from calling `setuid` binaries
(like `sudo`) to escalate back to root even if such binaries exist in the image.

---

### Set Resource Limits

Without resource limits, one container can consume all host CPU and memory —
bringing down every other service on the node.

```yaml
services:
  app:
    image: myapp:latest
    deploy:
      resources:
        limits:
          cpus: "0.5"         # max 50% of one CPU core
          memory: 512M        # max 512MB RAM
        reservations:
          cpus: "0.25"        # guaranteed 25% CPU
          memory: 256M        # guaranteed 256MB RAM
```

---

## 3. Secrets Management

### Never Use Environment Variables for Sensitive Secrets

Environment variables are visible in:
- `docker inspect` output
- Process listings (`/proc/*/environ` on Linux)
- Crash dumps and debug logs
- Any child process spawned by the container

```yaml
# ❌ Secret visible in docker inspect and child process env
environment:
  DB_PASSWORD: mysecretpassword
  API_KEY: sk-1234567890abcdef
```

### Use Docker Secrets (Swarm) or Kubernetes Secrets

```yaml
# Docker Swarm secret
services:
  app:
    image: myapp:latest
    secrets:
      - db_password           # mounted at /run/secrets/db_password

secrets:
  db_password:
    external: true            # managed by docker secret create
```

```yaml
# Kubernetes Secret as a volume mount
volumes:
  - name: app-secrets
    secret:
      secretName: myapp-secrets
      items:
        - key: db-password
          path: db_password   # available at /run/secrets/db_password
```

The secret is:
- A file on a `tmpfs` mount (in-memory — never touches disk)
- Only accessible to the specific container that declared it
- Not visible in `docker inspect` environment

### Use a Secrets Manager for Production

For production-grade secrets management:

| Platform | Tool |
|---|---|
| AWS | AWS Secrets Manager + IAM Roles for Service Accounts |
| Azure | Azure Key Vault + Workload Identity / CSI driver |
| GCP | GCP Secret Manager + Workload Identity |
| On-premise | HashiCorp Vault |

```yaml
# Azure Key Vault CSI driver in Kubernetes
volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: azure-keyvault-provider
```

---

## 4. Network Security

### Use Custom Bridge Networks (Never Share the Default)

All containers on the default `bridge` network can communicate with each other
and resolve each other by IP. This violates least-privilege.

```yaml
# ❌ All services on same network — any can talk to any
services:
  app:
    image: myapp:latest
  db:
    image: postgres:16
  redis:
    image: redis:7

# ✅ Explicit networks — only declared connections work
services:
  app:
    image: myapp:latest
    networks:
      - frontend
      - backend

  db:
    image: postgres:16
    networks:
      - backend              # only app can reach db, not public internet

  redis:
    image: redis:7
    networks:
      - backend

networks:
  frontend:
  backend:
    internal: true           # no outbound internet from backend network
```

---

### Disable Inter-Container Communication

```bash
# Start Docker daemon with ICC disabled — containers cannot reach each other
# unless explicitly linked via networks
dockerd --icc=false
```

Or in `/etc/docker/daemon.json`:
```json
{
  "icc": false
}
```

---

### Expose Only Required Ports

```yaml
# ❌ Binds to all host interfaces — reachable from anywhere
ports:
  - "5432:5432"    # PostgreSQL exposed to 0.0.0.0

# ✅ Bind to localhost only — not reachable externally
ports:
  - "127.0.0.1:5432:5432"

# ✅ Better — don't expose at all; let app container reach it
#    via Docker internal network (no host port mapping needed)
# (remove the ports: section entirely for internal-only services)
```

---

### Use TLS for All Service-to-Service Communication

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_SSL: "on"
    volumes:
      - certs:/var/lib/postgresql/certs
    command: >
      postgres
      -c ssl=on
      -c ssl_cert_file=/var/lib/postgresql/certs/server.crt
      -c ssl_key_file=/var/lib/postgresql/certs/server.key
```

Application connection string:
```
postgresql://user:pass@db:5432/mydb?sslmode=require
```

---

## 5. Docker Daemon Security

### Never Expose the Docker Socket to Containers

The Docker socket (`/var/run/docker.sock`) is the most dangerous thing you can
mount into a container. A container with access to the socket **is effectively root on the host**.

```yaml
# ❌ NEVER do this in production
volumes:
  - /var/run/docker.sock:/var/run/docker.sock

# This allows the container to:
# → Spawn new privileged containers
# → Mount the host filesystem
# → Read all other container environments (including secrets)
# → Escape the container entirely
```

If you need Docker-in-Docker (CI/CD), use alternatives:
- **Kaniko** — builds Docker images without the Docker daemon
- **Buildah** — builds OCI images without root or the daemon
- **Docker-in-Docker (dind) with rootless mode** — isolated daemon, not the host's

---

### Run Docker in Rootless Mode

Rootless mode runs the Docker daemon as a non-root user.
A container escape only reaches the unprivileged user, not root.

```bash
# Install rootless Docker
dockerd-rootless-setuptool.sh install

# Start rootless Docker daemon
systemctl --user start docker
```

---

### Use a Security Profile (seccomp / AppArmor)

Docker's default seccomp profile blocks ~44 dangerous system calls.
For sensitive workloads, apply a stricter custom profile.

```yaml
services:
  app:
    image: myapp:latest
    security_opt:
      - seccomp:/path/to/custom-seccomp.json
      - apparmor:docker-default
```

---

### Protect the Docker Daemon with TLS

If the Docker daemon must be accessible remotely (not recommended for production),
protect it with mutual TLS — not a plain TCP socket.

```bash
# ❌ Plain TCP — anyone on the network can control all your containers
dockerd -H tcp://0.0.0.0:2375

# ✅ TLS-authenticated remote access
dockerd \
  -H tcp://0.0.0.0:2376 \
  --tlsverify \
  --tlscacert=/certs/ca.pem \
  --tlscert=/certs/server-cert.pem \
  --tlskey=/certs/server-key.pem
```

---

## 6. Registry Security

### Use Private Registries for Production Images

Never push production application images to a public Docker Hub repository.
Use:
- **AWS ECR** (Elastic Container Registry)
- **Azure Container Registry (ACR)**
- **GCP Artifact Registry**
- **GitHub Container Registry (GHCR)** — with private repos

---

### Sign and Verify Images (Supply Chain Security)

```bash
# Sign an image with Docker Content Trust
export DOCKER_CONTENT_TRUST=1
docker push myregistry/myapp:v1.0.0

# Verify on pull — unsigned images are rejected
docker pull myregistry/myapp:v1.0.0
```

For Kubernetes, use **Sigstore/Cosign** + **Kyverno** or **OPA Gatekeeper**
to enforce that only signed images are allowed to run in the cluster.

---

### Regularly Pull and Rebuild Base Images

Base images receive security patches. If you never rebuild, your containers
accumulate CVEs from the base image over time.

```yaml
# GitHub Actions: nightly rebuild to pick up base image patches
on:
  schedule:
    - cron: '0 2 * * *'   # 2am every night

jobs:
  rebuild:
    steps:
      - run: docker build --no-cache -t myapp:latest .
      - run: trivy image --exit-code 1 --severity CRITICAL myapp:latest
      - run: docker push myapp:latest
```

---

## 7. Audit & Compliance

### Enable Docker Audit Logging

```json
// /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "experimental": false,
  "live-restore": true
}
```

Audit rules for the Docker socket:
```bash
# auditd — log all access to the Docker socket
auditctl -w /var/run/docker.sock -k docker
auditctl -w /etc/docker -k docker
auditctl -w /usr/bin/docker -k docker
```

---

### Run the Docker CIS Benchmark

The CIS Docker Benchmark is the authoritative hardening checklist.
`docker-bench-security` automates the check:

```bash
docker run --net host --pid host --userns host --cap-add audit_control \
  -v /var/lib:/var/lib \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /etc:/etc \
  --label docker_bench_security \
  docker/docker-bench-security
```

---

## Security Checklist

| Category | Practice | Priority |
|---|---|---|
| **Image** | Use minimal/distroless base images | High |
| **Image** | Pin to exact versions or digest | High |
| **Image** | Multi-stage builds — no build tools in production | High |
| **Image** | No secrets in Dockerfile or image layers | Critical |
| **Image** | Scan images for CVEs in CI/CD | High |
| **Runtime** | Run as non-root user | Critical |
| **Runtime** | Drop all capabilities, add back only what's needed | High |
| **Runtime** | Read-only root filesystem | High |
| **Runtime** | `no-new-privileges: true` | High |
| **Runtime** | Set CPU and memory limits | Medium |
| **Secrets** | Never use env vars for sensitive secrets | Critical |
| **Secrets** | Use Docker Secrets or a secrets manager | Critical |
| **Network** | Custom bridge networks per service group | High |
| **Network** | Do not expose internal service ports to the host | High |
| **Network** | TLS for all service-to-service traffic | High |
| **Daemon** | Never mount Docker socket into a container | Critical |
| **Daemon** | Use rootless Docker in production | High |
| **Daemon** | Apply seccomp / AppArmor profile | Medium |
| **Registry** | Use private registry for production images | High |
| **Registry** | Sign images; verify on pull | Medium |
| **Registry** | Nightly rebuilds to pick up base image patches | Medium |
| **Audit** | Enable Docker audit logging | Medium |
| **Audit** | Run CIS Docker Benchmark regularly | High |

---

## Key Takeaway

> Docker security is layered. No single practice is sufficient on its own.
>
> The highest-impact rules are:
> 1. **Never run as root** inside a container
> 2. **Never store secrets in images or environment variables**
> 3. **Never mount the Docker socket** into a container
> 4. **Drop all Linux capabilities** and add back only what is required
> 5. **Scan every image** before it reaches production
>
> Apply these five first. Then work through the rest of the checklist.
