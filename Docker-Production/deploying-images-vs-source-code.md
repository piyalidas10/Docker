# Deploying Images vs. Deploying Source Code

## Overview

Once Docker is installed and running on a remote machine (such as an AWS EC2 instance or a VPS), the next task is bringing your application onto that remote host. There are two primary deployment approaches to consider.

---

## Comparison of Deployment Approaches

| Approach | Workflow | Recommended? |
|---|---|---|
| **1. Deploy Source Code** | Copy source code + `Dockerfile` $\rightarrow$ remote server $\rightarrow$ `docker build` on remote host $\rightarrow$ `docker run` | ❌ **Not Recommended** |
| **2. Deploy Docker Image** | Build image locally (or in CI) $\rightarrow$ push image to registry $\rightarrow$ remote server pulls image $\rightarrow$ `docker run` | ✅ **Recommended / Industry Standard** |

---

## Deep Dive: The Two Approaches

### Approach 1: Build on the Remote Machine (Deploy Source Code)

```
LOCAL MACHINE
   │
   │ Transfer source code + Dockerfile (via Git / SCP / RSYNC)
   ▼
REMOTE SERVER
   │
   ├── docker build .
   │       ↓
   │   Docker Image
   │       ↓
   └── docker run
           ↓
       Container
```

#### Why This Approach is Problematic
- **Unnecessary Overhead & Complexity:** The remote production server must spend CPU, memory, and disk I/O executing build steps (`npm install`, compilation, asset bundling).
- **Tooling Leakage:** The remote server requires access to repository credentials, package managers, and source code.
- **Inconsistent Builds:** Differences in build-time network access, upstream dependency changes, or cache issues on the remote server can produce an image that differs from what was tested locally.

---

### Approach 2: Build Locally / CI $\rightarrow$ Push to Registry $\rightarrow$ Run Remotely (Deploy Built Image)

```
                BUILD
LOCAL MACHINE / CI ──────────────► Docker Image
                                         │
                                         │ docker push
                                         ▼
                                   CONTAINER REGISTRY
                              (Docker Hub, AWS ECR, etc.)
                                         │
                                         │ docker pull
                                         ▼
                                   REMOTE SERVER
                                         │
                                         │ docker run
                                         ▼
                                     CONTAINER
```

---

## Concrete Workflow Example

### Step 1: On Your Local Machine / CI

Build, tag with your registry namespace and version tag, and push:

```bash
# 1. Build the image locally
docker build -t myapp:1.0 .

# 2. Tag for the registry (e.g., Docker Hub)
docker tag myapp:1.0 username/myapp:1.0

# 3. Push the packaged artifact to the registry
docker push username/myapp:1.0
```

### Step 2: On the Remote Server (via SSH)

Pull the exact image and run it:

```bash
# 1. Pull the pre-built image
docker pull username/myapp:1.0

# 2. Run the container
docker run -d --rm --name my-app -p 8080:8080 username/myapp:1.0
```

---

## The Core Concept: The Image Is the Deployment Artifact

```
Source Code ──► Build ──► Docker Image ──► Deploy Image ──► Running Container
```

The Docker image itself is the compiled, packaged, immutable **deployment artifact**. 

You do **not** need to send:
- Source code files (`.ts`, `.js`, `.py`, `.go`)
- `Dockerfile`
- `package.json` / dependency locks
- `node_modules` or build toolchains

to the production host. Instead, you ship the ready-to-run image.

---

## Key DevOps Principle: Build Once, Deploy Anywhere

Building the image ahead of time guarantees consistency across environments:

```
Build Image (myapp:1.0)
         │
         ├──► Development / Local QA
         │
         ├──► Automated Testing & CI
         │
         ├──► Staging Environment
         │
         └──► Production Deployment
```

> **DevOps Golden Rule:**  
> **Build once $\rightarrow$ Test the artifact $\rightarrow$ Promote the exact same artifact $\rightarrow$ Deploy.**

Never rebuild the image for each target environment; pass environment-specific configuration (database URLs, API keys, ports) via environment variables at runtime (`docker run -e ...`).

---

## Image Registries in Enterprise Environments

In production and enterprise setups, images are typically stored in private container registries rather than public Docker Hub repositories:

| Cloud / Platform | Container Registry Service |
|---|---|
| **AWS** | AWS Elastic Container Registry (ECR) |
| **Google Cloud** | Google Artifact Registry / Container Registry (GCR) |
| **Microsoft Azure** | Azure Container Registry (ACR) |
| **GitHub** | GitHub Container Registry (GHCR) |
| **Self-Hosted / On-Premise** | Harbor, JFrog Artifactory, Sonatype Nexus |

---

## Summary

Don't treat Docker primarily as a tool for compiling and building code on your production host. Treat the **Docker image as the finished, self-contained application bundle** that is built once, tested, and distributed anywhere Docker runs.
