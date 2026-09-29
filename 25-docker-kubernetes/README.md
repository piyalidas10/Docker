# 25 — From Docker to Kubernetes: Architecture & Orchestration Deep Dive

As containerized systems grow from a single server to distributed, highly available production clusters, developers and operators transition from local tools (**Docker & Docker Compose**) to distributed container orchestrators (**Kubernetes**).

---

## 1. The Container Evolution Journey

```
┌────────────────────────────────────────────────────────┐
│                        Docker                          │
│        (Build images, package applications)            │
└───────────────────────────┬────────────────────────────┘
                            │ runs single
                            ▼
┌────────────────────────────────────────────────────────┐
│                      Container                         │
│            (Isolated process on one host)              │
└───────────────────────────┬────────────────────────────┘
                            │ coordinates multiple on 1 host
                            ▼
┌────────────────────────────────────────────────────────┐
│                    Docker Compose                      │
│     (Multi-container apps on a single machine)         │
└───────────────────────────┬────────────────────────────┘
                            │ scales to cluster of servers
                            ▼
┌────────────────────────────────────────────────────────┐
│               Container Orchestration                  │
│   (Auto-scaling, self-healing, rolling updates)        │
└───────────────────────────┬────────────────────────────┘
                            │ industry standard
                            ▼
┌────────────────────────────────────────────────────────┐
│                      Kubernetes                        │
│     (Enterprise production distributed platform)       │
└────────────────────────────────────────────────────────┘
```

---

## Table of Contents

1. [The Container Evolution Journey](#1-the-container-evolution-journey)
2. [The Ecosystem Hierarchy: Docker, containerd, OCI & Kubernetes](#2-the-ecosystem-hierarchy-docker-containerd-oci--kubernetes)
   - [Open Container Initiative (OCI)](#open-container-initiative-oci)
   - [containerd & runc](#containerd--runc)
   - [CRI (Container Runtime Interface) & Kubernetes](#cri-container-runtime-interface--kubernetes)
   - [Does Kubernetes Still Use Docker?](#does-kubernetes-still-use-docker)
3. [Docker vs. Docker Compose vs. Kubernetes Comparison](#3-docker-vs-docker-compose-vs-kubernetes-comparison)
4. [Core Kubernetes Building Blocks](#4-core-kubernetes-building-blocks)
   - [Pod (Atomic Unit)](#1-pod)
   - [ReplicaSet](#2-replicaset)
   - [Deployment (Declarative Updates)](#3-deployment)
   - [Service (ClusterIP, NodePort, LoadBalancer)](#4-service)
   - [Ingress (L7 Routing & TLS)](#5-ingress)
   - [ConfigMap & Secret](#6-configmap--secret)
   - [Namespace (Logical Isolation)](#7-namespace)
   - [StatefulSet (Stateful Workloads)](#8-statefulset)
   - [PersistentVolume (PV) & PersistentVolumeClaim (PVC)](#9-persistentvolume-pv--persistentvolumeclaim-pvc)
   - [Health Probes (liveness, readiness, startup)](#10-health-probes-liveness-readiness-startup)
   - [Resource Limits & Requests](#11-resource-requests--limits)
   - [Horizontal Pod Autoscaler (HPA)](#12-horizontal-pod-autoscaler-hpa)
5. [End-to-End Kubernetes Production Manifest Example](#5-end-to-end-kubernetes-production-manifest-example)
6. [Docker Compose to Kubernetes Mapping](#6-docker-compose-to-kubernetes-mapping)

---

## 2. The Ecosystem Hierarchy: Docker, containerd, OCI & Kubernetes

Understanding modern container infrastructure requires knowing how the low-level runtime specifications connect to high-level orchestrators:

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    High-Level Tools & Orchestrators                        │
│                                                                            │
│     ┌────────────────────────┐                  ┌───────────────────┐      │
│     │   Docker CLI / Compose │                  │    Kubernetes     │      │
│     └───────────┬────────────┘                  └─────────┬─────────┘      │
└─────────────────┼─────────────────────────────────────────┼────────────────┘
                  │ REST API                                │ CRI (gRPC)
                  ▼                                         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                  Container Runtime / Supervisor                            │
│                                                                            │
│                        ┌───────────────────────┐                           │
│                        │      containerd       │ (or CRI-O)                │
│                        └───────────┬───────────┘                           │
└────────────────────────────────────┼───────────────────────────────────────┘
                                     │ OCI Spec
                                     ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                      Low-Level OCI Runtime                                 │
│                                                                            │
│                        ┌───────────────────────┐                           │
│                        │         runc          │                           │
│                        └───────────┬───────────┘                           │
└────────────────────────────────────┼───────────────────────────────────────┘
                                     │ Linux Syscalls (clone, unshare, cgroups)
                                     ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                            Host Linux Kernel                               │
└────────────────────────────────────────────────────────────────────────────┘
```

### Open Container Initiative (OCI)
An open governance industry body that defines open container standards:
- **image-spec**: Standard format for container image manifests, layers, and configs.
- **runtime-spec**: Standard specification for how to run an unpacked container on a host.

---

### `containerd` & `runc`
- **`runc`**: The lightweight reference CLI implementation of the OCI runtime-spec. It talks directly to the Linux kernel to create namespaces, cgroups, and spawn container processes.
- **`containerd`**: An industrial-grade container lifecycle daemon that manages image pulling, storage, network attaching, and delegates container execution to `runc`.

---

### CRI (Container Runtime Interface) & Kubernetes
- **CRI** is the gRPC plugin interface that allows the Kubernetes **kubelet** agent to communicate with any standard container runtime (e.g. `containerd`, `CRI-O`) without having runtime-specific code compiled into Kubernetes.

---

### Does Kubernetes Still Use Docker?
- **Yes and No**: You still use **Docker** to write Dockerfiles and build OCI-compliant container images (`docker build`).
- In Kubernetes clusters (since v1.24+), Kubernetes removed the legacy **Dockershim** translation layer. Kubernetes communicates directly with **`containerd`** (or CRI-O) via CRI. The images built by Docker are 100% OCI-compliant and run seamlessly on Kubernetes.

---

## 3. Docker vs. Docker Compose vs. Kubernetes Comparison

| Dimension | Docker (`docker run`) | Docker Compose | Kubernetes (K8s) |
|---|---|---|---|
| **Scope** | Single container | Multi-container stack | Multi-node distributed cluster |
| **Host Target** | Single host | Single host | Hundreds/Thousands of nodes |
| **Self-Healing** | Basic (`--restart`) | Basic (`restart: always`) | Advanced (auto-restarts, node failover, eviction) |
| **Scaling** | Manual | `docker compose scale` (1 host) | Automatic (Horizontal Pod Autoscaler - HPA) |
| **Load Balancing** | Host port binding | Single host DNS | Built-in L4 Services & L7 Ingress controllers |
| **Rolling Updates** | Manual recreate | Manual / script-based | Native declarative zero-downtime rollouts & rollbacks |
| **Target Use Case** | Dev / Testing / Quick tasks | Local dev / Small production VM | Enterprise microservices & cloud-native clusters |

---

## 4. Core Kubernetes Building Blocks

### 1. Pod
The smallest and most basic deployable compute object in Kubernetes.
- A Pod encapsulates **one or more tightly-coupled containers** that share the same network namespace (IP address and port space) and storage volumes.
- In 95% of cases, you run **one container per Pod** (except for sidecar patterns like logging proxies or service meshes).

---

### 2. ReplicaSet
Maintains a stable set of identical replica Pods running at any given time. Ensures high availability by automatically spinning up new Pods if existing ones crash or nodes fail.

---

### 3. Deployment
A higher-level declarative controller that manages **ReplicaSets** and provides declarative zero-downtime **Rolling Updates**, pause/resume capabilities, and instant rollback to previous revisions.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-deployment
  labels:
    app: api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: api-container
          image: myregistry.com/my-api:v1.4.2
          ports:
            - containerPort: 3000
```

---

### 4. Service
An abstract way to expose an application running on a set of Pods as a network service with a single stable IP address and DNS name. Pods are ephemeral, but Services provide stable endpoints:
- **`ClusterIP`** (default): Accessible only inside the Kubernetes cluster.
- **`NodePort`**: Exposes the service on each Node's static port (`30000-32767`).
- **`LoadBalancer`**: Provisions a cloud provider load balancer (AWS NLB/ALB, GCP LB) pointing to the service.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-service
spec:
  type: ClusterIP
  selector:
    app: api
  ports:
    - port: 80
      targetPort: 3000
```

---

### 5. Ingress
An API object that manages external HTTP/HTTPS routing into cluster Services, providing SSL/TLS termination, name-based virtual hosting, and path-based routing (e.g., using NGINX Ingress, Traefik, or AWS ALB Ingress Controller).

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-service
                port:
                  number: 80
```

---

### 6. ConfigMap & Secret
Decouples configuration artifacts from container image binaries:
- **`ConfigMap`**: Stores non-confidential key-value pairs or config files (e.g. `NODE_ENV`, NGINX configs).
- **`Secret`**: Stores sensitive data (passwords, tokens, TLS keys) encoded in base64 or integrated with external vaults.

```yaml
# ConfigMap Example
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-config
data:
  NODE_ENV: "production"
  PORT: "3000"
---
# Secret Example
apiVersion: v1
kind: Secret
metadata:
  name: api-secrets
type: Opaque
stringData:
  DB_PASSWORD: "super-secure-password"
```

---

### 7. Namespace
Provides virtual cluster partitioning within the same physical Kubernetes cluster. Enables multi-tenancy, access control (RBAC), and resource quota boundaries (e.g., `development`, `staging`, `production`, `monitoring`).

---

### 8. StatefulSet
Manages stateful applications (databases like PostgreSQL, Redis, MongoDB, Kafka) that require:
- Unique, persistent network identities (`db-0`, `db-1`, `db-2`).
- Ordered, graceful deployment and scaling.
- Dedicated persistent storage attached to each individual Pod.

---

### 9. PersistentVolume (PV) & PersistentVolumeClaim (PVC)
- **PersistentVolume (PV)**: A piece of physical storage provisioned in the cluster (AWS EBS, GCP Persistent Disk, NFS, Ceph).
- **PersistentVolumeClaim (PVC)**: A user's request for storage (e.g. "I need 50GB ReadWriteOnce storage"). The claim binds to an available PV or dynamically provisions one via a `StorageClass`.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
```

---

### 10. Health Probes (liveness, readiness, startup)
Kubernetes evaluates container state using three probe types:

| Probe | Purpose | Action on Failure |
|---|---|---|
| **`startupProbe`** | Checks if slow-starting apps have finished initialization. | Kills and restarts the container if timeout exceeded. |
| **`livenessProbe`** | Detects application deadlocks or hung processes. | Kills and restarts the container automatically. |
| **`readinessProbe`** | Determines if the Pod is ready to accept user traffic. | Removes Pod IP from Service endpoints (no traffic routed). |

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 3000
  initialDelaySeconds: 15
  periodSeconds: 20
readinessProbe:
  httpGet:
    path: /ready
    port: 3000
  initialDelaySeconds: 5
  periodSeconds: 10
```

---

### 11. Resource Requests & Limits
Enforces Kubernetes scheduling and runtime guardrails:
- **`requests`**: Guaranteed minimum resources needed to schedule the Pod on a node.
- **`limits`**: Maximum CPU/Memory the container is allowed to consume before being throttled (CPU) or OOM-killed (Memory).

```yaml
resources:
  requests:
    cpu: "250m"      # 0.25 CPU Core
    memory: "256Mi"  # 256 Megabytes
  limits:
    cpu: "1000m"     # 1.0 CPU Core
    memory: "512Mi"  # 512 Megabytes
```

---

### 12. Horizontal Pod Autoscaler (HPA)
Automatically scales the number of Pod replicas in a Deployment based on observed CPU utilization, memory pressure, or custom Prometheus metrics:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-deployment
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 75
```

---

## 5. End-to-End Kubernetes Production Manifest Example

Below is a complete, production-grade manifest (`production-app.yaml`):

```yaml
# 1. ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-config
  namespace: default
data:
  NODE_ENV: "production"
  PORT: "3000"
---
# 2. Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-deployment
  namespace: default
  labels:
    app: api
spec:
  replicas: 3
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: api
          image: ghcr.io/myorg/my-api:v1.4.2
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 3000
          envFrom:
            - configMapRef:
                name: api-config
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "1000m"
              memory: "512Mi"
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 15
            periodSeconds: 20
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 10
---
# 3. Service
apiVersion: v1
kind: Service
metadata:
  name: api-service
  namespace: default
spec:
  type: ClusterIP
  selector:
    app: api
  ports:
    - port: 80
      targetPort: 3000
---
# 4. Horizontal Pod Autoscaler
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-deployment
  minReplicas: 3
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 75
```

---

## 6. Docker Compose to Kubernetes Mapping

| Docker Compose Concept | Kubernetes Equivalent |
|---|---|
| `service:` | `Deployment` + `Pod` |
| `ports:` | `Service` (ClusterIP / NodePort / LoadBalancer) + `Ingress` |
| `environment:` / `env_file:` | `ConfigMap` and `Secret` |
| `volumes:` (named) | `PersistentVolumeClaim` (PVC) + `PersistentVolume` (PV) |
| `volumes:` (bind mount) | `hostPath` volume (discouraged in prod) or ConfigMap file mount |
| `restart: always` | Controlled natively by `Deployment` & `ReplicaSet` controllers |
| `healthcheck:` | `livenessProbe`, `readinessProbe`, and `startupProbe` |
| `deploy.resources:` | `resources.requests` and `resources.limits` |
| `networks:` | Flat cluster pod network (CNI plugins like Calico, Cilium) |

---

## References

- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [Open Container Initiative (OCI) Specifications](https://opencontainers.org/)
- [containerd Architecture](https://containerd.io/)
- [Kubernetes Container Runtime Interface (CRI)](https://kubernetes.io/docs/concepts/architecture/cri/)
- [Kubernetes Production Best Practices](https://kubernetes.io/docs/setup/best-practices/)
