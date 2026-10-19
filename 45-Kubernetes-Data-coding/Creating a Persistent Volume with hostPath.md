# Creating a Persistent Volume (PV) with `hostPath`

---

## Overview

A **Persistent Volume (PV)** is a standalone cluster resource — detached from any Pod or Deployment. Rather than defining storage inside a Pod spec, a PV is created once by a cluster administrator and can then be claimed by any Pod running in the cluster.

This section walks through creating a PV using the `hostPath` type, stored in a file called `host-pv.yaml`.

> **Important:** `hostPath` only works on a **single-node** environment (like Minikube or Docker Desktop Kubernetes). Everything explained here about the PV structure and workflow applies equally to other volume types (e.g. `awsElasticBlockStore`, CSI drivers) used in real multi-node clusters.

---

## The `host-pv.yaml` File

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: host-pv
spec:
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  storageClassName: standard
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /data
    type: DirectoryOrCreate
```

---

## Field-by-Field Explanation

### Top-level keys

| Key | Value | Meaning |
|---|---|---|
| `apiVersion` | `v1` | Same API version as a Service — PersistentVolume is a core v1 resource |
| `kind` | `PersistentVolume` | Tells Kubernetes what type of resource to create — must be spelled exactly as shown |
| `metadata.name` | `host-pv` | The name of this PV — referenced later when a PVC optionally targets it by name |

---

### `spec.capacity`

```yaml
capacity:
  storage: 1Gi
```

Defines the **total storage capacity** this PV offers to the cluster.

- As a cluster administrator, you control how much capacity is made available
- When a Pod later **claims** this volume via a PVC, it specifies how much of this capacity it needs
- Here `1Gi` (one gibibyte) is defined — reduced from `4Gi` to ensure it is realistically available inside the local VM
- For units and notation, refer to the [Kubernetes Resource Model documentation](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

---

### `spec.volumeMode`

```yaml
volumeMode: Filesystem
```

Defines the storage type. Two modes are available:

| Mode | Description |
|---|---|
| `Filesystem` | The volume is mounted as a directory; used when the application reads and writes files (this case — a folder on the node filesystem) |
| `Block` | The volume is exposed as a raw block device; used for specialised workloads that manage their own filesystem |

Here `Filesystem` is correct because `hostPath` exposes a directory on the node's filesystem.

---

### `spec.accessModes`

```yaml
accessModes:
  - ReadWriteOnce
```

Defines **how this PV may be accessed** when claimed. Three modes exist:

| Access Mode | Meaning | `hostPath` compatible? |
|---|---|---|
| `ReadWriteOnce` (RWO) | Mounted read-write by a **single node**; multiple Pods on that same node may use it | ✅ Yes |
| `ReadOnlyMany` (ROX) | Mounted read-only by **multiple nodes** simultaneously | ❌ No — `hostPath` is node-local |
| `ReadWriteMany` (RWX) | Mounted read-write by **multiple nodes** simultaneously | ❌ No — `hostPath` is node-local |

> You list the access modes that are **allowed** for this PV. The exact mode used is chosen at claim time (in the PVC). For `hostPath`, only `ReadWriteOnce` is meaningful.

The official Kubernetes docs provide an [access mode compatibility matrix](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes) showing which modes each volume type supports. For the CSI type, compatibility depends on the specific driver.

---

### `spec.storageClassName`

```yaml
storageClassName: standard
```

Associates this PV with a **StorageClass**. A PVC that requests the same `storageClassName` can be bound to this PV. Using a consistent class name ensures the right PV is matched to the right claim.

---

### `spec.hostPath`

```yaml
hostPath:
  path: /data
  type: DirectoryOrCreate
```

| Key | Value | Meaning |
|---|---|---|
| `path` | `/data` | The directory on the **worker node's filesystem** where data is stored |
| `type` | `DirectoryOrCreate` | Create the directory if it does not already exist; fail if the path exists but is not a directory |

This is identical to the `hostPath` configuration used inside a Pod spec for a regular volume — the difference is that here it is defined as a **standalone cluster resource**, not embedded in a Deployment.

---

## What This PV Represents in the Cluster

```
Kubernetes Cluster
┌──────────────────────────────────────────────┐
│                                              │
│   PersistentVolume: host-pv                  │
│   ┌──────────────────────────────────────┐   │
│   │  capacity: 1Gi                       │   │
│   │  volumeMode: Filesystem              │   │
│   │  accessModes: ReadWriteOnce          │   │
│   │  storageClassName: standard          │   │
│   │  hostPath: /data (DirectoryOrCreate) │   │
│   └──────────────────────────────────────┘   │
│                                              │
│   Status: Available (waiting for a claim)   │
│                                              │
└──────────────────────────────────────────────┘
```

Once created, this PV sits in the cluster with status `Available`. Any Pod — from any Deployment — can use it by creating a matching **PersistentVolumeClaim**.

---

## Key Difference from a Regular Volume

| | Regular Volume (in Deployment) | Persistent Volume (`host-pv.yaml`) |
|---|---|---|
| **Defined in** | `spec.template.spec.volumes` inside a Deployment YAML | Separate `host-pv.yaml` — a standalone cluster resource |
| **Lifecycle** | Tied to the Pod / Deployment | Independent of any Pod or Deployment |
| **Reusable** | No — specific to that Deployment | Yes — any Pod in the cluster can claim it |
| **Admin control** | Developer configures per-Deployment | Cluster administrator defines once |

---

## Applying the PV

```bash
kubectl apply -f host-pv.yaml
kubectl get pv
```

Expected output:

```
NAME      CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      STORAGECLASS   AGE
host-pv   1Gi        RWO            Retain           Available   standard       <age>
```

Status `Available` means the PV exists and is waiting to be bound to a PVC.

---

## Next Step — The PersistentVolumeClaim

A PV on its own does nothing for a Pod. Pods connect to a PV through a **PersistentVolumeClaim (PVC)**, defined in `host-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: host-pvc
spec:
  volumeName: host-pv
  accessModes:
    - ReadWriteOnce
  storageClassName: standard
  resources:
    requests:
      storage: 1Gi
```

And the Deployment references the PVC — not the PV directly:

```yaml
# deployment.yaml (volumes section)
volumes:
  - name: story-volume
    persistentVolumeClaim:
      claimName: host-pvc
```

```
Pod (story-deployment)
  └── volumes.persistentVolumeClaim.claimName: host-pvc
            │
            ▼
       PVC: host-pvc  (requests 1Gi, ReadWriteOnce, storageClassName: standard)
            │
            ▼
       PV: host-pv    (offers 1Gi, ReadWriteOnce, storageClassName: standard)
            │
            ▼
       hostPath: /data on the worker node
```

The Pod only references the **claim by name**. The underlying storage implementation (`hostPath`, cloud disk, NFS, etc.) is entirely defined in the PV — invisible to the Pod.
