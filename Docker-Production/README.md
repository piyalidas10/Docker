# Docker in Production

## Why Containers Matter Beyond Development

Containers are great for development — but their real power shines when you move to production. Containers are independent, isolated packages containing both your **application code** and its **entire environment**. Because they are standardized and built with Docker, they can run on any machine where Docker is installed.

---

## The Core Problem Containers Solve

Without containers, teams frequently encounter mismatches between development and production environments:

- Code that works locally fails once deployed to a remote server.
- Different machines have different tool versions (e.g. Node.js).
- Manual configuration of each host machine is error-prone and inconsistent.

With Docker, the environment lives **inside the container** — not on the host machine. You don't install Node.js (or any other runtime) on your local machine or your production server. Everything the application needs is packaged inside the container image.

This means:
> **What works in a container on your local machine will also work after deployment on a remote machine.**

---

## Development and Production: Same Containers

Everything learned about Docker during local development applies directly to production. You ship the **same containers** you worked on locally to remote machines. The reproducible, isolated environment is the same in both places — that's the entire idea behind Docker.

Moving an application to production is therefore a matter of:
1. Building the image locally (or in CI).
2. Shipping that image to a remote host running Docker.
3. Running the container there to serve your users.

---

## Key Things to Watch Out For When Deploying

### 1. Bind Mounts → Do Not Use in Production

During development, bind mounts are used heavily to reflect live code changes inside running containers. In production, **bind mounts should not be used**. Production containers should be fully self-contained — all required code must be baked into the image at build time, not mounted from the host filesystem.

This does not contradict the container philosophy. The same container image still runs identically in both environments; the bind mount is simply a development convenience that is removed for production.

### 2. Some Apps Need a Build Step

Certain applications — React apps being a common example — require a **build step** that converts and optimizes source code before it can be served. This step happens after development and before deployment. Even so, you can still ship containers with fully reproducible environments. This module covers how to handle build steps correctly so the "same environment" guarantee is preserved.

### 3. Multi-Container Projects May Span Multiple Hosts

In multi-container projects, what runs together on one machine via Docker Compose during local development **may need to be split across multiple remote servers** in production. Whether to co-locate or split containers depends on the project, its scale, and its architecture. This is explored in depth throughout this module.

### 4. Control vs. Responsibility Trade-Off

Managing your own remote host gives you full control but also full responsibility — including keeping the machine secure, patched, and properly configured. This module includes lectures where we deliberately choose solutions with **less control but also less responsibility** (e.g. managed container platforms). For most developers, this trade-off is well worth it.

---

## What This Module Covers

| Topic | Description |
|---|---|
| Deploying containers | Moving containers from localhost to remote machines |
| Image vs. source code deployment | Building locally/CI vs. on remote servers ([`deploying-images-vs-source-code.md`](Docker-Production/deploying-images-vs-source-code.md:1)) |
| Bind mounts in production | Why to avoid them and what to use instead |
| Multi-stage target builds | Using `--target` to build specific stages ([`multi-stage-targeting.md`](Docker-Production/multi-stage-targeting.md:1)) |
| Build steps | Handling apps that require compilation/optimization before serving |
| Multi-container deployment | Splitting containers across multiple hosts when needed |
| Control vs. responsibility | Choosing managed platforms to reduce operational burden ([`deployment-philosophies.md`](Docker-Production/deployment-philosophies.md:1)) |
| Complete module wrap-up | Architectural evolution, persistent storage, and managed databases ([`module-summary.md`](Docker-Production/module-summary.md:1)) |

---

## Summary

Containers give us **reproducible, portable environments** that behave the same way in development and in production. The sections on local Docker development were not just preparation — everything learned there applies directly when deploying to remote hosts. This module brings it all together by walking through real deployment scenarios, trade-offs, and best practices.

---

## Deployment Scenarios and Getting Started

Docker projects vary in complexity — from a single container to multi-container architectures spanning multiple servers. This module builds up gradually, starting with the simplest case and working toward more complex deployments.

### Starting Point: A Simple Node.js App

The first example is a minimal **Node.js application** with:
- No database
- No additional services
- A single image, a single container

This stripped-down starting point lets us understand the core deployment workflow before tackling more complex scenarios.

### Basic Deployment Approach (Manual)

The fundamental deployment workflow for a self-managed remote server looks like this:

1. **Set up a remote server** — provision a machine in the cloud.
2. **Install Docker** on the remote host.
3. **Connect via SSH** to the remote host from your local machine.
4. **Push your image** to a Docker registry (e.g. Docker Hub) from your local machine.
5. **Pull the image** on the remote host from that registry.
6. **Run the container** on the remote host.
7. **Expose the necessary ports** so end users can reach the application over the internet.

---

## Choosing a Hosting Provider

There are hundreds of Docker-compatible hosting providers available. A quick search for "Docker hosting provider" will surface many options, along with comparison articles to help you choose.

### The Three Major Cloud Providers

The biggest and most widely used cloud service providers are:

| Provider | Full Name |
|---|---|
| **AWS** | Amazon Web Services |
| **Azure** | Microsoft Azure |
| **GCP** | Google Cloud Platform |

These platforms offer far more than just web hosting — they provide entire ecosystems of cloud services covering web hosting, databases, machine learning, networking, and much more.

> This course uses **AWS** as it is the largest cloud provider. However, the Docker concepts covered apply to any provider. Always consult the documentation of your chosen provider for provider-specific steps.

### AWS Free Tier

AWS offers a [free tier](https://aws.amazon.com/free/) that includes:

- **EC2 (Elastic Compute Cloud)** — AWS's remote server service — provides **750 instance hours/month free** for the first 12 months, which is enough to run one server continuously at no cost during that period.

> ⚠️ Always check the current free tier page before starting, as quotas and included services may change over time.

**Note:** A credit card is required to sign up with AWS (and most major hosting providers), even when using free tier services.

---

## AWS EC2: Launching a Remote Server

**EC2 (Elastic Compute Cloud)** is the AWS service used to provision and manage remote virtual machines (called *instances*). In this module, we:

1. Launch an EC2 instance — a remote server hosted by AWS.
2. Install Docker on that instance.
3. Push our local Docker image to Docker Hub.
4. Pull and run that container on the EC2 instance.
5. Verify the running application in a browser.

This is the first and most foundational deployment scenario covered in this module.

---

## Deploying a Node.js App to AWS EC2 — Step by Step

The first real deployment example is a basic **Node.js application** with no database, served to the web via an AWS EC2 instance. Getting it running involves three main steps.

### Step 1: Create and Launch an EC2 Instance

- Spin up a new EC2 instance — a remote virtual machine hosted by AWS.
- Create a **VPC (Virtual Private Cloud)** — a logically isolated network in AWS that the instance lives in.
- Create a **Security Group** — acts as a virtual firewall controlling inbound and outbound traffic to the instance.

### Step 2: Configure the Security Group

- Open (expose) all required ports to the internet so the EC2 instance can receive incoming traffic.
- For a Node app listening on port 80, port 80 must be allowed through the security group.

### Step 3: Connect via SSH and Run the Container

- **SSH (Secure Shell)** is a terminal-based protocol for connecting to and running commands on a remote machine securely.
- Connect to the EC2 instance via SSH from your local machine.
- Once connected, install Docker on the remote host.
- Pull the Docker image from the registry and run the container.

---

## The Demo Application

The example project is a minimal Node.js app that:
- Serves a single HTML file (`welcome.html`) for all incoming requests.
- Listens on **port 80**.
- Uses the **Alpine variant** of the Node base image (`node:alpine`) to keep the image size small and speed up build and deployment.

A `Dockerfile` is already provided with the project.

---

## Building and Testing Locally

Before deploying, build and verify the image locally.

**Build the image:**
```bash
docker build -t node-dep-example .
```

**Run the container locally:**
```bash
docker run -d --rm --name node-dep -p 80:80 node-dep-example
```

| Flag | Purpose |
|---|---|
| `-d` | Detached mode — runs in the background |
| `--rm` | Automatically removes the container when it stops |
| `--name node-dep` | Assigns a name to the container |
| `-p 80:80` | Maps port 80 on the host to port 80 in the container |

No volumes or networks are needed for this basic single-container app.

**Verify:** Open `http://localhost` in a browser — the demo application should be visible.

Once confirmed working locally, the same image is ready to be pushed to Docker Hub and pulled onto the EC2 instance.

---

## Bind Mounts vs. `COPY`: Development vs. Production

You may notice that in the `docker run` command used both locally and for deployment, **no bind mount or volume is used**:

```bash
docker run -d --rm --name node-dep -p 80:80 node-dep-example
```

There is an important distinction between running a container in **development mode** versus **production mode**:

### In Development (Bind Mounts)

- The container must encapsulate the runtime environment (Node.js, dependencies, tools), but **not necessarily the live source code**.
- Code can come from outside the container via a **bind mount** (`-v /path/on/host:/path/in/container`).
- This binds a local project folder directly to a folder inside the running container.
- Any local code changes are reflected **instantly** inside the container without needing to rebuild the image or restart the container.

### In Production (`COPY` / Self-Contained Images)

- When moving to a remote machine to serve end users, the container must be **completely standalone** and independent of its surrounding host.
- The image (and container based on it) should be the **single source of truth** — containing both the runtime environment and all source code.
- If we needed to manually place source code into a specific folder on the remote machine, it would defeat the entire purpose of containerization.
- For production, we use **`COPY` instead of bind mounts** in the `Dockerfile`. All application code is copied into the image during `docker build`, creating a standalone, reproducible snapshot.

### Same `Dockerfile` for Development and Production

Because bind mounts are configured at runtime via the `docker run` command (`-v` flag) — and **not** defined in the `Dockerfile` — you can use the **exact same `Dockerfile`** for both development and production:

| Aspect | Development | Production |
|---|---|---|
| **Source Code Strategy** | Bind Mount (`-v`) | `COPY` in `Dockerfile` |
| **Container Setup** | Depends on host filesystem for live updates | Completely self-contained / standalone |
| **`Dockerfile`** | Uses `COPY` (overwritten by bind mount at runtime) | Uses `COPY` |
| **`docker run` Command** | `docker run -v ...` | `docker run` (no `-v` bind mount) |

> **Key Takeaway:** One container, one image, with `COPY` providing a single reproducible code and environment snapshot that runs anywhere without requiring extra host-level setup.
