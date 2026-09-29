# 26 — Complete Docker Host Architecture: Containers, Networks, Storage & Compose

This module provides a unified architectural blueprint demonstrating how all the fundamental Docker subsystems—**Containers**, **Docker Engine**, **Bridge Networks**, **Named Volumes**, **Bind Mounts**, and **Docker Compose**—interlock on a single host.

---

## 1. Complete Docker Host Architecture Diagram

```
                       Docker Host
┌──────────────────────────────────────────────────┐
│                                                  │
│                  Docker Engine                   │
│                                                  │
│   ┌───────────┐      ┌───────────┐              │
│   │ Container │      │ Container │              │
│   │ Frontend  │─────►│ Backend   │              │
│   └─────┬─────┘      └─────┬─────┘              │
│         │                  │                    │
│         │              ┌───▼──────┐             │
│         │              │ Postgres │             │
│         │              └────┬─────┘             │
│         │                   │                    │
│         │              Named Volume              │
│         │                   │                    │
│   ┌─────▼───────────────────▼─────┐              │
│   │       Docker Network           │              │
│   └───────────────────────────────┘              │
│                                                  │
│   Bind Mount ─────► Host Source Code             │
│                                                  │
└──────────────────────────────────────────────────┘

             Docker Compose
                    │
                    ▼
          Manages all services
```

---

## Table of Contents

1. [Complete Docker Host Architecture Diagram](#1-complete-docker-host-architecture-diagram)
2. [Architectural Layer Breakdown](#2-architectural-layer-breakdown)
   - [The Docker Host](#the-docker-host)
   - [The Docker Engine](#the-docker-engine)
   - [Containers (Frontend, Backend, Database)](#containers-frontend-backend-database)
   - [Docker Network (Bridge & DNS Discovery)](#docker-network-bridge--dns-discovery)
   - [Storage Strategy: Named Volumes vs. Bind Mounts](#storage-strategy-named-volumes-vs-bind-mounts)
   - [Docker Compose Orchestration](#docker-compose-orchestration)
3. [Component Interplay & Request Lifecycle](#3-component-interplay--request-lifecycle)
4. [Complete Production-Grade `compose.yaml` Architecture](#4-complete-production-grade-composeyaml-architecture)
5. [Host File Hierarchy & Structure](#5-host-file-hierarchy--structure)
6. [Operational Commands & Life-Cycle Management](#6-operational-commands--life-cycle-management)
7. [Architecture Best Practices Checklist](#7-architecture-best-practices-checklist)

---

## 2. Architectural Layer Breakdown

### The Docker Host
- The physical bare-metal machine or virtual server (Linux, macOS, Windows) running the Docker daemon.
- Allocates CPU, RAM, disk partitions, and physical network adapters to the container subsystem.

---

### The Docker Engine
- The background daemon (`dockerd`) and runtime stack (`containerd` & `runc`) that coordinates processes, mounts filesystems, configures network bridges, and enforces resource guardrails.

---

### Containers (Frontend, Backend, Database)
- **Frontend Container**: Renders user interfaces, serves client bundles, or acts as an edge reverse proxy (e.g. NGINX, React/Vue app). Published to host ports (e.g., `80:80`).
- **Backend Container**: Business logic API server (e.g. Node.js, Python FastAPI, Go). Communicates with the database via internal container networking.
- **Postgres Database Container**: Stateful persistence engine listening on internal port `5432` without publishing ports to the host machine.

---

### Docker Network (Bridge & DNS Discovery)
- A private virtual bridge network connecting all containers.
- **Embedded DNS Server (`127.0.0.11`)**: Enables containers to discover and communicate with each other using service names (e.g., `http://backend:3000`, `postgres:5432`) without hardcoding volatile IP addresses.

---

### Storage Strategy: Named Volumes vs. Bind Mounts
1. **Named Volume (`pgdata`)**:
   - High-performance, Docker-managed persistent storage allocated at `/var/lib/docker/volumes/pgdata/_data`.
   - Decoupled from container lifecycles to ensure database data is preserved across container recreations.
2. **Bind Mount (`./src:/app/src`)**:
   - Maps host source code directly into the container.
   - Enables instant hot-reloading in local development environments.

---

### Docker Compose Orchestration
- Declarative tool that defines, builds, connects, and scales the multi-container stack with a single configuration file (`compose.yaml`).
- Automatically creates the shared bridge network, provisions named volumes, builds custom images, and boots services in dependency order.

---

## 3. Component Interplay & Request Lifecycle

```
1. Client Browser
       │ HTTP Request on http://localhost:80
       ▼
2. Host Port (80)
       │ Docker iptables NAT Forwarding
       ▼
3. Frontend Container (Port 80)
       │ Internal API call (http://backend:3000/api/users)
       │ Resolved via Docker Internal DNS
       ▼
4. Backend Container (Port 3000)
       │ Reads/Writes SQL query (postgres:5432)
       ▼
5. Postgres Database Container (Port 5432)
       │ Direct I/O Write
       ▼
6. Named Volume (`pgdata`) on Host Disk
```

---

## 4. Complete Production-Grade `compose.yaml` Architecture

Below is the complete implementation of the architectural blueprint:

```yaml
services:
  # ----------------------------------------------------
  # 1. Frontend Service (Web / Reverse Proxy)
  # ----------------------------------------------------
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    container_name: app_frontend
    restart: unless-stopped
    ports:
      # Published to host
      - "80:80"
    networks:
      - app_network
    depends_on:
      backend:
        condition: service_healthy
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ----------------------------------------------------
  # 2. Backend Service (API Server)
  # ----------------------------------------------------
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: app_backend
    restart: unless-stopped
    environment:
      NODE_ENV: production
      PORT: 3000
      DATABASE_URL: postgres://dbuser:${DB_PASSWORD}@postgres:5432/production_db
    volumes:
      # Optional bind mount for local development live-reload
      - ./backend/src:/app/src
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
    networks:
      - app_network
    depends_on:
      postgres:
        condition: service_healthy

  # ----------------------------------------------------
  # 3. Postgres Database Service (Stateful)
  # ----------------------------------------------------
  postgres:
    image: postgres:16-alpine
    container_name: app_postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: production_db
      POSTGRES_USER: dbuser
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      # Persistent named volume for Postgres data
      - pgdata:/var/lib/postgresql/data
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 1024M
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dbuser -d production_db"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    networks:
      - app_network
    # Notice: Database ports are NOT published to the host for security!

# ------------------------------------------------------
# Shared Bridge Network
# ------------------------------------------------------
networks:
  app_network:
    driver: bridge

# ------------------------------------------------------
# Named Volume Declarations
# ------------------------------------------------------
volumes:
  pgdata:
    driver: local
```

---

## 5. Host File Hierarchy & Structure

A standard directory layout reflecting this architecture:

```
my-application/
├── compose.yaml                # Master multi-container orchestration
├── .env                        # Environment secrets (DB_PASSWORD, etc.)
├── .dockerignore               # Ignores local node_modules, logs, .git
├── frontend/
│   ├── Dockerfile              # Multi-stage production NGINX build
│   └── src/                    # Frontend client code
└── backend/
    ├── Dockerfile              # Hardened non-root Node/Python build
    └── src/                    # Backend source code (bind-mounted in dev)
```

---

## 6. Operational Commands & Life-Cycle Management

```bash
# 1. Build images and start entire architecture in background
docker compose up -d --build

# 2. View running containers, status, and port bindings
docker compose ps

# 3. Stream consolidated logs across all containers
docker compose logs -f

# 4. Stream real-time resource utilization (CPU, RAM, Net I/O)
docker stats

# 5. Execute commands inside a running service
docker compose exec backend npm run migrate

# 6. Stop all containers preserving persistent named volumes
docker compose down

# 7. Stop all containers AND remove all named volumes (destructive!)
docker compose down -v
```

---

## 7. Architecture Best Practices Checklist

- [ ] **Unified Bridge Network**: Containers communicate by DNS service name (`backend`, `postgres`).
- [ ] **Port Security**: Only public entry points (Frontend/Proxy) publish host ports; database ports remain private.
- [ ] **Storage Separation**: Persistent database state stored in **Named Volumes**; source code in **Bind Mounts**.
- [ ] **Startup Synchronization**: `depends_on` configured with `condition: service_healthy` to avoid race conditions.
- [ ] **Resource Limits**: Memory and CPU guardrails defined under `deploy.resources`.
- [ ] **Log Rotation**: Size-capped logging drivers configured to prevent host disk exhaustion.

---

## References

- [Docker Architecture Overview](https://docs.docker.com/get-started/overview/#docker-architecture)
- [Docker Compose File Specification](https://docs.docker.com/compose/compose-file/)
- [Docker Networking in Compose](https://docs.docker.com/compose/networking/)
- [Manage Data in Docker](https://docs.docker.com/storage/)
