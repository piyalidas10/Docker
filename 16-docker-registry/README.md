# 16 — Docker Registry & Image Distribution

A **Docker Registry** is a centralized, hosted storage and distribution system for named Docker images. Registries allow developers, CI/CD automation pipelines, and production servers to share, version, push, and pull container images globally.

---

## The Registry Workflow: Push & Pull Lifecycle

```
┌────────────────────────────────────────────────────────┐
│                   Developer / CI Host                  │
│                                                        │
│  1. Build Image       2. Tag Image                     │
│  ┌──────────────┐     ┌─────────────────────────────┐  │
│  │    myapp     │ ──► │  username/myapp:1.0         │  │
│  └──────────────┘     └──────────────┬──────────────┘  │
└──────────────────────────────────────┼─────────────────┘
                                       │
                                       │ 3. docker push username/myapp:1.0
                                       ▼
┌────────────────────────────────────────────────────────┐
│              Docker Registry (Docker Hub,              │
│               AWS ECR, GHCR, Private Registry)         │
│                                                        │
│   Repository: username/myapp                           │
│   ┌───────────────────┬────────────────────────────┐   │
│   │ Tag: 1.0          │ Digest: sha256:7b9a4c...   │   │
│   ├───────────────────┼────────────────────────────┤   │
│   │ Tag: 1.1          │ Digest: sha256:3d8e1f...   │   │
│   └───────────────────┴────────────────────────────┘   │
└──────────────────────────────────────┬─────────────────┘
                                       │
                                       │ 4. docker pull username/myapp:1.0
                                       ▼
┌────────────────────────────────────────────────────────┐
│               Production Host / Server                 │
│                                                        │
│  5. Run Container                                      │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Container running from username/myapp:1.0        │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

---

## Table of Contents

1. [Key Concepts](#1-key-concepts)
   - [Docker Registry](#docker-registry)
   - [Docker Hub](#docker-hub)
   - [Private Registry](#private-registry)
   - [Image Repository](#image-repository)
   - [Image Tagging Anatomy](#image-tagging-anatomy)
   - [Push & Pull Operations](#push--pull-operations)
   - [Registry Authentication & Security](#registry-authentication--security)
2. [Complete Command Reference](#2-complete-command-reference)
   - [`docker login`](#docker-login)
   - [`docker tag`](#docker-tag)
   - [`docker push`](#docker-push)
   - [`docker pull`](#docker-pull)
   - [`docker logout`](#docker-logout)
3. [Step-by-Step Hands-On Guide: Docker Hub Workflow](#3-step-by-step-hands-on-guide-docker-hub-workflow)
4. [Working with Enterprise & Cloud Private Registries](#4-working-with-enterprise--cloud-private-registries)
   - [GitHub Container Registry (GHCR)](#github-container-registry-ghcr)
   - [AWS Elastic Container Registry (ECR)](#aws-elastic-container-registry-ecr)
   - [Self-Hosted Local Registry (`registry:2`)](#self-hosted-local-registry-registry2)
5. [Production Image Tagging Best Practices](#5-production-image-tagging-best-practices)
6. [Troubleshooting & Common Registry Issues](#6-troubleshooting--common-registry-issues)

---

## 1. Key Concepts

### Docker Registry
A registry is a service that contains collection of **repositories** and manages user authentication, authorization, access control, and storage of image layer blobs and manifests.

---

### Docker Hub
- The official default public registry hosted by Docker, Inc.
- Host for official community images (`ubuntu`, `nginx`, `node`, `postgres`).
- Offers both public open-source image hosting and private organizational repositories.

---

### Private Registry
An internal or access-restricted registry run within an enterprise network or cloud provider (e.g., AWS ECR, GCP Artifact Registry, Azure ACR, GitHub Packages, or self-hosted Harbor).
- Images are protected behind authentication credentials and VPC network controls.

---

### Image Repository
A collection of related images sharing the same application name but differentiated by **tags** (e.g. `username/myapp:1.0`, `username/myapp:1.1`, `username/myapp:latest`).

---

### Image Tagging Anatomy
A fully qualified Docker image name follows this standard syntax:

```
┌────────────────────────────────────────────────────────────────────────────┐
│ [registry_host[:port]/][namespace_or_username/]repository_name[:tag]       │
└────────────────────────────────────────────────────────────────────────────┘
```

| Component | Example | Description |
|---|---|---|
| **Registry Host** | `ghcr.io` / `12345.dkr.ecr.us-east-1.amazonaws.com` | If omitted, defaults to `docker.io` (Docker Hub) |
| **Namespace / Username** | `mycompany` / `john_doe` | Account, team, or organization name |
| **Repository Name** | `my-api` / `web-frontend` | The name of the specific application |
| **Tag** | `1.0.0` / `sha-8f3a9` / `latest` | Version identifier (defaults to `latest` if omitted) |

---

### Push & Pull Operations
- **`Push`**: Uploads image layer blobs and the JSON image manifest to the registry. Docker utilizes content-addressable storage — if a layer already exists on the registry, it is skipped (de-duplication).
- **`Pull`**: Downloads missing image layers from the registry onto the local host's container runtime storage.

---

### Registry Authentication & Security
- Registries require authentication credentials before allowing write (`push`) or restricted read (`pull`) operations.
- Credentials can be stored in the local Docker configuration file (`~/.docker/config.json`) or managed via credential helpers (e.g., `pass`, `osxkeychain`, `wincred`, AWS ECR credential helper).

---

## 2. Complete Command Reference

### `docker login`
Authenticates the Docker CLI client against a registry.

```bash
# Login to default Docker Hub (prompts for username and password / Personal Access Token)
docker login

# Login with explicit username and token via standard input (safe for CI/CD pipelines)
echo "$DOCKER_HUB_TOKEN" | docker login -u "$DOCKER_HUB_USER" --password-stdin

# Login to a custom / private registry (e.g. GitHub Container Registry)
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USER" --password-stdin

# Login to AWS ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com
```

---

### `docker tag`
Creates a new alias tag referring to an existing target image without duplicating the underlying image layers.

```bash
# Syntax: docker tag SOURCE_IMAGE[:TAG] TARGET_IMAGE[:TAG]

# Tag a local image for Docker Hub
docker tag myapp username/myapp:1.0

# Tag for GitHub Container Registry
docker tag myapp:latest ghcr.io/myorg/myapp:v1.0.0

# Tag image with multiple version aliases
docker tag username/myapp:1.0 username/myapp:latest
docker tag username/myapp:1.0 username/myapp:1
```

---

### `docker push`
Uploads the specified image repository and tag to the remote registry.

```bash
# Push specific tag to Docker Hub
docker push username/myapp:1.0

# Push all tags for a given repository
docker push --all-tags username/myapp

# Push to private registry
docker push ghcr.io/myorg/myapp:v1.0.0
```

---

### `docker pull`
Downloads an image from the remote registry to the local Docker engine.

```bash
# Pull official image from Docker Hub (implicit library namespace)
docker pull nginx:alpine

# Pull user repository image from Docker Hub
docker pull username/myapp:1.0

# Pull from private / custom registry
docker pull ghcr.io/myorg/myapp:v1.0.0

# Pull all tagged images in a repository
docker pull --all-tags username/myapp
```

---

### `docker logout`
Removes stored authentication credentials for the specified registry.

```bash
# Logout from Docker Hub
docker logout

# Logout from a specific private registry
docker logout ghcr.io
```

---

## 3. Step-by-Step Hands-On Guide: Docker Hub Workflow

Follow this end-to-end example to publish and consume an application image:

```bash
# Step 1: Create a simple application
echo 'console.log("Hello from Docker Registry!");' > app.js
cat <<EOF > Dockerfile
FROM node:20-alpine
WORKDIR /app
COPY app.js .
CMD ["node", "app.js"]
EOF

# Step 2: Build the image locally
docker build -t myapp .

# Step 3: Login to Docker Hub
docker login -u your_username

# Step 4: Tag the image with your Docker Hub username and version
docker tag myapp your_username/myapp:1.0
docker tag myapp your_username/myapp:latest

# Step 5: Push the image to Docker Hub
docker push your_username/myapp:1.0
docker push your_username/myapp:latest

# Step 6: Test pulling and running from any remote machine
docker run --rm your_username/myapp:1.0
```

---

## 4. Working with Enterprise & Cloud Private Registries

### GitHub Container Registry (GHCR)
1. Generate a GitHub Personal Access Token (PAT) with `read:packages` and `write:packages` scope.
2. Login and push:
   ```bash
   echo $CR_PAT | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
   docker tag my-api:latest ghcr.io/YOUR_GITHUB_USERNAME/my-api:1.0.0
   docker push ghcr.io/YOUR_GITHUB_USERNAME/my-api:1.0.0
   ```

### AWS Elastic Container Registry (ECR)
```bash
# 1. Authenticate Docker with AWS ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com

# 2. Tag image with full ECR URI
docker tag my-api:1.0 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-api:1.0

# 3. Push to ECR repository
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/my-api:1.0
```

### Self-Hosted Local Registry (`registry:2`)
You can run an open-source, local registry server in seconds for testing and local network caching:

```bash
# 1. Run local registry container on port 5000
docker run -d -p 5000:5000 --restart=always --name local-registry registry:2

# 2. Tag an image pointing to localhost:5000
docker tag nginx:alpine localhost:5000/my-custom-nginx:1.0

# 3. Push to local registry
docker push localhost:5000/my-custom-nginx:1.0

# 4. Pull and run from local registry
docker pull localhost:5000/my-custom-nginx:1.0
```

---

## 5. Production Image Tagging Best Practices

| Tag Type | Example | Usage Environment | Pros & Cons |
|---|---|---|---|
| **Semantic Version** | `myapp:v1.4.2` | Production releases | ✅ Fully deterministic & immutable<br>❌ Requires strict version release management |
| **Git Commit SHA** | `myapp:sha-8f3a19b` | Staging / CI builds | ✅ 100% traceable to source code commit<br>❌ Harder for humans to memorize |
| **Branch / Build Tag** | `myapp:main-142` | QA / Integration | ✅ Easy for automated deployments |
| **`latest`** | `myapp:latest` | Local development only | ⚠️ **Anti-pattern in production!** Overwritten on every build, destroys traceability and caching. |

---

## 6. Troubleshooting & Common Registry Issues

| Error Message | Root Cause | Solution |
|---|---|---|
| `denied: requested access to the resource is denied` | Not logged in, or lack push permissions to the target repository/organization | Run `docker login` and ensure the tag matches your exact username: `docker tag app username/app:1.0` |
| `unauthorized: authentication required` | Session expired or invalid credentials | Re-authenticate with `docker login` using an active Personal Access Token (PAT) |
| `http: server gave HTTP response to HTTPS client` | Trying to push to an insecure self-hosted registry without TLS | Add `"insecure-registries": ["myregistry.local:5000"]` to `/etc/docker/daemon.json` and restart Docker |
| `no basic auth credentials` | Docker config file lacks credentials for registry | Check credentials using `docker login <registry-domain>` |

---

## References

- [Docker Registry Overview](https://docs.docker.com/registry/)
- [Docker Hub Documentation](https://docs.docker.com/docker-hub/)
- [Docker Login CLI Reference](https://docs.docker.com/engine/reference/commandline/login/)
- [Docker Tag CLI Reference](https://docs.docker.com/engine/reference/commandline/tag/)
- [Docker Push CLI Reference](https://docs.docker.com/engine/reference/commandline/push/)
- [Deploying a Registry Server](https://docs.docker.com/registry/deploying/)
