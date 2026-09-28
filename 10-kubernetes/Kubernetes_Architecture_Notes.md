# Kubernetes Architecture Notes
> Based on Gate Smashers lecture transcript

---

## Introduction

- **Kubernetes** is a container **orchestration tool** used to manage thousands of containers at scale.
- Before learning Kubernetes, understanding **Docker and containers** is essential.
- The word *orchestration* comes from an **orchestra concert** — a master conductor manages all musicians; similarly, Kubernetes manages all containers.

---

## Why Do We Need Kubernetes?

| Scenario | Without Kubernetes | With Kubernetes |
|---|---|---|
| 2–4 containers | Easy to manage manually | Overkill |
| Thousands of containers | Chaotic, unmanageable | Fully automated |
| Scaling required | Manual intervention | Auto-scaling |
| Load balancing needed | Manual setup | Built-in |
| Node/pod failure | Manual recovery | Auto-recovery |

- In a **CI/CD pipeline**, new deployments and changes happen continuously — Kubernetes automates all of this.

---

## Production Architecture Diagram

```mermaid
flowchart TB
    subgraph External["🌐 External Access"]
        USER["👤 User / Developer\n(kubectl / UI)"]
        LB["⚖️ Load Balancer\n(Cloud / Ingress)"]
        CI["🔄 CI/CD Pipeline\n(Jenkins / GitHub Actions)"]
    end

    subgraph ControlPlane["🧠 Control Plane (Master Node)"]
        direction TB
        API["🖥️ API Server\n(kube-apiserver)\nEntry point — validates all requests"]
        ETCD[("🗄️ ETCD\nKey-Value Store\nCluster state & config")]
        SCHED["📅 Scheduler\n(kube-scheduler)\nAssigns pods to nodes"]
        CM["🔧 Controller Manager\n(kube-controller-manager)\nDesired state reconciliation"]
        CCM["☁️ Cloud Controller Manager\nCloud-provider integration\n(optional)"]

        API <-->|"read/write state"| ETCD
        API --> SCHED
        API --> CM
        API --> CCM
    end

    subgraph WorkerNode1["⚙️ Worker Node 1"]
        direction TB
        KL1["🤖 Kubelet\n(Node Agent)"]
        KP1["🔀 Kube-proxy\n(Networking)"]
        CR1["🐳 Container Runtime\n(Docker / containerd)"]

        subgraph Pod1A["📦 Pod A"]
            C1A["Container 1\n(App)"]
            C1B["Container 2\n(Sidecar)"]
        end
        subgraph Pod1B["📦 Pod B"]
            C1C["Container 3\n(DB)"]
        end

        KL1 --> CR1
        CR1 --> Pod1A
        CR1 --> Pod1B
        KP1 -. "networking" .-> Pod1A
        KP1 -. "networking" .-> Pod1B
    end

    subgraph WorkerNode2["⚙️ Worker Node 2"]
        direction TB
        KL2["🤖 Kubelet\n(Node Agent)"]
        KP2["🔀 Kube-proxy\n(Networking)"]
        CR2["🐳 Container Runtime\n(Docker / containerd)"]

        subgraph Pod2A["📦 Pod C"]
            C2A["Container 4\n(Frontend)"]
        end
        subgraph Pod2B["📦 Pod D"]
            C2B["Container 5\n(Backend)"]
            C2C["Container 6\n(Logger)"]
        end

        KL2 --> CR2
        CR2 --> Pod2A
        CR2 --> Pod2B
        KP2 -. "networking" .-> Pod2A
        KP2 -. "networking" .-> Pod2B
    end

    subgraph WorkerNode3["⚙️ Worker Node 3 (Auto-scaled)"]
        direction TB
        KL3["🤖 Kubelet\n(Node Agent)"]
        KP3["🔀 Kube-proxy\n(Networking)"]
        CR3["🐳 Container Runtime"]

        subgraph Pod3A["📦 Pod E"]
            C3A["Container 7\n(Replica)"]
        end

        KL3 --> CR3
        CR3 --> Pod3A
        KP3 -. "networking" .-> Pod3A
    end

    subgraph Storage["💾 Persistent Storage"]
        PV["Persistent Volume\n(PV)"]
        PVC["Persistent Volume Claim\n(PVC)"]
        SC["Storage Class\n(Dynamic provisioning)"]
        PVC --> PV
        PVC --> SC
    end

    subgraph Monitoring["📊 Observability"]
        PROM["Prometheus\n(Metrics)"]
        GRAF["Grafana\n(Dashboards)"]
        LOG["Log Aggregator\n(EFK / Loki)"]
        PROM --> GRAF
    end

    %% External to Control Plane
    USER -->|"kubectl commands\n(HTTPS:6443)"| API
    CI -->|"deploy manifests"| API
    LB -->|"route traffic"| KP1 & KP2 & KP3

    %% Control Plane to Worker Nodes
    API -->|"schedule pod"| KL1
    API -->|"schedule pod"| KL2
    API -->|"schedule pod"| KL3
    SCHED -->|"node selection"| API
    CM -->|"watch & reconcile"| API

    %% Worker Nodes cross-networking
    KP1 <-->|"pod-to-pod\ncommunication"| KP2
    KP2 <-->|"pod-to-pod\ncommunication"| KP3

    %% Storage
    Pod1B -->|"mounts"| PVC
    Pod2B -->|"mounts"| PVC

    %% Monitoring
    KL1 & KL2 & KL3 -->|"metrics/logs"| PROM
    Pod1A & Pod2A -->|"app logs"| LOG

    classDef controlplane fill:#dbeafe,stroke:#3b82f6,color:#1e3a8a
    classDef worker fill:#dcfce7,stroke:#16a34a,color:#14532d
    classDef external fill:#fef9c3,stroke:#ca8a04,color:#713f12
    classDef storage fill:#f3e8ff,stroke:#9333ea,color:#4a044e
    classDef observe fill:#ffe4e6,stroke:#e11d48,color:#881337

    class API,ETCD,SCHED,CM,CCM controlplane
    class KL1,KP1,CR1,Pod1A,Pod1B,C1A,C1B,C1C controlplane
    class KL2,KP2,CR2,Pod2A,Pod2B,C2A,C2B,C2C worker
    class KL3,KP3,CR3,Pod3A,C3A worker
    class USER,LB,CI external
    class PV,PVC,SC storage
    class PROM,GRAF,LOG observe
```

**Diagram Key:**
| Colour | Zone |
|---|---|
| 🔵 Blue | Control Plane (Master Node) & Worker Node 1 |
| 🟢 Green | Worker Nodes 2 & 3 |
| 🟡 Yellow | External access (users, CI/CD, load balancer) |
| 🟣 Purple | Persistent storage layer |
| 🔴 Red | Observability (Prometheus, Grafana, logging) |

- **Cluster** = Collection of nodes (master + workers), like a hotel.
- **Node** = A physical or virtual server.
- **Pod** = Smallest deployable unit; contains one or more containers.
- **Persistent Volume (PV/PVC)** = Durable storage that survives pod restarts.
- **Cloud Controller Manager** = Optional component that integrates with AWS/GCP/Azure APIs.

---

## Master Node Components

### 1. API Server
- **Entry point** for all client requests (via UI or CLI).
- Acts like the **reception area** of a hotel.
- Validates syntax and authenticates requests before processing.

### 2. ETCD
- A **key-value pair database**.
- Stores the **entire cluster state**: which nodes exist, which pods are running, which have availability.
- Like the hotel's **booking register** — checks room availability.

### 3. Scheduler
- Decides **which pod gets allocated** to which worker node, based on resource availability (CPU, memory).
- Like the **hotel manager** who assigns you to Room 501.
- After allocation, the assignment is saved back to ETCD.

### 4. Control Manager
- Monitors the **health and state** of the cluster continuously.
- If a pod fails, it **replicates or reschedules** it on a new pod/node.
- Ensures the **desired state matches the actual state** — like ensuring a hotel guest has water, electricity, and services throughout their stay.

---

## Worker Node Components

### 5. Kubelet
- A **node agent** running on every worker node.
- Watches the API server for assigned pods and **deploys the container** into the allocated pod.
- Like **room service** — escorts your luggage to Room 501 and sets everything up.
- Continuously checks that pods are **running and healthy**.

### 6. Kube-proxy
- Handles **networking and load balancing** between pods.
- Enables **pod-to-pod communication** (like a walkie-talkie/phone system between hotel rooms).
- Prevents overload — ensures no single pod is overwhelmed while another sits idle.

### 7. Container Runtime
- The engine that actually **runs the containers** (e.g., Docker).
- Controls when containers start, stop, and pause.
- Manages the underlying **CPU and memory** usage.

---

## Real-Life Hotel Analogy Summary

| Kubernetes Component | Hotel Analogy |
|---|---|
| Cluster | The entire hotel |
| Master Node | Hotel headquarters / management |
| Worker Node | Individual floors / sections |
| Pod | A hotel room |
| Container | Guest (with luggage/dependencies) |
| API Server | Reception desk |
| ETCD | Booking register / database |
| Scheduler | Hotel manager assigning rooms |
| Control Manager | Operations manager (ensures guest happiness) |
| Kubelet | Room service / bellboy |
| Kube-proxy | Internal phone/walkie-talkie network |
| Container Runtime | Actual room infrastructure (electricity, water) |

---

## Request Flow — Step by Step

1. **Client** sends a deploy request via UI or CLI.
2. Request hits the **API Server** → validates the request.
3. **ETCD** is queried → checks available resources in the cluster.
4. **Scheduler** allocates an appropriate **Pod** on a worker node.
5. Allocation is saved back to **ETCD**.
6. **API Server** forwards the instruction to the worker node.
7. **Kubelet** (on the worker node) receives the instruction and deploys the container into the pod.
8. **Kube-proxy** sets up networking so pods can communicate and balances load.
9. **Control Manager** continuously monitors — if anything fails, it self-heals.

---

## Key Takeaways

- Kubernetes is essential when managing **large-scale containerized applications**.
- The **master node** orchestrates everything; **worker nodes** do the actual work.
- Every component has a clear, single responsibility.
- The system is **self-healing** — failed pods are automatically restarted or rescheduled.
- Kubernetes integrates naturally into **DevOps CI/CD pipelines**.

---

*Source: Gate Smashers — Kubernetes Architecture lecture*
