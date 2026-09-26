# 09 — Production Patterns

Moving Docker workloads to production requires more than just `docker run`. This section covers the patterns, hardening techniques, and tooling that make containers production-ready.

---

## 1. Multi-Stage Builds (Lean Images)

Keep the final image as small as possible by separating build-time tools from runtime artefacts.

```dockerfile
# Stage 1 — build
FROM node:20 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2 — production image (no dev tools, no source)
FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
USER node                          # run as non-root
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

---

## 2. Run as Non-Root

By default containers run as `root`. Drop to a least-privilege user:

```dockerfile
# Create a system user and switch to it
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
```

Or use a pre-built non-root base image (e.g. `node:20-alpine` already includes the `node` user).

---

## 3. Read-Only Filesystem

Prevent container processes from writing to the filesystem (except explicitly mounted volumes):

```bash
docker run --read-only \
  --tmpfs /tmp \
  -v app-logs:/app/logs \
  my-image
```

```yaml
# compose.yaml
services:
  api:
    image: my-api
    read_only: true
    tmpfs:
      - /tmp
```

---

## 4. Resource Limits

Prevent a runaway container from starving the host:

```bash
docker run \
  --memory 512m \
  --cpus 1.0 \
  my-image
```

```yaml
# compose.yaml
services:
  api:
    image: my-api
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
        reservations:
          memory: 128M
```

---

## 5. Health Checks

Let Docker (and orchestrators) know when a container is truly ready:

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1
```

```yaml
# compose.yaml
healthcheck:
  test: ["CMD", "wget", "-qO-", "http://localhost:3000/health"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 10s
```

---

## 6. Restart Policies

```yaml
restart: unless-stopped    # restart on crash; stop manually
restart: always            # always restart, even after daemon restart
restart: on-failure        # restart only on non-zero exit
```

---

## 7. Secrets Management

Never bake secrets into images or environment variables that leak into `docker inspect`.

```bash
# Docker Swarm secrets
echo "s3cr3t" | docker secret create db_password -

# Reference in compose.yaml (Swarm mode)
services:
  api:
    secrets:
      - db_password
secrets:
  db_password:
    external: true
```

For non-Swarm, use a `.env` file or an external secrets store (Vault, AWS Secrets Manager, etc.), and mount secrets as files.

---

## 8. Logging

Configure a log driver to ship logs to a central system:

```yaml
services:
  api:
    image: my-api
    logging:
      driver: "json-file"        # default
      options:
        max-size: "10m"
        max-file: "5"
```

Other drivers: `syslog`, `journald`, `fluentd`, `awslogs`, `gelf`.

---

## 9. Image Tagging Strategy

| Tag | Example | Use |
|---|---|---|
| Semantic version | `my-app:1.4.2` | Production — unambiguous |
| Git SHA | `my-app:abc1234` | CI/CD traceability |
| `latest` | `my-app:latest` | Development only — avoid in prod |

---

## 10. Image Security Scanning

```bash
# Scan with Docker Scout
docker scout cves my-image:1.0

# Or use Trivy (open-source)
trivy image my-image:1.0
```

---

## Production Checklist

- [ ] Multi-stage build — no build tools in the final image
- [ ] Non-root `USER` set in Dockerfile
- [ ] No secrets in environment variables or image layers
- [ ] `HEALTHCHECK` defined
- [ ] Resource limits (`--memory`, `--cpus`) set
- [ ] Restart policy configured
- [ ] Log rotation / driver configured
- [ ] Image scanned for CVEs before deployment
- [ ] `.dockerignore` excludes dev files and secrets
- [ ] Minimal base image (Alpine or distroless)

---

## References

- [Docker security best practices](https://docs.docker.com/develop/security-best-practices/)
- [Multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
- [Docker Scout](https://docs.docker.com/scout/)
- [Trivy](https://aquasecurity.github.io/trivy/)
