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
