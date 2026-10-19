# Volumes to Persistent Volumes

---

## The Problem with Regular Volumes

We have seen how Kubernetes volumes work and explored the `emptyDir`, `hostPath`, and `CSI` types. However, regular volumes come with a fundamental limitation:

> **Volumes are tied to Pods — when a Pod is destroyed or replaced, the volume (and its data) is lost.**

### Specific scenarios where this matters

| Scenario | Problem |
|---|---|
| Pod is terminated and replaced | Volume is destroyed along with the Pod |
| Scaling from 1 Pod to 2 Pods (`emptyDir`) | New Pod gets its own empty directory — no access to data written by the first Pod |
| Multi-node cluster with `hostPath` | Only works on a single-node setup (e.g. Minikube); in a real cluster with multiple worker nodes, Pods on different nodes do **not** share the same host path |

### Why `hostPath` is not a real solution

`hostPath` appeared to solve the multi-Pod data sharing problem — but only because **Minikube is a single-node environment**. All Pods run on the same worker node, so they all share the same host path.

On a real cluster (e.g. on AWS with multiple worker nodes), `hostPath` breaks down entirely. Pods scheduled on different nodes would each read from a different local path and see different data.

---

## When You Need Pod and Node Independent Storage

Not all data needs to survive Pod replacement. Temporary and intermediate results can safely be lost. But for **long-term, key application data**, you cannot afford to lose it just because a Pod was scaled up or replaced.

| Data type | Loss acceptable? |
|---|---|
| Intermediate results, session data | ✅ Usually fine |
| Uploaded files, database records, key app data | ❌ Must survive |

---

## Introducing Persistent Volumes

Kubernetes provides a solution: **Persistent Volumes (PV)**.

As the name implies, these are **Pod and Node independent** volumes that always persist, regardless of Pod lifecycle.

### But wait — don't some regular volume types already persist?

Yes — types like `awsElasticBlockStore`, `azureDisk`, `azureFile`, and `nfs` store data outside the Pod or node, so the data itself survives Pod termination. Unlike `emptyDir`, data on AWS or Azure servers is not erased when a Pod shuts down.

So why do we need a separate Persistent Volume concept?

---

## What Makes Persistent Volumes Different

The key distinction is **where the volume is defined and managed**, not just where data is stored.

| | Regular Volumes | Persistent Volumes |
|---|---|---|
| **Defined in** | Pod / Deployment YAML (`spec.template.spec`) | Standalone cluster resource — independent of any Pod |
| **Lifecycle** | Tied to the Pod | Fully independent of Pods and Nodes |
| **Reusability** | Must be reconfigured per Pod/Deployment | Define once, use in multiple Pods |
| **Admin control** | Per-Pod config | Central, cluster-level management |
| **Multi-Pod sharing** | Limited (type-dependent) | Full flexibility via claims |

With Persistent Volumes, the volume is **detached from the Pod entirely** — including detachment from the Pod lifecycle.

---

## How Persistent Volumes Work

```
Cluster
 ├── Node A
 │    └── Pod 1
 │         └── PersistentVolumeClaim ──────────┐
 ├── Node B                                     │
 │    └── Pod 2                                 ▼
 │         └── PersistentVolumeClaim ──► PersistentVolume (external storage)
 └── Node C
      └── Pod 3
           └── PersistentVolumeClaim ──────────┘
```

### Key entities

| Entity | Role |
|---|---|
| **PersistentVolume (PV)** | A standalone cluster resource that represents actual storage (e.g. cloud disk, NFS share). Defined independently of any Pod. |
| **PersistentVolumeClaim (PVC)** | A request for storage made by a Pod. The Pod includes a claim; the claim connects to a matching PersistentVolume. |

- Pods contain **claims**, not volume definitions directly
- Claims reach out to standalone **persistent volumes** to request access
- Multiple Pods on different Nodes can hold claims to the same or different persistent volumes
- Storage is **not on the cluster nodes** — it is truly independent (e.g. a cloud storage service)

---

## Persistent Volume Types

The available types for Persistent Volumes are similar to regular volume types, but with important differences:

- `emptyDir` is **not available** — it is inherently Pod-specific and has no place in the persistent volume concept
- `hostPath` is **available but restricted** — only usable in a single-node setup (like Minikube); not suitable for real multi-node clusters
- Cloud storage types (`awsElasticBlockStore`, `azureFile`, `azureDisk`) and the flexible `csi` type are the real targets for production use

> `hostPath` with Persistent Volumes is used here **only for local development and learning**. In a real deployment (e.g. on AWS), you would use the CSI type with a driver like the AWS EFS CSI driver instead.

---

## Summary

| Concept | Key Point |
|---|---|
| Regular volumes | Defined inside Pod specs; tied to Pod lifecycle |
| `emptyDir` | Pod-specific; lost on Pod removal |
| `hostPath` | Node-specific; only works on single-node setups like Minikube |
| **Persistent Volumes** | Cluster-level resources; fully Pod and Node independent |
| **PersistentVolumeClaim** | The bridge between a Pod and a PersistentVolume |
| Production storage | Use cloud types or CSI driver; data lives outside the cluster nodes |

The next step is to define a **PersistentVolume** and a **PersistentVolumeClaim** in YAML and connect them to a Pod — starting with `hostPath` to understand the mechanics before moving to real cloud storage.
