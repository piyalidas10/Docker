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


---


# Kubernetes Pods: One Container or Multiple Containers?

## Core concept

**Yes, a Kubernetes Pod can contain multiple containers.** However, for independently deployable application services, a common enterprise design is to run each service in its own Pod, managed by its own Kubernetes Deployment.

A Worker Node is a machine that provides CPU, memory, storage, and networking resources. It can run many Pods, and each Pod can contain one or more containers.

## Option A: All four containers in one Pod

```text
Kubernetes Worker Node
└── One Pod
    ├── Angular frontend container
    ├── Banking API container
    ├── Authentication container
    └── Background worker container
```

This is valid Kubernetes architecture, but all four containers are scheduled together as one Pod.

### Trade-offs

- **Scaling:** You cannot independently scale one container by scaling the Pod. Scaling the Pod creates another copy of the whole Pod, including all four containers.
- **Deployment:** The containers share a Pod lifecycle. Updating a container image through a Pod's controller generally replaces the Pod, so the other containers may be restarted too.
- **Resources:** Each container can have its own CPU and memory requests and limits. However, the containers are scheduled together on the same node.
- **Failure isolation:** A container can fail without necessarily stopping the other containers immediately, but all four services share the same Pod boundary and placement.
- **Networking:** Containers in the same Pod share a network namespace and can communicate through `localhost`. They must avoid conflicting port usage.

## Option B: Four separate Pods

A typical design for independently scalable services looks like this:

```text
Kubernetes Cluster
├── Frontend Deployment
│   └── Frontend Pods (e.g., 2 replicas)
├── Banking API Deployment
│   └── Banking API Pods (e.g., 5 replicas)
├── Authentication Deployment
│   └── Authentication Pods (e.g., 3 replicas)
└── Background Worker Deployment
    └── Worker Pods (e.g., 2 replicas)
```

*Replica counts above are illustrative, not production sizing recommendations.*

### Why separate Pods?

| Requirement | Benefit of separate Pods |
|---|---|
| Banking API traffic increases | Scale the API without duplicating the frontend, authentication service, and worker |
| Frontend needs a new version | Deploy the frontend independently |
| Worker needs more CPU or memory | Tune worker resources independently |
| Authentication needs maintenance | Update authentication independently |
| One service needs more replicas | Scale that service without scaling every other service |

Kubernetes **Deployments** commonly manage the desired number of replicas for each stateless service. Kubernetes **Services** can provide stable network endpoints for communication between services.

## When should multiple containers share one Pod?

Multiple containers in one Pod are useful when they are tightly coupled and need to run together. Common examples include:

1. **Application + logging sidecar:** A helper collects or processes logs for the main application.
2. **Application + proxy sidecar:** A proxy supports traffic handling or communication for the main application.
3. **Application + helper container:** A helper updates files or configuration shared with the main application through a mounted volume.

This is commonly called the **sidecar pattern**. Containers in the same Pod share a network namespace and can share mounted volumes.

## Banking application recommendation

For these four services, a sensible starting architecture is:

- **Angular frontend:** Its own Deployment and Pods. Angular is normally built into static files served by Nginx or another web server. The Angular application itself runs in the user's browser; the web server runs in the container.
- **Banking API:** Its own Deployment and Pods.
- **Authentication service:** Its own Deployment and Pods.
- **Background worker:** Its own Deployment and Pods.

This lets each service be deployed, scaled, and resource-tuned independently.

## Key takeaway

> One Pod can contain multiple containers, but separate Pods are generally preferred for application services that need independent deployment and scaling. Use multiple containers in one Pod when they form a tightly coupled unit that benefits from sharing a lifecycle, network namespace, or storage.

### Quick interview answer

**Why not put all four containers in one Pod?**

You can, but scaling the Pod would duplicate all four containers together. Separate Pods managed by separate Deployments let the frontend, API, authentication service, and background worker scale and release independently. Multiple containers in one Pod are more appropriate for tightly coupled helpers such as sidecars.





