# Docker Persistent Storage: The Bridge to Cloud Storage

## The Right Mental Model

> **Docker volumes and cloud storage do not compete.**
> A Docker volume is the **bridge** that connects a running container to whatever storage lives underneath — whether that is a local disk, a cloud block device (EBS, Azure Disk), or even a cloud-backed volume driver (like `rexray` or `nfs`).
> Without the volume, the container simply cannot reach any storage at all.

---

## Why the Container Needs a Bridge

Docker containers are **stateless and ephemeral by design**. A container has no persistent filesystem of its own — everything written inside it disappears when the container stops or is replaced. The container process (your database, your app) only knows how to read and write a **local filesystem path** like `/var/lib/postgresql/data`.

Cloud storage (EBS, Azure Disk, GCS Filestore) lives **outside** the container. The container cannot talk to it directly. A Docker volume is what **mounts** that external storage into the container's filesystem namespace so the process can use it transparently.

```
┌─────────────────────────────────────┐
│          Docker Container           │
│                                     │
│  PostgreSQL writes to               │
│  /var/lib/postgresql/data  ─────────┼────► Docker Volume
│                                     │             │
└─────────────────────────────────────┘             │ mounts / bridges
                                                    ▼
                                     ┌──────────────────────────┐
                                     │   Underlying Storage     │
                                     │                          │
                                     │  • Local disk (dev)      │
                                     │  • EBS volume (AWS)      │
                                     │  • Azure Managed Disk    │
                                     │  • NFS / GCS Filestore   │
                                     └──────────────────────────┘
```

The **container doesn't change**. The **volume driver** decides what storage backend is used. This is the power of the abstraction.

---

## Volume Drivers: How the Bridge Reaches Cloud Storage

Docker's volume driver system is what makes this bridging work across environments:

| Volume Driver | Backs Into | Use Case |
|---|---|---|
| `local` (default) | Host disk | Development, single-node |
| `rexray/ebs` | AWS EBS | Production on EC2 |
| `azure-file` | Azure File Storage | Production on Azure |
| `nfs` | NFS / GCS Filestore | Shared multi-container storage |
| `s3fs` / `goofys` | AWS S3 | Large file storage (not DBs) |

Same `volumes:` declaration in your Compose file — different driver, different cloud backend. **The container sees a filesystem path either way.**

---

## The Core Problem Without the Bridge

```
Container starts → writes data to /var/lib/mysql
Container crashes  → ALL that data is GONE
Container restarts → starts fresh with empty filesystem
```

Even if your cloud has EBS, Azure Disk, or GCS attached to the **host VM**, the container cannot see it unless a Docker volume bridges that storage into the container's namespace.

---

## Real-World Example: PostgreSQL Backed by EBS (AWS)

### Without a Volume — Data Lost on Restart
```yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: secret
# Container restarts → /var/lib/postgresql/data wiped → data gone
```

### With a Local Volume (Dev / Single Node)
```yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: secret
    volumes:
      - pgdata:/var/lib/postgresql/data   # bridges to host disk

volumes:
  pgdata:
```

### With an EBS-Backed Volume (Production on AWS)
```yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: secret
    volumes:
      - pgdata:/var/lib/postgresql/data   # same declaration

volumes:
  pgdata:
    driver: rexray/ebs                    # bridge now reaches AWS EBS
    driver_opts:
      size: "50"
      volumetype: "gp3"
```

The **container definition is identical**. Only the volume driver changes. The bridge adapts to the environment.

---

## Cloud Object Storage (S3) is a Different Layer

Cloud object storage like S3, Azure Blob, or GCS is an **HTTP-based API store** — not a filesystem. It operates at a completely different layer:

| Layer | Technology | Accessed Via | Suitable For |
|---|---|---|---|
| Container filesystem | Docker Volume | Mount path (`/data`) | Databases, caches, runtime state |
| Cloud block storage | EBS, Azure Disk | Volume driver (bridge) | Persistent VM-level disks |
| Cloud object storage | S3, GCS, Blob | HTTP API / SDK | Backups, media, archives, logs |

S3 is not something a volume bridges to for a database — it's too slow (50–200ms per call vs. <1ms for local I/O) and not POSIX-compatible. It plays a complementary role: long-term durability and scale, not runtime I/O.

---

## The Complete Picture

```
┌──────────────────────────────────────────────────────────────┐
│                     Docker Container                         │
│   App writes to /data  ──► Docker Volume (bridge)           │
└──────────────────────────────────────────────────────────────┘
                                    │
               ┌────────────────────┼────────────────────┐
               ▼                    ▼                    ▼
        Local Disk             AWS EBS              Azure Disk
        (dev/test)           (prod AWS)           (prod Azure)
                                    │
                            Backup job runs
                                    │
                                    ▼
                             AWS S3 / Glacier
                          (long-term durability)
```

- **Docker Volume** = the bridge (always needed)
- **Cloud Block Storage** = what the bridge connects to in production
- **Cloud Object Storage** = the archive/backup tier downstream

---

## Quick Reference

| Question | Answer |
|---|---|
| Can a container write directly to EBS without a volume? | No. The volume driver bridges EBS into the container. |
| Can a container write directly to S3 without a volume? | Only via SDK/HTTP in app code, not as a filesystem. |
| Does Docker volume compete with cloud storage? | No. It bridges the container to it. |
| What changes between dev and prod storage? | The volume driver. The container stays the same. |
| Why can't S3 replace a Docker volume for a database? | Wrong access pattern — HTTP API, not POSIX I/O. |

---

## Key Takeaway

> A Docker volume is not an alternative to cloud storage.
> It is the **mounting mechanism** — the bridge — that gives a container access to whatever storage backend exists in that environment.
> Remove the volume, and the container is cut off from all storage, cloud or otherwise.
