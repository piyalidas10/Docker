# Docker Ecosystem and Tools

A structured reference to the tools, platforms, and projects that extend Docker
across the full software development and operations lifecycle.

---

## Ecosystem Map

```
                          DOCKER ECOSYSTEM
                                │
     ┌──────────────────────────┼──────────────────────────┐
     │                          │                          │
  Build                       Run                       Operate
     │                          │                          │
  ┌──┴──┐                   ┌───┴───┐                  ┌───┴───┐
  Image  CI/CD          Orchestrate  Network        Monitor  Security
 Building Pipelines      & Schedule  & Storage      & Log    & Scan
```

---

## 1. Container Orchestration

Orchestrators manage the scheduling, scaling, networking, and health of containers
across clusters of machines.

| Tool | Type | Best For |
|---|---|---|
| **Kubernetes** | Open source | Industry standard; complex, large-scale deployments |
| **Docker Swarm** | Built into Docker | Simple clustering; smaller teams already using Docker Compose |
| **Nomad** | HashiCorp | Mixed workloads — containers + VMs + bare-metal jobs together |

### Kubernetes
The de facto standard for container orchestration. Manages pods, services, deployments,
storage, secrets, and auto-scaling across multi-node clusters.

```yaml
# Kubernetes Deployment — 3 replicas, rolling update
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: myapp
  template:
    spec:
      containers:
        - name: myapp
          image: myapp:v2.0.0
          resources:
            limits:
              memory: "512Mi"
              cpu: "500m"
```

### Docker Swarm
Docker's native clustering solution. Uses the same Compose file format — lower
learning curve for teams already comfortable with Docker Compose.

```bash
# Initialise a swarm
docker swarm init

# Deploy a stack to the swarm
docker stack deploy -c docker-compose.yml myapp

# Scale a service
docker service scale myapp_web=5
```

### Nomad
HashiCorp's workload orchestrator. Supports Docker containers, raw executables,
Java JARs, and VMs — useful when you have non-containerised workloads to schedule
alongside containers.

---

## 2. Container Registries

Registries store and distribute Docker images. Choosing the right one depends on
your cloud provider, access control requirements, and cost model.

| Registry | Provider | Type | Key Feature |
|---|---|---|---|
| **Docker Hub** | Docker | Public/Private | Largest public image library |
| **Amazon ECR** | AWS | Private | IAM-based auth; integrates with ECS/EKS |
| **Google Artifact Registry** | GCP | Private | Replaced GCR; multi-format (Docker, Maven, npm) |
| **Azure Container Registry (ACR)** | Azure | Private | Integrates with AKS, Azure DevOps, Defender |
| **GitHub Container Registry (GHCR)** | GitHub | Public/Private | Tied to GitHub repos and Actions |
| **Harbor** | Open source | Self-hosted | RBAC, image scanning, replication, air-gapped |

```bash
# Pull from Docker Hub
docker pull nginx:alpine

# Push to ACR
az acr login --name myregistry
docker tag myapp:latest myregistry.azurecr.io/myapp:v1.0.0
docker push myregistry.azurecr.io/myapp:v1.0.0

# Push to ECR
aws ecr get-login-password | docker login --username AWS \
  --password-stdin 123456789.dkr.ecr.us-east-1.amazonaws.com
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/myapp:v1.0.0
```

---

## 3. CI/CD Integration

CI/CD tools build, test, scan, and deploy Docker images automatically on every code change.

| Tool | Type | Docker Support |
|---|---|---|
| **GitHub Actions** | Cloud | Native Docker build/push actions |
| **GitLab CI/CD** | Cloud / Self-hosted | Docker-in-Docker; Kaniko support |
| **Jenkins** | Self-hosted | Docker Pipeline plugin; agent containers |
| **CircleCI** | Cloud | Machine executor with Docker pre-installed |
| **Travis CI** | Cloud | Docker service in build environment |

### GitHub Actions — Full Build, Scan, Push Pipeline

```yaml
name: Build and Push

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build image
        run: docker build -t myapp:${{ github.sha }} .

      - name: Scan for vulnerabilities
        run: |
          curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh
          ./bin/trivy image --exit-code 1 --severity CRITICAL myapp:${{ github.sha }}

      - name: Login to ACR
        uses: azure/docker-login@v1
        with:
          login-server: myregistry.azurecr.io
          username: ${{ secrets.ACR_USERNAME }}
          password: ${{ secrets.ACR_PASSWORD }}

      - name: Push image
        run: |
          docker tag myapp:${{ github.sha }} myregistry.azurecr.io/myapp:${{ github.sha }}
          docker push myregistry.azurecr.io/myapp:${{ github.sha }}
```

---

## 4. Monitoring and Logging

| Tool | Category | What It Does |
|---|---|---|
| **Prometheus** | Metrics | Scrapes and stores time-series metrics; alert rules |
| **Grafana** | Visualisation | Dashboards for Prometheus, Loki, and other data sources |
| **cAdvisor** | Container metrics | Per-container CPU, memory, network, and disk usage |
| **ELK Stack** | Log analytics | Elasticsearch (store) + Logstash (ingest) + Kibana (visualise) |
| **Grafana Loki** | Log aggregation | Log aggregation designed for Kubernetes/Docker; pairs with Promtail |
| **Fluentd / Fluent Bit** | Log collection | Unified log collector; ships to ELK, Loki, Datadog, Splunk |

### Prometheus + cAdvisor + Grafana Stack

```yaml
services:
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
    ports:
      - "8080:8080"

  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - "3000:3000"

volumes:
  prometheus_data:
  grafana_data:
```

### Loki + Promtail (lightweight log aggregation)

```yaml
services:
  app:
    image: myapp:latest
    volumes:
      - app_logs:/var/log/myapp

  promtail:
    image: grafana/promtail:latest
    volumes:
      - app_logs:/var/log/myapp:ro
      - ./promtail-config.yml:/etc/promtail/config.yml
    command: -config.file=/etc/promtail/config.yml

volumes:
  app_logs:
```

---

## 5. Security Tools

| Tool | What It Does |
|---|---|
| **Trivy** | Scans images, filesystems, and repos for CVEs and misconfigs |
| **Docker Scout** | Built-in Docker Hub vulnerability and policy analysis |
| **Anchore Engine** | Deep image inspection with user-defined acceptance policies |
| **Clair** | Static analysis of CVEs in container image layers |
| **Falco** | Runtime security — detects anomalous behaviour in running containers |
| **Snyk Container** | Dev-friendly scanning integrated into IDE and CI |

```bash
# Trivy — scan image
trivy image --severity HIGH,CRITICAL myapp:latest

# Trivy — scan a running container's filesystem
trivy fs /

# Falco — detect suspicious runtime behaviour (runs as a privileged container)
docker run --rm -it --privileged \
  -v /var/run/docker.sock:/host/var/run/docker.sock \
  -v /dev:/host/dev \
  -v /proc:/host/proc:ro \
  falcosecurity/falco

# Example Falco rule: alert when a shell is spawned inside a container
# rule: Terminal shell in container
# condition: spawned_process and container and shell_procs and proc.tty != 0
# output: "Shell spawned in a container (user=%user.name container=%container.name)"
# priority: WARNING
```

---

## 6. Development Tools

| Tool | What It Does |
|---|---|
| **Docker Compose** | Define and run multi-container apps with a single YAML file |
| **Docker Desktop** | GUI for Mac/Windows — includes Docker Engine, Compose, K8s |
| **Portainer** | Web UI for managing containers, stacks, volumes, and registries |
| **Dive** | Explore image layers; find wasted space and unnecessary files |
| **VS Code Docker Extension** | IntelliSense for Dockerfiles and Compose; container management in editor |
| **Lazydocker** | Terminal UI for managing containers, images, and volumes |

```bash
# Dive — analyse image layer efficiency
dive myapp:latest

# Output shows:
# Layer 1: 120MB  (base image)
# Layer 2:   5MB  (npm install)
# Layer 3:  45MB  (copied node_modules — could be multi-stage instead)
# Wasted space: 45MB — fixable with multi-stage build

# Portainer — spin up management UI
docker run -d -p 9000:9000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

---

## 7. Networking

| Tool | What It Does |
|---|---|
| **Weave Net** | Virtual network connecting Docker containers across multiple hosts |
| **Calico** | Network policy enforcement; BGP-based routing for Kubernetes |
| **Cilium** | eBPF-powered networking, security, and observability for containers |
| **Flannel** | Simple overlay network for Kubernetes pods |

```yaml
# Calico network policy — deny all ingress except from the api service
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-only
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api        # only the api pod can reach the database
```

---

## 8. Storage

| Tool | What It Does |
|---|---|
| **Longhorn** | Cloud-native distributed block storage for Kubernetes; snapshots, backups |
| **Portworx** | Enterprise Kubernetes storage; multi-cloud, encryption, DR |
| **Rexray** | Docker volume plugin for cloud storage backends (EBS, Azure Disk, GCS) |
| **OpenEBS** | Open source storage for Kubernetes; multiple storage engines |

```yaml
# Longhorn StorageClass in Kubernetes
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "3"      # replicate across 3 nodes
  staleReplicaTimeout: "2880"
  fromBackup: ""
```

---

## 9. Service Discovery

| Tool | What It Does |
|---|---|
| **Consul** | Service mesh — service discovery, health checks, KV store, mTLS |
| **etcd** | Distributed key-value store; used internally by Kubernetes |
| **ZooKeeper** | Distributed coordination; used by Kafka for leader election |

```yaml
# Consul agent in Docker
services:
  consul:
    image: hashicorp/consul:latest
    command: agent -dev -client=0.0.0.0
    ports:
      - "8500:8500"    # web UI
      - "8600:8600/udp" # DNS

  app:
    image: myapp:latest
    environment:
      CONSUL_HTTP_ADDR: consul:8500
```

---

## 10. Container Management Platforms

| Platform | What It Is |
|---|---|
| **Rancher** | Open source; manages multiple Kubernetes clusters from one UI |
| **OpenShift** | Red Hat enterprise Kubernetes; adds CI/CD, image builds, developer portal |
| **Docker Enterprise** | Commercial Docker platform with enterprise support and governance |
| **Lens** | Desktop IDE for Kubernetes cluster management |

---

## 11. Serverless Containers

| Tool | What It Does |
|---|---|
| **OpenFaaS** | Runs functions as containers on Docker Swarm or Kubernetes |
| **Knative** | Kubernetes-based serverless — scale to zero, event-driven |
| **AWS Fargate** | Run containers without managing EC2 nodes |
| **Azure Container Apps** | Serverless containers with built-in KEDA scaling on Azure |

```yaml
# Knative Service — scales to zero when idle
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: myfunction
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "0"   # scale to zero
        autoscaling.knative.dev/maxScale: "100"
    spec:
      containers:
        - image: myregistry/myfunction:latest
```

---

## 12. Image Building Tools

| Tool | What It Does | When to Use |
|---|---|---|
| **BuildKit** | Docker's next-gen build backend; parallel builds, caching, secrets | Default in Docker 23+; always use |
| **Kaniko** | Builds images inside Kubernetes without the Docker daemon | CI/CD in K8s clusters |
| **Buildah** | Builds OCI images without root or daemon | Rootless / daemonless CI |
| **ko** | Builds minimal Go container images directly from source | Go microservices |

```dockerfile
# BuildKit: mount a secret during build (never stored in image layer)
# syntax=docker/dockerfile:1
FROM node:20-alpine
RUN --mount=type=secret,id=npm_token \
    NPM_TOKEN=$(cat /run/secrets/npm_token) npm install

# BuildKit: cache mount — speeds up repeated builds
RUN --mount=type=cache,target=/root/.npm \
    npm ci --prefer-offline
```

```bash
# Kaniko — build inside Kubernetes pod, push to registry
kubectl run kaniko --image=gcr.io/kaniko-project/executor:latest \
  --restart=Never \
  -- --dockerfile=Dockerfile \
     --context=git://github.com/myorg/myapp \
     --destination=myregistry.azurecr.io/myapp:latest
```

---

## 13. Testing Tools

| Tool | What It Does |
|---|---|
| **Container Structure Test** | Validates image structure — file existence, commands, metadata |
| **Testcontainers** | Spins up real containers in unit/integration tests (Java, Go, Python, JS) |
| **Goss** | Fast, YAML-based server/container validation |

```yaml
# Container Structure Test — validate image contents
schemaVersion: "2.0.0"
commandTests:
  - name: "node version"
    command: "node"
    args: ["--version"]
    expectedOutput: ["v20\\."]

fileExistenceTests:
  - name: "app entrypoint exists"
    path: "/app/dist/server.js"
    shouldExist: true

metadataTest:
  exposedPorts: ["3000"]
  user: "appuser"            # must not be root
```

```java
// Testcontainers — real PostgreSQL in a JUnit test (Java)
@Testcontainers
class OrderRepositoryTest {
    @Container
    static PostgreSQLContainer<?> postgres =
        new PostgreSQLContainer<>("postgres:16-alpine");

    @Test
    void shouldSaveOrder() {
        // connects to a real, isolated PostgreSQL container
        // torn down automatically after the test class
    }
}
```

---

## Quick Reference: Tool Selection Guide

| Need | Recommended Tool |
|---|---|
| Orchestrate containers at scale | Kubernetes (AKS / EKS / GKE) |
| Simple multi-container local dev | Docker Compose |
| Private image registry on Azure | Azure Container Registry |
| Scan images for CVEs | Trivy |
| Runtime threat detection | Falco |
| Distributed block storage for K8s | Longhorn |
| Build images without Docker daemon | Kaniko or Buildah |
| Log aggregation for containers | Loki + Promtail |
| Metrics and dashboards | Prometheus + Grafana + cAdvisor |
| Service discovery + health checks | Consul |
| Manage multiple K8s clusters | Rancher |
| Serverless containers on Azure | Azure Container Apps (Knative/KEDA) |
| Integration tests with real DBs | Testcontainers |
| Inspect image layer waste | Dive |

---

## Key Takeaway

> Docker itself is the foundation. The ecosystem around it handles everything else:
> orchestration, observability, security, storage, networking, and developer experience.
>
> You do not need every tool — pick the ones that fit your current scale and complexity.
> Start with Compose for local dev, add Prometheus + Grafana for observability,
> Trivy for security scanning, and Kubernetes when you need to orchestrate at scale.
> Build from there.
