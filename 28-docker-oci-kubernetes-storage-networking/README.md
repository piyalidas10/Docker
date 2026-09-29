# 28 — Docker/OCI Image + Kubernetes Orchestration + External/Cluster Storage & Networking

When migrating production workloads from local Docker environments to enterprise-grade Kubernetes platforms, the underlying concepts evolve from single-node Docker primitives into distributed, fault-tolerant cluster abstractions.

---

## 1. Docker Concept vs. Production Kubernetes Equivalent

| Docker Concept | Production Kubernetes Equivalent | Architectural Reality |
|---|---|---|
| **Docker Image** | ✅ **Still used** (OCI Image) | Kubernetes pulls standard OCI/Docker container images from authenticated registries (ECR, GHCR, Docker Hub, Harbor). |
| **Container** | ✅ **Still exists** (inside Pods) | Containers run inside **Pods**. A Pod is the atomic unit of scheduling and can host one or more co-located containers sharing localhost & volumes. |
| **Docker Volume** | ⚠️ **Replaced** by **PV / PVC / StorageClasses** | Kubernetes abstracts storage using **PersistentVolumes (PV)** and **PersistentVolumeClaims (PVC)** backed by cloud/enterprise storage (AWS EBS/EFS, Ceph, NFS, Azure Disk). |
| **Bind Mount** | ⚠️ **Replaced** (hostPath is discouraged) | Kubernetes has `hostPath`, but it is **strictly avoided** in production because it couples Pods to specific worker nodes. Config files are mounted via **ConfigMaps** and **Secrets** instead. |
| **Docker Compose** | ❌ **Replaced** by **Deployments, Services, StatefulSets** | Docker Compose is not designed for multi-node distributed clusters. Kubernetes manifests and Helm/Kustomize manage distributed orchestration, autoscaling, and self-healing. |
| **Docker Network** | ❌ **Replaced** by **CNI Plugins (Pod/Service Networking)** | Docker bridge networks do not span multiple hosts. Kubernetes utilizes **Container Network Interface (CNI)** plugins (Calico, Cilium, AWS VPC CNI) to provide a flat, routable cluster network. |
| **Docker Daemon (`dockerd`)** | ❌ **Replaced** by **CRI Runtimes (`containerd`, CRI-O)** | Kubernetes no longer uses `dockerd`. It talks directly to lightweight OCI runtimes like **`containerd`** via the Container Runtime Interface (CRI). |
| **Utility Container** | ✅ **Replaced** by **Jobs, CronJobs & Init Containers** | One-off tasks, database migrations, and setup scripts run as Kubernetes **Jobs** or **initContainers** prior to the main application startup. |

---

## Table of Contents

1. [Docker Concept vs. Production Kubernetes Equivalent](#1-docker-concept-vs-production-kubernetes-equivalent)
2. [Enterprise Architecture: The Banking Example](#2-enterprise-architecture-the-banking-example)
   - [Development: Local Docker Compose Topology](#development-local-docker-compose-topology)
   - [Production: Enterprise Kubernetes Cluster Architecture](#production-enterprise-kubernetes-cluster-architecture)
3. [Persistent Storage Pipeline: Pod &rarr; PVC &rarr; Enterprise Storage](#3-persistent-storage-pipeline-pod--pvc--enterprise-storage)
4. [Configuration & Secret Decoupling (ConfigMap & Secret &rarr; Pod)](#4-configuration--secret-decoupling-configmap--secret--pod)
5. [Cluster Networking & Ingress vs. Docker Ports](#5-cluster-networking--ingress-vs-docker-ports)
6. [Utility Tasks: Init Containers & Kubernetes Jobs](#6-utility-tasks-init-containers--kubernetes-jobs)
7. [Complete Production Banking Manifest Implementation](#7-complete-production-banking-manifest-implementation)
8. [Production Migration Summary](#8-production-migration-summary)

---

## 2. Enterprise Architecture: The Banking Example

Consider a high-availability **Banking System** comprising an API service, a Redis cache, and a transactional PostgreSQL database.

### Development: Local Docker Compose Topology
On a single developer machine, Docker Compose runs all containers on one host network:

```
                  Docker Compose (Local Dev)
                             │
            ┌────────────────┼────────────────┐
            │                │                │
            ▼                ▼                ▼
       banking-api       PostgreSQL         Redis
            │                │                │
            └────────────────┼────────────────┘
                             │
                      Docker Network
```

---

### Production: Enterprise Kubernetes Cluster Architecture
In production, the application is decoupled across multiple physical/virtual nodes with automated load balancing, replication, and high-availability:

```
                            Kubernetes Cluster
                                    │
                ┌───────────────────┴───────────────────┐
                │                                       │
     Banking API Deployment                        Redis Pod /
  (Auto-scaling, Zero-Downtime)                  Stateful Service
                │                                       │
       ┌────────┼────────┐                              │
       ▼        ▼        ▼                              │
     Pod 1    Pod 2    Pod 3                            │
       │        │        │                              │
       └────────┼────────┘                              │
                │                                       │
                ▼                                       │
       Kubernetes Service ◄─────────────────────────────┘
      (Internal Load Balancing)
                │
                ▼
           Banking API
  (External Ingress Traffic / TLS)
```

---

## 3. Persistent Storage Pipeline: Pod &rarr; PVC &rarr; Enterprise Storage

In production Kubernetes, Pods are ephemeral and can be rescheduled to any node in the cluster. Stateful data is detached from individual nodes using **Dynamic Storage Provisioning**:

```
┌────────────────────────────────────────────────────────┐
│                   Banking API Pod                      │
│            (Stateful Database / Storage)               │
└───────────────────────────┬────────────────────────────┘
                            │ mounts volume
                            ▼
┌────────────────────────────────────────────────────────┐
│             PersistentVolumeClaim (PVC)                │
│         "I need 100Gi ReadWriteOnce Storage"           │
└───────────────────────────┬────────────────────────────┘
                            │ bound by StorageClass
                            ▼
┌────────────────────────────────────────────────────────┐
│               Kubernetes Storage System                │
│             (CSI Driver / PersistentVolume)            │
└───────────────────────────┬────────────────────────────┘
                            │ dynamically provisions
                            ▼
┌────────────────────────────────────────────────────────┐
│                   Enterprise Storage                   │
│      (AWS EBS gp3, Azure Managed Disk, Ceph, SAN)      │
└────────────────────────────────────────────────────────┘
```

1. **Banking Pod** declares a volume mount referencing a `PersistentVolumeClaim` (PVC).
2. The **CSI (Container Storage Interface) Driver** communicates with the cloud provider or SAN storage array.
3. If a worker node crashes, Kubernetes reschedules the Pod to a healthy node and **reattaches the cloud storage volume automatically**.

---

## 4. Configuration & Secret Decoupling (ConfigMap & Secret &rarr; Pod)

Never bake configuration or credentials into container images. Kubernetes injects runtime parameters dynamically:

```
┌────────────────────────┐         ┌────────────────────────┐
│       ConfigMap        │         │         Secret         │
│  (DB_HOST, LOG_LEVEL)  │         │   (DB_PASSWORD, API_KEY) │
└───────────┬────────────┘         └───────────┬────────────┘
            │                                  │
            │          ┌───────────────┐       │
            └─────────►│  Banking Pod  │◄──────┘
                       │  (Container)  │
                       └───────────────┘
```

- **ConfigMap**: Injected as environment variables or mounted as read-only configuration files (`/etc/config/app.json`).
- **Secret**: Stored in etcd (encrypted at rest), mounted in-memory via `tmpfs` into the Pod to avoid persisting credentials on worker node disks.

---

## 5. Cluster Networking & Ingress vs. Docker Ports

| Docker Networking | Kubernetes Cluster Networking |
|---|---|
| Single host `docker0` bridge network | **Flat CNI Network**: Every Pod gets a unique, routable cluster IP across all nodes |
| Host port binding (`-p 8080:80`) creates NAT rules on 1 host | **Kubernetes Service**: Cluster-wide virtual IP (ClusterIP) with round-robin proxying |
| Reverse proxy container (NGINX) manually configured | **Ingress Controller**: Layer 7 gateway handling SSL/TLS termination, rate limiting, and path-based routing |

---

## 6. Utility Tasks: Init Containers & Kubernetes Jobs

In Docker Compose, database migrations and seeding are run as separate utility containers (`docker compose run migrate`). 

In Kubernetes:
- **`initContainers`**: Run sequentially **before** the application container starts. If the migration fails, the main container never boots.
- **Kubernetes `Job`**: Runs a one-time batch task to completion (e.g. database backup, data export).

```
┌────────────────────────────────────────────────────────┐
│                      Banking Pod                       │
│                                                        │
│   ┌──────────────────────────────────────────────┐     │
│   │   initContainer: "db-migration"              │     │
│   │   (Runs flyway/prisma schema migrations)     │     │
│   └──────────────────────┬───────────────────────┘     │
│                          │ completes successfully (0)  │
│                          ▼                             │
│   ┌──────────────────────────────────────────────┐     │
│   │   appContainer: "banking-api"                │     │
│   │   (Starts listening for customer requests)   │     │
│   └──────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────┘
```

---

## 7. Complete Production Banking Manifest Implementation

Below is a complete, production-ready Kubernetes specification (`banking-production.yaml`) demonstrating all enterprise components working in unison:

```yaml
# ==========================================
# 1. Non-Sensitive Application Config
# ==========================================
apiVersion: v1
kind: ConfigMap
metadata:
  name: banking-config
  namespace: production
data:
  NODE_ENV: "production"
  PORT: "8080"
  DB_HOST: "postgres-service"
  REDIS_HOST: "redis-service"

---
# ==========================================
# 2. Sensitive Database & API Secrets
# ==========================================
apiVersion: v1
kind: Secret
metadata:
  name: banking-secrets
  namespace: production
type: Opaque
stringData:
  DB_USER: "bank_admin"
  DB_PASSWORD: "SuperSecureBankingPassword2025!"
  JWT_SECRET: "BankTokenSigningKey987654321"

---
# ==========================================
# 3. Persistent Storage Claim (Enterprise Storage)
# ==========================================
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: production
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3-encrypted # Cloud CSI Storage Class
  resources:
    requests:
      storage: 100Gi

---
# ==========================================
# 4. Stateful Database (PostgreSQL)
# ==========================================
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-db
  namespace: production
spec:
  serviceName: postgres-service
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_DB
              value: "banking_db"
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: banking-secrets
                  key: DB_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: banking-secrets
                  key: DB_PASSWORD
          volumeMounts:
            - name: db-data
              mountPath: /var/lib/postgresql/data
          resources:
            requests:
              cpu: "1000m"
              memory: "2Gi"
            limits:
              cpu: "2000m"
              memory: "4Gi"
      volumes:
        - name: db-data
          persistentVolumeClaim:
            claimName: postgres-pvc

---
# ==========================================
# 5. Database Internal Service
# ==========================================
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: production
spec:
  type: ClusterIP
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432

---
# ==========================================
# 6. Banking API Deployment (Multi-Replica with Init Container)
# ==========================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: banking-api-deployment
  namespace: production
  labels:
    app: banking-api
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: banking-api
  template:
    metadata:
      labels:
        app: banking-api
    spec:
      # Init Container: Runs DB migrations before API starts
      initContainers:
        - name: run-db-migrations
          image: ghcr.io/mybank/banking-migrator:v1.4.0
          envFrom:
            - configMapRef:
                name: banking-config
            - secretKeyRef:
                name: banking-secrets
      # Main Application Container
      containers:
        - name: banking-api
          image: ghcr.io/mybank/banking-api:v1.4.0
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: banking-config
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: banking-secrets
                  key: DB_PASSWORD
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              cpu: "1500m"
              memory: "1Gi"
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 20
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5

---
# ==========================================
# 7. Banking API Service & Ingress
# ==========================================
apiVersion: v1
kind: Service
metadata:
  name: banking-api-service
  namespace: production
spec:
  type: ClusterIP
  selector:
    app: banking-api
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: banking-api-ingress
  namespace: production
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-production"
spec:
  tls:
    - hosts:
        - api.mybank.com
      secretName: banking-tls-cert
  rules:
    - host: api.mybank.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: banking-api-service
                port:
                  number: 80
```

---

## 8. Production Migration Summary

```
┌──────────────────────────────────────────────┐
│        Development (Docker Compose)          │
│   • Single-node host execution               │
│   • Local Docker bridge network              │
│   • Named volumes on local host disk         │
│   • Environment files (.env)                 │
│   • Manual process restarts                  │
└──────────────────────┬───────────────────────┘
                       │
                       │ Continuous Delivery (CI/CD)
                       ▼
┌──────────────────────────────────────────────┐
│       Production (Enterprise Kubernetes)     │
│   • OCI images run via containerd runtime    │
│   • Multi-replica Deployments (Zero Downtime)│
│   • CNI Flat Cluster Network + L7 Ingress    │
│   • Dynamic Enterprise Storage (PV / PVC)    │
│   • ConfigMaps & etcd-encrypted Secrets      │
│   • Automated self-healing & HPA scaling     │
└──────────────────────────────────────────────┘
```

---

## References

- [Kubernetes Architecture Documentation](https://kubernetes.io/docs/concepts/architecture/)
- [Kubernetes Persistent Volumes & CSI Drivers](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Kubernetes Container Runtime Interface (CRI)](https://kubernetes.io/docs/concepts/architecture/cri/)
- [Kubernetes Ingress Controllers](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Open Container Initiative (OCI)](https://opencontainers.org/)
