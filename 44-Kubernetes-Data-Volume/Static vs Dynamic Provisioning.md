# Static vs Dynamic Provisioning

---

## Overview

There are two common ways to obtain persistent storage in Kubernetes. The difference lies in **who creates the PersistentVolume** — an administrator ahead of time, or the cluster automatically on demand.

---

## Static Provisioning

An administrator manually creates PersistentVolumes before any application needs them. Applications then request storage by creating a PVC, and Kubernetes binds the PVC to a compatible pre-existing PV.

### How it works

```
1. Admin creates PV
       │
       ▼
   PersistentVolume (available, unbound)

2. Application creates PVC
       │
       ▼
   PersistentVolumeClaim (pending)

3. Kubernetes binds PVC to a compatible PV
       │
       ▼
   PVC  ──────────────────►  PV  (bound)
   (used by Pod)              (data stored externally)
```

### Steps

| Step | Actor | Action |
|---|---|---|
| 1 | **Administrator** | Creates a PV YAML and applies it to the cluster — defines capacity, access mode, storage type |
| 2 | **Application / Developer** | Creates a PVC YAML requesting a specific amount and access mode |
| 3 | **Kubernetes** | Finds a PV that satisfies the PVC's requirements and binds them together |

### When to use it

- Storage is provisioned and managed **in advance** by an operations team
- Specific storage devices or configurations must be pre-allocated (e.g. dedicated database disks)
- Environments where automated provisioning is not available or not permitted

---

## Dynamic Provisioning

No pre-created PVs are needed. An administrator configures a **StorageClass** that defines a provisioner and its parameters. When an application creates a PVC, Kubernetes automatically provisions a new PV through the configured provisioner and binds it to the claim.

### How it works

```
1. Admin configures StorageClass
       │
       ▼
   StorageClass (defines provisioner + parameters)

2. Application creates PVC referencing the StorageClass
       │
       ▼
   PersistentVolumeClaim (pending)

3. Kubernetes provisions storage and creates a PV automatically
       │
       ▼
   PV  ◄──── automatically created by provisioner
    │
    └──────────────────►  PVC  (bound)
                          (used by Pod)
```

### Steps

| Step | Actor | Action |
|---|---|---|
| 1 | **Administrator** | Creates a StorageClass YAML specifying a provisioner (e.g. AWS EBS CSI, Azure Disk CSI) and storage parameters |
| 2 | **Application / Developer** | Creates a PVC that references the StorageClass by name |
| 3 | **Kubernetes** | Calls the provisioner, which creates the actual storage resource (e.g. a cloud disk), then creates and binds a PV automatically |

### When to use it

- Automated application deployments where storage should be created **on demand**
- Cloud environments where storage can be provisioned programmatically (AWS, Azure, GCP)
- Teams want to remove manual storage management from the deployment workflow

---

## Comparison

| | Static Provisioning | Dynamic Provisioning |
|---|---|---|
| **PV created by** | Administrator (manually) | Kubernetes / provisioner (automatically) |
| **Requires StorageClass** | No (optional) | Yes |
| **Requires pre-created PV** | Yes | No |
| **Storage allocated** | In advance | On demand when PVC is created |
| **Flexibility** | Lower — PVs must match PVC requirements | Higher — provisioner creates exactly what is requested |
| **Admin overhead** | Higher — each PV must be created and maintained | Lower — StorageClass is configured once |
| **Typical environment** | On-premise, fixed storage infrastructure | Cloud (AWS, Azure, GCP), automated deployments |

---

## Key Resource: StorageClass

Dynamic provisioning depends on a **StorageClass** resource. It acts as a template that tells Kubernetes:

- **Which provisioner** to call (e.g. `ebs.csi.aws.com`, `disk.csi.azure.com`)
- **What parameters** to pass (disk type, IOPS, replication zone, etc.)
- **Reclaim policy** — what happens to the PV when the PVC is deleted (`Delete` or `Retain`)

```yaml
# Example StorageClass (AWS EBS via CSI)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard-ssd
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

A PVC then requests this class by name:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-storage
spec:
  storageClassName: standard-ssd
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

Kubernetes calls the AWS EBS CSI provisioner, which creates a 10 GiB `gp3` disk and binds it to the claim — no manual PV creation required.

---

## Summary

```
Static Provisioning                 Dynamic Provisioning
───────────────────────             ────────────────────────────
Admin creates PV manually    vs.    Admin configures StorageClass once
App creates PVC              vs.    App creates PVC (references StorageClass)
Kubernetes binds PVC to PV   vs.    Kubernetes provisions PV automatically
```

> In enterprise environments, **dynamic provisioning is common** because it removes manual storage management and integrates naturally with cloud infrastructure. The appropriate choice depends on your infrastructure, storage requirements, and operational model.
