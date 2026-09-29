# 17 — Docker Security & Hardening Best Practices

Container security is a multi-layered discipline spanning **image building**, **container runtime configuration**, **host system protection**, and **supply chain integrity**. Containers share the host operating system kernel; therefore, misconfigurations can lead to container breakout vulnerabilities and host compromise.

---

## The Container Security Attack Surface

```
┌────────────────────────────────────────────────────────┐
│                      Host Kernel                       │
│    (Namespaces, Cgroups, LSM: AppArmor / SELinux)      │
└───────────────────────────┬────────────────────────────┘
                            │
        ┌───────────────────┴───────────────────┐
        ▼                                       ▼
┌───────────────────────────────┐   ┌───────────────────────────────┐
│     Insecure Container        │   │    Hardened Container         │
│  ❌ Runs as root (UID 0)       │   │  ✅ Non-root USER (UID 10001)  │
│  ❌ Writable root filesystem  │   │  ✅ Read-only root filesystem │
│  ❌ Default Linux capabilities│   │  ✅ Dropped ALL capabilities  │
│  ❌ Docker socket mounted     │   │  ✅ No socket mounts          │
│  ❌ Unscanned bloated image   │   │  ✅ Minimal Distroless base   │
│  ❌ Unlimited CPU/RAM         │   │  ✅ Hard resource limits      │
└───────────────────────────────┘   └───────────────────────────────┘
```

---

## Table of Contents

1. [Core Security Principles & Defense-in-Depth](#1-core-security-principles--defense-in-depth)
2. [Image Security & Supply Chain](#2-image-security--supply-chain)
   - [Minimal Base Images & Distroless](#minimal-base-images--distroless)
   - [Vulnerability Scanning (Trivy, Docker Scout, Snyk)](#vulnerability-scanning-trivy-docker-scout-snyk)
   - [Preventing Secret Leakage](#preventing-secret-leakage)
   - [Docker Content Trust (Image Signing)](#docker-content-trust-image-signing)
3. [Container Runtime Hardening](#3-container-runtime-hardening)
   - [Running as Non-Root (Principle of Least Privilege)](#running-as-non-root-principle-of-least-privilege)
   - [Read-Only Root Filesystem](#read-only-root-filesystem)
   - [Linux Capabilities (`--cap-drop` & `--cap-add`)](#linux-capabilities---cap-drop---cap-add)
   - [`no-new-privileges` Flag](#no-new-privileges-flag)
   - [Resource Limits (DoS Protection)](#resource-limits-dos-protection)
4. [Docker Socket & Daemon Security](#4-docker-socket--daemon-security)
   - [The Danger of `/var/run/docker.sock`](#the-danger-of-varrundockersock)
   - [Rootless Docker Mode](#rootless-docker-mode)
   - [Securing Remote Daemon with TLS](#securing-remote-daemon-with-tls)
5. [Kernel Security Modules: AppArmor & Seccomp](#5-kernel-security-modules-apparmor--seccomp)
6. [Production-Hardened Examples](#6-production-hardened-examples)
   - [Hardened Dockerfile](#hardened-dockerfile)
   - [Hardened CLI Command](#hardened-cli-command)
   - [Hardened Docker Compose File](#hardened-docker-compose-file)
7. [Comprehensive Docker Security Checklist](#7-comprehensive-docker-security-checklist)

---

## 1. Core Security Principles & Defense-in-Depth

Docker security adheres to five core tenets:
1. **Least Privilege**: Never run containers as root; drop unnecessary Linux kernel capabilities.
2. **Minimal Attack Surface**: Strip compilers, shells, package managers, and debug tools from production images.
3. **Immutability**: Enforce read-only root filesystems and immutable image tags.
4. **Isolation**: Prevent container-to-container network snooping and isolate process trees.
5. **Continuous Verification**: Scan container images across the entire CI/CD lifecycle for known CVEs.

---

## 2. Image Security & Supply Chain

### Minimal Base Images & Distroless
Large base images (e.g. `ubuntu:latest` or standard `node:latest`) contain hundreds of OS utilities (package managers, SSH clients, bash, curl) that an attacker can leverage once inside.

- **Alpine Linux**: Uses `musl-libc` and `busybox` (~5 MB).
- **Distroless**: Maintained by Google (`gcr.io/distroless/static-debian12`), contains **only** the application runtime and its direct dependencies. It includes **no shell**, **no package manager**, and **no standard utilities**.

```dockerfile
# Build binary in stage 1
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -o /server .

# Production stage using Distroless non-root
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=builder /server /server
USER nonroot:nonroot
CMD ["/server"]
```

---

### Vulnerability Scanning (Trivy, Docker Scout, Snyk)
Automate vulnerability detection inside your CI/CD pipeline before pushing images to a registry:

```bash
# 1. Scan image using Trivy (fails CI if CRITICAL CVEs found)
trivy image --exit-code 1 --severity HIGH,CRITICAL myapp:1.0

# 2. Scan with Docker Scout
docker scout cves myapp:1.0
docker scout quickview myapp:1.0

# 3. Scan with Snyk
snyk container test myapp:1.0 --severity-threshold=high
```

---

### Preventing Secret Leakage
**Never** bake secrets (API keys, private keys, database passwords) into Dockerfiles using `ENV` or `ARG`, as they are stored permanently in the image layer history.

#### ❌ Dangerous (Leaked into Image Metadata):
```dockerfile
ARG DB_PASSWORD=mysecret
ENV API_KEY=abc-123-secret
```

#### ✅ Secure (BuildKit Mount Secret):
```dockerfile
# Mount temporary secret during build without saving into layer history
# syntax=docker/dockerfile:1.4
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc npm ci
```
Build command:
```bash
docker build --secret id=npmrc,src=.npmrc -t my-app .
```

---

### Docker Content Trust (Image Signing)
Docker Content Trust (DCT) uses digital signatures and cryptographic keys (Notary/Cosign) to ensure images were created by a trusted publisher and have not been tampered with.

```bash
# Enable Content Trust in your shell environment
export DOCKER_CONTENT_TRUST=1

# Any build/push automatically signs the image with your notary key
docker push myorg/myapp:1.0.0

# Any pull verifies publisher signature before pulling
docker pull myorg/myapp:1.0.0
```

---

## 3. Container Runtime Hardening

### Running as Non-Root (Principle of Least Privilege)
By default, Docker runs the container process as `root` (UID 0). A container breakout gives root privilege on the underlying host.

```dockerfile
# Create system group and user with fixed UID/GID >= 10000
RUN addgroup -g 10001 -S appgroup && \
    adduser -u 10001 -S appuser -G appgroup

# Set file permissions
COPY --chown=appuser:appgroup . /app

# Switch user
USER appuser
```

---

### Read-Only Root Filesystem
Make the container root filesystem immutable (`--read-only`). This prevents attackers from installing rootkits, modifying binaries, or downloading malicious scripts into the container filesystem at runtime.

Any required writable directories (e.g. `/tmp`, logs) must be mounted via `tmpfs` or dedicated volumes:

```bash
docker run -d \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  -v app-logs:/app/logs \
  myapp:1.0
```

---

### Linux Capabilities (`--cap-drop` & `--cap-add`)
Linux divides traditional root privileges into distinct privileges called **Capabilities**. By default, Docker grants containers a subset of capabilities (e.g. `CAP_CHOWN`, `CAP_NET_BIND_SERVICE`, `CAP_KILL`).

**Best Practice**: Drop **ALL** capabilities and selectively add back only what the application strictly needs:

```bash
# Drop all capabilities and add back only NET_BIND_SERVICE (bind port < 1024)
docker run -d \
  --cap-drop=ALL \
  --cap-add=NET_BIND_SERVICE \
  nginx:alpine
```

---

### `no-new-privileges` Flag
Prevents container processes from gaining additional privileges via `setuid` or `setgid` binaries.

```bash
docker run --security-opt=no-new-privileges:true myapp:1.0
```

---

### Resource Limits (DoS Protection)
Resource starvation attacks (Fork bombs, memory leaks) can destabilize the host machine. Always enforce memory and CPU ceilings:

```bash
docker run -d \
  --memory="512m" \
  --memory-swap="512m" \
  --cpus="1.5" \
  --pids-limit=100 \
  myapp:1.0
```

---

## 4. Docker Socket & Daemon Security

### The Danger of `/var/run/docker.sock`
Mounting `/var/run/docker.sock` inside a container gives that container **complete root access to the host machine**. Anyone with access to the Docker socket can spin up a privileged container with the host root filesystem mounted (`-v /:/host`).

```bash
# ❌ NEVER DO THIS in production web applications!
docker run -v /var/run/docker.sock:/var/run/docker.sock web-app
```
*Only trusted CI runners or container monitoring daemons (e.g. Portainer, Datadog) should ever have controlled access to the Docker socket.*

---

### Rootless Docker Mode
Rootless mode executes both the **Docker daemon (`dockerd`) and containers** as a regular non-root user on the host OS. Even if a container breakout occurs, the attacker only gains unprivileged access on the host.

```bash
# Install rootless docker script
dockerd-rootless-setuptool.sh install

# Set socket environment variable
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
```

---

### Securing Remote Daemon with TLS
If you must expose the Docker daemon over TCP (e.g., port 2376), **never expose it as plain unencrypted HTTP**. Always enforce mutual TLS (mTLS) with client and server certificates:

```json
// /etc/docker/daemon.json
{
  "tls": true,
  "tlscacert": "/etc/docker/ca.pem",
  "tlscert": "/etc/docker/server-cert.pem",
  "tlskey": "/etc/docker/server-key.pem",
  "tlsverify": true,
  "hosts": ["tcp://0.0.0.0:2376", "unix:///var/run/docker.sock"]
}
```

---

## 5. Kernel Security Modules: AppArmor & Seccomp

### Seccomp (Secure Computing Mode)
Seccomp filters and blocks dangerous system calls (syscalls) from containers to the Linux kernel. Docker has a default seccomp profile that blocks over 40 dangerous syscalls (e.g., `sys_chroot`, `acct`, `mount`).

```bash
# Run with default seccomp profile (applied by default)
docker run --security-opt seccomp=default myapp

# Run with a custom restricted seccomp profile
docker run --security-opt seccomp=/etc/docker/custom-profile.json myapp
```

### AppArmor / SELinux
AppArmor provides Mandatory Access Control (MAC) profiles limiting file and capability access:

```bash
# Enforce a custom AppArmor profile
docker run --security-opt apparmor=docker-default-hardened myapp
```

---

## 6. Production-Hardened Examples

### Hardened Dockerfile
```dockerfile
# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json tsconfig.json ./
RUN npm ci
COPY src/ ./src
RUN npm run build
RUN npm prune --production

# Stage 2: Minimal Hardened Runtime
FROM node:20-alpine
WORKDIR /app

ENV NODE_ENV=production

# 1. Create unprivileged non-root user
RUN addgroup -g 10001 -S appgroup && \
    adduser -u 10001 -S appuser -G appgroup

# 2. Copy only necessary artifacts with correct non-root ownership
COPY --chown=appuser:appgroup --from=builder /app/node_modules ./node_modules
COPY --chown=appuser:appgroup --from=builder /app/dist ./dist
COPY --chown=appuser:appgroup package.json ./

# 3. Switch to non-root user
USER appuser

EXPOSE 3000

# 4. Built-in health check
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "dist/index.js"]
```

---

### Hardened CLI Command
```bash
docker run -d \
  --name secure-service \
  --restart unless-stopped \
  --user 10001:10001 \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --security-opt=no-new-privileges:true \
  --cap-drop=ALL \
  --memory=512m \
  --cpus=1.0 \
  --pids-limit=100 \
  --log-driver json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  -p 127.0.0.1:3000:3000 \
  myregistry.com/my-service:1.0.0
```

---

### Hardened Docker Compose File
```yaml
services:
  secure-api:
    image: myregistry.com/my-service:1.0.0
    restart: unless-stopped
    read_only: true
    user: "10001:10001"
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=64m
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
          pids: 100
        reservations:
          memory: 128M
    ports:
      # Bound to localhost interface only
      - "127.0.0.1:3000:3000"
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/health"]
      interval: 30s
      timeout: 3s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

---

## 7. Comprehensive Docker Security Checklist

### Image Hardening
- [ ] Base images are minimal (Alpine, Distroless, or Scratch).
- [ ] Multi-stage builds are used; build compilers/SDKs excluded from production image.
- [ ] Images scanned for vulnerabilities (`trivy image`, `docker scout`) before deployment.
- [ ] No secrets or credentials in `Dockerfile`, `ENV`, or image layers.
- [ ] Specific immutable image tags used (no `latest`).
- [ ] Docker Content Trust enabled / images cryptographically signed.

### Container Runtime Hardening
- [ ] Container runs as an explicit non-root user (`USER` directive or `--user`).
- [ ] Root filesystem is read-only (`--read-only` / `read_only: true`).
- [ ] All Linux capabilities dropped (`--cap-drop=ALL`).
- [ ] Privilege escalation disabled (`--security-opt=no-new-privileges:true`).
- [ ] CPU, Memory, and PID limits enforced.
- [ ] Container ports bound to specific local IPs rather than open `0.0.0.0` where possible.
- [ ] `/var/run/docker.sock` is never mounted into untrusted containers.

### Host & Daemon Hardening
- [ ] Docker daemon updated to latest stable version with security patches.
- [ ] Rootless Docker evaluated and enabled where feasible.
- [ ] Unused images, containers, and volumes routinely pruned.
- [ ] Logging driver configured with size rotation to prevent disk exhaustion.

---

## References

- [Docker Security Overview](https://docs.docker.com/engine/security/)
- [CIS Docker Benchmark Guidelines](https://www.cisecurity.org/benchmark/docker)
- [Google Distroless Container Images](https://github.com/GoogleContainerTools/distroless)
- [Aqua Security Trivy Scanner](https://aquasecurity.github.io/trivy/)
- [Docker Engine Seccomp Profiles](https://docs.docker.com/engine/security/seccomp/)
