# 13 — Docker Containers Deep Dive

A **Container** is a lightweight, isolated, runnable instance of a Docker image. It packages an application and all its runtime dependencies, running directly as an isolated process on the host operating system kernel.

---

## The Fundamental Distinction: Image vs. Container

```
┌─────────────────────────────────────────┐
│              Docker Image               │
│  (Read-Only Blueprint / Template / OCI) │
└────────────────────┬────────────────────┘
                     │
                     │  docker run / docker create
                     │
                     ▼
┌─────────────────────────────────────────┐
│            Docker Container             │
│  (Isolated, Running / Created Instance  │
│   with a Read-Write Container Layer)    │
└─────────────────────────────────────────┘
```

| Dimension | Image | Container |
|---|---|---|
| **State** | Static, immutable, read-only | Dynamic, stateful, active/stopped |
| **Storage** | Layered filesystem stored in image store | Read-only image layers + thin **Read-Write container layer** |
| **Execution** | Passive file on disk / registry | Active operating system process(es) |
| **Analogy** | Class definition / Executable file on disk | Instantiated object in memory / Running process |

---

## Table of Contents

1. [Container Core Concepts](#1-container-core-concepts)
   - [Container Creation](#container-creation)
   - [Container Lifecycle](#container-lifecycle)
   - [Running vs. Stopped Containers](#running-vs-stopped-containers)
   - [Container Filesystem (Copy-on-Write)](#container-filesystem-copy-on-write)
   - [Container Isolation (Namespaces & Cgroups)](#container-isolation-namespaces--cgroups)
   - [Container Processes](#container-processes)
   - [Container Logs](#container-logs)
   - [Container Metadata](#container-metadata)
   - [Container Ports & Port Mapping](#container-ports--port-mapping)
2. [Complete Command Reference](#2-complete-command-reference)
   - [`docker run`](#docker-run)
   - [`docker start`](#docker-start)
   - [`docker stop`](#docker-stop)
   - [`docker restart`](#docker-restart)
   - [`docker pause` & `docker unpause`](#docker-pause--docker-unpause)
   - [`docker rm`](#docker-rm)
   - [`docker ps` & `docker ps -a`](#docker-ps--docker-ps--a)
   - [`docker logs`](#docker-logs)
   - [`docker inspect`](#docker-inspect)
   - [`docker exec`](#docker-exec)
   - [`docker cp`](#docker-cp)
   - [`docker stats`](#docker-stats)
3. [Container Lifecycle State Diagram](#3-container-lifecycle-state-diagram)
4. [Hands-On Practice Workflow](#4-hands-on-practice-workflow)

---

## 1. Container Core Concepts

### Container Creation
When a container is created (`docker create` or `docker run`), Docker:
1. Pulls the specified image if it is not already available locally.
2. Allocates a thin **Read-Write layer** on top of the image's immutable read-only layers.
3. Sets up networking interfaces and assigns a private IP address from Docker's bridge network.
4. Initializes Linux namespaces and control groups (cgroups) for resource constraints and process isolation.

---

### Container Lifecycle
A container moves through distinct states:
- **Created**: Initialized, filesystem prepared, but process not yet started.
- **Running**: The primary process (PID 1) is actively executing.
- **Paused**: All processes frozen in place using the cgroups freezer subsystem (no CPU consumed).
- **Restarting**: In the middle of an automatic restart loop according to restart policies.
- **Exited / Stopped**: The main process exited or received `SIGTERM`/`SIGKILL`. Filesystem state remains preserved.
- **Dead**: An unrecoverable state (usually due to I/O lockup); ready to be removed.

---

### Running vs. Stopped Containers
- **Running Container**: Consumes host CPU, RAM, open file descriptors, network bandwidth, and disk space.
- **Stopped Container**: Process has terminated (PID 1 dead). It consumes **zero CPU and RAM**, but its writable disk layer and container configuration persist on host disk until explicitly deleted with `docker rm`.

---

### Container Filesystem (Copy-on-Write)
Docker uses a storage driver (e.g. `overlay2`) based on the **Copy-on-Write (CoW)** strategy:
- All underlying image layers are **read-only**.
- When a container modifies an existing file from the image, Docker copies the file up into the container's **Read-Write layer** before modifying it.
- When the container is deleted (`docker rm`), its writable layer is permanently discarded. Persistent data must be placed in **Volumes**.

```
┌───────────────────────────────────────────────┐
│     Container Writable Layer (Read-Write)     │  <-- Deleted on `docker rm`
├───────────────────────────────────────────────┤
│          Image Layer 3 (Read-Only)            │
├───────────────────────────────────────────────┤
│          Image Layer 2 (Read-Only)            │
├───────────────────────────────────────────────┤
│          Image Layer 1 (Read-Only)            │
└───────────────────────────────────────────────┘
```

---

### Container Isolation (Namespaces & Cgroups)
Containers achieve isolation without running a virtual machine through Linux kernel primitives:
1. **Linux Namespaces (What the container can SEE)**:
   - `pid`: Process tree isolation (container sees its main process as PID 1).
   - `net`: Isolated network devices, routing tables, port mappings.
   - `mnt`: Isolated filesystem mount points.
   - `ipc`: Inter-process communication and shared memory isolation.
   - `uts`: Independent hostname and domain name.
   - `user`: Maps container root UID 0 to an unprivileged UID on the host.
2. **Control Groups / Cgroups (How much the container can USE)**:
   - Limits and measures CPU, memory, disk I/O, and max process count.

---

### Container Processes
Every container must have exactly **one primary process** (PID 1 inside the container).
- If PID 1 terminates, the container immediately exits.
- PID 1 is responsible for reaping orphan zombie processes and handling termination signals (`SIGTERM`, `SIGINT`).

---

### Container Logs
Docker captures everything written by the container's PID 1 process to standard output (`stdout`) and standard error (`stderr`).
- These log streams are handled by the configured logging driver (default: `json-file`).
- You can inspect these streams anytime using `docker logs`.

---

### Container Metadata
Every container contains JSON-formatted metadata detailing:
- Container ID, creation time, state history, and exit codes.
- Network settings (IP address, MAC address, gateway, open ports).
- Mounted volumes and host bind mounts.
- Environment variables and resource limits.
- Retrieve full metadata with `docker inspect <container_id>`.

---

### Container Ports & Port Mapping
Containers run in isolated network namespaces. By default, processes listening on ports inside the container are unreachable from the outside host network.

- **Port Mapping (`-p host_port:container_port`)**:
  Instructs Docker to create a NAT routing rule (via `iptables`) forwarding traffic from the host machine to the container's internal port.
  ```bash
  # Map host port 8080 to container port 80
  docker run -d -p 8080:80 nginx
  ```
- **Random Port Allocation (`-P`)**:
  Publishes all ports exposed by `EXPOSE` in the Dockerfile to random high-numbered ports on the host.

---

## 2. Complete Command Reference

### `docker run`
Creates and starts a new container from an image in one atomic step.

```bash
# Basic run
docker run nginx

# Detached mode (background) with custom name and port mapping
docker run -d --name web-server -p 8080:80 nginx

# Interactive terminal (foreground) with auto-removal on exit
docker run -it --rm alpine sh

# Run with environment variables and memory limits
docker run -d \
  --name my-api \
  --memory 512m \
  -e NODE_ENV=production \
  -p 3000:3000 \
  node:20-alpine
```

**Common Flags:**
- `-d` / `--detach`: Run container in background and print container ID.
- `-it`: Keep STDIN open (`-i`) and allocate a pseudo-TTY (`-t`).
- `--name <name>`: Assign a custom name to the container.
- `-p <host_port>:<container_port>`: Publish/forward container port to host.
- `--rm`: Automatically remove the container when it exits.
- `-e <KEY>=<VAL>`: Set an environment variable.
- `-v <host_path>:<container_path>`: Mount a volume or bind mount.
- `--restart <policy>`: Set restart policy (`no`, `always`, `unless-stopped`, `on-failure`).

---

### `docker start`
Starts one or more already created or stopped containers without recreating them.

```bash
# Start a stopped container
docker start web-server

# Start and attach terminal
docker start -a -i my-interactive-container
```

---

### `docker stop`
Gracefully stops a running container. Docker sends a `SIGTERM` signal to PID 1, waits for a grace period (default 10 seconds), and sends `SIGKILL` if the container has not stopped.

```bash
# Graceful stop (10s timeout)
docker stop web-server

# Stop with custom timeout of 30 seconds
docker stop -t 30 web-server
```

---

### `docker restart`
Stops and then starts a container (`docker stop` followed by `docker start`).

```bash
docker restart web-server
```

---

### `docker pause` & `docker unpause`
Freezes and unfreezes all processes in a container using the Linux cgroups freezer subsystem.

```bash
# Pause container (zero CPU consumed, memory retained)
docker pause web-server

# Resume container execution
docker unpause web-server
```

---

### `docker rm`
Deletes one or more stopped containers, purging their writable layer from the host filesystem.

```bash
# Remove a stopped container
docker rm web-server

# Force-remove a running container (sends SIGKILL first)
docker rm -f web-server

# Remove all stopped containers in one command
docker container prune -f
```

---

### `docker ps` & `docker ps -a`
Lists containers running or present on the system.

```bash
# List only currently RUNNING containers
docker ps

# List ALL containers (running, stopped, created, exited)
docker ps -a

# Output only container IDs (useful for scripting)
docker ps -aq

# Format output using custom Go template
docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
```

---

### `docker logs`
Fetches stdout and stderr logs emitted by the container's primary process.

```bash
# View all existing logs
docker logs web-server

# Stream live log output in real-time (like tail -f)
docker logs -f web-server

# View the last 50 lines with timestamps
docker logs --tail 50 -t web-server
```

---

### `docker inspect`
Returns low-level configuration and runtime details in JSON format.

```bash
# View entire JSON metadata object
docker inspect web-server

# Extract container IP address
docker inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' web-server

# Extract current health check status
docker inspect --format '{{.State.Health.Status}}' web-server

# Extract container exit code
docker inspect --format '{{.State.ExitCode}}' web-server
```

---

### `docker exec`
Executes a new command or starts a sub-shell inside an already running container.

```bash
# Open an interactive Bash/Sh shell inside a running container
docker exec -it web-server sh

# Run a one-off command without opening a shell
docker exec web-server nginx -t

# Run a command as root inside a non-root container (debugging)
docker exec -u 0 -it web-server whoami
```

---

### `docker cp`
Copies files and directories between the host filesystem and a container. Works for both running and stopped containers.

```bash
# Copy file from host into container
docker cp ./custom-nginx.conf web-server:/etc/nginx/nginx.conf

# Copy file from container out to host
docker cp web-server:/var/log/nginx/access.log ./host-access.log
```

---

### `docker stats`
Streams live resource usage metrics (CPU percentage, memory usage, memory limit, network I/O, block I/O, PIDs) for all running containers.

```bash
# Stream live metrics for all running containers
docker stats

# Stream metrics for a specific container
docker stats web-server

# Show one-time snapshot without streaming
docker stats --no-stream
```

---

## 3. Container Lifecycle State Diagram

```
                 docker create
                      │
                      ▼
               ┌─────────────┐
        ┌─────►│   CREATED   │
        │      └──────┬──────┘
        │             │ docker start / docker run
        │             ▼
        │      ┌─────────────┐   docker pause     ┌─────────────┐
        │      │   RUNNING   │ ─────────────────► │   PAUSED    │
        │      │   (PID 1)   │ ◄───────────────── │  (freezer)  │
        │      └──────┬──────┘   docker unpause   └─────────────┘
        │             │
        │   docker    │ process exits / docker stop / docker kill
        │  restart    ▼
        │      ┌─────────────┐
        └──────┤   STOPPED   │
               │  (EXITED)   │
               └──────┬──────┘
                      │ docker rm
                      ▼
               ┌─────────────┐
               │   DELETED   │
               └─────────────┘
```

---

## 4. Hands-On Practice Workflow

Run through this complete workflow to master container management:

```bash
# 1. Run an NGINX container in the background
docker run -d --name my-nginx -p 8080:80 nginx:alpine

# 2. Check running container status
docker ps

# 3. Stream real-time logs
docker logs -f my-nginx &

# 4. Check resource utilization
docker stats --no-stream my-nginx

# 5. Execute commands inside the container
docker exec -it my-nginx ls -la /usr/share/nginx/html

# 6. Copy a custom index page into the container
echo "<h1>Hello from Docker Container!</h1>" > index.html
docker cp index.html my-nginx:/usr/share/nginx/html/index.html

# 7. Pause and unpause the container
docker pause my-nginx
docker unpause my-nginx

# 8. Stop the container
docker stop my-nginx

# 9. Verify it appears in stopped containers list
docker ps -a

# 10. Clean up container and local test file
docker rm my-nginx
rm index.html
```

---

## References

- [Docker run reference documentation](https://docs.docker.com/engine/reference/commandline/run/)
- [Docker container commands CLI reference](https://docs.docker.com/engine/reference/commandline/container/)
- [Understanding Docker storage drivers and Copy-on-Write](https://docs.docker.com/storage/storagedriver/)
- [Linux Namespaces and Cgroups overview](https://man7.org/linux/man-pages/man7/namespaces.7.html)
