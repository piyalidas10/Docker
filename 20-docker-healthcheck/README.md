# 20 — Docker Healthchecks Deep Dive

A **Healthcheck** is a mechanism that allows Docker (and container orchestrators like Docker Swarm and Kubernetes) to determine whether the application process running inside a container is truly functioning correctly and ready to receive traffic—not merely that its main process (PID 1) is running.

---

## The Core Concept: Process Alive vs. Application Healthy

```
Without HEALTHCHECK:
┌──────────────────────────────────────────────┐
│  Container Status: "Up"                      │
│  PID 1 is running, but app is deadlocked,    │ ❌ Traffic routed to broken app!
│  out of DB connections, or crashing on /api  │
└──────────────────────────────────────────────┘

With HEALTHCHECK:
┌────────────────────────────────────────────────────────┐
│                      Application                       │
│                           │                            │
│                           ▼                            │
│                     Health Check                       │
│          (Periodic HTTP / script probe)                │
│                           │                            │
│            ┌──────────────┴──────────────┐             │
│            ▼                             ▼             │
│   Status: "healthy"             Status: "unhealthy"    │
│   ✅ Ready to serve traffic      ❌ Traffic blocked /   │
│                                    Container restarted │
└────────────────────────────────────────────────────────┘
```

---

## Table of Contents

1. [Why Are Healthchecks Important?](#1-why-are-healthchecks-important)
2. [Healthcheck States & Lifecycle](#2-healthcheck-states--lifecycle)
3. [Dockerfile `HEALTHCHECK` Instruction](#3-dockerfile-healthcheck-instruction)
4. [Healthchecks in Docker Compose](#4-healthchecks-in-docker-compose)
5. [Orchestrating Startup Order (`depends_on: condition: service_healthy`)](#5-orchestrating-startup-order-depends_on-condition-service_healthy)
6. [Common Healthcheck Probes & Patterns](#6-common-healthcheck-probes--patterns)
7. [Inspecting & Debugging Container Health](#7-inspecting--debugging-container-health)

---

## 1. Why Are Healthchecks Important?

A container process might be alive (reporting `Up (running)`), but the underlying application could be:
- Deadlocked or hung in an infinite loop.
- Unable to establish a connection to its database.
- Experiencing memory exhaustion.
- Still initializing and not yet ready to accept incoming user requests.

Docker Healthchecks solve this by periodically executing a probe command inside the container and tracking the exit code:
- `0`: **Success / Healthy** — The container is operational.
- `1`: **Unhealthy** — The container probe failed.
- `2`: **Reserved** — Do not use this exit status.

---

## 2. Healthcheck States & Lifecycle

A container with healthchecks moves through distinct health states:

```
            docker run
                │
                ▼
      ┌──────────────────┐
      │   starting       │ ◄─── During --start-period (probe failures do NOT
      └────────┬─────────┘      count against max retries)
               │
       Probe Returns 0 (Success)
               │
               ▼
      ┌──────────────────┐  Probe Returns 1 (> retries)  ┌──────────────────┐
      │    healthy       │ ─────────────────────────────► │    unhealthy     │
      └──────────────────┘ ◄───────────────────────────── └──────────────────┘
                            Probe Returns 0 (Recovery)
```

1. **`starting`**: Initial state while the container starts up and during the `start_period`.
2. **`healthy`**: The health probe command succeeded (returned exit code `0`).
3. **`unhealthy`**: The probe command consecutively failed more than the configured `retries` count.

---

## 3. Dockerfile `HEALTHCHECK` Instruction

You can define health monitoring directly in the `Dockerfile`.

### Syntax:
```dockerfile
HEALTHCHECK [OPTIONS] CMD <command>
```

### Options:
- `--interval=<duration>`: Frequency of probe execution (default: `30s`).
- `--timeout=<duration>`: Max time allowed for a single probe to finish (default: `30s`).
- `--start-period=<duration>`: Grace period for app initialization before failures count against retries (default: `0s`).
- `--retries=<number>`: Number of consecutive failures needed to mark container `unhealthy` (default: `3`).

### Example:
```dockerfile
FROM node:20-alpine

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .

EXPOSE 8000

# Probe health endpoint using curl
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl --fail http://localhost:8000/health || exit 1

CMD ["node", "server.js"]
```

> **Tip:** If using minimal base images like Alpine without `curl`, use `wget -qO-` or a small native script (e.g., Node/Python script):
> ```dockerfile
> HEALTHCHECK --interval=15s --timeout=3s \
>   CMD wget -qO- http://localhost:8000/health || exit 1
> ```

To disable an inherited healthcheck from a parent image:
```dockerfile
HEALTHCHECK NONE
```

---

## 4. Healthchecks in Docker Compose

In `compose.yaml`, healthchecks can be declared, customized, or overridden per service:

```yaml
services:
  web:
    image: my-web-app:1.0
    ports:
      - "8000:8000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    restart: unless-stopped
```

### Alternative `test` formats in Compose:
```yaml
# Exec form (recommended)
test: ["CMD", "curl", "-f", "http://localhost:8000/health"]

# Shell string form
test: "curl -f http://localhost:8000/health || exit 1"

# Disable healthcheck for this service
test: ["NONE"]
```

---

## 5. Orchestrating Startup Order (`depends_on: condition: service_healthy`)

By default, Docker Compose `depends_on` only waits for a dependent container to **start**, not for its application to become **ready**.

Using `service_healthy`, Compose waits for the database/service to pass its health check before starting downstream services:

```yaml
services:
  # Database service with PostgreSQL ready probe
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: appdb
      POSTGRES_PASSWORD: secretpassword
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d appdb"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

  # API service will NOT start until postgres is confirmed HEALTHY
  api:
    image: my-backend-api:1.0
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      DATABASE_URL: postgres://postgres:secretpassword@postgres:5432/appdb
    ports:
      - "8000:8000"
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
```

---

## 6. Common Healthcheck Probes & Patterns

### 1. HTTP Endpoint Probe (Web Apps & APIs)
```bash
# Using curl (-f / --fail returns non-zero for 4xx/5xx responses)
CMD curl -f http://localhost:8000/health || exit 1

# Using wget on Alpine Linux
CMD wget -qO- http://localhost:8000/health || exit 1
```

### 2. Database Probes

#### PostgreSQL:
```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U postgres"]
  interval: 10s
  timeout: 5s
  retries: 5
```

#### MySQL:
```yaml
healthcheck:
  test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
  interval: 10s
  timeout: 5s
  retries: 3
```

#### Redis:
```yaml
healthcheck:
  test: ["CMD", "redis-cli", "ping"]
  interval: 10s
  timeout: 3s
  retries: 3
```

### 3. TCP Port Probe (Without HTTP/tools)
```bash
# Check if internal port is listening using bash /dev/tcp
CMD bash -c "</dev/tcp/127.0.0.1/8000" || exit 1
```

---

## 7. Inspecting & Debugging Container Health

```bash
# 1. View health status in docker ps output (shows: (healthy), (unhealthy), or (health: starting))
docker ps

# 2. Extract specific health status
docker inspect --format '{{json .State.Health.Status}}' my-container

# 3. View detailed log history of recent health check probe outputs
docker inspect --format '{{json .State.Health}}' my-container | jq

# 4. View exit codes and probe error logs
docker inspect --format='{{range .State.Health.Log}}Exit: {{.ExitCode}} Output: {{.Output}}{{end}}' my-container
```

---

## References

- [Dockerfile HEALTHCHECK Reference](https://docs.docker.com/engine/reference/builder/#healthcheck)
- [Compose File Healthcheck Specification](https://docs.docker.com/compose/compose-file/05-services/#healthcheck)
- [Controlling Startup Order with service_healthy](https://docs.docker.com/compose/startup-order/)
