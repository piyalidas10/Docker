# Storage Classes and Applying PV + PVC + Deployment

---

## Overview

Before applying the PV, PVC, and Deployment, there is one important piece that needs to be in place: **StorageClasses**.

---

## What is a StorageClass?

A **StorageClass** is a Kubernetes concept that gives administrators fine-grained control over how storage is managed and how volumes are provisioned behind the scenes.

It works together with the PersistentVolume configuration to tell Kubernetes:
- **How** the storage should be provisioned
- **What type** of storage backend to use
- **What parameters** apply to that storage

> For this local setup, the default StorageClass that ships with Minikube (and Docker Desktop Kubernetes) is already configured for `hostPath` — so it works without any extra setup. We just need to **reference it by name** in both the PV and PVC.

---

## Checking Available StorageClasses

```bash
kubectl get sc
```

On Minikube / Docker Desktop, you will see something like:

```
NAME                 PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
standard (default)   docker.io/hostpath         Delete          Immediate           false                  <age>
```

The `standard` StorageClass is the one to use here.

---

## Adding `storageClassName` to the PV and PVC

Both the PV and the PVC must reference the **same** `storageClassName` for binding to succeed.

### `host-pv.yaml` — add `storageClassName`

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: host-pv
spec:
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  storageClassName: standard        # ← required
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /data
    type: DirectoryOrCreate
```

### `host-pvc.yaml` — add `storageClassName`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: host-pvc
spec:
  volumeName: host-pv
  accessModes:
    - ReadWriteOnce
  storageClassName: standard        # ← must match the PV
  resources:
    requests:
      storage: 1Gi
```

> Both files use `storageClassName: standard`. If they do not match, Kubernetes cannot bind the PVC to the PV.

---

## Applying Everything — The Correct Order

Apply the resources in this order: **PV first, then PVC, then Deployment**.

```bash
kubectl apply -f host-pv.yaml
kubectl apply -f host-pvc.yaml
kubectl apply -f deployment.yaml
```

Applying the PVC before the PV exists is fine — Kubernetes will simply keep the PVC in `Pending` state until a compatible PV appears. However, applying the PV first is cleaner and avoids unnecessary wait time.

---

## Verifying the State

### Check PersistentVolumes

```bash
kubectl get pv
```

Expected output:

```
NAME      CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM              STORAGECLASS   AGE
host-pv   1Gi        RWO            Retain           Bound    default/host-pvc   standard       <age>
```

- `STATUS: Bound` — the PV is claimed by `host-pvc` ✅

### Check PersistentVolumeClaims

```bash
kubectl get pvc
```

Expected output:

```
NAME       STATUS   VOLUME    CAPACITY   ACCESS MODES   STORAGECLASS   AGE
host-pvc   Bound    host-pv   1Gi        RWO            standard       <age>
```

- `STATUS: Bound` — the PVC is connected to `host-pv` ✅

### Check the Deployment

```bash
kubectl get deployments
kubectl get pods
```

Expected output:

```
NAME               READY   UP-TO-DATE   AVAILABLE   AGE
story-deployment   2/2     2            2           <age>
```

Both replicas are running and using the PersistentVolume via the claim.

---

## What Changed vs a Pod-Specific Volume?

From a **functional perspective**, the application behaves the same as before with the `hostPath` pod-specific volume — the data is written to `/data` on the node either way.

The difference is architectural:

| Aspect | Pod-specific `hostPath` volume | PV + PVC (`host-pv` / `host-pvc`) |
|---|---|---|
| **Volume defined in** | Deployment YAML inline | Standalone `host-pv.yaml` |
| **Pod references** | Storage type directly | Claim name only (`host-pvc`) |
| **Volume reusable by other Pods** | No | Yes — any Pod can claim it |
| **Storage config separate from app config** | No | Yes — PV is fully decoupled from Pod |
| **Node independence (with other types)** | No | Yes — when using cloud/CSI types |

> With `hostPath`, data is still tied to the node filesystem (`/data`). The node independence benefit is realised only when you switch to a cloud-backed or network-backed PV type (e.g. `awsElasticBlockStore`, `nfs`, or a CSI driver). The PV/PVC structure remains identical — only the storage backend changes.

---

## When to Use PVs — Matching Volume Type to Data Type

| Type of data | Appropriate storage |
|---|---|
| **Intermediate results, caches, temporary files** | Pod-specific volume (`emptyDir`, or `hostPath` for local dev) — data loss on Pod removal is acceptable |
| **User-generated data, accounts, products, uploaded files** | PersistentVolume + PVC — data must survive Pod and node changes |

> For temporary and intermediate data, pod-specific volumes are often sufficient. You could use a PersistentVolume for them too, but it is not necessary. For long-term application data — the kind that must **never be lost** — PersistentVolumes with PersistentVolumeClaims are the right solution.

---

## Summary

```
StorageClass: standard
    │
    ├── Referenced by host-pv.yaml  (storageClassName: standard)
    └── Referenced by host-pvc.yaml (storageClassName: standard)
            │
            ▼
    Kubernetes binds PVC to PV  →  STATUS: Bound

Apply order:
    kubectl apply -f host-pv.yaml
    kubectl apply -f host-pvc.yaml
    kubectl apply -f deployment.yaml

Result:
    host-pv   → Bound
    host-pvc  → Bound
    story-deployment → 2/2 Pods running
    Pods → using host-pvc → host-pv → /data on node
```

You now have a **standalone, cluster-level volume** fully decoupled from the Pod specification. Both replicas of `story-deployment` share the same storage, and the volume configuration lives independently in `host-pv.yaml` — not buried inside the Deployment. Any other Pod in the cluster could create a new claim and use the same volume if needed.
