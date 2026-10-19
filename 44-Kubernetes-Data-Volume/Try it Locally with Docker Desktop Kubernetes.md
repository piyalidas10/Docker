# Try it Locally with Docker Desktop Kubernetes

---

## Overview

Since you are learning Kubernetes locally on Windows, you can use `hostPath` to understand how PV and PVC binding works in practice. This is a **learning example**, not a recommended production storage configuration.

---

## Step 1 — Create the configuration file

Create a file named `pv-pvc-demo.yaml` with both the PersistentVolume and PersistentVolumeClaim defined in a single file, separated by `---`:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: demo-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: /mnt/data/demo-pv
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ""
  resources:
    requests:
      storage: 500Mi
```

### What each field means

**PersistentVolume (`demo-pv`)**

| Field | Value | Meaning |
|---|---|---|
| `capacity.storage` | `1Gi` | Total storage capacity of this PV |
| `accessModes` | `ReadWriteOnce` | Can be mounted read-write by a single node at a time |
| `persistentVolumeReclaimPolicy` | `Retain` | When the PVC is deleted, the PV and its data are kept — not automatically recycled |
| `storageClassName` | `""` | Empty string — this PV is not associated with any StorageClass; must be matched manually |
| `hostPath.path` | `/mnt/data/demo-pv` | Directory on the Kubernetes node's filesystem used as storage |

**PersistentVolumeClaim (`demo-pvc`)**

| Field | Value | Meaning |
|---|---|---|
| `accessModes` | `ReadWriteOnce` | Requests a volume that supports single-node read-write access |
| `storageClassName` | `""` | Must match the PV's `storageClassName` for manual binding |
| `resources.requests.storage` | `500Mi` | Requests 500 MiB — the PV offers 1Gi, which satisfies this request |

---

## Step 2 — Apply the configuration

```bash
kubectl apply -f pv-pvc-demo.yaml
```

Then check the status of both resources:

```bash
kubectl get pv
kubectl get pvc
```

### Expected output

```
NAME       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM              STORAGECLASS   REASON   AGE
demo-pv    1Gi        RWO            Retain           Bound    default/demo-pvc                           <age>
```

```
NAME       STATUS   VOLUME    CAPACITY   ACCESS MODES   STORAGECLASS   AGE
demo-pvc   Bound    demo-pv   1Gi        RWO                           <age>
```

`demo-pv` and `demo-pvc` should both show **`Bound`**, confirming that Kubernetes has matched the claim to the volume.

---

## Step 3 — Inspect the binding (optional)

For more detail on either resource:

```bash
kubectl describe pv demo-pv
kubectl describe pvc demo-pvc
```

Look for the `Status: Bound` line and the `Volume` / `Claim` fields showing the bidirectional binding.

---

## Step 4 — Clean up

To remove both resources when you are done experimenting:

```bash
kubectl delete pvc demo-pvc
kubectl delete pv demo-pv
```

> Because the reclaim policy is `Retain`, deleting the PVC does **not** delete the PV automatically. You must delete the PV separately. The data at `/mnt/data/demo-pv` on the node filesystem also remains until manually removed.

---

## Important Notes

| Note | Detail |
|---|---|
| **`hostPath` stores data on the node** | Data is written to the Kubernetes node's local filesystem (`/mnt/data/demo-pv`), not to a separate cloud storage service |
| **`Retain` policy** | The underlying data is not automatically recycled when the claim is released — manual cleanup is required |
| **Single-node only** | On a single-node Docker Desktop cluster this is useful for experimentation; it does not provide node-independent storage |
| **Not for production** | In a production deployment, choose an appropriate StorageClass and supported storage backend (e.g. AWS EBS CSI, Azure Disk CSI, NFS) |

---

## What This Demonstrates

```
kubectl apply -f pv-pvc-demo.yaml
        │
        ├── Creates demo-pv  (1Gi, hostPath, Retain, storageClassName: "")
        │
        └── Creates demo-pvc (requests 500Mi, storageClassName: "")
                │
                ▼
        Kubernetes matches PVC to PV
        (same accessMode, compatible size, matching storageClassName)
                │
                ▼
        Both resources show STATUS: Bound ✅
```

The PVC requested 500 Mi and the PV offered 1 Gi — Kubernetes binds them because the PV satisfies the claim's requirements. The Pod would then reference `demo-pvc` by name to use this storage.
