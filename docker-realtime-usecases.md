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

---

> **Tip:** Combine Docker with **Kubernetes** for orchestrating large fleets of containers, auto-scaling, and self-healing deployments in production.
