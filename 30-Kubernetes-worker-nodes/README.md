# Kubernetes Worker Nodes

## Overview

A **Worker Node** is simply a machine — a computer, an EC2 instance, for example — running somewhere and managed by the **Master Node**.

---

## What runs inside a Worker Node

```
┌──────────────────────────────────────────────────────────┐
│                      WORKER NODE                         │
│              (your machine / EC2 instance)               │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │                     POD A                         │  │
│  │                                                    │  │
│  │   ┌──────────────────┐   ┌──────────────────┐    │  │
│  │   │   Container 1    │   │   Container 2    │    │  │
│  │   │  (app / backend) │   │  (sidecar / etc) │    │  │
│  │   └──────────────────┘   └──────────────────┘    │  │
│  │   ┌──────────────────────────────────────────┐    │  │
│  │   │         Volume (shared storage)          │    │  │
│  │   └──────────────────────────────────────────┘    │  │
│  │   ┌──────────────────────────────────────────┐    │  │
│  │   │      Config (env vars, secrets, etc.)    │    │  │
│  │   └──────────────────────────────────────────┘    │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │                     POD B                         │  │
│  │   ┌──────────────────┐                            │  │
│  │   │   Container 3    │  (different task / image)  │  │
│  │   └──────────────────┘                            │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌──────────────────┐  ┌────────────┐  ┌────────────┐  │
│  │      Docker      │  │  kubelet   │  │   Proxy    │  │
│  │ (runs containers)│  │ (talks to  │  │ (traffic   │  │
│  │                  │  │ Master Node│  │  control)  │  │
│  └──────────────────┘  └────────────┘  └────────────┘  │
└──────────────────────────────────────────────────────────┘
                          ▲
                          │ managed by
                          ▼
                    MASTER NODE
```

---

## Pods

- A **Pod** hosts one or more application containers and all their associated resources.
- Resources inside a Pod include:
  - **Configuration** — environment variables, secrets, and settings needed to run the containers correctly.
  - **Volumes** — shared storage space on disk that containers within the Pod can read from and write to.
- Pods are **created, managed, and deleted by Kubernetes** (the Master Node).
- You can have **multiple Pods on a single Worker Node**, which can be:
  - **Scaled copies** of the same Pod — to distribute incoming traffic across multiple identical instances.
  - **Completely different Pods** — running different containers for entirely different tasks.

### Single vs Multiple Containers in a Pod

| Scenario | When to use |
|---|---|
| **One container per Pod** | The most common pattern; one app process per Pod |
| **Multiple containers per Pod** | When containers need to work together very closely (e.g. a main app + a logging sidecar) |

---

## Software on every Worker Node

| Software | Purpose |
|---|---|
| **Docker** | Required to create and run the containers inside each Pod |
| **kubelet** | Communication service between the Worker Node and the Master Node; allows the Master Node to control and monitor Pods on this node |
| **Proxy (kube-proxy)** | Handles incoming and outgoing network traffic; ensures only allowed traffic reaches the Pods and leaves the node |

---

## Key Characteristics

- A Worker Node is **not task-specific** — it is simply a machine with a certain amount of CPU and memory.
- Just like running multiple containers with `docker run` or `docker compose` on your local machine (backend + frontend + database), a Worker Node can run **totally different containers and tasks** simultaneously.
- Worker Nodes are typically machines offered by a **cloud provider** (e.g. AWS EC2 instances), not your local machine.

---

## Kubernetes Desired State Model

With Kubernetes, you only define the **desired end state** — what should be running and how.

If you use a cloud provider like **AWS**, services such as **Amazon EKS** will:
1. Provision the required EC2 instances (Worker Nodes).
2. Install all required software (Docker, kubelet, kube-proxy).
3. Register the nodes with the Master Node.

You do **not** have to configure individual machines manually. You just need to understand what is happening under the hood so you know what your configuration is doing.


## Why Can't You Put All 4 Containers in One Pod? (Frontend, Banking API, Authentication, Background Worker)

You **can** technically put all 4 containers inside one Pod — Kubernetes allows it. But for an enterprise banking application, separate Pods per service is the standard approach. The reason comes down to how Kubernetes uses the Pod as its fundamental unit of **deployment, scaling, and scheduling**.

---

### Option A — All 4 containers in one Pod

```
┌─────────────────────────────────────────────┐
│              ONE KUBERNETES POD             │
│   (shared network namespace & lifecycle)    │
│                                             │
│  ┌──────────────────┐  ┌─────────────────┐  │
│  │ Angular Frontend │  │   Banking API   │  │
│  │  (Nginx server)  │  │   (Node.js)     │  │
│  └──────────────────┘  └─────────────────┘  │
│  ┌──────────────────┐  ┌─────────────────┐  │
│  │ Authentication   │  │Background Worker│  │
│  │   (Python)       │  │   (Node.js)     │  │
│  └──────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────┘
```

This is valid, but it introduces serious trade-offs:

| Problem | Why it matters |
|---|---|
| **No independent scaling** | If the Banking API needs 5 replicas but the frontend needs 2, you cannot scale them separately — the entire Pod scales together |
| **No independent deployment** | Updating one container forces the whole Pod to be replaced, disrupting all other services |
| **No independent resource allocation** | You cannot give the Authentication service more CPU without resizing the entire Pod |
| **Blast radius on failure** | A crash loop in one container affects the scheduling and lifecycle of all four |

---

### Option B — Four separate Pods (recommended enterprise approach)

```
┌──────────────────────────────────────────────────────┐
│                  KUBERNETES CLUSTER                  │
│                                                      │
│  ┌───────────────┐  ┌───────────────┐                │
│  │ Frontend Pod  │  │  API Pod      │                │
│  │  × 2 replicas │  │  × 5 replicas │                │
│  │  (Nginx)      │  │  (Node.js)    │                │
│  └───────────────┘  └───────────────┘                │
│  ┌───────────────┐  ┌───────────────┐                │
│  │  Auth Pod     │  │  Worker Pod   │                │
│  │  × 3 replicas │  │  × 2 replicas │                │
│  │  (Python)     │  │  (Node.js)    │                │
│  └───────────────┘  └───────────────┘                │
└──────────────────────────────────────────────────────┘
```

> Replica counts are illustrative only, not production sizing recommendations.

Each service gets its own **Deployment** (which manages replicas) and its own **Service** (which provides a stable network endpoint for other services to call).

| Operational need | With separate Pods |
|---|---|
| Banking API traffic spikes | Scale only the API Deployment |
| Frontend gets a new build | Deploy frontend independently, zero downtime for API |
| Worker needs more CPU | Adjust worker resource limits without touching other services |
| Authentication needs patching | Update and restart auth Pods only |
| One service crashes | Other services keep running unaffected |

---

### When should multiple containers share one Pod?

Multiple containers per Pod are appropriate when they are **tightly coupled** and must run together as a single unit. The common pattern is the **sidecar pattern**:

| Sidecar use case | Description |
|---|---|
| **App + logging sidecar** | <img src="./imgs/Application + logging sidecar.jpg" width="90%" /> <br/> The sidecar collects or ships logs from the main app container |
| **App + proxy sidecar** | <img src="./imgs/Application + proxy sidecar.jpg" width="90%" /> <br/> A proxy (e.g. Envoy) handles traffic routing or mTLS on behalf of the app |
| **App + config helper** | <img src="./imgs/Application + helper container.jpg" width="90%" /> <br/> An init or helper container writes shared config files before the main app starts |

Sidecar containers share the Pod's **network namespace** (communicate via `localhost`), share **mounted volumes**, and share the Pod **lifecycle** — which is exactly why they belong together.

The four banking services (frontend, API, auth, worker) do **not** share a lifecycle, do not need to communicate over `localhost`, and are scaled independently — so they do not qualify for the sidecar pattern.

---

### The rule to remember

> **Use one Pod per independently deployable, scalable service.**  
> **Use multiple containers in one Pod only when they form a tightly coupled unit that benefits from a shared lifecycle, network, or storage.**

For the banking application:

| Service | Deployment unit | Reason |
|---|---|---|
| Angular frontend | Separate Pod | Served by Nginx; scales with user traffic |
| Banking API | Separate Pod | Core business logic; scales with API load |
| Authentication | Separate Pod | Security-critical; updated and scaled independently |
| Background worker | Separate Pod | Processes jobs asynchronously; scaled by queue depth |

> **Note on Angular:** Angular compiles to static files. The container does not run Angular itself — it runs a web server (typically Nginx) that serves those static files. The Angular application executes in the user's browser.

---

### Interview answer (one sentence)

> "One Pod can hold multiple containers, but separate Pods are the standard for independently deployable services because they allow independent scaling, deployment, and failure isolation; multiple containers in one Pod are reserved for tightly coupled helpers like sidecars."




