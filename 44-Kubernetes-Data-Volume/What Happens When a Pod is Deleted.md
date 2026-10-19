# What Happens When a Pod is Deleted?

---

## Scenario: PostgreSQL Running on Kubernetes

Imagine your banking application runs PostgreSQL inside a Kubernetes Pod on Worker Node 1.

---

## Before Pod Deletion

```
Worker Node 1
┌─────────────────────────────────┐
│                                 │
│   PostgreSQL Pod                │
│   ┌─────────────────────────┐   │
│   │  container: postgres    │   │
│   │                         │   │
│   │  volumeMount:           │   │
│   │    /var/lib/postgresql  │   │◄──── PersistentVolumeClaim
│   └─────────────────────────┘   │              │
│                                 │              ▼
└─────────────────────────────────┘   PersistentVolume
                                       (external storage)
                                      ┌──────────────────┐
                                      │  database files  │
                                      │  - pg_data/      │
                                      │  - WAL logs      │
                                      │  - tables, etc.  │
                                      └──────────────────┘
```

- The PostgreSQL Pod runs on Worker Node 1
- Its data is written to an external **PersistentVolume** via a **PersistentVolumeClaim**
- The actual database files live outside the node — on persistent storage (e.g. a cloud disk or EFS)

---

## Pod Deletion

The Pod is terminated — due to a crash, a rolling update, node failure, or manual deletion.

```
Worker Node 1
┌─────────────────────────────────┐
│                                 │
│   PostgreSQL Pod  ✗ DELETED     │
│                                 │
└─────────────────────────────────┘

PersistentVolumeClaim  ──────────► PersistentVolume
(still exists)                     (still exists, data intact)
                                  ┌──────────────────┐
                                  │  database files  │  ✅ SAFE
                                  │  - pg_data/      │
                                  │  - WAL logs      │
                                  └──────────────────┘
```

> The Pod is gone — but the **PersistentVolumeClaim and PersistentVolume are independent cluster resources**. They are not deleted when the Pod is deleted. The data remains intact.

---

## After Pod Replacement

Kubernetes schedules a new Pod — possibly on a **different worker node**.

```
Worker Node 2  (or any node)
┌─────────────────────────────────┐
│                                 │
│   New PostgreSQL Pod            │
│   ┌─────────────────────────┐   │
│   │  container: postgres    │   │
│   │                         │   │
│   │  volumeMount:           │   │◄──── Same PersistentVolumeClaim
│   │    /var/lib/postgresql  │   │              │
│   └─────────────────────────┘   │              ▼
│                                 │   Same PersistentVolume
└─────────────────────────────────┘   (same data, reattached)
                                      ┌──────────────────┐
                                      │  database files  │  ✅ INTACT
                                      │  - pg_data/      │
                                      │  - WAL logs      │
                                      └──────────────────┘
```

- The new Pod references the **same PersistentVolumeClaim** in its spec
- The claim reconnects to the **same PersistentVolume**
- The replacement Pod picks up exactly where the old Pod left off — **no data loss**

> This works as long as the storage backend supports reattachment. For example, a cloud block storage volume (AWS EBS) can be detached from one node and reattached to another. A network file system (AWS EFS via CSI) is accessible from any node simultaneously.

---

## Comparison: `emptyDir` vs Persistent Volume

| | `emptyDir` | PersistentVolume + PVC |
|---|---|---|
| **Storage location** | Inside the Pod (ephemeral) | External, independent of Pod and Node |
| **Pod deleted** | ❌ Data is destroyed | ✅ Data survives |
| **Pod replaced on same node** | ❌ New empty directory | ✅ Claim reconnects to existing data |
| **Pod replaced on different node** | ❌ New empty directory | ✅ Data accessible (if backend supports it) |
| **Use case** | Temporary scratch space, caching | Databases, file storage, any long-term data |

---

## Key Rules

1. **PersistentVolumes and PersistentVolumeClaims are cluster resources** — they exist independently of any Pod and are not removed when a Pod is deleted.
2. **The new Pod must reference the same PVC** in its spec to reconnect to the existing data.
3. **Storage backend determines portability** — network-attached storage (NFS, EFS, Azure File) works across any node; block storage (EBS, Azure Disk) typically attaches to one node at a time.
4. **`emptyDir` provides no persistence** — a replacement Pod always starts with a completely empty directory, regardless of what the previous Pod wrote.

---

## Summary

```
Pod deleted
    │
    ├── emptyDir volume?   ──► Data LOST. New Pod gets empty scratch space.
    │
    └── PersistentVolume + PVC?
            │
            ├── PVC still exists   ──► Claim is preserved
            ├── PV still exists    ──► Data is intact on external storage
            └── New Pod mounts PVC ──► Full access to existing data ✅
```

> Persistent Volumes decouple your data from the Pod lifecycle. No matter what happens to the Pod — crash, replacement, rescheduling to a new node — the data remains safe and accessible to the next Pod that claims it.
