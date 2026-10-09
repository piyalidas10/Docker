# Docker Concepts FAQ

---

## 1. Do We Need Docker When We Have Kubernetes?

**Short answer: Yes, in most cases you still need Docker (or something like it).**

Kubernetes is an **orchestration platform** — it manages *where* and *how* containers run across a cluster of machines. But Kubernetes itself does **not build container images**. It only *runs* them.

### What Kubernetes Does
- Schedules and runs containers across nodes
- Handles scaling, self-healing, load balancing
- Manages deployments, rollouts, and rollbacks

### What Docker Does (that Kubernetes does not)
- **Builds container images** from a `Dockerfile`
- **Pushes images** to a container registry (Docker Hub, ECR, GCR, etc.)
- Provides a **local development runtime** for running containers on your machine

### The Relationship

```
Developer → docker build → image → docker push → registry
                                                       ↓
                                              Kubernetes pulls
                                              & runs the image
```

Kubernetes pulls the image you built (with Docker or another tool) and runs it. The two tools **complement** each other rather than compete.

### Can You Use Kubernetes Without Docker?
Yes. Kubernetes dropped Docker as its default runtime in v1.24 (via `dockershim` removal) and now uses the **CRI (Container Runtime Interface)**. Common runtimes include:

| Runtime | Notes |
|---|---|
| **containerd** | Default in most managed clusters (EKS, GKE, AKS) |
| **CRI-O** | Lightweight, used in OpenShift |
| **Docker Engine (via cri-dockerd)** | Still works but needs an adapter |

Even without Docker as a runtime, most teams **still use Docker to build images** locally because it is the most familiar and widely supported toolchain.

### Bottom Line
- **Kubernetes ≠ replacement for Docker.** They operate at different layers.
- You can replace Docker with alternatives (see section 3), but you still need *something* to build and push images.

---

## 2. Are Docker Volumes, Bind Mounts, and Networking Useful for Development?

**Yes — these three features are arguably more useful in development than in production.**

### Bind Mounts — Hot Reloading Without Rebuilding

A bind mount maps a **directory on your host machine** directly into the container.

```bash
docker run -v $(pwd)/src:/app/src my-app
```

- Code changes on your host are **instantly visible inside the container**
- No need to rebuild the image on every change
- Essential for frameworks with hot-reload (Node/Nodemon, Python/Flask debug mode, etc.)

> **Production note:** Bind mounts are generally avoided in production because they create a tight coupling between the container and the host filesystem.

### Volumes — Persisting State Across Restarts

Named volumes store data managed by Docker itself (not tied to a specific host path).

```bash
docker run -v db-data:/var/lib/postgresql/data postgres
```

- Survive `docker stop` / `docker start` cycles
- Ideal for local databases (Postgres, MySQL, MongoDB) during development
- Shared between containers in `docker-compose`

> **Production note:** In production, persistent state is usually handled by managed databases or cloud storage — not Docker volumes.

### Networking — Isolated Local Environments

Docker's bridge network allows containers to talk to each other by **service name** rather than hardcoded IPs.

```yaml
# docker-compose.yml
services:
  api:
    build: .
  db:
    image: postgres
```

Inside the `api` container, you can reach the database at `db:5432` — no IP configuration needed.

- Mirrors production service-to-service communication locally
- Keeps your dev stack isolated from your host network
- Multiple projects can run simultaneously without port conflicts (using separate networks)

### Summary Table

| Feature | Dev Value | Production Value |
|---|---|---|
| Bind Mounts | ⭐⭐⭐ Hot reload, instant feedback | ⚠️ Rarely used |
| Volumes | ⭐⭐⭐ Persist local DB data | ⚠️ Usually replaced by managed storage |
| Networking | ⭐⭐⭐ Service discovery, isolation | ✅ Handled by Kubernetes/service mesh |

All three features shine brightest in **local development and docker-compose-based workflows**.

---

## 3. Replacements / Alternatives to Docker

Docker is not the only tool in the container ecosystem. Here are the most notable alternatives:

### Image Building Alternatives

| Tool | Description |
|---|---|
| **Podman** | Drop-in Docker replacement; daemonless, rootless by default. CLI is almost identical (`podman build`, `podman run`). Developed by Red Hat. |
| **Buildah** | Builds OCI-compliant images without a daemon. Often used alongside Podman. |
| **kaniko** | Builds images inside a Kubernetes pod — no Docker daemon needed. Popular in CI/CD pipelines on Kubernetes. |
| **BuildKit** | The build engine now embedded in Docker itself (`docker buildx`). Can also be used standalone. |
| **Nix / nixpkgs** | Reproducible image builds using the Nix package manager. Steep learning curve but highly deterministic. |

### Container Runtime Alternatives

| Runtime | Used By |
|---|---|
| **containerd** | Default in Docker Engine, EKS, GKE, AKS |
| **CRI-O** | OpenShift, some bare-metal Kubernetes setups |
| **gVisor** | Google — adds a user-space kernel for stronger isolation |
| **Kata Containers** | VM-level isolation with container-like UX |

### All-in-One Dev Environment Alternatives

| Tool | Description |
|---|---|
| **Podman Desktop** | GUI for Podman; aims to replace Docker Desktop |
| **Rancher Desktop** | Bundles containerd + nerdctl + Kubernetes (k3s) locally |
| **Lima** | Linux VMs on macOS with automatic file sharing and port forwarding |
| **nerdctl** | Docker-compatible CLI for containerd |

### Why Most Teams Still Use Docker
- Massive ecosystem and community
- `Dockerfile` is the de facto standard
- Docker Compose is hard to beat for local multi-service dev
- Docker Hub is the most widely used public registry
- Most CI/CD platforms have first-class Docker support

> **Podman** is the closest practical replacement if you want to move away from Docker, especially on Linux. For Kubernetes-native CI/CD, **kaniko** is popular.

---

*See also: [`deployment-philosophies.md`](./deployment-philosophies.md) | [`module-summary.md`](./module-summary.md)*
