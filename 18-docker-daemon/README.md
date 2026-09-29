# 18 — Docker Daemon (`dockerd`): Architecture, Operations & Production Role

The **Docker Daemon** (`dockerd`) is the core, long-running background service that manages the entire lifecycle of Docker containers, images, networks, storage volumes, and runtime security on a host.

---

## 1. High-Level Daemon Architecture

The Docker ecosystem uses a decoupled, client–server architecture where the Docker CLI interacts with `dockerd` over a REST API, and `dockerd` interacts with lower-level container runtime layers (`containerd` & `runc`).

```
┌────────────────────────────────────────────────────────────────────────┐
│                              Docker Client                             │
│                  (docker CLI / Docker Compose / SDKs)                  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    │ REST API over:
                                    │ • Unix Socket: /var/run/docker.sock
                                    │ • TCP Socket:  tcp://0.0.0.0:2376
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        Docker Daemon (`dockerd`)                       │
│                                                                        │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                        Engine Subsystems                       │   │
│   │  • Image Management (Layers, Manifests, Storage Drivers)       │   │
│   │  • Network Driver (bridge, host, overlay, macvlan)             │   │
│   │  • Volume Driver (local, cloud plugins, NFS)                   │   │
│   │  • Security & Auth (TLS, Seccomp, AppArmor, AuthZ plugins)     │   │
│   │  • Build Engine (BuildKit)                                     │   │
│   │  • Logging Drivers (json-file, syslog, fluentd, awslogs)       │   │
│   └────────────────────────────────┬───────────────────────────────┘   │
└────────────────────────────────────┼───────────────────────────────────┘
                                     │ gRPC API
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                               containerd                               │
│                   (OCI Container Lifecycle Manager)                    │
│                                    │
│                 ┌──────────────────┴──────────────────┐
│                 ▼                                     ▼
│       containerd-shim-runc-v2               containerd-shim-runc-v2
│                 │                                     │
│                 ▼                                     ▼
│               runc                                  runc
│     (OCI Runtime CLI / fork)              (OCI Runtime CLI / fork)
│                 │                                     │
│                 ▼                                     ▼
│      ┌─────────────────────┐               ┌─────────────────────┐
│      │  Container Process  │               │  Container Process  │
│      │   (App A / PID 1)   │               │   (App B / PID 1)   │
│      └─────────────────────┘               └─────────────────────┘
└────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                           Host Linux Kernel                            │
│           (Namespaces, Control Groups - cgroups, iptables, eBPF)       │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Table of Contents

1. [High-Level Daemon Architecture](#1-high-level-daemon-architecture)
2. [Introduction: What is the Docker Daemon?](#2-introduction-what-is-the-docker-daemon)
3. [Component Breakdown: dockerd vs containerd vs runc](#3-component-breakdown-dockerd-vs-containerd-vs-runc)
4. [Why Do We Need the Docker Daemon?](#4-why-do-we-need-the-docker-daemon)
5. [How the Daemon Works in Production](#5-how-the-daemon-works-in-production)
6. [Configuring the Production Daemon (`daemon.json`)](#6-configuring-the-production-daemon-daemonjson)
7. [Daemon Management & Troubleshooting Commands](#7-daemon-management--troubleshooting-commands)
8. [Production Daemon Hardening Checklist](#8-production-daemon-hardening-checklist)

---

## 2. Introduction: What is the Docker Daemon?

The **Docker Daemon (`dockerd`)** is a persistent background process running on the host system. It listens for Docker API requests and performs the heavy lifting required to build, run, distribute, and orchestrate containers.

### Key Responsibilities of `dockerd`:
- **API Server**: Listens for HTTP REST commands sent via Unix sockets or secure TCP connections.
- **Image Lifecycle**: Pulls, unpacks, verifies, and stores layered filesystem images from remote registries.
- **Container Lifecycle**: Creates, executes, pauses, monitors, and stops containers.
- **Storage Subsystem**: Manages storage drivers (`overlay2`), copy-on-write image layers, and named persistent volumes.
- **Network Subsystem**: Configures Linux bridge devices (`docker0`), allocates virtual ethernet pairs (`veth`), and programs `iptables` NAT routing rules.
- **Resource Management**: Integrates with host kernel `cgroups` to enforce CPU, RAM, and I/O quotas.

---

## 3. Component Breakdown: `dockerd` vs `containerd` vs `runc`

Modern Docker is split into modular components adhering to Open Container Initiative (OCI) standards:

| Component | Role | Description |
|---|---|---|
| **`dockerd`** | High-Level Engine | Handles user-facing API, CLI commands, image building (BuildKit), volume management, user authentication, and high-level networking. |
| **`containerd`** | Core Container Supervisor | Industry-standard runtime daemon managing image transfer, container execution, process monitoring, and snapshot storage. (Also used directly by Kubernetes). |
| **`containerd-shim`** | Process Decoupler | A lightweight daemon that stays attached to the container process. Allows daemon restarts/crashes without killing running containers (**Live Restore**). |
| **`runc`** | Low-Level OCI Runtime | CLI tool that talks directly to the Linux kernel to create namespaces, configure cgroups, and spawn the container process before exiting. |

---

## 4. Why Do We Need the Docker Daemon?

Without a centralized daemon, managing container workloads on Linux would require manual kernel-level administration:

```
Manual (Without Daemon):
Raw Kernel Syscalls + clone() + unshare() + manual cgroup v2 mounts + custom iptables rules + manual overlayfs mounts

With Docker Daemon:
docker run -d -p 80:80 --memory 512m nginx
```

### Core Problems Solved by the Daemon:

1. **Abstraction over Complex Kernel Features**:
   - Manages namespaces (`pid`, `net`, `mnt`, `ipc`, `uts`, `user`) and cgroups automatically without requiring low-level C syscalls or manual mount commands.
2. **Centralized Resource Governance**:
   - Prevents noisy-neighbor starvation by dynamically orchestrating CPU shares, memory swap limits, and block I/O.
3. **Automated Dynamic Networking & Routing**:
   - Manages virtual bridges, dynamically assigns IPs to containers from private subnets, and updates `iptables` for port mapping.
4. **Storage Layering & Image Distribution**:
   - Handles multi-layer union filesystems (`overlay2`), caching, and content-addressable checksum verification when pulling from registries.
5. **Declarative State & Self-Healing**:
   - Continuously evaluates container health checks and automatically restarts crashed services according to restart policies.

---

## 5. How the Daemon Helps in Production

In enterprise production deployments, the Docker Daemon provides the operational backbone for reliability, observability, and security:

### 1. High Availability via "Live Restore"
In production, you often need to upgrade or restart the Docker daemon without disrupting running client traffic. With `live-restore` enabled, `containerd-shim` keeps containers running even while `dockerd` is stopped or being updated.

### 2. Centralized Log Ingestion
The daemon intercepts standard output/error from all containers and ships them directly to centralized log platforms (AWS CloudWatch, Fluentd, Syslog, Datadog) using built-in logging drivers.

### 3. Automated Storage & Volume Orchestration
Integrates with enterprise storage drivers and cloud plugins (AWS EBS, NFS, Ceph) to mount resilient storage into stateful containers.

### 4. Enterprise Security Controls
- **TLS Authentication**: Authenticates external CI/CD or orchestrator connections.
- **Seccomp / AppArmor Default Enforcements**: Restricts dangerous kernel system calls globally.
- **Rootless Execution**: Allows running `dockerd` without root privileges on the host OS.

### 5. Automated Health Monitoring & Self-Healing
If a production container fails its internal `HEALTHCHECK` or crashes due to an unhandled exception, `dockerd` triggers automatic restarts (`restart: always` or `unless-stopped`).

---

## 6. Configuring the Production Daemon (`daemon.json`)

The Docker Daemon is configured globally via `/etc/docker/daemon.json`. Below is a hardened, production-ready configuration:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "no-new-privileges": true,
  "icc": false,
  "userland-proxy": false,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  },
  "features": {
    "buildkit": true
  },
  "tls": true,
  "tlsverify": true,
  "tlscacert": "/etc/docker/certs/ca.pem",
  "tlscert": "/etc/docker/certs/server-cert.pem",
  "tlskey": "/etc/docker/certs/server-key.pem",
  "hosts": [
    "unix:///var/run/docker.sock",
    "tcp://0.0.0.0:2376"
  ]
}
```

### Configuration Parameters Explained:

- **`live-restore: true`**: Keeps containers alive during daemon downtime, maintenance, or upgrades.
- **`log-opts`**: Prevents disk exhaustion by capping container log files at 50MB with a maximum of 5 rotated files.
- **`icc: false`**: Disables inter-container communication on the default bridge network for network isolation.
- **`no-new-privileges: true`**: Prevents processes inside containers from gaining additional privileges via `setuid` binaries.
- **`userland-proxy: false`**: Replaces the userland proxy with native kernel `iptables` routing for lower latency and better throughput.
- **`default-ulimits`**: Increases open file descriptor limits for high-concurrency production workloads.

---

## 7. Daemon Management & Troubleshooting Commands

### Managing the Daemon Service:
```bash
# Check daemon status
sudo systemctl status docker

# Start / Stop / Restart daemon
sudo systemctl start docker
sudo systemctl restart docker
sudo systemctl stop docker

# Reload daemon configuration without restarting running containers
sudo systemctl reload docker
```

### Inspecting Daemon Info & Diagnostics:
```bash
# View comprehensive daemon configuration and runtime metrics
docker info

# View system-wide disk space usage (images, containers, volumes, build cache)
docker system df

# View real-time daemon events stream
docker events

# Inspect daemon logs on Linux (systemd journal)
sudo journalctl -u docker.service --since "1 hour ago" -f
```

### Routine Production Maintenance:
```bash
# Clean up dangling images, stopped containers, and unused build caches
docker system prune -f

# Deep cleanup including unused persistent volumes (use with caution!)
docker system prune -a --volumes
```

---

## 8. Production Daemon Hardening Checklist

- [ ] **Live Restore Enabled**: `"live-restore": true` is configured in `/etc/docker/daemon.json`.
- [ ] **Log Rotation Enforced**: Global `max-size` and `max-file` log limits defined to protect host root partitions.
- [ ] **Privilege Escalation Blocked**: `"no-new-privileges": true` enabled.
- [ ] **Inter-Container Communication (ICC) Disabled**: Set `"icc": false` on default bridge network.
- [ ] **Remote Daemon Encrypted**: Mutual TLS (`tlsverify: true`) enabled for any TCP socket listeners.
- [ ] **Default Storage Driver**: Verified using `overlay2`.
- [ ] **File Descriptor Quotas**: Configured sufficient `nofile` ulimits for high-load workloads.
- [ ] **Storage Monitoring**: Automated host alerts for `/var/lib/docker/` partition usage (>80%).

---

## References

- [Docker Daemon Reference (`dockerd`)](https://docs.docker.com/engine/reference/commandline/dockerd/)
- [Configure the Docker Daemon (`daemon.json`)](https://docs.docker.com/engine/reference/commandline/dockerd/#daemon-configuration-file)
- [Live Restore for Production Zero-Downtime Daemon Restarts](https://docs.docker.com/config/containers/live-restore/)
- [Docker Architecture & Storage Drivers](https://docs.docker.com/storage/storagedriver/)
