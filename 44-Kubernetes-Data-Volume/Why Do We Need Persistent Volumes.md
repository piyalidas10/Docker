# Why Do We Need Persistent Volumes?

---

## The Problem

Kubernetes offers several ways to attach storage to a Pod. Understanding their differences explains exactly why Persistent Volumes exist.

---

## A. `emptyDir` — Temporary Storage

An `emptyDir` volume is created fresh every time a Pod is assigned to a node.

```
Pod assigned to node
        │
        ▼
  emptyDir created (empty)
        │
  containers in Pod write data
        │
        ▼
  Pod removed
        │
        ▼
  emptyDir deleted — data gone ❌
        │
        ▼
  Replacement Pod assigned
        │
        ▼
  New emptyDir created (empty again)
```

### Characteristics

| Property | Behaviour |
|---|---|
| **Created** | When a Pod is assigned to a node |
| **Shared** | Between containers in the same Pod, when mounted appropriately |
| **Deleted** | When the Pod is removed |
| **Replacement Pod** | Gets a new, empty `emptyDir` — previous data is not accessible |

### When it is acceptable

`emptyDir` is suitable for **truly temporary data** — scratch space, caches, intermediate results — where losing the data on Pod removal is not a problem.

---

## B. `hostPath` — Node-Local Storage

A `hostPath` volume maps a directory on the **worker node's filesystem** into the Pod.

```
Worker Node 1                      Worker Node 2
┌──────────────────────┐           ┌──────────────────────┐
│  /data/app  ◄── Pod  │           │  /data/app  ◄── Pod  │
│  (has data)          │           │  (empty or different)│
└──────────────────────┘           └──────────────────────┘
         ▲                                   ▲
         │                                   │
  Pod scheduled here              Pod rescheduled here
  data is visible ✅               data is NOT visible ❌
```

### Characteristics

| Property | Behaviour |
|---|---|
| **Storage location** | Directory on the worker node running the Pod |
| **Pod deleted, same node** | Data can remain on the node |
| **Pod rescheduled on different node** | The new node has its own filesystem — previous data is not visible |
| **Multi-node clusters** | Not a suitable general-purpose solution for persistent storage |

### When it is acceptable

`hostPath` works in **single-node setups** (such as a local Minikube environment) where all Pods always run on the same node. It is not a reliable solution for real multi-node clusters.

---

## C. Persistent Volume (PV) — Independently Managed Storage

A PersistentVolume is a cluster-level resource that represents storage provisioned for the cluster. Its lifecycle is **independent of any Pod**.

```
Cluster
┌────────────────────────────────────────────────────┐
│                                                    │
│   Worker Node 1          Worker Node 2             │
│   ┌──────────────┐       ┌──────────────┐          │
│   │  Pod A       │       │  Pod B       │          │
│   │  └── PVC ───────────────── PVC ────────┐       │
│   └──────────────┘       └──────────────┘  │       │
│                                             ▼       │
│                                    PersistentVolume │
│                                    (external storage│
│                                     cloud disk,     │
│                                     NFS, CSI, etc.) │
└────────────────────────────────────────────────────┘
```

### Characteristics

| Property | Behaviour |
|---|---|
| **Lifecycle** | Separate from any Pod — survives Pod deletion |
| **Storage backend** | Cloud disks, network file systems, CSI drivers, and other supported types |
| **How Pods access it** | Through a PersistentVolumeClaim (PVC) |
| **Node independence** | Not tied to a specific worker node (depends on storage backend) |
| **Provisioning** | Manually by an admin (static) or automatically via a StorageClass (dynamic) |

---

## Important Caveat

> A PersistentVolume does **not** automatically guarantee that data survives every failure or that multiple Pods can mount it simultaneously.

Those capabilities depend on:

| Factor | What it controls |
|---|---|
| **Storage backend** | Whether the underlying system supports multi-node access or high availability |
| **Access mode** | `ReadWriteOnce` (one node), `ReadOnlyMany` (many nodes, read-only), `ReadWriteMany` (many nodes, read-write) |
| **Configuration** | Replication, backup, availability zone placement |
| **Reclaim policy** | `Retain` (PV kept after PVC deleted), `Delete` (PV and data deleted with PVC) |

---

## Summary Comparison

| | `emptyDir` | `hostPath` | PersistentVolume |
|---|---|---|---|
| **Storage location** | Inside the Pod (ephemeral) | Worker node filesystem | External (cloud, NFS, CSI) |
| **Survives container restart** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Survives Pod deletion** | ❌ No | ✅ On same node | ✅ Yes (lifecycle independent) |
| **Works across multiple nodes** | ❌ No | ❌ No | ✅ Yes (backend-dependent) |
| **Lifecycle tied to Pod** | ✅ Yes | Partial | ❌ No — fully independent |
| **Suitable for production data** | ❌ No | ❌ No (single-node only) | ✅ Yes |

---

## Conclusion

`emptyDir` and `hostPath` cover narrow, specific scenarios. Neither provides the **Pod and Node independence** required for real persistent storage in a multi-node cluster.

PersistentVolumes exist to:

1. **Decouple storage from Pod lifecycle** — data is not lost when a Pod is deleted or replaced
2. **Decouple storage from Node placement** — Pods can be rescheduled freely without losing access to data
3. **Centralise storage management** — defined once at the cluster level, used by many Pods via claims
4. **Support any backend** — through native types or the CSI driver ecosystem
