# Kubernetes — Deploying a Node.js Application

## Folder Structure

```
32-Kubernetes-deployment/
├── app/
│   ├── app.js            ← Node.js application
│   └── package.json      ← Node.js dependencies
├── Dockerfile            ← Container image definition
├── deployment.yaml       ← Kubernetes Deployment manifest
├── service.yaml          ← Kubernetes Service manifest
├── configmap.yaml        ← Kubernetes ConfigMap (environment config)
└── README.md             ← This file
```

---

## Architecture Diagram

```
  Developer Machine
  ─────────────────
  kubectl apply -f deployment.yaml
  kubectl apply -f service.yaml
         │
         ▼
┌────────────────────────────────────────────────────────────────┐
│                          CLUSTER                               │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    MASTER NODE                           │  │
│  │  ┌─────────────┐  ┌───────────┐  ┌──────────────────┐  │  │
│  │  │  API Server │  │ Scheduler │  │ Controller Mgr   │  │  │
│  │  └──────┬──────┘  └─────┬─────┘  └────────┬─────────┘  │  │
│  │         │               │                 │             │  │
│  └─────────┼───────────────┼─────────────────┼─────────────┘  │
│            │ schedules     │ picks node      │ reconciles      │
│            ▼               ▼                 ▼                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   WORKER NODE                            │  │
│  │                                                          │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │               SERVICE (NodePort/LB)                │  │  │
│  │  │          Stable IP · Port 80 → 3000                │  │  │
│  │  └───────────────────────┬────────────────────────────┘  │  │
│  │                          │ routes traffic                │  │
│  │          ┌───────────────┼───────────────┐               │  │
│  │          ▼               ▼               ▼               │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐     │  │
│  │  │    POD 1     │ │    POD 2     │ │    POD 3     │     │  │
│  │  │ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ │     │  │
│  │  │ │ node-app │ │ │ │ node-app │ │ │ │ node-app │ │     │  │
│  │  │ │:3000     │ │ │ │:3000     │ │ │ │:3000     │ │     │  │
│  │  │ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ │     │  │
│  │  └──────────────┘ └──────────────┘ └──────────────┘     │  │
│  │          ▲               ▲               ▲               │  │
│  │          └───────────────┴───────────────┘               │  │
│  │                   ConfigMap (env vars)                   │  │
│  │                   Docker image pulled from               │  │
│  │                   registry (Docker Hub / ECR)            │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
         ▲
         │  external traffic (browser / API client)
         │  http://<node-ip>:30080  or  LoadBalancer IP
```

---

## Why 3 Pods?

The [`deployment.yaml`](deployment.yaml) sets `replicas: 3`, meaning Kubernetes always keeps **three identical copies** of the Node.js container running simultaneously. Here is why that number matters:

### 1 — High Availability (no single point of failure)
If one Pod crashes, is evicted, or its node goes down, the other two Pods keep serving traffic without any interruption. The Deployment controller detects the lost Pod and immediately schedules a replacement, restoring the replica count back to 3.

| Replicas | One Pod dies | Result |
|---|---|---|
| 1 | ✗ | **Downtime** — app is unavailable until the replacement starts |
| 3 | ✗ | **No downtime** — 2 Pods continue serving; replacement starts in background |

### 2 — Load Distribution
The Service (NodePort / LoadBalancer) acts as a built-in load balancer. Incoming requests are round-robin'd across all healthy Pods, so no single Pod is a bottleneck. Three replicas triple the throughput capacity compared to one.

```
Request 1  →  POD 1
Request 2  →  POD 2
Request 3  →  POD 3
Request 4  →  POD 1   ← round-robin restarts
```

### 3 — Zero-Downtime Rolling Updates
When you push a new image version (`kubectl set image …`), Kubernetes performs a **rolling update**:

1. Starts a new Pod with the updated image.
2. Waits for it to become `Ready`.
3. Terminates one old Pod.
4. Repeats until all 3 Pods run the new version.

With 3 replicas the default strategy (`maxUnavailable: 1`, `maxSurge: 1`) guarantees **at least 2 Pods are always up** during the rollout — traffic never drops to zero.

### 4 — Graceful Node Maintenance
When a cluster node is drained for maintenance (`kubectl drain`), Kubernetes evicts its Pods and reschedules them on other nodes. With 3 replicas spread across nodes, at most 1 Pod is displaced at a time while the remaining 2 stay live.

### Summary

| Reason | Benefit |
|---|---|
| High Availability | Survives individual Pod or node failure without downtime |
| Load Distribution | Spreads traffic; increases throughput |
| Rolling Updates | At least 2 Pods serving during a deployment rollout |
| Node Maintenance | Pods re-scheduled without full service interruption |

> **Tip:** 3 is the recommended minimum for production workloads. You can scale up at any time with `kubectl scale deployment node-app --replicas=5`.

---

## How to Decide How Many Pods to Run

There is no single magic number. The right replica count is driven by four factors: **traffic load**, **availability target**, **resource budget**, and **whether you use auto-scaling**. Work through each factor in order.

---

### Factor 1 — Availability Target (minimum floor)

This is your starting point before you think about load at all.

| Environment | Minimum replicas | Rationale |
|---|---|---|
| Local / dev | 1 | No HA needed; cost matters |
| Staging | 2 | Catch config issues; cheap HA |
| Production | **3** | Survive 1 failure + tolerate a rolling update simultaneously |
| Business-critical | 5+ | Survive 2 simultaneous failures |

> **Rule of thumb:** Always run at least **N + 1** replicas, where N is the number of simultaneous failures you want to tolerate.
> For 1 failure tolerance → 2 replicas minimum. For 2 → 3 minimum. For 3 → 4 minimum, and so on.

---

### Factor 2 — Traffic Load (throughput ceiling)

Measure (or estimate) how many requests per second (RPS) your app must handle at peak, then divide by what a single Pod can serve.

```
                Peak RPS you must handle
replicas  =  ──────────────────────────────
               RPS a single Pod can serve
```

**Example:**
- Your load test shows one Pod handles **200 RPS** at ≤ 200 ms p99 latency.
- Your peak traffic is **900 RPS**.
- Raw replicas needed: 900 ÷ 200 = **4.5 → round up to 5**.
- Add a 20 % headroom buffer: 5 × 1.2 = **6 replicas**.

**How to measure a single Pod's capacity:**

```bash
# Run the app with 1 replica
kubectl scale deployment node-app --replicas=1

# Load-test it (install k6 or hey first)
k6 run --vus 50 --duration 30s loadtest.js
# or
hey -n 10000 -c 50 http://<node-ip>:30080/
```

Watch CPU and memory while ramping up concurrent users. The replica capacity is the RPS at which latency or error rate first degrades.

---

### Factor 3 — Node & Resource Budget

Each Pod consumes CPU and memory from a worker node. Make sure your cluster can actually schedule all the replicas you want.

```
Max replicas on a node  =  floor( node_allocatable_cpu / pod_cpu_request )
```

**Example — single node with 4 CPU cores:**

| Pod CPU request | Max Pods schedulable |
|---|---|
| 0.5 CPU (500 m) | 4 ÷ 0.5 = **8 Pods** |
| 1.0 CPU | 4 ÷ 1.0 = **4 Pods** |
| 2.0 CPU | 4 ÷ 2.0 = **2 Pods** |

Check your node's allocatable resources:
```bash
kubectl describe node <node-name> | grep -A5 "Allocatable"
```

Check what each Pod currently consumes:
```bash
kubectl top pod
```

> **Tip:** Always set `resources.requests` and `resources.limits` in [`deployment.yaml`](deployment.yaml). Without them the Scheduler cannot make placement decisions and you risk node OOM.

---

### Factor 4 — Horizontal Pod Autoscaler (HPA) — let Kubernetes decide

Instead of manually picking a fixed number, define a **minimum** and **maximum** and let the HPA scale automatically based on CPU or custom metrics.

```yaml
# hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: node-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: node-app
  minReplicas: 3        # ← never go below 3 (availability floor)
  maxReplicas: 10       # ← never exceed 10 (cost ceiling)
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60   # scale out when avg CPU > 60 %
```

```bash
kubectl apply -f hpa.yaml
kubectl get hpa          # watch it scale
```

**How HPA chooses replica count:**

```
desired replicas  =  ceil( current replicas × ( current metric / target metric ) )

Example:
  current replicas = 3,  current CPU = 90 %,  target = 60 %
  desired = ceil( 3 × 90/60 ) = ceil(4.5) = 5
```

HPA will scale up to 5 Pods, then back down once traffic subsides.

---

### Decision Checklist

Work through this before setting `replicas:` in [`deployment.yaml`](deployment.yaml):

```
[ ] 1. What is the minimum replica count for my availability SLA?
         → dev: 1  |  staging: 2  |  prod: 3+

[ ] 2. What is the peak RPS I need to handle?
         → divide by single-Pod capacity, add 20 % headroom

[ ] 3. Do my worker nodes have enough CPU/memory to schedule that many Pods?
         → kubectl describe node + kubectl top pod

[ ] 4. Should I use HPA?
         → yes for variable/unpredictable traffic
         → no for steady, predictable load where a fixed count is fine

[ ] 5. Set replicas = max( availability floor, load-based count )
```

---

### Quick Reference

| Scenario | Recommended replicas |
|---|---|
| Local development | 1 |
| CI / staging | 2 |
| Small production (< 500 RPS) | 3 |
| Medium production (500–2 000 RPS) | 5–8 |
| High-traffic production (> 2 000 RPS) | HPA: min 5, max 20+ |
| Mission-critical (zero-downtime SLA) | HPA: min 6, max 30+ across 3 AZs |

---

## Step-by-Step Deployment Process

### Step 1 — Write the Node.js Application

Create a simple HTTP server in [`app/app.js`](app/app.js) that listens on port **3000**.

See [`app/app.js`](app/app.js) and [`app/package.json`](app/package.json).

---

### Step 2 — Create a Dockerfile

The [`Dockerfile`](Dockerfile) defines how to build a container image for the Node.js app.

Key steps inside the Dockerfile:
1. Start from the official `node:18-alpine` base image.
2. Set the working directory to `/app`.
3. Copy `package.json` and run `npm install`.
4. Copy the rest of the app source code.
5. Expose port `3000`.
6. Set the start command to `node app.js`.

---

### Step 3 — Build and Push the Docker Image

```bash
# Build the image
docker build -t <your-dockerhub-username>/node-app:latest .

# Push to Docker Hub (or ECR / GCR / ACR)
docker push <your-dockerhub-username>/node-app:latest
```

> Kubernetes pulls the image from this registry when creating Pods. Update the image name in `deployment.yaml` to match.

---

### Step 4 — Apply the ConfigMap

The [`configmap.yaml`](configmap.yaml) stores environment variables separately from the container image, so config can change without rebuilding the image.

```bash
kubectl apply -f configmap.yaml
```

---

### Step 5 — Apply the Deployment

The [`deployment.yaml`](deployment.yaml) tells Kubernetes:
- Which container image to run.
- How many Pod replicas to maintain (3 in this example).
- Which environment variables (from the ConfigMap) to inject.
- Resource requests and limits for each Pod.

```bash
kubectl apply -f deployment.yaml
```

Verify the Pods are running:
```bash
kubectl get pods
```

Expected output:
```
NAME                        READY   STATUS    RESTARTS   AGE
node-app-6d7b9c8f4-abc12    1/1     Running   0          30s
node-app-6d7b9c8f4-def34    1/1     Running   0          30s
node-app-6d7b9c8f4-ghi56    1/1     Running   0          30s
```

---

### Step 6 — Apply the Service

The [`service.yaml`](service.yaml) exposes the Pods to external traffic via a stable IP and port.

```bash
kubectl apply -f service.yaml
```

Verify the Service:
```bash
kubectl get services
```

Expected output:
```
NAME           TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
node-app-svc   NodePort   10.100.200.10   <none>        80:30080/TCP   15s
```

Access the app at: `http://<node-ip>:30080`

---

### Step 7 — Verify the Full Deployment

```bash
# Check all resources
kubectl get all

# Describe a Pod for details
kubectl describe pod <pod-name>

# View logs from a Pod
kubectl logs <pod-name>

# Scale the deployment (e.g. to 5 replicas)
kubectl scale deployment node-app --replicas=5
```

---

### Step 8 — Update the Application (Rolling Update)

```bash
# Build and push a new image version
docker build -t <your-dockerhub-username>/node-app:v2 .
docker push <your-dockerhub-username>/node-app:v2

# Update the deployment image — triggers a rolling update
kubectl set image deployment/node-app node-app=<your-dockerhub-username>/node-app:v2

# Watch the rollout
kubectl rollout status deployment/node-app

# Rollback if needed
kubectl rollout undo deployment/node-app
```

---

### Step 9 — Tear Down

```bash
kubectl delete -f service.yaml
kubectl delete -f deployment.yaml
kubectl delete -f configmap.yaml
```

---

## Summary

| Step | Action | Command / File |
|---|---|---|
| 1 | Write app | `app/app.js`, `app/package.json` |
| 2 | Containerise | `Dockerfile` |
| 3 | Build & push image | `docker build` + `docker push` |
| 4 | Apply config | `kubectl apply -f configmap.yaml` |
| 5 | Deploy Pods | `kubectl apply -f deployment.yaml` |
| 6 | Expose via Service | `kubectl apply -f service.yaml` |
| 7 | Verify | `kubectl get all` |
| 8 | Update | `kubectl set image` + `kubectl rollout` |
| 9 | Tear down | `kubectl delete -f *.yaml` |
