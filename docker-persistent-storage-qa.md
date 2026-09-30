# Docker Persistent Storage — Real-World Q&A

A practical deep-dive into storage backends, data loss risks, production recommendations,
and orchestration choices for a SaaS platform migrating to containerised microservices on Azure.

---

## Q1: Why not just use an NFS server with a hierarchical folder structure as the storage backend?

You can — and for small teams or early-stage platforms, NFS is a perfectly reasonable starting point.
But as soon as you operate at scale, NFS introduces a class of problems that purpose-built storage tools
are specifically designed to eliminate.

### What NFS gives you
- A familiar POSIX filesystem your containers can mount as a standard volume
- Simple hierarchical folders — no new concepts to learn
- Works with any volume driver (`nfs` driver in Docker / Kubernetes NFS provisioner)

### What NFS does NOT give you

| Concern | NFS Reality | Purpose-built Tool Advantage |
|---|---|---|
| **High availability** | NFS server is a single point of failure | Distributed stores (Ceph, Longhorn) replicate across nodes |
| **Automatic failover** | Manual intervention if NFS host dies | Self-healing — replicas promote automatically |
| **Dynamic provisioning** | Admin must pre-create shares manually | StorageClasses in K8s auto-provision volumes on demand |
| **Snapshots & clones** | Not built-in; requires OS-level tooling | First-class feature in Longhorn, Portworx, Azure Disk CSI |
| **Encryption at rest** | Depends entirely on the OS/NFS config | Built-in with most CSI drivers and managed cloud disks |
| **Performance isolation** | All containers share the same NFS bandwidth | Per-volume QoS and IOPS limits in managed solutions |
| **Observability** | Minimal; you see disk usage on the host | Rich metrics (IOPS, throughput, latency) per PVC in Longhorn/Portworx |

### The real risk: NFS is a shared resource

Every container writing to the same NFS mount competes for the same I/O bandwidth.
A single misbehaving container (unbounded log writes, a runaway job) can degrade storage
performance for every other service on the platform simultaneously.

### When NFS is still fine
- Dev/test environments
- Read-heavy workloads (config files, static assets)
- Shared read-only data between containers (model files, reference data)

For a growing SaaS platform moving to microservices, NFS as your primary
persistence backend is technical debt you will eventually need to pay off.

---

## Q2: How dangerous is Docker for persistent data? Common causes of catastrophic data loss

> Docker is most suited for microservices where the application runs inside the container
> but storage and sessions are maintained in a shared database or external cache.
> **You simply should not store anything inside the container itself.**

This is the correct mental model. Here is why, and where things go catastrophically wrong:

### The Cardinal Rule
```
Container filesystem = ephemeral scratch space
Persistent data      = must live outside the container, always
```

### Top Causes of Catastrophic Data Loss in Docker Environments

#### 1. Storing data inside the container layer
The most common mistake. Any write to a path that is NOT a mounted volume
goes into the container's writable layer — and is destroyed when the container is removed.

```bash
# This destroys all data written to /var/lib/mysql
docker rm my-database-container
```

**Fix:** Every stateful path must be a mounted volume.

#### 2. `docker-compose down -v`
The `-v` flag removes named volumes along with containers.
One mistyped command in production deletes your database.

```bash
docker-compose down        # safe — volumes persist
docker-compose down -v     # DANGER — volumes destroyed
```

**Fix:** CI/CD pipelines and runbooks must never include `-v` for production environments.
Use named volumes (not anonymous volumes) so accidental removal is harder.

#### 3. Container upgrades done wrong
Bringing a container down and spinning a new one with a newer image is the standard Docker upgrade pattern.
If the data path is not mounted to an external volume, the upgrade **silently destroys all data**.

```bash
# Old container removed — if /data is not a volume, data is gone
docker stop app && docker rm app
docker run --name app new-image:v2   # /data starts empty
```

**Fix:** Containers must always be stateless. All state lives in mounted volumes or external services
(databases, Redis, blob storage). This is also why clusters work — stateless containers
can be replaced on any node without data coordination overhead.

#### 4. Anonymous volumes instead of named volumes
```yaml
volumes:
  - /var/lib/postgresql/data   # anonymous — tied to container lifecycle, easy to lose
```
vs.
```yaml
volumes:
  - pgdata:/var/lib/postgresql/data   # named — persists independently of containers
```
Anonymous volumes are hard to identify and easy to prune accidentally with `docker volume prune`.

#### 5. `docker system prune` or `docker volume prune` in production
These commands are safe on dev machines. In production they are catastrophic.
`docker volume prune` removes all volumes not currently attached to a running container —
including volumes belonging to stopped (but not removed) containers.

#### 6. No backup strategy
Docker volumes are not automatically backed up. If the host disk fails, the volume is gone.
This is not a Docker bug — it is an operational gap.

**Fix:** Snapshot policies on cloud block disks (Azure Disk snapshots, EBS snapshots),
plus periodic logical backups (pg_dump → Azure Blob Storage).

#### 7. Bind mounts with wrong host paths
```yaml
volumes:
  - ./data:/var/lib/postgresql/data   # bind mount
```
If the host path `./data` is empty (first deploy, CI runner, new node), PostgreSQL starts
with an empty data directory and initialises a fresh cluster — silently discarding the expectation
of existing data. Named volumes avoid this class of mistake.

---

## Q3: Recommended Persistent Storage for Your SaaS Platform on Azure

### Your profile
- **Data payloads:** 5 KB – 100 KB (small structured records)
- **Processing:** small–medium resource consumption
- **Volume:** medium, growing steadily
- **Architecture:** monolith → containerised microservices on Azure
- **Includes:** data warehouse migration

### Recommended Stack

#### Transactional / operational data → Azure Database for PostgreSQL (Flexible Server)
Do not run your own PostgreSQL in a container for production SaaS data.
Managed PaaS databases on Azure give you:
- Automated backups with point-in-time restore (up to 35 days)
- High availability with automatic failover
- Read replicas for scaling read-heavy microservices
- No volume management — Azure handles the storage layer entirely
- Works natively with Azure Private Link (containers connect securely inside your VNet)

Your small payload size (5–100 KB) is exactly the sweet spot for a relational store.
Indexing, transactions, and foreign keys are all available and performant at this size.

#### Container-attached persistent volumes → Azure Disk CSI Driver (for Kubernetes)
For any microservice that genuinely needs a local volume
(message queue persistence, local caching, file processing scratch space):

- Use **Azure Managed Disks** via the `disk.csi.azure.com` StorageClass
- Choose `Premium SSD` for latency-sensitive workloads, `Standard SSD` for cost-sensitive ones
- Disk snapshots are built-in — automate them with Azure Backup Vault policies

```yaml
# Kubernetes PVC backed by Azure Premium SSD
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: service-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: managed-premium
  resources:
    requests:
      storage: 10Gi
```

#### Shared file storage across pods → Azure Files CSI Driver
For volumes that multiple pods need to read/write simultaneously
(shared upload staging, inter-service file exchange):

- Use **Azure Files** (`file.csi.azure.com` StorageClass)
- SMB or NFS protocol, mounts as `ReadWriteMany`
- Backed by Azure Storage with 99.9% SLA

#### Data warehouse → Azure Synapse Analytics or Azure SQL Data Warehouse
Do not containerise your data warehouse. This is the one workload that benefits most from
managed PaaS services:

- **Azure Synapse Analytics** if you need combined data integration + analytics
- **Azure SQL Hyperscale** if your warehouse is relational and query patterns are well-understood
- Both handle storage scaling automatically and integrate with Azure Data Factory for ETL pipelines

#### Unstructured / blob data (user uploads, exports, logs) → Azure Blob Storage
Access via SDK from application code — not as a mounted volume.
Lifecycle management policies automatically tier cold data to archive storage, controlling cost as volume grows.

### Summary Architecture

```
Microservice A  ──► Azure Database for PostgreSQL  (transactional data)
Microservice B  ──► Azure Disk (CSI) PVC           (local stateful volume)
Microservice C  ──► Azure Files (CSI) PVC           (shared file access)
All services    ──► Azure Blob Storage (SDK)        (unstructured / uploads)
Analytics       ──► Azure Synapse Analytics         (data warehouse)
```

---

## Q4: Kubernetes vs. Rancher/Cattle — Is Kubernetes Over-Engineered for Small–Medium Platforms?

### Short answer
Kubernetes is not over-engineered for a SaaS platform migrating to microservices —
it is the right long-term foundation. The operational complexity is real, but it front-loads
work that Rancher/Cattle (now largely retired) would eventually force you to redo anyway.

### Rancher/Cattle vs. Kubernetes

| Capability | Rancher Cattle (legacy) | Kubernetes |
|---|---|---|
| Container scheduling | Basic | Advanced (affinity, taints, topology spread) |
| Self-healing | Restart failed containers | Restart, reschedule on healthy nodes, liveness/readiness probes |
| Rolling deployments | Limited | First-class (`RollingUpdate`, `maxSurge`, `maxUnavailable`) |
| Service discovery | DNS-based | CoreDNS + Services + Endpoints (robust) |
| Storage abstraction | Basic volumes | CSI drivers, StorageClasses, PVCs, dynamic provisioning |
| Secrets management | Basic | Kubernetes Secrets + integration with Azure Key Vault via CSI |
| Auto-scaling | Manual | HPA (CPU/memory), KEDA (event-driven), Cluster Autoscaler |
| Multi-tenancy | Minimal | Namespaces, RBAC, Network Policies, Resource Quotas |
| Ecosystem | Limited | Vast — Helm, Argo CD, Istio, Prometheus, Cert-Manager, etc. |
| Azure integration | None native | AKS — first-class Azure integration |

Cattle was deprecated. Rancher itself now runs Kubernetes underneath.

### Kubernetes strengths specific to your Azure SaaS context

1. **AKS (Azure Kubernetes Service)** is fully managed — Microsoft handles the control plane,
   etcd, and API server. You only manage worker nodes (or use virtual nodes for serverless scale).

2. **Azure CSI drivers** are maintained by Microsoft and work natively with AKS.
   Azure Disk, Azure Files, and Azure Blob Storage are first-class storage backends
   with no third-party drivers needed.

3. **Azure AD Workload Identity** — microservices authenticate to Azure services
   (Blob Storage, Key Vault, Service Bus) using Kubernetes service accounts mapped to
   Azure Managed Identities. No credentials stored in containers or environment variables.

4. **KEDA (Kubernetes Event-Driven Autoscaling)** is open-source, Azure-sponsored,
   and integrates with Azure Service Bus, Event Hubs, and Storage Queues.
   Scale your processing microservices to zero when idle and out to hundreds of replicas under load —
   critical for a cost-efficient SaaS platform.

5. **Helm + GitOps (Argo CD / Flux)** — declarative, version-controlled deployments.
   Every change to infrastructure and application config is a git commit.
   Rollback is `git revert`.

### Is it over-engineered?
The learning curve is real. For a team running 2–3 services, raw Docker Compose on a VM
may ship faster in the short term. But once you cross into:
- Multiple microservices with independent scaling needs
- Rolling deployments with zero downtime
- More than one environment (dev/staging/prod)
- Any compliance or security requirement (RBAC, audit logs, secret management)

...Kubernetes pays its complexity cost back quickly. For a SaaS platform with a growing data warehouse
and a microservices migration already planned, AKS is the correct foundation to build on now —
not something to migrate to later when pain forces it.

---

## Supplemental Reading

### Docker Storage & Volumes
- [Docker official docs — Manage data in Docker](https://docs.docker.com/storage/)
- [Docker volumes vs. bind mounts vs. tmpfs](https://docs.docker.com/storage/volumes/)
- [Docker volume drivers](https://docs.docker.com/engine/extend/plugins_volume/)

### Azure Storage for Containers
- [Azure Disk CSI driver for AKS](https://learn.microsoft.com/azure/aks/azure-disk-csi)
- [Azure Files CSI driver for AKS](https://learn.microsoft.com/azure/aks/azure-files-csi)
- [Azure Blob CSI driver for AKS](https://learn.microsoft.com/azure/aks/azure-blob-csi)
- [Best practices for storage in AKS](https://learn.microsoft.com/azure/aks/operator-best-practices-storage)

### Kubernetes & AKS
- [AKS documentation](https://learn.microsoft.com/azure/aks/)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [KEDA — Kubernetes Event-Driven Autoscaling](https://keda.sh)
- [Azure AD Workload Identity](https://learn.microsoft.com/azure/aks/workload-identity-overview)

### Architecture & Best Practices
- [12-Factor App](https://12factor.net) — the foundational reference for stateless, container-friendly application design (Factor VI: Processes must be stateless; Factor IV: Backing services)
- [The Twelve-Factor App — Backing Services](https://12factor.net/backing-services)

---

## Core Takeaways

> 1. **Never store data inside a container.** Containers are stateless compute units. All state belongs in external volumes, databases, or caches.
> 2. **Docker volumes are the bridge** from the container to whatever storage backend exists — local disk, cloud block storage, or managed PaaS.
> 3. **For Azure SaaS:** use managed PaaS databases (PostgreSQL Flexible Server, Synapse) for data, Azure Disk/Files CSI for volume-attached storage, and Azure Blob for unstructured data.
> 4. **AKS + Kubernetes** is the right orchestration choice for a microservices SaaS platform — not over-engineered when you account for the full lifecycle of the platform.
> 5. **Operational discipline** (no `-v` on `docker-compose down`, named volumes, backup policies) prevents the majority of catastrophic data loss incidents.
