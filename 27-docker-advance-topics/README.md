# 27 — Docker Advanced Topics: Internals, Security, Multi-Platform & Cluster Orchestration

This guide covers advanced Docker capabilities, low-level Linux kernel primitives, supply-chain security, multi-architecture image building, and production container orchestration.

---

## 1. Advanced Docker Architecture Landscape

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                            Developer & CI Tooling                                │
│       Docker Buildx ──► BuildKit ──► Multi-Platform Builds (AMD64 / ARM64)       │
│       Docker Contexts ──► Multi-Engine Management (Local, Remote, Swarm, K8s)    │
└────────────────────────────────────────┬─────────────────────────────────────────┘
                                         │
                                         ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│                        Supply Chain & Security Gates                             │
│       Cosign / Docker Content Trust (DCT) ──► SBOM Generation (Syft)             │
│       Vulnerability Scanning (Trivy) ──► OCI Multi-Arch Manifest Lists           │
└────────────────────────────────────────┬─────────────────────────────────────────┘
                                         │
                                         ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│                      Host Engine & Cluster Runtime                               │
│       Rootless Docker ──► Docker Swarm & Overlay Networks ──► Docker Secrets     │
└────────────────────────────────────────┬─────────────────────────────────────────┘
                                         │
                                         ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│                      Low-Level Container Runtime Stack                           │
│               containerd (CRI/gRPC) ──► runc (OCI Runtime Spec)                  │
│       Linux Kernel Primitives: Namespaces (Isolation) + cgroups v2 (Limits)      │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## Table of Contents

1. [Advanced Image Building: BuildKit & Buildx](#1-advanced-image-building-buildkit--buildx)
   - [BuildKit Engine](#buildkit-engine)
   - [Docker Buildx](#docker-buildx)
   - [Multi-Platform Images (ARM64 vs. AMD64)](#multi-platform-images-arm64-vs-amd64)
   - [Docker Manifest Lists & OCI Images](#docker-manifest-lists--oci-images)
2. [Supply Chain Security & Provenance](#2-supply-chain-security--provenance)
   - [Software Bill of Materials (SBOM)](#software-bill-of-materials-sbom)
   - [Docker Content Trust (DCT) & Cosign Image Signing](#docker-content-trust-dct--cosign-image-signing)
   - [Automated Vulnerability Scanning (Trivy / Grype)](#automated-vulnerability-scanning-trivy--grype)
   - [Supply-Chain Verification Pipeline](#supply-chain-verification-pipeline)
3. [Daemon & Engine Advanced Operations](#3-daemon--engine-advanced-operations)
   - [Rootless Docker Mode](#rootless-docker-mode)
   - [Docker Contexts (Managing Remote Daemons)](#docker-contexts-managing-remote-daemons)
   - [Docker Plugins (Volume, Network, AuthZ)](#docker-plugins-volume-network-authz)
4. [Docker Swarm & Clustering](#4-docker-swarm--clustering)
   - [Swarm Architecture (Managers vs. Workers)](#swarm-architecture-managers-vs-workers)
   - [Overlay Networks (Multi-Host VXLAN)](#overlay-networks-multi-host-vxlan)
   - [Docker Secrets Management](#docker-secrets-management)
5. [Low-Level Container Runtime & Kernel Primitives](#5-low-level-container-runtime--kernel-primitives)
   - [Linux Namespaces (Process & Resource Isolation)](#linux-namespaces-process--resource-isolation)
   - [Linux Control Groups (cgroups v1 vs. cgroups v2)](#linux-control-groups-cgroups-v1-vs-cgroups-v2)
   - [containerd & runc (OCI Implementation)](#containerd--runc-oci-implementation)
   - [The OCI Specification (Image & Runtime Specs)](#the-oci-specification-image--runtime-specs)
   - [Runtime Security: Seccomp, AppArmor & Capabilities](#runtime-security-seccomp-apparmor--capabilities)

---

## 1. Advanced Image Building: BuildKit & Buildx

### BuildKit Engine
**BuildKit** replaces the legacy Docker build engine. Key advantages:
- **Parallel Stage Execution**: Non-dependent multi-stage build targets execute concurrently.
- **Cache Mounts (`--mount=type=cache`)**: Preserves package manager caches across builds without expanding image size.
- **Secret Mounts (`--mount=type=secret`)**: Exposes tokens/credentials at build time without baking them into layer metadata.
- **Direct SSH Forwarding (`--mount=type=ssh`)**: Clones private Git repositories using the host SSH agent.

```dockerfile
# syntax=docker/dockerfile:1.4
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -o /app/server .
```

---

### Docker Buildx
`buildx` is a Docker CLI plugin that extends image building with full BuildKit capabilities, multi-node builders, and multi-architecture cross-compilation.

```bash
# Create and switch to a custom multi-architecture builder instance
docker buildx create --name mybuilder --driver docker-container --bootstrap --use

# Inspect builder status
docker buildx inspect mybuilder
```

---

### Multi-Platform Images (ARM64 vs. AMD64)
Modern production environments span **AMD64** (Intel/AMD x86_64 servers in AWS, Azure, GCP) and **ARM64** (Apple Silicon, AWS Graviton processors, Ampere instances).

```
┌────────────────────────────────────────────────────────┐
│             Single Tag: myorg/app:1.0.0                │
│              (OCI Manifest List / Index)               │
└───────────────────────────┬────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
  ┌───────────────────────┐   ┌───────────────────────┐
  │   linux/amd64 Layer   │   │   linux/arm64 Layer   │
  │   (x86_64 Cloud VMs)  │   │   (Apple M-series,    │
  │                       │   │    AWS Graviton)      │
  └───────────────────────┘   └───────────────────────┘
```

#### Building and Pushing Multi-Arch Images:
```bash
# Build for AMD64 and ARM64 simultaneously and push directly to registry
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t myorg/myapp:v1.0.0 \
  --push .
```

---

### Docker Manifest Lists & OCI Images
A **Manifest List** (or OCI Image Index) is a JSON document pointing to architecture-specific image manifests. When a client pulls `myorg/myapp:v1.0.0`, Docker automatically inspects the host kernel architecture and pulls the matching layer digest.

```bash
# Inspect the multi-architecture manifest list for an image
docker manifest inspect nginx:alpine
```

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.index.v1+json",
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "size": 528,
      "digest": "sha256:7f3a9e...",
      "platform": { "architecture": "amd64", "os": "linux" }
    },
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "size": 528,
      "digest": "sha256:3d8b1c...",
      "platform": { "architecture": "arm64", "os": "linux" }
    }
  ]
}
```

---

## 2. Supply Chain Security & Provenance

Modern container security protects every stage from source commit to registry distribution.

### Software Bill of Materials (SBOM)
An **SBOM** is a comprehensive, machine-readable inventory of all software packages, libraries, binaries, and dependencies packaged inside a container image (SPDX or CycloneDX format).

```bash
# Generate SBOM using Docker CLI (powered by Syft / BuildKit)
docker buildx build --sbom=true -t myorg/myapp:1.0 .

# Extract SBOM using Syft (standalone)
syft myorg/myapp:1.0 -o spdx-json > sbom.json
```

---

### Docker Content Trust (DCT) & Cosign Image Signing
Ensures container images are digitally signed and have not been tampered with in transit.

#### 1. Docker Content Trust (Notary v1):
```bash
# Enforce signature verification before pulling
export DOCKER_CONTENT_TRUST=1
docker pull myorg/myapp:1.0.0
```

#### 2. Cosign (Sigstore - Modern Standard):
```bash
# Generate keypair
cosign generate-key-pair

# Sign container image in registry
cosign sign --key cosign.key myorg/myapp:1.0.0

# Verify image signature before deployment
cosign verify --key cosign.pub myorg/myapp:1.0.0
```

---

### Automated Vulnerability Scanning (Trivy / Grype)
Scan images for known Common Vulnerabilities and Exposures (CVEs) across OS packages and application dependencies:

```bash
# Scan image and block CI build if CRITICAL CVEs exist
trivy image --exit-code 1 --severity CRITICAL,HIGH myorg/myapp:1.0.0

# Scan SBOM directly
trivy sbom sbom.json
```

---

## 3. Daemon & Engine Advanced Operations

### Rootless Docker Mode
Rootless mode runs the **Docker daemon (`dockerd`) and containers inside a user namespace** without requiring `root` privileges on the host OS:
- Mitigates container breakout attacks — an attacker escaping a container only gains unprivileged access on the host.
- Uses `slirp4netns` or `VPNKit` for unprivileged user-mode networking.

```bash
# Install rootless docker (per-user daemon)
dockerd-rootless-setuptool.sh install

# Export socket path for current user
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
```

---

### Docker Contexts (Managing Remote Daemons)
Docker Contexts allow switching the `docker` CLI between local machines, remote cloud VMs, Docker Swarm clusters, or Kubernetes endpoints without editing environment variables:

```bash
# Create a context for a remote staging server over SSH
docker context create staging-server --docker "host=ssh://deploy@staging.example.com"

# Create a context for a production cluster
docker context create prod-cluster --docker "host=tcp://prod-docker.example.com:2376,ca=/path/ca.pem,cert=/path/cert.pem,key=/path/key.pem"

# List all available contexts
docker context ls

# Switch active context
docker context use staging-server

# All subsequent CLI commands execute on the staging server!
docker ps
```

---

### Docker Plugins (Volume, Network, AuthZ)
Docker plugins extend engine capabilities with out-of-tree drivers:
- **Volume Plugins**: Integrate cloud storage (e.g. `rexray/ebs` for AWS EBS, `vieux/sshfs` for network shares).
- **Network Plugins**: Integrate software-defined networking (e.g. Weave, Calico).
- **Authorization Plugins (AuthZ)**: Enforce granular Open Policy Agent (OPA) access control rules on API requests.

```bash
# Install and enable a volume plugin
docker plugin install vieux/sshfs
docker volume create -d vieux/sshfs -o sshcmd=user@server:/data my-remote-vol
```

---

## 4. Docker Swarm & Clustering

Docker Swarm turns a pool of Docker hosts into a single, self-healing, fault-tolerant virtual Docker engine.

### Swarm Architecture (Managers vs. Workers)

```
┌────────────────────────────────────────────────────────┐
│                    Swarm Manager Node                  │
│       Raft Consensus ──► Task Dispatcher ──► API       │
└───────────────────────────┬────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
┌───────────────────────────┐   ┌───────────────────────────┐
│     Swarm Worker Node     │   │     Swarm Worker Node     │
│   ┌───────────────────┐   │   │   ┌───────────────────┐   │
│   │ Task (Container)  │   │   │   │ Task (Container)  │   │
│   └───────────────────┘   │   │   └───────────────────┘   │
└───────────────────────────┘   └───────────────────────────┘
```

```bash
# Initialize Swarm on manager node
docker swarm init --advertise-addr 192.168.1.10

# Join a worker node to cluster
docker swarm join --token <worker-token> 192.168.1.10:2377

# Deploy a multi-replica service with rolling update policy
docker service create \
  --name web-api \
  --replicas 5 \
  --update-delay 10s \
  --update-parallelism 2 \
  -p 80:80 \
  myorg/web-api:1.0.0
```

---

### Overlay Networks (Multi-Host VXLAN)
Overlay networks enable containers on **different physical/virtual hosts** to communicate securely without host port mappings:
- Uses **VXLAN (Virtual Extensible LAN)** encapsulation on UDP port 4789.
- Built-in AES-256 data plane encryption can be enabled with a single flag.

```bash
# Create an encrypted overlay network spanning all Swarm nodes
docker network create \
  --driver overlay \
  --opt encrypted \
  app-overlay-net
```

---

### Docker Secrets Management
Docker Swarm provides encrypted at-rest and in-transit secrets management (Raft log encryption):
- Secrets are mounted as in-memory files at `/run/secrets/<secret_name>` in container RAM (`tmpfs`), never written to disk or container layers.

```bash
# Create a secret from stdin or file
echo "db_prod_password_99" | docker secret create db_password -

# Assign secret to a running Swarm service
docker service create \
  --name backend-api \
  --secret db_password \
  myorg/api:1.0.0
```

---

## 5. Low-Level Container Runtime & Kernel Primitives

Containers are not virtual machines; they are standard Linux processes isolated via kernel features.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Docker CLI / Client                             │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     containerd (Lifecycle Manager)                     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                       runc (OCI Reference CLI)                         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                           Host Linux Kernel                            │
│  ┌──────────────────────────────┐    ┌──────────────────────────────┐  │
│  │       Linux Namespaces       │    │      Control Groups (cgroups)│  │
│  │ (pid, net, mnt, ipc, uts,    │    │ (CPU limits, RAM quota,      │  │
│  │  user, cgroup)               │    │  I/O limits, PIDs ceiling)   │  │
│  └──────────────────────────────┘    └──────────────────────────────┘  │
│  ┌──────────────────────────────┐    ┌──────────────────────────────┐  │
│  │        Seccomp Syscalls      │    │     AppArmor / SELinux (MAC) │  │
│  └──────────────────────────────┘    └──────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

---

### Linux Namespaces (Process & Resource Isolation)
Namespaces restrict **what a containerized process can SEE**:

| Namespace | Linux Flag | What it Isolates |
|---|---|---|
| **PID** | `CLONE_NEWPID` | Process IDs (container main process sees itself as PID 1). |
| **NET** | `CLONE_NEWNET` | Network interfaces, IP routing tables, port bindings. |
| **MNT** | `CLONE_NEWNS` | Mount points and filesystem hierarchy. |
| **IPC** | `CLONE_NEWIPC` | Inter-process communication and shared memory segments. |
| **UTS** | `CLONE_NEWUTS` | System hostname and NIS domain name. |
| **USER** | `CLONE_NEWUSER`| Maps container UID 0 (root) to an unprivileged UID on the host. |
| **CGROUP**| `CLONE_NEWCGROUP`| Isolates the cgroup hierarchy view inside the container. |

---

### Linux Control Groups (cgroups v1 vs. cgroups v2)
Control Groups limit and meter **how much resources a container can USE**:
- **cgroups v1**: Multi-hierarchy controllers (`/sys/fs/cgroup/cpu`, `/sys/fs/cgroup/memory`).
- **cgroups v2**: Unified single-hierarchy tree, accurate OOM attribution, eBPF integration, and Pressure Stall Information (PSI).

---

### `containerd` & `runc` (OCI Implementation)
- **`runc`**: Lightweight low-level OCI CLI tool written in Go that invokes Linux syscalls (`clone`, `unshare`, `pivot_root`, `setns`) to configure namespaces and launch the container process before exiting.
- **`containerd`**: Daemon managing container supervisor lifecycle, image pulling, snapshotting (`overlayfs`), and inter-process communication using `containerd-shim`.

---

### The OCI Specification (Image & Runtime Specs)
The **Open Container Initiative** standardizes container technology:
1. **OCI Image Specification (`image-spec`)**: Standardizes rootfs tarballs, JSON configuration blobs, and manifest digests.
2. **OCI Runtime Specification (`runtime-spec`)**: Standardizes the filesystem bundle and `config.json` schema consumed by runtimes like `runc` and `crun`.

---

### Runtime Security: Seccomp, AppArmor & Capabilities
- **Seccomp (Secure Computing)**: Filters and drops dangerous kernel system calls (e.g. `reboot`, `sys_ptrace`).
- **Linux Capabilities**: Breaks root privileges into fine-grained units (`CAP_NET_BIND_SERVICE`, `CAP_CHOWN`).
- **AppArmor / SELinux**: Enforces Mandatory Access Control (MAC) file and network security profiles.

```bash
# Production hardened execution dropping all kernel capabilities
docker run -d \
  --name secure-app \
  --cap-drop=ALL \
  --cap-add=NET_BIND_SERVICE \
  --security-opt=no-new-privileges:true \
  --security-opt seccomp=default \
  -p 80:80 \
  myorg/myapp:1.0.0
```

---

## References

- [Docker BuildKit Documentation](https://docs.docker.com/build/buildkit/)
- [Docker Buildx Multi-Platform Builds](https://docs.docker.com/build/building/multi-platform/)
- [Open Container Initiative (OCI) Specs](https://opencontainers.org/)
- [containerd Architecture](https://containerd.io/)
- [Sigstore Cosign Documentation](https://docs.sigstore.dev/cosign/overview/)
- [Aqua Security Trivy Scanner](https://aquasecurity.github.io/trivy/)
