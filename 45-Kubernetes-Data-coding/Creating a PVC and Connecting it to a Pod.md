# Creating a PersistentVolumeClaim and Connecting it to a Pod

---

## Overview

A **PersistentVolume (PV)** defines storage as a standalone cluster resource. On its own, it does nothing for a Pod. The second part of the equation is the **PersistentVolumeClaim (PVC)** — a request made by a Pod to use that volume.

The workflow has two parts:

1. **Define the claim** — `host-pvc.yaml`
2. **Connect the claim to the Pod** — update `deployment.yaml` to reference the PVC

---

## Part 1 — The PersistentVolumeClaim (`host-pvc.yaml`)

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

### Field-by-field explanation

| Field | Value | Meaning |
|---|---|---|
| `apiVersion` | `v1` | PersistentVolumeClaim is a core v1 resource |
| `kind` | `PersistentVolumeClaim` | Tells Kubernetes this is a PVC — must be spelled exactly as shown |
| `metadata.name` | `host-pvc` | The name of this claim — referenced by Pods that want to use it |
| `spec.volumeName` | `host-pv` | Claims the specific PV named `host-pv` by name (direct binding) |
| `spec.accessModes` | `ReadWriteOnce` | The access mode **used** when claiming — must be supported by the target PV |
| `spec.storageClassName` | `standard` | Must match the `storageClassName` defined on the PV for binding to succeed |
| `spec.resources.requests.storage` | `1Gi` | The amount of storage requested — must not exceed the PV's `capacity.storage` |

---

### Claiming by name vs claiming by resource

There are two ways to connect a PVC to a PV:

| Approach | How | When to use |
|---|---|---|
| **By name** (`volumeName`) | Directly references a specific PV by its `metadata.name` | Simple setups with a known, pre-created PV |
| **By resource** (label selectors, capacity, StorageClass) | Kubernetes finds any PV that satisfies the request | Larger clusters with many PVs; dynamic provisioning via StorageClass |

Here `volumeName: host-pv` is used — straightforward and explicit.

---

### `resources.requests` — the counterpart to `capacity`

```
PV:  spec.capacity.storage: 1Gi   ← maximum available
PVC: spec.resources.requests.storage: 1Gi  ← amount requested
```

- The requested amount must not exceed the PV's capacity
- In a scenario with multiple claims on the same PV, each claim requests a portion
- Requesting more across all claims than is actually available can cause errors when Pods start writing data

---

### What the PVC does NOT do yet

At this point the PVC:
- ✅ Exists as a cluster resource
- ✅ Is bound to `host-pv`
- ❌ Is **not yet connected to any Pod**

A Pod must explicitly reference this claim to use it.

---

## Part 2 — Connecting the PVC to the Pod (`deployment.yaml`)

The connection is made in the Pod spec inside the Deployment, under the `volumes` key.

```yaml
# deployment.yaml
spec:
  replicas: 2
  selector:
    matchLabels:
      app: story
  template:
    metadata:
      labels:
        app: story
    spec:
      containers:
        - name: story
          image: academind/kub-data-demo:2
          env:
            - name: STORY_FOLDER
              valueFrom:
                configMapKeyRef:
                  name: data-store-env
                  key: folder
          volumeMounts:
            - mountPath: /app/story
              name: story-volume
      volumes:
        - name: story-volume
          persistentVolumeClaim:       # ← previously: hostPath or emptyDir
            claimName: host-pvc        # ← name of the PVC defined above
```

### What changed compared to a regular volume

Previously the `volumes` entry used an inline type (`hostPath`, `emptyDir`) that defined the storage directly inside the Pod spec:

```yaml
# Before — regular hostPath volume (pod-specific)
volumes:
  - name: story-volume
    hostPath:
      path: /data
      type: DirectoryOrCreate
```

Now it uses the `persistentVolumeClaim` type and references the claim by name:

```yaml
# After — persistent volume claim (cluster-level, pod-independent)
volumes:
  - name: story-volume
    persistentVolumeClaim:
      claimName: host-pvc
```

| | Before | After |
|---|---|---|
| **Volume defined in** | Deployment YAML inline | Standalone `host-pv.yaml` |
| **Pod connects to** | Storage directly | A claim (`host-pvc`) |
| **`volumeMounts`** | Unchanged | Unchanged — same `mountPath: /app/story` |
| **Storage scope** | Pod-specific | Cluster-level, reusable across Pods |

> `volumeMounts` does **not** change. The container still mounts the volume at `/app/story`. The only change is *where the volume comes from* — now from a claim rather than an inline definition.

---

## The Complete Chain

```
Pod (story-deployment — 2 replicas)
  └── volumes:
        └── persistentVolumeClaim.claimName: host-pvc
                  │
                  ▼
            PVC: host-pvc
            - accessModes: ReadWriteOnce
            - storageClassName: standard
            - requests: 1Gi
            - volumeName: host-pv
                  │
                  ▼
            PV: host-pv
            - capacity: 1Gi
            - volumeMode: Filesystem
            - storageClassName: standard
            - accessModes: ReadWriteOnce
            - hostPath: /data (DirectoryOrCreate)
                  │
                  ▼
            /data on the worker node filesystem
```

Both replicas of the Pod share the same PVC, which connects to the same PV and therefore the same underlying storage at `/data`.

---

## Applying Everything

Apply the PV, PVC, and Deployment in order:

```bash
kubectl apply -f host-pv.yaml
kubectl apply -f host-pvc.yaml
kubectl apply -f deployment.yaml
```

Check the status:

```bash
kubectl get pv
kubectl get pvc
kubectl get pods
```

### Expected state

```
NAME      CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM              STORAGECLASS   AGE
host-pv   1Gi        RWO            Retain           Bound    default/host-pvc   standard       <age>
```

```
NAME       STATUS   VOLUME    CAPACITY   ACCESS MODES   STORAGECLASS   AGE
host-pvc   Bound    host-pv   1Gi        RWO            standard       <age>
```

Both `host-pv` and `host-pvc` show **`Bound`** — the claim is connected to the volume and the Pods can use the storage.

---

## What This Achieves

| Goal | Achieved? |
|---|---|
| Data survives container restarts | ✅ Yes — volume is outside the container |
| Data survives Pod deletion and replacement | ✅ Yes — PV and PVC are independent of the Pod |
| Multiple Pods share the same storage | ✅ Yes — both replicas use `host-pvc` → `host-pv` → `/data` |
| Node independence (multi-node cluster) | ⚠️ No — `hostPath` is still node-local; use a cloud/CSI type for true node independence |
| Pod spec decoupled from storage implementation | ✅ Yes — Pod only references `host-pvc` by name; storage details are in `host-pv.yaml` |

> **Note:** For this local `hostPath` demo the node dependency still exists, as `hostPath` data lives on the node filesystem. However, everything you have learned about defining PVs, PVCs, and connecting them to Pods applies identically when using a different volume type — such as `awsElasticBlockStore` or a CSI driver — where real node independence is provided.
