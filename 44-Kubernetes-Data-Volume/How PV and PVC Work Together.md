# How PV and PVC Work Together

---

## Overview

Persistent storage in Kubernetes involves several components working together. Rather than defining storage implementation details inside a Pod, the application **requests** storage through a claim — and Kubernetes handles the rest.

---

## The Four Main Components

```
┌──────────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster                                              │
│                                                                  │
│   ┌─────────────┐     ┌─────────────────┐     ┌─────────────┐  │
│   │     Pod     │────►│  Persistent     │────►│ Persistent  │  │
│   │             │     │  Volume Claim   │     │   Volume    │  │
│   │ (e.g.       │     │  (PVC)          │     │   (PV)      │  │
│   │  PostgreSQL)│     │                 │     │             │  │
│   └─────────────┘     └─────────────────┘     └──────┬──────┘  │
│                                                       │         │
└───────────────────────────────────────────────────────┼─────────┘
                                                        │
                                                        ▼
                                              ┌──────────────────┐
                                              │  Storage Backend │
                                              │  (cloud disk,    │
                                              │   NFS, EFS, etc.)│
                                              └──────────────────┘
```

### Component descriptions

| Component | What it is | Responsibility |
|---|---|---|
| **Pod** | Your application | Runs the workload that needs persistent storage |
| **PersistentVolumeClaim (PVC)** | A storage request | Declares the required size and access mode; does not specify the underlying implementation |
| **PersistentVolume (PV)** | The storage resource | Represents actual storage made available to the cluster; satisfies the PVC request |
| **StorageClass** | A provisioning template | Defines how storage can be dynamically provisioned (provisioner, parameters, reclaim policy) |
| **CSI driver** | A storage plugin | Connects Kubernetes to supported external storage systems |

---

## The Key Design Principle

> Your application Pod requests storage through a PVC **instead of** defining the underlying storage implementation directly.

In a regular Kubernetes volume, the Pod spec contains the full storage configuration — the type, path, cloud credentials, etc. This couples the application to the storage implementation.

With PV and PVC, the layers are separated:

```
Without PV/PVC                      With PV/PVC
──────────────────────────          ──────────────────────────────────
Pod spec contains:                  Pod spec contains:
  volumes:                            volumes:
    - name: data                        - name: data
      awsElasticBlockStore:               persistentVolumeClaim:
        volumeID: vol-0abc123              claimName: my-storage-claim
        fsType: ext4
                                    PVC defines:
                                      storage: 10Gi
                                      accessModes: ReadWriteOnce

                                    PV (or StorageClass) defines:
                                      the actual AWS EBS config
```

The Pod only knows it needs storage. The *how* is handled elsewhere.

---

## How the Components Connect

### Step-by-step binding flow

```
1. Admin creates a PV (static) OR configures a StorageClass (dynamic)
        │
        ▼
2. Developer creates a PVC
   - Specifies: storage size, access mode, optional StorageClass name
        │
        ▼
3. Kubernetes finds a matching PV (or provisions one via StorageClass)
        │
        ▼
4. PVC is bound to the PV
        │
        ▼
5. Pod references the PVC by name
        │
        ▼
6. Kubernetes mounts the storage into the container at the specified path
```

---

## Access Modes

The PVC specifies how the storage should be accessed. The PV must support the requested mode.

| Access Mode | Meaning | Typical backend |
|---|---|---|
| `ReadWriteOnce` (RWO) | Mounted read-write by a single node | Cloud block storage (EBS, Azure Disk) |
| `ReadOnlyMany` (ROX) | Mounted read-only by many nodes | Shared file storage |
| `ReadWriteMany` (RWX) | Mounted read-write by many nodes | NFS, AWS EFS, Azure File |

---

## Reclaim Policy

When a PVC is deleted, the reclaim policy on the PV determines what happens to the data:

| Policy | Behaviour |
|---|---|
| `Retain` | PV and data are kept — admin must manually clean up or reassign |
| `Delete` | PV and the underlying storage resource are deleted automatically |
| `Recycle` | Deprecated — basic scrub and make available again |

---

## Minimal Example (Static Provisioning with `hostPath`)

### PersistentVolume

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: my-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /data
    type: DirectoryOrCreate
```

### PersistentVolumeClaim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-storage-claim
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

### Pod referencing the PVC

```yaml
spec:
  containers:
    - name: app
      image: my-app
      volumeMounts:
        - mountPath: /app/data
          name: app-storage
  volumes:
    - name: app-storage
      persistentVolumeClaim:
        claimName: my-storage-claim
```

The Pod only references the claim by name. It has no knowledge of `hostPath`, cloud provider APIs, or any storage implementation detail.

---

## Summary

```
Pod
 └── references PVC by name
        │
        ▼
       PVC
        │  declares: size + access mode
        ▼
        PV  ◄─── created by admin (static)
         │   or  created by StorageClass provisioner (dynamic)
         │
         ▼
   Storage Backend
   (cloud disk, NFS, EFS, CSI-backed system, etc.)
```

| Layer | Owned by | Contains |
|---|---|---|
| Pod | Developer | Application logic + claim reference |
| PVC | Developer | Storage requirements (size, access mode) |
| PV | Admin / provisioner | Storage implementation details |
| StorageClass | Admin | Dynamic provisioning rules |
| CSI driver | Storage provider / admin | Integration with actual storage system |
