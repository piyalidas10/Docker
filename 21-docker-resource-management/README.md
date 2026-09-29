# 21 — Docker Resource Management & Limits

Resource management allows operators to enforce hard boundaries and soft reservations on the amount of **CPU**, **Memory (RAM)**, and **Disk I/O** individual containers can consume from the host operating system.

---

## Why Resource Limits Matter in Production

Without resource guardrails, a single misbehaved container (e.g. memory leak, runaway thread, or fork bomb) can exhaust host resources and starve all other containers and host OS daemons:

```
Without Limits (Resource Starvation):
┌────────────────────────────────────────────────────────┐
│                      Host System                       │
│                                                        │
│  ┌─────────────────────────┐  ┌─────────────────────┐  │
│  │ Container A (App)       │  │ Container B (DB)    │  │
│  │ Memory Leak consumes    │  │ Starved of Memory   │  │
│  │ 100% of host RAM & CPU  │  │ ❌ Killed by Host   │  │
│  │                         │  │    OOM Killer!      │  │
│  └─────────────────────────┘  └─────────────────────┘  │
└────────────────────────────────────────────────────────┘

With Limits & Reservations (Predictable Isolation):
┌────────────────────────────────────────────────────────┐
│                      Host System                       │
│                                                        │
│  ┌─────────────────────────┐  ┌─────────────────────┐  │
│  │ Container A (App)       │  │ Container B (DB)    │  │
│  │ Hard Limit: 512MB RAM   │  │ Guaranteed: 1GB RAM │  │
│  │ Max CPU: 1.0 Core       │  │ Max CPU: 2.0 Cores  │  │
│  │ ✅ Isolated boundary    │  │ ✅ Stable operation │  │
│  └─────────────────────────┘  └─────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

---

## Table of Contents

1. [Key Concepts](#1-key-concepts)
   - [Memory Limits (`--memory`)](#memory-limits---memory)
   - [Memory Reservations (`--memory-reservation`)](#memory-reservations---memory-reservation)
   - [OOM Killer Behavior (`--oom-kill-disable`)](#oom-killer-behavior---oom-kill-disable)
   - [CPU Limits (`--cpus`)](#cpu-limits---cpus)
   - [CPU Shares (`--cpu-shares`)](#cpu-shares---cpu-shares)
   - [CPU Pinning (`--cpuset-cpus`)](#cpu-pinning---cpuset-cpus)
2. [CLI Execution Examples](#2-cli-execution-examples)
3. [Resource Limits in Docker Compose](#3-resource-limits-in-docker-compose)
4. [Monitoring Resources: `docker stats`](#4-monitoring-resources-docker-stats)
5. [Under the Hood: Linux cgroups v1 & v2](#5-under-the-hood-linux-cgroups-v1--v2)
6. [Best Practices for Production Resource Sizing](#6-best-practices-for-production-resource-sizing)

---

## 1. Key Concepts

### Memory Limits (`--memory` / `-m`)
- **What it is**: The **hard upper limit** on the maximum amount of physical RAM the container can consume.
- **Behavior**: If the container process attempts to allocate memory beyond this limit, the Linux kernel Out-Of-Memory (OOM) killer immediately terminates the container process with **Exit Code 137**.
- **Units**: `b`, `k`, `m`, `g` (e.g., `512m`, `2g`). Minimum value is `6m`.

---

### Memory Reservations (`--memory-reservation`)
- **What it is**: A **soft limit** or guaranteed memory baseline.
- **Behavior**: Docker allows the container to use more memory than the reservation as long as the host has free RAM. When the host encounters memory contention, Docker forces containers back down to their reservation thresholds.

---

### OOM Killer Behavior (`--oom-kill-disable`)
- By default, when a container exceeds its memory limit, the Linux kernel Out-Of-Memory killer halts the process.
- **Flag**: `--oom-kill-disable` blocks the kernel from killing the container process when it runs out of memory (use with extreme caution, only with explicit `--memory` set).

---

### CPU Limits (`--cpus`)
- **What it is**: Guarantees the maximum number of CPU cores a container can use over a scheduling period (Completely Fair Scheduler - CFS quota).
- **Format**: Decimal float (e.g. `1.0` = 1 full CPU core, `0.5` = 50% of one core, `2.5` = two and a half cores).
- **Example**: On a 4-core machine, `--cpus=2.0` restricts the container to at most 50% of total host processing capacity.

---

### CPU Shares (`--cpu-shares` / `-c`)
- **What it is**: A **relative priority weight** (default: `1024`) used during CPU contention.
- **Behavior**: Unlike `--cpus` which sets a hard cap, CPU shares only take effect when multiple containers compete for CPU cycles:
  - Container A (`--cpu-shares=1024`) gets 2x more CPU time than Container B (`--cpu-shares=512`) during heavy load.
  - When Container A is idle, Container B can use 100% of the CPU.

---

### CPU Pinning (`--cpuset-cpus`)
- **What it is**: Restricts a container's execution to specific physical or logical CPU cores.
- **Example**: `--cpuset-cpus="0,1"` ensures the container only executes on CPU Core 0 and Core 1.

---

## 2. CLI Execution Examples

```bash
# 1. Basic memory and CPU hard limits
docker run -d \
  --name myapp \
  --memory=512m \
  --cpus=1.0 \
  myapp:1.0

# 2. Hard limit with soft memory reservation
docker run -d \
  --name api-server \
  --memory=1g \
  --memory-reservation=256m \
  --cpus=1.5 \
  myapp:1.0

# 3. Memory limit + Swap limit (Total virtual memory = memory + swap)
# Here: 512MB RAM + 512MB Swap = 1GB Total
docker run -d \
  --memory=512m \
  --memory-swap=1g \
  myapp:1.0

# 4. Disable Swap entirely (Memory Limit == Memory Swap)
docker run -d \
  --memory=512m \
  --memory-swap=512m \
  myapp:1.0

# 5. CPU priority weighting and CPU pinning
docker run -d \
  --name batch-worker \
  --cpu-shares=512 \
  --cpuset-cpus="2,3" \
  myapp:1.0

# 6. PID limit (Prevents fork bombs)
docker run -d \
  --name safe-app \
  --pids-limit=100 \
  myapp:1.0
```

---

## 3. Resource Limits in Docker Compose

In `compose.yaml`, resource constraints are defined under the `deploy.resources` block:

```yaml
services:
  api:
    image: my-api:1.0
    deploy:
      resources:
        # Hard upper limits (Container cannot exceed these)
        limits:
          cpus: "1.5"
          memory: 512M
          pids: 150
        # Soft reservations (Guaranteed minimum capacity)
        reservations:
          cpus: "0.5"
          memory: 128M

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: secret
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 2048M
        reservations:
          cpus: "1.0"
          memory: 512M
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:
```

---

## 4. Monitoring Resources: `docker stats`

The `docker stats` command streams real-time CPU, RAM, network I/O, and disk I/O metrics across all running containers:

```bash
# 1. Stream live resource usage for all running containers
docker stats

# Sample Output:
# CONTAINER ID   NAME     CPU %     MEM USAGE / LIMIT     MEM %     NET I/O          BLOCK I/O        PIDS
# a1b2c3d4e5f6   api      0.45%     142.3MiB / 512MiB     27.80%    1.2MB / 850kB    12.4MB / 0B      24
# f6e5d4c3b2a1   db       1.12%     310.8MiB / 2GiB       15.17%    850kB / 1.2MB    145MB / 2.1MB    38

# 2. Inspect a specific container
docker stats api

# 3. One-time snapshot (non-streaming, ideal for automated scripts)
docker stats --no-stream

# 4. Custom formatted output
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
```

---

## 5. Under the Hood: Linux cgroups v1 & v2

Docker enforces resource constraints through the Linux kernel **Control Groups (cgroups)** subsystem:

- **cgroups v1**: Separate hierarchies for each resource controller (`/sys/fs/cgroup/cpu`, `/sys/fs/cgroup/memory`).
- **cgroups v2**: Unified hierarchy providing accurate out-of-memory tracking and pressure stall information (PSI).

Inspect a container's applied kernel limits on the host:
```bash
# Inspect container memory limit via Docker CLI
docker inspect --format '{{.HostConfig.Memory}}' myapp

# Inspect kernel cgroup memory limit directly (Linux)
cat /sys/fs/cgroup/memory/docker/<container_id>/memory.limit_in_bytes
```

---

## 6. Best Practices for Production Resource Sizing

1. **Always Set Memory Hard Limits**: Uncapped containers invite cluster-wide OOM cascades.
2. **Set Reservations for Mission-Critical Workloads**: Ensure databases and message brokers have guaranteed physical RAM allocations.
3. **Prevent Swap Thrashing**: In latency-sensitive apps (e.g. Redis, Java JVMs), disable swap by setting `--memory-swap` equal to `--memory`.
4. **Set PID Limits (`--pids-limit`)**: Guard against process exhaustion attacks and recursive thread creation bugs.
5. **Monitor with Alerts**: Integrate monitoring agents (Prometheus cAdvisor, Datadog) to alert when memory usage exceeds 85% of limit.

---

## References

- [Docker Runtime Options: Resource Constraints](https://docs.docker.com/config/containers/resource_constraints/)
- [Docker stats CLI Reference](https://docs.docker.com/engine/reference/commandline/stats/)
- [Compose File Specification: Resources](https://docs.docker.com/compose/compose-file/deploy/#resources)
