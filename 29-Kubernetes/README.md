# Kubernetes

## Core Components

- **Cluster**: A set of Node machines which are running the Containerized Application (Worker Nodes) or control other Nodes (Master Node)
- **Nodes**: Physical or virtual machine with a certain hardware capacity which hosts one or multiple Pods and communicates with the Cluster
- **Master Node**: Cluster Control Plane, managing the Pods across Worker Nodes
- **Worker Node**: Hosts Pods, running App Containers (+ resources)
- **Pods**: Pods hold the actual running App Containers + their required resources (e.g. volumes)
- **Containers**: Normal (Docker) Containers
- **Services**: A logical set (group) of Pods with a unique, Pod- and Container-independent IP address

---

## Kubernetes Architecture

The diagram below shows how all core components relate to each other inside a Kubernetes Cluster.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            CLUSTER                                      │
│                                                                         │
│  ┌──────────────────────────────┐                                       │
│  │        MASTER NODE           │                                       │
│  │   (Cluster Control Plane)    │                                       │
│  │                              │                                       │
│  │  ┌────────────────────────┐  │                                       │
│  │  │    API Server          │  │  ← Entry point for all commands       │
│  │  └────────────────────────┘  │                                       │
│  │  ┌────────────────────────┐  │                                       │
│  │  │    Scheduler           │  │  ← Assigns Pods to Worker Nodes       │
│  │  └────────────────────────┘  │                                       │
│  │  ┌────────────────────────┐  │                                       │
│  │  │  Controller Manager    │  │  ← Monitors & reconciles cluster state│
│  │  └────────────────────────┘  │                                       │
│  │  ┌────────────────────────┐  │                                       │
│  │  │       etcd             │  │  ← Distributed key-value state store  │
│  │  └────────────────────────┘  │                                       │
│  └──────────────────────────────┘                                       │
│                 │  controls & schedules                                  │
│                 ▼                                                        │
│  ┌──────────────────────┐   ┌──────────────────────┐                   │
│  │     WORKER NODE 1    │   │     WORKER NODE 2    │  ...              │
│  │                      │   │                      │                   │
│  │  ┌────────────────┐  │   │  ┌────────────────┐  │                   │
│  │  │    SERVICE     │  │   │  │    SERVICE     │  │                   │
│  │  │  (stable IP)   │  │   │  │  (stable IP)   │  │                   │
│  │  └───────┬────────┘  │   │  └───────┬────────┘  │                   │
│  │          │ routes to │   │          │ routes to │                   │
│  │  ┌───────▼────────┐  │   │  ┌───────▼────────┐  │                   │
│  │  │     POD A      │  │   │  │     POD C      │  │                   │
│  │  │ ┌────────────┐ │  │   │  │ ┌────────────┐ │  │                   │
│  │  │ │ Container  │ │  │   │  │ │ Container  │ │  │                   │
│  │  │ └────────────┘ │  │   │  │ └────────────┘ │  │                   │
│  │  │ ┌────────────┐ │  │   │  └────────────────┘  │                   │
│  │  │ │  Volumes   │ │  │   │  ┌────────────────┐  │                   │
│  │  │ └────────────┘ │  │   │  │     POD D      │  │                   │
│  │  └────────────────┘  │   │  │ ┌────────────┐ │  │                   │
│  │  ┌────────────────┐  │   │  │ │ Container  │ │  │                   │
│  │  │     POD B      │  │   │  │ └────────────┘ │  │                   │
│  │  │ ┌────────────┐ │  │   │  └────────────────┘  │                   │
│  │  │ │ Container  │ │  │   │                      │                   │
│  │  │ └────────────┘ │  │   │  ┌────────────────┐  │                   │
│  │  └────────────────┘  │   │  │    kubelet     │  │                   │
│  │                      │   │  │  kube-proxy    │  │                   │
│  │  ┌────────────────┐  │   │  └────────────────┘  │                   │
│  │  │    kubelet     │  │   └──────────────────────┘                   │
│  │  │  kube-proxy    │  │                                               │
│  │  └────────────────┘  │                                               │
│  └──────────────────────┘                                               │
└─────────────────────────────────────────────────────────────────────────┘
```

### How the components interact

| Component | Role | Communicates With |
|---|---|---|
| **Cluster** | Top-level boundary grouping all nodes and resources | Contains Master Node + Worker Nodes |
| **Master Node** | Control Plane — makes global decisions about the cluster | API Server talks to all Worker Nodes via kubelet |
| **API Server** | Single entry point for `kubectl` commands and internal calls | Scheduler, Controller Manager, etcd, kubelets |
| **Scheduler** | Watches for unscheduled Pods and assigns them to a Worker Node | API Server |
| **Controller Manager** | Runs controllers that reconcile desired vs actual state | API Server |
| **etcd** | Persistent store for all cluster state | API Server only |
| **Worker Node** | Runs the actual workloads (Pods & Containers) | Registers with Master Node via kubelet |
| **kubelet** | Agent on each Worker Node; ensures Pods are running | API Server |
| **kube-proxy** | Maintains network rules on each Node for Service routing | API Server |
| **Pod** | Smallest deployable unit; wraps one or more Containers + Volumes | Exposed via a Service |
| **Container** | Docker container running the application code | Lives inside a Pod |
| **Service** | Stable virtual IP + DNS name that load-balances traffic to Pods | Routes to matching Pods via label selectors |

### Request flow (end to end)

1. A user runs `kubectl apply` → request hits the **API Server** on the **Master Node**.
2. The **Scheduler** picks a suitable **Worker Node** for any new **Pods**.
3. The **kubelet** on that **Worker Node** pulls the image and starts the **Container** inside the **Pod**.
4. A **Service** is created with a stable IP and a label selector pointing to those **Pods**.
5. Incoming traffic hits the **Service** IP → **kube-proxy** routes it to a healthy **Pod** → the **Container** handles the request.
