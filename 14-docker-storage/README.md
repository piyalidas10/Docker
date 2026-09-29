# 14 — Docker Storage Deep Dive

Managing storage is a critical aspect of running real-world applications in Docker. Containers are **ephemeral** by default, meaning any data written to a container's default filesystem is lost when the container is removed. Docker provides dedicated storage mechanisms to manage persistent and temporary state.

---

## The Default Problem: Container Ephemeral Filesystem

```
┌──────────────────────────────────────────────┐
│                  Container                   │
│  ┌────────────────────────────────────────┐  │
│  │ Writable Container Layer (Read-Write)  │  │ ──► Data written here
│  ├────────────────────────────────────────┤  │
│  │     Image Layers (Read-Only)           │  │
│  └────────────────────────────────────────┘  │
└──────────────────────┬───────────────────────┘
                       │
                       │  docker rm <container>
                       ▼
┌──────────────────────────────────────────────┐
│           CONTAINER REMOVED                  │
│   ❌ ALL DATA IN WRITABLE LAYER LOST!         │
└──────────────────────────────────────────────┘
```

By default:
1. Every container has an isolated, writable layer on top of its read-only image layers.
2. Changes are stored inside this writable layer using a Copy-on-Write (CoW) storage driver (e.g., `overlay2`).
3. **When the container is stopped and removed (`docker rm`), this writable layer is completely deleted.**
4. Writable layers are tightly coupled to the host and offer lower I/O performance compared to direct volume mounts.

To persist data, share files with the host, or optimize memory-only writes, Docker provides **Volumes**, **Bind Mounts**, and **tmpfs Mounts**.

---

## Table of Contents

1. [Docker Storage Architecture Overview](#1-docker-storage-architecture-overview)
2. [Docker Named Volumes](#2-docker-named-volumes)
3. [Docker Anonymous Volumes](#3-docker-anonymous-volumes)
4. [Bind Mounts](#4-bind-mounts)
5. [tmpfs Mounts (In-Memory Storage)](#5-tmpfs-mounts-in-memory-storage)
6. [Side-by-Side Comparison & When to Use What](#6-side-by-side-comparison--when-to-use-what)
7. [Storage in Docker Compose](#7-storage-in-docker-compose)
8. [Volume Management Commands Cheat Sheet](#8-volume-management-commands-cheat-sheet)

---

## 1. Docker Storage Architecture Overview

```
                      ┌──────────────────────────────────────────────┐
                      │                  Host Machine                │
                      │                                              │
                      │  ┌────────────────────────────────────────┐  │
                      │  │ Docker Managed Area:                   │  │
                      │  │ /var/lib/docker/volumes/               │  │
                      │  │ (Named & Anonymous Volumes)            │  │
                      │  └───────────────────┬────────────────────┘  │
                      │                      │                       │
                      │  ┌───────────────────┼────────────────────┐  │
                      │  │ Host File System: │                    │  │
                      │  │ /home/user/app    │ (Bind Mounts)      │  │
                      │  └───────────────────┼────────────────────┘  │
                      │                      │                       │
                      │  ┌───────────────────┼────────────────────┐  │
                      │  │ Host System RAM:  │ (tmpfs Mounts)     │  │
                      │  └───────────────────┼────────────────────┘  │
                      └──────────────────────┼───────────────────────┘
                                             │
                                             ▼
                               ┌───────────────────────────┐
                               │         Container         │
                               │   Filesystem Mount Point  │
                               └───────────────────────────┘
```

---

## 2. Docker Named Volumes

**Named Volumes** are explicitly named persistent storage areas managed entirely by Docker on the host filesystem (located at `/var/lib/docker/volumes/<volume_name>/_data` on Linux).

### Key Characteristics:
- **Lifecycle is independent of containers**: Deleting the container leaves the volume and all its data intact.
- **Managed by Docker**: You do not need to worry about host directory paths or OS permissions.
- **Safe for concurrent sharing**: Multiple containers can read/write to the same named volume simultaneously.
- **High Performance**: Native I/O performance without Copy-on-Write translation overhead.

### Step-by-Step Usage:

```bash
# 1. Create a named volume explicitly
docker volume create postgres-data

# 2. Inspect volume details and host storage location
docker volume inspect postgres-data

# 3. Run a container attaching the named volume
docker run -d \
  --name db-server \
  -e POSTGRES_PASSWORD=mysecretpassword \
  -v postgres-data:/var/lib/postgresql/data \
  postgres:16-alpine

# 4. Remove the container
docker stop db-server
docker rm db-server

# 5. Start a new container reusing the EXACT SAME volume (zero data loss)
docker run -d \
  --name new-db-server \
  -e POSTGRES_PASSWORD=mysecretpassword \
  -v postgres-data:/var/lib/postgresql/data \
  postgres:16-alpine
```

### Modern `--mount` Syntax:
```bash
docker run -d \
  --name db-server \
  --mount type=volume,source=postgres-data,target=/var/lib/postgresql/data \
  postgres:16-alpine
```

---

## 3. Docker Anonymous Volumes

An **Anonymous Volume** is created without providing a custom name. Docker generates a random 64-character hash as its identifier (e.g. `4f8c2b1e9...`).

### How Anonymous Volumes Are Created:
1. **Via CLI (`-v <container_path>` without a host source)**:
   ```bash
   docker run -d \
     --name temp-db \
     -v /var/lib/postgresql/data \
     postgres:16-alpine
   ```
2. **Via Dockerfile `VOLUME` Instruction**:
   ```dockerfile
   VOLUME ["/var/lib/postgresql/data"]
   ```

### Behavior & Gotchas:
- Docker creates a new random volume directory in `/var/lib/docker/volumes/` on each run.
- When the container is removed with `docker rm -v <container_name>`, the anonymous volume is deleted.
- **Gotcha**: If removed without `-v`, the anonymous volume remains on disk, creating **orphaned storage leaks**.
- To purge orphaned anonymous volumes:
  ```bash
  docker volume prune -f
  ```

### When to Use Anonymous Volumes:
- To bypass the container writable layer for high-write temporary files without polluting host directories.
- To prevent sub-directories from being overridden when using bind mounts (e.g., preserving `/app/node_modules`).

---

## 4. Bind Mounts

A **Bind Mount** directly maps an exact file or directory path from the host machine into a specific path inside the container.

### Key Characteristics:
- **Host dependent**: Relies on the exact host directory structure and OS file permissions.
- **Bi-directional Live Synchronization**: Modifying a file on the host immediately updates the container, and vice-versa.
- **Not managed by Docker**: Docker will not back up or manage lifecycle for bind mounts.

### Common Usage Example: Local Development with Live Reload

```bash
# Mount current working directory src folder into container
docker run -it --rm \
  --name dev-node \
  -p 3000:3000 \
  -v "$(pwd)/src:/app/src" \
  node:20-alpine sh
```

### Modern `--mount` Syntax for Bind Mounts:
```bash
docker run -d \
  --name web-proxy \
  --mount type=bind,source=/etc/nginx/nginx.conf,target=/etc/nginx/nginx.conf,readonly \
  -p 80:80 \
  nginx:alpine
```

### The Node Modules Masking Pattern (Bind Mount + Anonymous Volume)
When bind-mounting a local project into a container, local files might overwrite `node_modules` inside the container. You can protect it using an anonymous volume:

```bash
docker run -d \
  -p 3000:3000 \
  -v "$(pwd):/app" \
  -v /app/node_modules \
  my-node-app
```
*Here, `-v /app/node_modules` creates an anonymous volume that overlays the host's bind mount, preventing the host from shadowing the container's installed modules.*

---

## 5. tmpfs Mounts (In-Memory Storage)

A **tmpfs Mount** stores data directly in the **host system's volatile RAM (memory)** instead of writing to disk.

### Key Characteristics:
- **Zero Disk Writes**: Files exist purely in RAM.
- **Security**: Data is never persisted to non-volatile host disk or container writable layers.
- **Ultra-Fast Performance**: Bypasses filesystem drivers entirely; reads/writes operate at memory speed.
- **Wiped on Container Stop**: When the container stops, the tmpfs mount is wiped clean.

### Usage Example:

```bash
# Mount a 64MB memory tmpfs partition to /tmp
docker run -d \
  --name secure-app \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  my-secure-image
```

### Modern `--mount` Syntax:
```bash
docker run -d \
  --name secure-app \
  --mount type=tmpfs,target=/app/cache,tmpfs-size=128m \
  my-secure-image
```

---

## 6. Side-by-Side Comparison & When to Use What

| Feature | Named Volume | Anonymous Volume | Bind Mount | tmpfs Mount |
|---|---|---|---|---|
| **Storage Location** | `/var/lib/docker/volumes/<name>` | `/var/lib/docker/volumes/<hash>` | Arbitrary Host Path (e.g. `./src`) | Host RAM Memory |
| **Persistence** | **Permanent** (survives container removal) | Survives until pruned or removed | **Permanent** on host | **Ephemeral** (lost on container stop) |
| **Managed by** | Docker Engine | Docker Engine | User / Host OS | Host Linux Kernel |
| **Portability** | High (works identically on Mac/Win/Linux) | High | Low (depends on host paths) | Linux host only |
| **Sharing** | Excellent (multiple containers) | Hard to reference | Excellent | Cannot share across containers |
| **Performance** | High Native Disk I/O | High Native Disk I/O | Host filesystem dependent | Maximum (RAM bus speed) |

### When to Use Each:

```
┌───────────────────────────────────────────────┐
│              What are you storing?            │
└───────────────────────┬───────────────────────┘
                        │
      ┌─────────────────┼─────────────────┐
      │                 │                 │
      ▼                 ▼                 ▼
Stateful Data      Source Code       Sensitive State /
(Databases/Files)  (Dev Hot-Reload)  Ephemeral Caches
      │                 │                 │
      ▼                 ▼                 ▼
[ Named Volume ]  [ Bind Mount ]      [ tmpfs Mount ]
```

1. **Use Named Volumes when**:
   - Running databases (PostgreSQL, MySQL, Redis, MongoDB).
   - Storing user uploads or persistent application media.
   - Sharing persistent data across multiple containers.
   - Running in production environments.

2. **Use Bind Mounts when**:
   - Developing locally and needing source code live-reload.
   - Injecting host configuration files (`nginx.conf`, `redis.conf`) as read-only (`:ro`).
   - Mounting host SSL/TLS certificates or socket files (`/var/run/docker.sock`).

3. **Use Anonymous Volumes when**:
   - Preventing specific subfolders (like `/app/node_modules`) from being overwritten by a host bind mount.
   - Discardable write operations that need to bypass Copy-on-Write performance overhead.

4. **Use tmpfs Mounts when**:
   - Storing sensitive temporary tokens, private keys, or credentials that must not touch disk.
   - Running high-throughput scratchpads or transient session caches.

---

## 7. Storage in Docker Compose

Docker Compose makes defining and orchestrating storage declarative and readable.

```yaml
services:
  # Web App with Bind Mount for dev & tmpfs for cache
  web:
    image: node:20-alpine
    working_dir: /app
    ports:
      - "3000:3000"
    volumes:
      # 1. Bind mount for live code reload
      - ./src:/app/src
      # 2. Anonymous volume to preserve container node_modules
      - /app/node_modules
      # 3. Named volume for uploaded media files
      - user_uploads:/app/uploads
    tmpfs:
      # 4. tmpfs mount in RAM for session cache
      - /tmp:size=64M

  # Database using a Named Volume for permanent persistence
  database:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: mydb
      POSTGRES_PASSWORD: secretpassword
    volumes:
      # Named volume attached to Postgres data directory
      - db_data:/var/lib/postgresql/data

# Top-level volume declaration (creates managed named volumes)
volumes:
  db_data:
  user_uploads:
```

---

## 8. Volume Management Commands Cheat Sheet

```bash
# Create a named volume
docker volume create my-vol

# List all volumes on the host
docker volume ls

# Inspect volume metadata (driver, mountpoint on host)
docker volume inspect my-vol

# Remove a specific unused volume
docker volume rm my-vol

# Remove ALL unused (unattached) volumes (frees disk space)
docker volume prune -f

# Backup a named volume to a tarball on the host
docker run --rm \
  -v my-vol:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/my-vol-backup.tar.gz -C /data .

# Restore a tarball into a named volume
docker run --rm \
  -v my-vol:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/my-vol-backup.tar.gz -C /data
```

---

## References

- [Docker Storage Overview](https://docs.docker.com/storage/)
- [Use Volumes Documentation](https://docs.docker.com/storage/volumes/)
- [Use Bind Mounts Documentation](https://docs.docker.com/storage/bind-mounts/)
- [Use tmpfs Mounts Documentation](https://docs.docker.com/storage/tmpfs/)
