# Kubernetes Persistent Storage

## Overview

Containers are **naturally ephemeral** — any data saved inside a container is lost if it crashes or restarts. Kubernetes solves this through a layered storage abstraction that decouples applications from the underlying physical storage infrastructure.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                  KUBERNETES PERSISTENT STORAGE ARCHITECTURE                  │
│                                                                             │
│   APPLICATION LAYER          KUBERNETES LAYER           CLOUD / INFRA       │
│                                                                             │
│   ┌─────────────────┐                                                       │
│   │   Pod /         │                                                       │
│   │   Deployment    │                                                       │
│   │                 │                                                       │
│   │  ┌───────────┐  │                                                       │
│   │  │ Container │  │                                                       │
│   │  │           │  │                                                       │
│   │  │  ephemeral│  │                                                       │
│   │  │  storage ❌│  │                                                       │
│   │  └─────┬─────┘  │                                                       │
│   └────────┼────────┘                                                       │
│            │ points to                                                      │
│            ▼                                                                │
│   ┌─────────────────┐     binds to    ┌─────────────────┐                  │
│   │      PVC        │ ◄──────────────► │       PV        │                  │
│   │ (Persistent     │                 │ (Persistent     │                  │
│   │  Volume Claim)  │                 │  Volume)        │                  │
│   │                 │                 │                 │                  │
│   │ • Size: 20GB    │                 │ • Actual cluster│                  │
│   │ • AccessMode:   │                 │   resource      │                  │
│   │   ReadWriteOnce │                 │ • Pre-provisioned│                 │
│   └─────────────────┘                 │   or dynamic    │                  │
│            ▲                          └────────┬────────┘                  │
│            │                                   │ provisioned by            │
│            │ watches &                         ▼                           │
│   ┌────────┴────────┐              ┌─────────────────┐                     │
│   │  PV Controller  │              │  Storage Class  │                     │
│   │                 │              │      (SC)       │                     │
│   │ Built-in control│              │                 │                     │
│   │ loop. Matches   │              │ Defines tiers:  │                     │
│   │ PVCs to PVs and │              │ • Fast SSD      │                     │
│   │ binds them.     │              │ • Slow HDD      │                     │
│   └─────────────────┘              │                 │                     │
│                                    │ Enables dynamic │                     │
│                                    │ provisioning    │                     │
│                                    └────────┬────────┘                     │
│                                             │ talks to cloud provider      │
│                                             ▼                              │
│                              ┌──────────────────────────────────────────┐  │
│                              │        External Storage Providers         │  │
│                              │                                          │  │
│                              │  ┌────────────┐  ┌────────────────────┐  │  │
│                              │  │  AWS EBS   │  │   GCE Persistent   │  │  │
│                              │  │ (Elastic   │  │      Disk          │  │  │
│                              │  │   Block    │  │                    │  │  │
│                              │  │   Store)   │  └────────────────────┘  │  │
│                              │  └────────────┘                          │  │
│                              │  ┌────────────┐  ┌────────────────────┐  │  │
│                              │  │ Azure Disk │  │    Azure File      │  │  │
│                              │  │            │  │                    │  │  │
│                              │  └────────────┘  └────────────────────┘  │  │
│                              └──────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. The Core Components

### Pod / Deployment

The containerized application running inside the cluster. Containers are naturally **ephemeral** — any data written inside the container's filesystem is lost when it crashes, restarts, or is rescheduled to a different node.

```
┌──────────────────────────────────────────────────────────────────────────┐
│              WHY EPHEMERAL STORAGE IS A PROBLEM                           │
│                                                                          │
│   Pod running          Pod crashes            New Pod starts             │
│   ┌──────────┐         ┌──────────┐           ┌──────────┐              │
│   │Container │  ──►    │Container │  ──►       │Container │             │
│   │          │         │  DEAD ✖  │            │          │             │
│   │ /data/   │         │          │            │ /data/   │             │
│   │  db.sql  │         └──────────┘            │ EMPTY ❌  │             │
│   └──────────┘                                 └──────────┘              │
│                         Data lost!             Fresh start — no data     │
└──────────────────────────────────────────────────────────────────────────┘
```

---

### Persistent Volume Claim (PVC)

A **request for storage** by a user or Pod. It functions like a ticket or voucher, specifying storage requirements without needing to know the underlying infrastructure details.

| PVC Property    | Example Value      | Description                                    |
|-----------------|--------------------|------------------------------------------------|
| `storage`       | `20Gi`             | Requested storage size                         |
| `accessModes`   | `ReadWriteOnce`    | How the volume can be mounted (see table below)|
| `storageClassName` | `fast-ssd`      | Which Storage Class tier to request            |

**Access Modes:**

| Mode              | Meaning                                                           |
|-------------------|-------------------------------------------------------------------|
| `ReadWriteOnce`   | Mounted read-write by a **single** node                          |
| `ReadOnlyMany`    | Mounted read-only by **many** nodes                              |
| `ReadWriteMany`   | Mounted read-write by **many** nodes                             |

**Example PVC YAML:**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: fast-ssd
```

---

### Persistent Volume (PV)

A **piece of storage** in the cluster that has been provisioned by an administrator or dynamically created by a Storage Class. It is an actual cluster resource — just like a Node is a computing resource.

| PV Property      | Description                                                       |
|------------------|-------------------------------------------------------------------|
| `capacity`       | The amount of storage (e.g., `20Gi`)                              |
| `accessModes`    | How this volume can be accessed                                   |
| `reclaimPolicy`  | What happens when the PVC is deleted (`Retain`, `Delete`, `Recycle`) |
| `storageClassName` | The Storage Class this PV belongs to                            |

**Example PV YAML (static provisioning):**

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: database-pv
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: fast-ssd
  awsElasticBlockStore:
    volumeID: vol-0123456789abcdef0
    fsType: ext4
```

---

### Storage Class (SC)

A **profile** that describes the "classes" of storage offered. It allows administrators to define different tiers and enables **dynamic provisioning** — automatically creating a PV when a PVC requests it, without any manual administrator intervention.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                       STORAGE CLASS TIERS                                 │
│                                                                          │
│   ┌──────────────────────────────┐  ┌──────────────────────────────┐    │
│   │   Storage Class: fast-ssd    │  │   Storage Class: slow-hdd    │    │
│   │                              │  │                              │    │
│   │  provisioner: aws-ebs        │  │  provisioner: aws-ebs        │    │
│   │  type: gp3 (SSD)             │  │  type: sc1 (HDD)             │    │
│   │                              │  │                              │    │
│   │  Use for: databases,         │  │  Use for: backups, logs,     │    │
│   │  high-IOPS workloads         │  │  archival storage            │    │
│   │                              │  │                              │    │
│   │  💲 Higher cost              │  │  💲 Lower cost               │    │
│   └──────────────────────────────┘  └──────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────┘
```

**Example Storage Class YAML:**

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp3
  fsType: ext4
reclaimPolicy: Delete
allowVolumeExpansion: true
```

---

### PV Controller

A **built-in control loop** in Kubernetes that continuously watches for new PVCs, finds a matching available PV, and binds them together. This is part of the Kubernetes Controller Manager running on the control plane.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        PV CONTROLLER LOOP                                 │
│                                                                          │
│   1. New PVC created             PVC status: Pending                    │
│            │                                                             │
│            ▼                                                             │
│   2. PV Controller scans         Looks for PV matching:                 │
│      available PVs               • size ≥ requested                     │
│                                  • matching access mode                  │
│                                  • matching storage class                │
│            │                                                             │
│     ┌──────┴──────┐                                                      │
│     │             │                                                      │
│  Match found   No match found                                            │
│     │             │                                                      │
│     ▼             ▼                                                      │
│  Bind PVC      Storage Class creates new PV dynamically                 │
│  to PV         (talks to cloud provider API)                            │
│     │             │                                                      │
│     └──────┬──────┘                                                      │
│            ▼                                                             │
│   3. PVC status: Bound           PV status: Bound                       │
│      Volume mounted to Pod ✔                                             │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 2. External Storage Providers

The actual cloud infrastructure where data physically resides. Kubernetes communicates with these providers via **CSI (Container Storage Interface)** drivers.

| Provider          | Service               | Description                                              |
|-------------------|-----------------------|----------------------------------------------------------|
| **AWS**           | EBS (Elastic Block Store) | Block storage for EC2/EKS; ReadWriteOnce              |
| **Google Cloud**  | GCE Persistent Disk   | Block storage for GKE; SSD and HDD options              |
| **Azure**         | Azure Disk            | Block storage; ReadWriteOnce                            |
| **Azure**         | Azure File            | SMB/NFS file share; ReadWriteMany supported             |

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    EXTERNAL STORAGE PROVIDERS                             │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                          AWS                                      │   │
│  │  ┌────────────────────────────────────────────────────────────┐  │   │
│  │  │  EBS (Elastic Block Store)                                  │  │   │
│  │  │  • Block-level storage attached to a single EC2/EKS node   │  │   │
│  │  │  • High performance, low latency                           │  │   │
│  │  │  • Access mode: ReadWriteOnce                              │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                        Google Cloud                               │   │
│  │  ┌────────────────────────────────────────────────────────────┐  │   │
│  │  │  GCE Persistent Disk                                        │  │   │
│  │  │  • Network-attached block storage for GKE                  │  │   │
│  │  │  • SSD (pd-ssd) or HDD (pd-standard) options               │  │   │
│  │  │  • Access mode: ReadWriteOnce / ReadOnlyMany                │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                          Azure                                    │   │
│  │  ┌─────────────────────────┐  ┌─────────────────────────────┐   │   │
│  │  │     Azure Disk          │  │       Azure File             │   │   │
│  │  │  • Block storage        │  │  • SMB / NFS file share     │   │   │
│  │  │  • ReadWriteOnce        │  │  • ReadWriteMany supported  │   │   │
│  │  │  • Attached to one node │  │  • Shared across nodes      │   │   │
│  │  └─────────────────────────┘  └─────────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 3. How the Workflow Operates (Left to Right)

### Step 1 — Requesting Storage

The Pod does **not** talk directly to cloud storage. It points to a **PVC**.

```
  Pod / Deployment
  ┌──────────────────────────────────────────┐
  │                                          │
  │   spec:                                  │
  │     volumes:                             │
  │       - name: data-volume                │
  │         persistentVolumeClaim:           │
  │           claimName: database-pvc  ──────┼──► PVC
  │     containers:                          │
  │       - name: app                        │
  │         volumeMounts:                    │
  │           - mountPath: /data             │
  │             name: data-volume            │
  └──────────────────────────────────────────┘
```

### Step 2 — Binding the Volume

The **PV Controller** matches the PVC to an available PV. If no matching PV exists, the **Storage Class** automatically talks to the cloud provider to provision a new one.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         BINDING WORKFLOW                                  │
│                                                                          │
│   PVC created                                                            │
│      │                                                                   │
│      ▼                                                                   │
│   PV Controller checks available PVs                                     │
│      │                                                                   │
│      ├── PV available? ──────────────► Bind PVC ↔ PV directly           │
│      │                                                                   │
│      └── No PV available? ──────────► Storage Class provisions new PV   │
│                                       (calls AWS/GCP/Azure API)         │
│                                       Then binds PVC ↔ new PV           │
│                                                                          │
│   Result: PVC status = Bound  │  PV status = Bound                      │
└──────────────────────────────────────────────────────────────────────────┘
```

### Step 3 — Accessing the Data

Once PVC and PV are bound, the volume is **mounted into the Pod**. The application reads and writes data to a path that is backed by durable external storage.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                      DATA PERSISTENCE GUARANTEE                           │
│                                                                          │
│   Pod 1 running          Pod 1 crashes           Pod 2 starts            │
│   ┌──────────┐           ┌──────────┐            ┌──────────┐           │
│   │Container │           │Container │            │Container │           │
│   │          │           │  DEAD ✖  │            │          │           │
│   │ /data/   │           └──────────┘            │ /data/   │           │
│   │  db.sql  │                                   │  db.sql  │           │
│   └────┬─────┘                                   └────┬─────┘           │
│        │ mounted via PVC                              │ re-mounted       │
│        ▼                                             ▼                  │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │                    Physical Storage (EBS / GCE PD / Azure Disk)  │  │
│   │                           Data persists ✔                        │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│   Even though Pod 1 died and Pod 2 took its place, the data on          │
│   the external storage remains intact and is re-attached automatically. │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Complete End-to-End Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     COMPLETE PERSISTENT STORAGE FLOW                         │
│                                                                             │
│                                                                             │
│  ┌─────────────┐   references   ┌─────────────┐                            │
│  │     Pod     │ ─────────────► │     PVC     │                            │
│  │             │                │             │                            │
│  │  /data      │                │ size: 20Gi  │                            │
│  │  (mounted)  │                │ mode: RWO   │                            │
│  └─────────────┘                └──────┬──────┘                            │
│                                        │                                   │
│                                        │  watched by                       │
│                                        ▼                                   │
│                               ┌─────────────────┐                          │
│                               │   PV Controller  │                          │
│                               │  (control loop)  │                          │
│                               └────────┬────────┘                          │
│                                        │                                   │
│                          ┌─────────────┴──────────────┐                    │
│                          │                            │                    │
│                   PV available                  No PV available            │
│                          │                            │                    │
│                          ▼                            ▼                    │
│                   ┌─────────────┐           ┌──────────────────┐           │
│                   │     PV      │           │  Storage Class   │           │
│                   │  (existing) │           │  (dynamic prov.) │           │
│                   └──────┬──────┘           └────────┬─────────┘           │
│                          │                          │                      │
│                          │                          │ calls API             │
│                          │                          ▼                      │
│                          │              ┌───────────────────────┐          │
│                          │              │  Cloud Provider       │          │
│                          │              │  AWS EBS / GCE PD /   │          │
│                          │              │  Azure Disk / File     │          │
│                          │              │  → new PV created      │          │
│                          │              └──────────┬────────────┘          │
│                          │                         │                       │
│                          └──────────┬──────────────┘                       │
│                                     │                                      │
│                                     ▼                                      │
│                            PVC ↔ PV  BOUND ✔                               │
│                                     │                                      │
│                                     ▼                                      │
│                         Volume mounted into Pod ✔                          │
│                         Data persists across Pod restarts ✔                │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Component Reference Summary

| Component          | Type              | Role                                                                     |
|--------------------|-------------------|--------------------------------------------------------------------------|
| **Pod/Deployment** | Workload          | Runs the application; references a PVC for persistent storage            |
| **PVC**            | Storage request   | Ticket specifying size, access mode, and storage class needed            |
| **PV**             | Storage resource  | Actual storage unit in the cluster; pre-provisioned or dynamically created|
| **Storage Class**  | Storage profile   | Defines storage tiers; enables dynamic PV provisioning                   |
| **PV Controller**  | Control loop      | Watches PVCs, finds matching PVs, and binds them together                |
| **AWS EBS**        | Cloud storage     | Block storage on AWS; attached to a single node (ReadWriteOnce)          |
| **GCE PD**         | Cloud storage     | Persistent Disk on Google Cloud; SSD or HDD                              |
| **Azure Disk**     | Cloud storage     | Block storage on Azure; single-node attachment                           |
| **Azure File**     | Cloud storage     | Shared file storage on Azure; supports multi-node access (ReadWriteMany) |

---

## Key Takeaways

1. **Containers are ephemeral** — without persistent storage, data is lost on every Pod restart or crash.
2. **PVCs abstract storage requests** — Pods request storage via a PVC without knowing which cloud provider or disk backs it.
3. **PVs are the actual storage units** — they exist as cluster resources and can be pre-provisioned manually or created dynamically.
4. **Storage Classes enable dynamic provisioning** — a PVC request automatically triggers cloud API calls to create real storage on demand.
5. **The PV Controller binds PVCs to PVs** — this control loop runs continuously, ensuring every pending PVC finds a match.
6. **Data outlives the Pod** — even when a Pod dies and a new one takes its place, the data on external storage remains intact and is re-attached automatically.
