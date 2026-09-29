# Docker

Covering containers, images, volumes, bind mounts, utility containers, Docker Compose, networking, and Kubernetes.


<img src="./imgs/Docker Architecture Ecosystem.png" width="100%" />

---

## Table of Contents

1. [Introduction to Docker](#1-introduction-to-docker)
2. [Docker Architecture](#2-docker-architecture)
3. [Why Was Docker Introduced?](#3-why-was-docker-introduced)
4. [Why Do We Need Docker?](#4-why-do-we-need-docker)
5. [Docker vs Virtual Machine](#5-docker-vs-virtual-machine)
6. [How Docker Is Used in Production](#6-how-docker-is-used-in-production)
7. [Limitations of Docker](#7-limitations-of-docker)
8. [Modules](#8-modules)

---

## 1. Introduction to Docker

**Docker** is an open-source platform that enables developers to **build, ship, and run applications inside lightweight, portable containers**. A container packages an application together with all its dependencies — libraries, configuration files, and runtime — so it runs consistently across any environment: a developer laptop, a test server, or a production cloud.

Docker was first released in **2013** by Solomon Hykes at dotCloud (later renamed Docker, Inc.) and quickly became the industry standard for container-based development and deployment.

### Key Concepts

| Concept | Description |
|---|---|
| **Image** | A read-only, layered blueprint for a container (built from a `Dockerfile`) |
| **Container** | A running instance of an image — isolated, ephemeral, and lightweight |
| **Dockerfile** | A text file with instructions to build a Docker image |
| **Registry** | A storage service for images (e.g. Docker Hub, AWS ECR, GitHub Container Registry) |
| **Volume** | Persistent storage that survives container restarts |

---

## 2. Docker Architecture

Docker uses a **client–server architecture** composed of several components that communicate over a REST API.

```
┌─────────────────────────────────────────────────────────────┐
│                        Docker Client                        │
│          (docker CLI / Docker Desktop / SDKs)               │
└────────────────────────┬────────────────────────────────────┘
                         │  REST API (Unix socket / TCP)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                       Docker Daemon (dockerd)               │
│                                                             │
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────────┐  │
│   │   Images    │   │ Containers  │   │    Networks &    │  │
│   │  (layers)   │   │ (runtime)   │   │     Volumes      │  │
│   └─────────────┘   └─────────────┘   └─────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Container Runtime                        │
│              (containerd → runc / OCI spec)                 │
└─────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                      Docker Registry                        │
│          (Docker Hub / ECR / GCR / private registry)        │
└─────────────────────────────────────────────────────────────┘
```

### Components

| Component | Role |
|---|---|
| **Docker Client** | The CLI (`docker`) or UI that sends commands to the daemon |
| **Docker Daemon (`dockerd`)** | Background service that manages images, containers, networks, and volumes |
| **containerd** | Industry-standard container runtime; manages the container lifecycle |
| **runc** | Low-level OCI-compliant runtime that actually creates and runs containers using Linux namespaces and cgroups |
| **Docker Registry** | Remote store for images; `docker pull` / `docker push` communicate with it |
| **Docker Hub** | The default public registry hosted by Docker, Inc. |

---

## 3. Why Was Docker Introduced?

Before Docker, deploying applications meant dealing with the classic **"it works on my machine"** problem — differences between developer, staging, and production environments caused unpredictable failures.

### Problems Docker Solved

- **Environment inconsistency** — different OS versions, library versions, and config across dev/staging/prod.
- **Heavy VMs** — the only prior isolation mechanism was full virtual machines, which were slow to boot and resource-intensive.
- **Dependency hell** — installing conflicting versions of runtimes (Python 2 vs 3, Node 14 vs 18) on the same host caused breakage.
- **Slow onboarding** — setting up a new developer's machine could take days.
- **Unreliable deployments** — manual server configuration led to configuration drift over time.

Docker introduced a **standardised, image-based packaging format** that bundles the application and all its dependencies into a single artifact that behaves identically everywhere.

---

## 4. Why Do We Need Docker?

Docker is needed because modern software development demands **speed, consistency, and scalability** across heterogeneous environments.

### Core Benefits

| Need | How Docker Helps |
|---|---|
| **Portability** | Run the same container on a laptop, CI server, or cloud VM without changes |
| **Isolation** | Each container has its own filesystem, network, and process space |
| **Speed** | Containers start in milliseconds vs minutes for VMs |
| **Reproducibility** | A `Dockerfile` is version-controlled — any team member can reproduce the exact environment |
| **Resource efficiency** | Containers share the host OS kernel; no guest OS overhead |
| **Microservices** | Run each service in its own container with independent scale and deploy cycles |
| **CI/CD pipelines** | Build once, promote the same image through test → staging → production |
| **Dependency management** | Pin exact versions of every dependency inside the image |

---

## 5. Docker vs Virtual Machine

Both Docker containers and virtual machines (VMs) provide **isolation**, but they do so at different layers of the stack.

```
┌──────────────────────────┐     ┌──────────────────────────┐
│      VIRTUAL MACHINE     │     │      DOCKER CONTAINER    │
├──────────────────────────┤     ├──────────────────────────┤
│        App A             │     │       App A              │
│        App Libs          │     │       App Libs           │
│     Guest OS (full)      │     │  (no guest OS — shared   │
│     (GBs of overhead)    │     │   host kernel)           │
├──────────────────────────┤     ├──────────────────────────┤
│      Hypervisor          │     │    Container Runtime     │
│  (VMware / Hyper-V etc.) │     │  (containerd / runc)     │
├──────────────────────────┤     ├──────────────────────────┤
│       Host OS            │     │       Host OS            │
├──────────────────────────┤     ├──────────────────────────┤
│    Physical Hardware     │     │    Physical Hardware     │
└──────────────────────────┘     └──────────────────────────┘
```

### Comparison Table

| Attribute | Docker Container | Virtual Machine |
|---|---|---|
| **Startup time** | Milliseconds | Minutes |
| **Size** | MBs (image layers) | GBs (full OS disk) |
| **OS overhead** | Shares host kernel | Full guest OS per VM |
| **Isolation level** | Process-level (namespaces + cgroups) | Hardware-level (hypervisor) |
| **Security boundary** | Weaker (shared kernel) | Stronger (separate kernel) |
| **Portability** | Highly portable via OCI images | Less portable (hypervisor-dependent) |
| **Use case** | Microservices, CI/CD, dev environments | Full OS isolation, legacy workloads |

> **Rule of thumb:** Use Docker for application-level isolation and speed. Use VMs when you need strong security boundaries or must run a different OS kernel (e.g. Windows on Linux host).

---

## 6. How Docker Is Used in Production

Docker is a foundational piece of most modern production infrastructure. Below are the most common real-world patterns.

### 6.1 CI/CD Pipelines

Every commit triggers a pipeline that:
1. Builds a Docker image from the `Dockerfile`
2. Runs automated tests inside a container
3. Pushes the verified image to a registry (ECR, GCR, Docker Hub)
4. Deploys the image to production (Kubernetes, ECS, etc.)

### 6.2 Container Orchestration

In production, containers are managed by an **orchestrator** rather than run directly with `docker run`:

| Orchestrator | Description |
|---|---|
| **Kubernetes (K8s)** | Industry-standard; handles scheduling, scaling, self-healing, rolling updates |
| **Amazon ECS / Fargate** | AWS-native container management; Fargate is serverless (no node management) |
| **Docker Swarm** | Built-in Docker clustering — simpler than K8s for smaller deployments |

### 6.3 Immutable Infrastructure

Production images are **never patched in place**. Instead:
- A new image is built with the fix.
- The old containers are replaced by containers from the new image (rolling update / blue-green deploy).
- Old images are kept in the registry for rollback.

### 6.4 Twelve-Factor App Pattern

Docker encourages twelve-factor principles:
- Config via **environment variables** (`ENV` / `--env-file`)
- Stateless containers with state stored in **external volumes or databases**
- Logs written to **stdout/stderr** and collected by the platform

### 6.5 Security Hardening in Production

- Run containers as **non-root** users (`USER` directive in Dockerfile)
- Use **read-only root filesystems** (`--read-only`)
- Scan images for CVEs with tools like **Trivy**, **Snyk**, or **Docker Scout**
- Sign images with **Docker Content Trust / Notary**
- Apply **resource limits** (`--memory`, `--cpus`) to prevent noisy-neighbour issues

---

## 7. Limitations of Docker

Docker is powerful but not without trade-offs. Understanding its limitations helps you choose the right tool for each job.

| Limitation | Detail |
|---|---|
| **Shared kernel** | All containers share the host OS kernel. A kernel vulnerability can affect all containers. VMs offer stronger isolation. |
| **Not ideal for GUI apps** | Docker is designed for headless, server-side workloads. Running desktop GUI applications requires complex X11/Wayland forwarding. |
| **Persistent storage complexity** | Containers are ephemeral by design. Managing stateful workloads (databases, file uploads) requires careful volume planning. |
| **Networking complexity** | Multi-host networking, service meshes, and overlay networks add significant operational complexity at scale. |
| **Limited Windows container support** | Windows containers require a Windows host OS and are less mature than Linux containers in terms of ecosystem tooling. |
| **No built-in orchestration at scale** | Docker Swarm is simple but lacks the features of Kubernetes for large-scale, multi-cluster deployments. |
| **Image size bloat** | Without discipline (multi-stage builds, minimal base images), images can grow very large, slowing pull times. |
| **Security defaults** | By default, containers run as root and have broad capabilities — requires deliberate hardening. |
| **Resource overhead at high density** | At very high container densities, the container runtime and overlay filesystem can become a performance bottleneck. |
| **Learning curve** | Dockerfile best practices, layer caching, networking, and orchestration concepts require significant upfront investment. |

---

## 8. Modules

| # | Topic | Description |
|---|---|---|
| 01 | [Images & Containers](./01-images-containers/README.md) | Pulling images, running containers, lifecycle commands |
| 02 | [Dockerfile](./02-dockerfile/README.md) | Writing Dockerfiles, layer caching, multi-stage builds |
| 03 | [Volumes](./03-volumes/README.md) | Named volumes, anonymous volumes, backup & restore |
| 04 | [Bind Mounts](./04-bind-mounts/README.md) | Host-path mounts, live reload in development |
| 05 | [Networking](./05-networking/README.md) | Bridge networks, DNS resolution, port mapping |
| 06 | [Utility Containers](./06-utility-containers/README.md) | One-off command containers, ENTRYPOINT pattern |
| 07 | [Docker Compose](./07-docker-compose/README.md) | Compose file syntax, multi-service stacks, overrides |
| 08 | [Multi-Container App](./08-multi-container-app/README.md) | Full-stack example with API, DB, cache, and proxy |
| 09 | [Production Patterns](./09-production-patterns/README.md) | Security hardening, resource limits, health checks |
| 10 | [Kubernetes](./10-kubernetes/README.md) | Pods, Deployments, Services, kubectl, K8s vs Docker |
