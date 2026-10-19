# Docker Volumes vs Kubernetes PV/PVC

---

## Overview

If you have been learning Docker storage, the Kubernetes Persistent Volume concepts map naturally onto what you already know. This page draws those connections explicitly.

> These are **conceptual equivalents**, not identical implementations. The underlying mechanisms, resource management, and lifecycle rules differ between Docker and Kubernetes.

---

## Side-by-Side Comparison

| Docker | Kubernetes | Notes |
|---|---|---|
| **Docker volume** | **PersistentVolume (PV)** | The actual storage resource — where data lives |
| **Container uses a volume** | **Pod uses a PVC to request storage** | The container/Pod declares what storage it needs; it does not manage the storage directly |
| **Docker Compose `volumes:` config** | **PVC and optionally PV / StorageClass config** | Both are declarative definitions of required storage |
| **Docker volume driver** | **Kubernetes CSI driver + storage backend** | The plugin layer that connects the container runtime to real storage |
| **Container recreated; volume may persist** | **Pod recreated; data can persist independently** | In both cases, the storage resource outlives the compute unit — if configured correctly |

---

## Concept Mapping in Depth

### Docker volume → PersistentVolume (PV)

In Docker, a named volume (e.g. `docker volume create pg-data`) is a managed storage resource that exists on the host independently of any container.

In Kubernetes, a **PersistentVolume** is a cluster-level resource that represents real storage — a cloud disk, an NFS share, or any CSI-backed system — that exists independently of any Pod.

```
Docker                          Kubernetes
──────────────────────          ──────────────────────────────────
docker volume create pg-data    kubectl apply -f pv.yaml
  └── stored on Docker host       └── stored on cloud / NFS / etc.
  └── survives container stop     └── survives Pod deletion
```

---

### Container uses a volume → Pod uses a PVC

In Docker, a container declares which volume to mount:

```yaml
# docker-compose.yml
services:
  db:
    image: postgres
    volumes:
      - pg-data:/var/lib/postgresql/data

volumes:
  pg-data:
```

In Kubernetes, a Pod does not reference a PV directly. Instead it references a **PersistentVolumeClaim**, which in turn binds to a matching PV:

```yaml
# Pod spec (simplified)
volumes:
  - name: pg-storage
    persistentVolumeClaim:
      claimName: pg-data-claim
```

The Pod asks for storage via the claim — the cluster resolves which actual PV satisfies it.

---

### Docker Compose `volumes:` → PVC + PV / StorageClass

| Docker Compose | Kubernetes equivalent |
|---|---|
| Top-level `volumes:` block | PersistentVolume YAML (or StorageClass for dynamic provisioning) |
| Per-service `volumes:` mount | PersistentVolumeClaim YAML + `volumeMounts` in Pod spec |
| Named volume (implicit driver) | PVC bound to a PV with a matching StorageClass |

Both approaches are declarative — you describe what you need and the runtime/cluster handles provisioning.

---

### Docker volume driver → Kubernetes CSI driver

In Docker, volume drivers (e.g. `local`, `rexray`, third-party plugins) determine where and how data is stored.

In Kubernetes, **CSI (Container Storage Interface) drivers** serve the same role:

| Docker | Kubernetes |
|---|---|
| `docker volume create --driver rexray` | PV referencing a `csi:` block with a specific driver |
| Plugin installed on Docker host | CSI driver deployed as a DaemonSet/StatefulSet in the cluster |
| Abstracts underlying storage from container | Abstracts underlying storage from Pod |

---

### Container recreated → Pod recreated; data persists

In Docker, if you stop and remove a container but keep the named volume, a new container can mount the same volume and find the previous data intact.

```bash
docker rm my-db
docker run -v pg-data:/var/lib/postgresql/data postgres
# previous data is still there ✅
```

In Kubernetes, the same principle applies with PV/PVC:

```
Pod deleted  →  PVC still exists  →  PV still exists  →  data intact
New Pod      →  mounts same PVC   →  picks up existing data ✅
```

Without a PV/PVC (i.e. using `emptyDir`), the behaviour is closer to a Docker container with **no volume** — data is gone when the container/Pod is removed.

---

## Important Differences

Despite the conceptual similarities, there are key differences you must be aware of:

| Aspect | Docker | Kubernetes |
|---|---|---|
| **Scope** | Single host (or Swarm with plugins) | Cluster — spans multiple nodes |
| **Volume lifecycle** | Managed by Docker Engine | Managed by Kubernetes control plane |
| **Portability** | Volume is local to the Docker host | PV can be network-attached and accessible from any node |
| **Dynamic provisioning** | Not built-in | Supported via StorageClass — PVs can be created automatically on demand |
| **Docker Desktop Kubernetes** | Uses Docker Engine volumes | Uses its own resource management — a Docker named volume is **not** automatically a Kubernetes PV |

> A Docker named volume on your laptop is **not** automatically a Kubernetes PersistentVolume. Docker Desktop Kubernetes and Docker Engine manage storage independently.

---

## Summary

```
Docker                          Kubernetes
──────────────────────          ──────────────────────────
Named volume                 ≈  PersistentVolume (PV)
Container volume mount       ≈  PersistentVolumeClaim (PVC)
Compose volumes: block       ≈  PVC + PV / StorageClass YAML
Volume driver                ≈  CSI driver
Volume survives container    ≈  PV/PVC survive Pod deletion
```

The mental model transfers well. The main additions in Kubernetes are the **claim indirection** (Pod → PVC → PV), the **cluster-wide scope**, and the **CSI driver ecosystem** for attaching any kind of external storage.
