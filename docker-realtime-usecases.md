# Docker Real-World Use Cases

A practical guide to how Docker is used in real-world software development and operations.

---

## 1. Microservices Architecture

**Scenario:** An e-commerce platform splits its monolith into independent services (auth, cart, payments, notifications).

**How Docker helps:**
- Each microservice runs in its own container with its own dependencies.
- Services can be scaled independently based on load.
- Teams deploy their service without affecting others.

```yaml
# docker-compose.yml
version: "3.9"
services:
  auth-service:
    build: ./auth
    ports:
      - "3001:3001"
  cart-service:
    build: ./cart
    ports:
      - "3002:3002"
  payment-service:
    build: ./payment
    ports:
      - "3003:3003"
```

---

## 2. CI/CD Pipeline Integration

**Scenario:** A dev team wants consistent builds across local machines and CI servers (GitHub Actions, Jenkins).

**How Docker helps:**
- Build and test inside a Docker container — same environment everywhere.
- No "works on my machine" issues.
- Docker images are pushed to a registry and deployed directly.

```yaml
# GitHub Actions example
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build Docker image
        run: docker build -t myapp:${{ github.sha }} .
      - name: Run tests
        run: docker run myapp:${{ github.sha }} npm test
      - name: Push to registry
        run: docker push myregistry/myapp:${{ github.sha }}
```

---

## 3. Local Development Environment

**Scenario:** A new developer joins a Node.js + PostgreSQL + Redis project and needs to get running fast.

**How Docker helps:**
- One `docker-compose up` spins up the entire stack locally.
- No need to install Postgres or Redis natively.
- Consistent DB versions across all developer machines.

```yaml
# docker-compose.yml
version: "3.9"
services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgres://user:pass@db:5432/mydb
      - REDIS_URL=redis://cache:6379
    depends_on:
      - db
      - cache
  db:
    image: postgres:15
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: mydb
  cache:
    image: redis:7
```

---

## 4. Running Legacy Applications

**Scenario:** A company has a 10-year-old app that requires Python 2.7 and an old version of OpenSSL.

**How Docker helps:**
- Package the legacy app with its exact runtime dependencies in a container.
- Run it alongside modern apps without polluting the host system.
- No need to maintain a dedicated legacy server.

```dockerfile
FROM python:2.7-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .
CMD ["python", "app.py"]
```

---

## 5. Database Isolation for Testing

**Scenario:** Integration tests need a real database but must not touch the production or shared dev database.

**How Docker helps:**
- Spin up a fresh database container before tests, tear it down after.
- Each test run gets a clean, isolated database state.
- Works in CI with zero manual setup.

```bash
# Start a temporary test database
docker run -d --name test-db \
  -e POSTGRES_PASSWORD=secret \
  -p 5433:5432 \
  postgres:15

# Run tests against it
DATABASE_URL=postgres://postgres:secret@localhost:5433/postgres npm test

# Clean up
docker stop test-db && docker rm test-db
```

---

## 6. Blue-Green / Zero-Downtime Deployments

**Scenario:** A SaaS product needs to deploy new versions without downtime.

**How Docker helps:**
- Run the new container (green) alongside the old one (blue).
- Switch the load balancer to the new container once it's healthy.
- Instantly roll back by pointing traffic back to the blue container.

```bash
# Deploy new version (green)
docker run -d --name app-green -p 3001:3000 myapp:v2

# Health check passes → switch traffic via nginx/load balancer

# Remove old version (blue)
docker stop app-blue && docker rm app-blue
```

---

## 7. Multi-Tenant SaaS Isolation

**Scenario:** A SaaS platform serves hundreds of clients, each needing an isolated runtime environment.

**How Docker helps:**
- Spin up a dedicated container per tenant on demand.
- Resource limits (CPU/memory) enforced per container.
- One tenant's crash or overload doesn't affect others.

```bash
docker run -d \
  --name tenant-abc \
  --memory="512m" \
  --cpus="0.5" \
  -e TENANT_ID=abc \
  myapp:latest
```

---

## 8. Machine Learning Model Serving

**Scenario:** A data science team trains a model in Python and wants to deploy it as an API.

**How Docker helps:**
- Package the model, dependencies (TensorFlow, PyTorch, etc.), and API server into one image.
- Reproducible — the same image runs in dev, staging, and production.
- Easy to version models by tagging Docker images.

```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY model/ ./model/
COPY serve.py .

EXPOSE 8080
CMD ["python", "serve.py"]
```

---

## 9. Scheduled Jobs & Batch Processing

**Scenario:** A finance team runs nightly data export scripts that depend on specific library versions.

**How Docker helps:**
- Run the job as a Docker container via cron or a job scheduler (Kubernetes CronJob).
- Container exits when the job completes — no persistent process overhead.
- Easy to test the exact job container locally before scheduling it.

```bash
# Run as a one-off job
docker run --rm \
  -e DB_URL=postgres://... \
  -v /data/exports:/output \
  finance-export:latest
```

---

## 10. Edge & IoT Deployments

**Scenario:** A smart manufacturing company deploys analytics software to hundreds of factory floor devices.

**How Docker helps:**
- Package the app once; deploy the same container image to all edge devices.
- Remote updates via image pull — no SSH scripting across hundreds of machines.
- Works on ARM-based edge hardware with multi-arch Docker images.

```bash
# Build for ARM (Raspberry Pi / edge device)
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  -t myregistry/edge-analytics:latest \
  --push .
```

---

## 11. Persistent Storage — What Lives in Docker Volumes

**Scenario:** A production SaaS stack needs its data to survive container restarts,
image upgrades, and node replacements. The question is: what exactly goes into a volume?

**How Docker volumes help:**
- Decouple data lifetime from container lifetime — the container is disposable, the volume is not.
- Bypass the overlay2 copy-on-write filesystem for native host I/O performance.
- Provide a named, locatable place on the host for backups, migration, and sharing between containers.

### 11.1 DB Data Files (The Database Itself)

The most critical use. Without a volume, every `docker rm` or image upgrade wipes the entire database.

```yaml
services:
  postgres:
    image: postgres:16
    volumes:
      - pg_data:/var/lib/postgresql/data   # tables, indexes, WAL logs

  mysql:
    image: mysql:8
    volumes:
      - mysql_data:/var/lib/mysql          # InnoDB data files, redo logs

  mongo:
    image: mongo:7
    volumes:
      - mongo_data:/data/db               # BSON documents, oplog

volumes:
  pg_data:
  mysql_data:
  mongo_data:
```

---

### 11.2 Redis Persistence (RDB / AOF)

Redis keeps data in RAM. RDB snapshots and AOF logs are how it writes that data to disk.
Without a volume those files are inside the container layer — destroyed on container removal.

```yaml
services:
  redis:
    image: redis:7-alpine
    command: redis-server --save 60 1 --appendonly yes
    volumes:
      - redis_data:/data     # dump.rdb + appendonly.aof survive container replacement

volumes:
  redis_data:
```

> **Note:** The volume alone is not enough. Without `--appendonly yes` or `--save`,
> Redis holds everything in RAM and writes nothing to disk at all.

---

### 11.3 TLS Certificates

Let's Encrypt certificates (managed by Certbot or Traefik) and internal CA certificates
must survive container restarts. Without a volume, HTTPS breaks on every restart.

```yaml
services:
  nginx:
    image: nginx:alpine
    volumes:
      - certs:/etc/letsencrypt          # certificate + private key
      - certs_www:/var/www/certbot      # ACME challenge files

  certbot:
    image: certbot/certbot
    volumes:
      - certs:/etc/letsencrypt          # writes renewed certs here
      - certs_www:/var/www/certbot

volumes:
  certs:
  certs_www:
```

---

### 11.4 Application Logs

Logs written by the app to disk must survive container crashes — that is exactly when
you need them most for incident debugging. A shared volume lets a log shipper read them
independently of the app container.

```yaml
services:
  app:
    image: myapp:latest
    volumes:
      - app_logs:/var/log/myapp         # logs survive crashes

  log_shipper:
    image: grafana/promtail:latest
    volumes:
      - app_logs:/var/log/myapp:ro      # ships to Loki; read-only mount

volumes:
  app_logs:
```

---

### 11.5 File Uploads (Staging)

Files uploaded by users need to survive long enough for processing (virus scan, resizing,
format conversion) before being pushed to permanent object storage (S3, Azure Blob).

```yaml
services:
  api:
    image: myapi:latest
    volumes:
      - uploads:/app/uploads            # receives and stores uploaded files

  processor:
    image: file-processor:latest
    volumes:
      - uploads:/app/uploads:ro         # reads, scans, then pushes to blob storage

volumes:
  uploads:
```

---

### 11.6 Message Queue Messages

Kafka and RabbitMQ store unacknowledged messages on disk. Without a volume,
in-flight messages between services are destroyed when the broker container restarts.

```yaml
services:
  rabbitmq:
    image: rabbitmq:3-management
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq  # queue definitions + unacknowledged messages

  kafka:
    image: confluentinc/cp-kafka:latest
    volumes:
      - kafka_data:/var/lib/kafka/data   # topic partitions + consumer offsets

volumes:
  rabbitmq_data:
  kafka_data:
```

---

### 11.7 Search Indexes

Elasticsearch, OpenSearch, and Meilisearch build large on-disk indexes. Rebuilding them
from scratch against a production dataset can take hours — they must never be lost.

```yaml
services:
  elasticsearch:
    image: elasticsearch:8.13.0
    volumes:
      - es_data:/usr/share/elasticsearch/data   # inverted indexes, shards, segments

  meilisearch:
    image: getmeili/meilisearch:latest
    volumes:
      - meili_data:/meili_data                  # full search index

volumes:
  es_data:
  meili_data:
```

---

### 11.8 Metrics / Time-Series Data

Prometheus scrapes and stores time-series blocks on disk with a default 15-day retention.
Grafana stores dashboard definitions and datasource config. Both are lost without volumes.

```yaml
services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - prometheus_data:/prometheus      # time-series metric blocks (15-day retention)

  grafana:
    image: grafana/grafana:latest
    volumes:
      - grafana_data:/var/lib/grafana    # dashboards, datasources, user settings

volumes:
  prometheus_data:
  grafana_data:
```

---

### 11.9 Build / Package Caches

CI/CD pipeline containers re-download npm packages, Maven JARs, or pip wheels on every
run if nothing is cached. Mounting a cache volume reduces build time from minutes to seconds.

```yaml
services:
  builder:
    image: node:20
    volumes:
      - npm_cache:/root/.npm             # npm package cache survives between builds
      - maven_cache:/root/.m2            # Maven local repository

volumes:
  npm_cache:
  maven_cache:
```

---

### 11.10 Runtime Secrets (Files)

API keys, service account JSON files, and TLS private keys should never be baked into
a Docker image. They are mounted as read-only volumes at runtime from the host or a
secrets manager (Docker Swarm Secrets, Kubernetes Secrets, Azure Key Vault CSI).

```yaml
services:
  app:
    image: myapp:latest
    volumes:
      - /run/secrets/db_password:/run/secrets/db_password:ro   # read-only secret file
      - /run/secrets/api_key:/run/secrets/api_key:ro
```

In Kubernetes the same pattern applies — Secrets are projected as volume mounts:

```yaml
volumes:
  - name: app-secrets
    secret:
      secretName: my-app-secrets
```

---

### Production Volume Map

```
Production Docker Stack
│
├── pg_data             → PostgreSQL tables, indexes, WAL logs
├── mysql_data          → MySQL InnoDB data files
├── mongo_data          → MongoDB documents, oplog
├── redis_data          → Redis RDB snapshots + AOF log
├── es_data             → Elasticsearch indexes + shards
├── kafka_data          → Kafka topic partitions + consumer offsets
├── rabbitmq_data       → RabbitMQ queues + unacked messages
├── certs               → TLS certificates + private keys
├── app_logs            → Application log files
├── uploads             → User upload staging area
├── prometheus_data     → Metrics time-series (15-day retention)
├── grafana_data        → Dashboards + datasource config
├── npm_cache           → npm package cache (CI/CD)
└── maven_cache         → Maven local repository (CI/CD)
```

### The Rule

> If a process writes important data to disk and that data must survive
> a container restart or replacement — it needs a Docker volume.

---

## Summary Table

| Use Case                        | Key Benefit                          |
|---------------------------------|--------------------------------------|
| Microservices                   | Isolated, independently scalable     |
| CI/CD Pipelines                 | Consistent build environments        |
| Local Dev Environment           | One-command setup for the full stack |
| Legacy App Support              | Run old runtimes without host impact |
| DB Isolation for Testing        | Clean state per test run             |
| Blue-Green Deployments          | Zero-downtime releases               |
| Multi-Tenant SaaS               | Resource-isolated per-tenant runtime |
| ML Model Serving                | Reproducible, versionable inference  |
| Scheduled / Batch Jobs          | Ephemeral, dependency-safe execution |
| Edge / IoT Deployments          | Uniform deployment across devices    |
| **Persistent Storage (Volumes)**| Data survives container lifecycle    |

---

> **Tip:** Combine Docker with **Kubernetes** for orchestrating large fleets of containers, auto-scaling, and self-healing deployments in production.
