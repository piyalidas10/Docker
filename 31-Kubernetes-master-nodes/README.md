# Kubernetes Master Nodes

## Overview

The **Master Node** is the **Cluster Control Plane** — it manages all Worker Nodes and the Pods running on them. It does not run application containers itself; instead, it runs a set of control services that keep the cluster in the desired state.

---

## What runs inside a Master Node

```
┌──────────────────────────────────────────────────────────┐
│                      MASTER NODE                         │
│                  (Cluster Control Plane)                 │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │                   API Server                       │  │
│  │  - Entry point for all communication               │  │
│  │  - Counterpart to the kubelet on Worker Nodes      │  │
│  │  - Receives instructions and relays them           │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │                   Scheduler                        │  │
│  │  - Watches for new / unhealthy Pods                │  │
│  │  - Decides which Worker Node a new Pod runs on     │  │
│  │  - Tells the API Server what to tell the nodes     │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │             Kube-Controller Manager                │  │
│  │  - Watches and controls Worker Nodes overall       │  │
│  │  - Ensures the correct number of Pods are running  │  │
│  │  - Works closely with Scheduler & API Server       │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │             Cloud-Controller Manager               │  │
│  │  - Cloud-provider-specific variant of the above    │  │
│  │  - Translates Kubernetes instructions to AWS,      │  │
│  │    Azure, GCP, etc.                                │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │                     etcd                           │  │
│  │  - Distributed key-value store                     │  │
│  │  - Holds the entire cluster state                  │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
          │  manages via API Server + kubelet
          ▼
┌─────────────────┐   ┌─────────────────┐
│  WORKER NODE 1  │   │  WORKER NODE 2  │  ...
└─────────────────┘   └─────────────────┘
```

---

## Services on the Master Node

| Service | Purpose |
|---|---|
| **API Server** | The central communication hub of the cluster. It is the counterpart to the `kubelet` running on each Worker Node, and is the only component that reads from and writes to `etcd`. |
| **Scheduler** | Watches for Pods that have no assigned node (e.g. after scaling or a Pod crash) and selects the best Worker Node to place them on. It then instructs the API Server accordingly. |
| **Kube-Controller Manager** | Runs a set of controllers that continuously reconcile the actual cluster state with the desired state — ensuring the right number of Pods are always up and running. Works closely with the Scheduler and API Server. |
| **Cloud-Controller Manager** | A cloud-provider-specific variant of the Kube-Controller Manager. Translates Kubernetes instructions into API calls to AWS, Azure, GCP, etc. Allows cloud providers to manage infrastructure on your behalf. |
| **etcd** | A distributed, reliable key-value store that persists the entire cluster state. Only the API Server communicates with etcd directly. |

---

## How the Master Node services work together

```
kubectl apply -f config.yaml
        │
        ▼
  ┌─────────────┐
  │  API Server │ ◄──────────────────────────────────┐
  └──────┬──────┘                                    │
         │                                           │
         ▼                                           │
  ┌─────────────┐    new Pod needed?    ┌───────────────────────┐
  │  Scheduler  │ ─────────────────────►│  Pick Worker Node     │
  └─────────────┘                       └──────────┬────────────┘
                                                   │
         ┌─────────────────────────────────────────┘
         │ instruct kubelet on chosen Worker Node
         ▼
  ┌──────────────────┐
  │  Worker Node     │
  │  (kubelet starts │
  │   the Pod)       │
  └──────────────────┘
         ▲
  ┌──────────────────────┐
  │ Kube-Controller Mgr  │  watches overall node & Pod health,
  │ Cloud-Controller Mgr │  reconciles state, talks to cloud APIs
  └──────────────────────┘
```

---

## Cloud Provider Integration

Major cloud providers (AWS, Azure, GCP) offer **managed Kubernetes services** (e.g. Amazon EKS, Azure AKS, Google GKE) that:

1. **Provision** the Master Node infrastructure automatically.
2. **Run** all control-plane services (API Server, Scheduler, Controller Managers, etcd) on your behalf.
3. Use the **Cloud-Controller Manager** to translate Kubernetes desired state into cloud-specific API calls (e.g. creating load balancers, attaching storage volumes, spinning up EC2 instances).

As a developer, you only need to **provide your Kubernetes configuration** (desired state). The cloud provider handles all the heavy lifting of setting up and maintaining the control plane.
