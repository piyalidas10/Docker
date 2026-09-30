# Docker Volumes in Enterprise & Banking Environments

## The Core Distinction

> **Docker volumes solve persistence.**
> They do NOT by themselves solve high availability, disaster recovery, or data durability at scale.

For a small SaaS or dev environment, one PostgreSQL container with one named volume is sufficient.
For a critical banking database, that is just the starting point — not the finish line.

---

## What a Production Banking Database Actually Looks Like

```
                        Application
                             │
                             ▼
                   PostgreSQL HA Setup
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
          Primary                        Replica
       (read + write)                  (read only)
              │                             │
              └──────────────┬──────────────┘
                             │
                   Streaming Replication
                   (WAL shipped continuously)
                             │
                   ┌─────────┴──────────┐
                   ▼                    ▼
          Enterprise Storage       Backup Storage
          (Azure Disk / EBS /    (Azure Blob / S3 /
           SAN / NFS HA)          Glacier / Tape)
                   │
          Snapshot policies
          Encryption at rest
          Access audit logs
```

This is what Docker volumes are a **part of** — not a replacement for the entire stack.

---

## The 7 Layers That Go Beyond a Docker Volume

### 1. Replication

A single volume on a single host is a single point of failure. Replication sends every
committed transaction to one or more replica nodes in real time.

```
Primary Container          Replica Container
┌─────────────────┐        ┌─────────────────┐
│ PostgreSQL      │        │ PostgreSQL       │
│ (read + write)  │──WAL──►│ (read only)      │
└────────┬────────┘        └────────┬─────────┘
         │                          │
    pg_data                    pg_replica_data
    VOLUME                       VOLUME
         │                          │
    Host Disk A                Host Disk B
    (AZ East)                  (AZ West)
```

Both nodes have Docker volumes — but the **replication** between them is what makes
data survive a single node failure.

**Tools:**
- PostgreSQL Streaming Replication (built-in)
- Patroni — adds automatic leader election and failover on top of streaming replication
- pgpool-II — connection pooling + load balancing across primary/replica

```yaml
# Patroni + PostgreSQL HA with Docker
services:
  postgres-primary:
    image: patroni/patroni:latest
    environment:
      PATRONI_NAME: primary
      PATRONI_POSTGRESQL_DATA_DIR: /data/patroni
    volumes:
      - pg_primary_data:/data/patroni

  postgres-replica:
    image: patroni/patroni:latest
    environment:
      PATRONI_NAME: replica
      PATRONI_POSTGRESQL_DATA_DIR: /data/patroni
    volumes:
      - pg_replica_data:/data/patroni

volumes:
  pg_primary_data:
  pg_replica_data:
```

---

### 2. Automatic Failover

Replication keeps data in sync. Failover is what happens when the primary dies.
Without failover automation, an engineer must manually promote the replica — unacceptable
for a banking system with a 99.99% SLA.

```
Normal State                    Failover State
────────────                    ──────────────
Primary  ──alive──► Writes      Primary  ──DEAD──✗
Replica  ──sync──► Standby      Replica  ──promoted──► now accepts Writes
                                Patroni/etcd detected failure in < 30s
```

**Tools:**
- **Patroni** — uses etcd or Consul as distributed consensus; promotes replica automatically
- **repmgr** — PostgreSQL replication manager with failover scripts
- **AWS RDS Multi-AZ** / **Azure Database for PostgreSQL Flexible Server** — managed failover

---

### 3. Backups (Point-in-Time Recovery)

Replication protects against hardware failure. Backups protect against
**logical corruption** — accidental `DROP TABLE`, a bad migration, ransomware.
They serve entirely different purposes.

```
Timeline
────────────────────────────────────────────────────────────►
T=0        T=6h         T=12h      T=18h    T=23h    T=now
│          │            │          │         │         │
└─base─────┘            │          └──oops───┘         │
  backup                │           DROP TABLE          │
  (pg_basebackup)       └──WAL archive continuously─────┘
                              │
                    Restore to T=17h:59 (1 min before the mistake)
                    using base backup + WAL replay
```

**Tools:**
- `pg_basebackup` — full base backup
- `pgBackRest` — enterprise-grade backup with WAL archiving, incremental backups, compression
- `Barman` — backup and recovery manager for PostgreSQL
- **Azure Database for PostgreSQL** — built-in PITR up to 35 days, no tooling required

```bash
# pgBackRest: take a full backup
pgbackrest --stanza=main backup --type=full

# Restore to a specific point in time
pgbackrest --stanza=main restore \
  --recovery-option="recovery_target_time=2024-06-15 14:30:00"
```

---

### 4. Enterprise Storage Backend

For banking, the Docker volume driver matters as much as the volume declaration.
Local disk is not acceptable for production financial data.

| Environment | Volume Backend | Why |
|---|---|---|
| AWS | EBS `gp3` / `io2` | Block storage, per-volume IOPS control, snapshots |
| Azure | Azure Managed Disk (Premium SSD) | 99.9% SLA, built-in encryption, Azure Backup integration |
| On-premise | SAN (NetApp, Pure Storage) | Hardware-level RAID, fibre channel, enterprise support |
| Kubernetes | CSI driver (Azure Disk, AWS EBS) | Dynamic provisioning, StorageClass, PVC lifecycle management |

```yaml
# Kubernetes PVC backed by Azure Premium SSD
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-primary-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: managed-premium    # Azure Disk CSI
  resources:
    requests:
      storage: 500Gi
```

---

### 5. Encryption

A Docker volume stores data in plaintext on the host disk unless the underlying storage
is encrypted. For banking and financial data this is non-negotiable.

**Layers of encryption:**

```
Application (in-memory)
      │
      ▼
PostgreSQL process
      │   pgcrypto (column-level encryption for PCI-DSS fields)
      ▼
Docker Volume mount path (/var/lib/postgresql/data)
      │
      ▼
Host disk
      │   dm-crypt / LUKS (Linux full-disk encryption)
      ▼
Cloud block storage
      │   Azure Disk Encryption / EBS encryption (AES-256, managed keys)
      ▼
Physical media
      │   Hardware encryption (self-encrypting drives)
```

For regulatory compliance (PCI-DSS, HIPAA, GDPR):
- **Encryption at rest** — storage-layer or OS-layer encryption
- **Column-level encryption** — `pgcrypto` for fields like card numbers, SSNs
- **Encryption in transit** — TLS between app and PostgreSQL (`sslmode=require`)
- **Key management** — Azure Key Vault, AWS KMS — keys must be separate from the data

---

### 6. Monitoring

A Docker volume filling up silently crashes the database. An undetected replication lag
means the replica is behind and failover would cause data loss.

**Critical metrics for a banking DB cluster:**

| Metric | Alert Threshold | Tool |
|---|---|---|
| Disk usage (volume) | > 80% | Prometheus `node_exporter` |
| Replication lag | > 30 seconds | `pg_stat_replication` + Prometheus |
| Connection count | > 80% of `max_connections` | `pg_stat_activity` |
| Transaction rate | Sudden drop > 50% | Prometheus + Grafana |
| Backup job status | Any failure | pgBackRest + Alertmanager |
| WAL archive lag | > 5 minutes | pgBackRest monitoring |

```yaml
# Prometheus alert: replication lag critical
- alert: PostgresReplicationLagCritical
  expr: pg_replication_lag_seconds > 30
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "Replica is {{ $value }}s behind primary — failover risk"
```

---

### 7. Disaster Recovery

Disaster recovery goes beyond backups — it defines how quickly you can restore service
after a catastrophic event (entire region outage, ransomware, human error at scale).

**Key metrics:**
- **RTO (Recovery Time Objective)** — maximum acceptable downtime (e.g., 1 hour)
- **RPO (Recovery Point Objective)** — maximum acceptable data loss (e.g., 5 minutes)

```
RPO = 5 min means: backups/WAL archives must be at most 5 minutes old at any point
RTO = 1 hour means: you must be able to restore and serve traffic within 60 minutes

Docker volume alone:
  RPO = time since last manual backup (potentially hours or days)
  RTO = however long it takes you to notice + manually restore
  → Not acceptable for banking

With pgBackRest WAL archiving + cross-region replica:
  RPO = seconds (continuous WAL streaming)
  RTO = < 5 minutes (Patroni automatic promotion)
  → Acceptable for banking SLAs
```

**DR runbook components:**
1. Automated WAL shipping to a geographically separate region
2. Hot standby in the DR region (replica already running, just not receiving writes)
3. Automated health checks that trigger promotion without human intervention
4. Tested restore procedures — DR that has never been tested is not DR

---

## The Full Enterprise Stack

```
┌─────────────────────────────────────────────────────────────────┐
│                     Banking Application                         │
└─────────────────────────────┬───────────────────────────────────┘
                              │ TLS (sslmode=require)
                              ▼
                    ┌──────────────────┐
                    │  pgpool / HAProxy │  ← connection pooling + routing
                    └────────┬─────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
     ┌────────────────┐           ┌────────────────┐
     │  PostgreSQL     │           │  PostgreSQL     │
     │  Primary        │◄─Patroni─►│  Replica        │
     │  (AZ East)      │  etcd     │  (AZ West)      │
     └───────┬─────────┘           └───────┬─────────┘
             │                             │
        pg_primary_data              pg_replica_data
        [Azure Premium SSD]          [Azure Premium SSD]
        [Encrypted + Snapshots]      [Encrypted + Snapshots]
             │                             │
             └──────────┬──────────────────┘
                        │  WAL archiving (continuous)
                        ▼
              ┌──────────────────┐
              │  Azure Blob /    │
              │  pgBackRest      │  ← base backups + WAL archive
              │  (PITR 35 days)  │
              └──────────────────┘
                        │
                        ▼
              ┌──────────────────┐
              │  DR Region       │
              │  Hot Standby     │  ← cross-region replica
              │  Replica (AZ)    │
              └──────────────────┘
```

---

## Summary: What Each Layer Solves

| Layer | What It Protects Against | Without It |
|---|---|---|
| **Docker Volume** | Container restart / replacement | Data wiped on every `docker rm` |
| **Replication** | Single node hardware failure | No failover target |
| **Automatic Failover** | Manual intervention delay | Minutes/hours of downtime |
| **Backups (PITR)** | Logical corruption, accidental delete | Unrecoverable data loss |
| **Enterprise Storage** | Disk failure, IOPS limits | I/O bottleneck, no SLA |
| **Encryption** | Regulatory non-compliance, data theft | PCI-DSS / HIPAA violation |
| **Monitoring** | Silent failures (full disk, lag) | Outage discovered by customers |
| **Disaster Recovery** | Regional outage, ransomware | Permanent data loss |

---

## Key Takeaway

> A Docker volume is the foundation — it solves the most basic problem:
> data survives the container lifecycle.
>
> For production financial systems, it is **one layer of eight**.
> The remaining seven layers — replication, failover, backups, enterprise storage,
> encryption, monitoring, and disaster recovery — each protect against a failure
> mode that the volume alone cannot address.
>
> A banking database that runs in Docker is entirely viable.
> The difference is not whether you use Docker volumes —
> it is whether you build all the layers on top of them.
