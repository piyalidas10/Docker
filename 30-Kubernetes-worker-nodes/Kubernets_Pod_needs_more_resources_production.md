# What if the Frontend Pod needs more resources in production?

A DevOps engineer or developer defined the following resource requests in the Kubernetes Deployment manifest:

| Pod | CPU requested | RAM requested |
|---|---|---|
| Frontend Pod | 0.5 core | 512 MiB |
| Banking API Pod | 2 cores | 2 GiB |
| Authentication Pod | 1 core | 1 GiB |
| Background Worker Pod | 1 core | 2 GiB |

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: banking-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: banking-api
  template:
    metadata:
      labels:
        app: banking-api
    spec:
      containers:
        - name: banking-api
          image: banking-api:1.0
          resources:
            requests:
              cpu: "1"
              memory: "1Gi"
            limits:
              cpu: "2"
              memory: "2Gi"
```

In a production banking application, if the **Frontend Pod needs more CPU or RAM than originally requested**, Kubernetes will **not** automatically increase its resource requests. The outcome depends on whether you configure **Horizontal Pod Autoscaling (HPA), Vertical Pod Autoscaling (VPA), or neither**.

## 7.1 What happens when the Frontend Pod needs more resources?

Suppose your Kubernetes cluster has one Worker Node with **8 CPU cores** and **16 GiB RAM**. Frontend traffic increases and it now needs more CPU capacity.

```
Worker Node  (8 CPU · 16 GiB RAM)
┌──────────────────────────────────────────────────────────────┐
│  Frontend Pod          │  0.5 CPU · 512 MiB  ← needs more   │
│  Banking API Pod       │  2 CPU   · 2 GiB                    │
│  Authentication Pod    │  1 CPU   · 1 GiB                    │
│  Background Worker Pod │  1 CPU   · 2 GiB                    │
└──────────────────────────────────────────────────────────────┘

  ↓ Frontend traffic increases

Kubernetes needs an autoscaling policy or an updated resource
configuration to respond appropriately.
```

## 7.2 Who allocates more resources, and how?

There are three common scenarios.

---

### Scenario A — Developer or DevOps engineer updates the Deployment

They change the requested resources in the YAML manifest (e.g. from `500m` CPU to `1000m` CPU, and from `512Mi` to `1Gi` RAM):

```yaml
resources:
  requests:
    cpu: "1000m"    # increased from 500m
    memory: "1Gi"   # increased from 512Mi
  limits:
    cpu: "2"
    memory: "2Gi"
```

The Kubernetes Scheduler then evaluates whether the Pod can fit on a Worker Node. If it can, Kubernetes schedules the replacement Pod with the new request. If it cannot, the Pod may remain `Pending` until capacity becomes available or the cluster is expanded.

---

### Scenario B — HPA adds more Frontend Pods

The Horizontal Pod Autoscaler monitors metrics such as CPU utilisation and increases the number of replicas when its scaling rules trigger:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: frontend-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: frontend
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

For example, one Frontend Pod becomes three. Each new Pod has the configured resource request; HPA does **not** automatically increase the CPU or RAM request of an individual Pod. If the Worker Nodes lack capacity, the Cluster Autoscaler (when configured and supported by the infrastructure) can add nodes.

---

### Scenario C — VPA adjusts the resource request

The Vertical Pod Autoscaler can recommend or automatically adjust CPU and memory requests based on observed usage and its policies:

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: frontend-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: frontend
  updatePolicy:
    updateMode: "Auto"   # or "Off" (recommend only) / "Initial"
```

Depending on its configuration and update mode, applying changes may require recreating a Pod. VPA does not itself add Worker Nodes; the cluster must have enough capacity.

---

## 7.3 How do CPU and RAM behave when the Pod needs more than its request?

| Resource | If usage exceeds the request |
|---|---|
| **CPU** | The container can use additional available CPU, subject to its CPU limit and node contention. A request is not a hard usage cap. |
| **RAM** | The container can use memory beyond its request if available, subject to its memory limit and node capacity. If it exceeds its memory limit, it can be terminated with an `OOMKilled` status. |
| **Node capacity** | Kubernetes does not create extra physical CPU or RAM. A new Pod may remain `Pending` if no node can accommodate its requests. |

> **Important:** A resource *request* is primarily used for scheduling and resource-allocation decisions. A resource *limit* controls the maximum CPU or memory the container is permitted to use.

## 7.4 Example: Scaling a banking Frontend

```
Step 1 — Incoming banking traffic increases
         More users access the banking frontend
              │
              ▼
Step 2 — HPA detects increased CPU utilisation
         Configured target: 70% average CPU
              │
              ▼
Step 3 — Frontend Deployment scales out
         ┌──────────┐  ┌──────────┐  ┌──────────┐
         │  Pod 1   │  │  Pod 2   │  │  Pod 3   │
         │ 0.5 CPU  │  │ 0.5 CPU  │  │ 0.5 CPU  │
         │ 512 MiB  │  │ 512 MiB  │  │ 512 MiB  │
         └──────────┘  └──────────┘  └──────────┘
         Each Pod retains its configured resource request
              │
              ▼
Step 4 — Cluster Autoscaler (if configured)
         Adds Worker Nodes when unschedulable Pods
         require more capacity and the infrastructure permits it
```

> HPA does not guarantee that scaling will happen instantly. Metrics availability, scaling policies, image startup time, node capacity, and infrastructure limits all affect the response.

## 7.5 Who is responsible in an enterprise banking team?

| Responsibility | Typical owner |
|---|---|
| Define initial CPU/RAM requests and limits | Developer, platform engineer, or DevOps engineer |
| Configure HPA/VPA and scaling policies | Platform engineering / DevOps / SRE |
| Schedule Pods onto suitable Worker Nodes | Kubernetes Scheduler |
| Increase the number of Worker Nodes | Cluster Autoscaler plus the underlying infrastructure provider, when configured |
| Monitor production usage and tune requests | SRE, platform team, and application team |

In practice, these responsibilities vary by organization. A developer may submit the resource configuration through a Git-based deployment workflow, while the platform team owns the cluster and enforces resource policies.

> **Key takeaway:** Kubernetes can schedule Pods and respond to configured autoscaling policies, but it does **not** automatically rewrite resource requests whenever an application needs more CPU or RAM. Use **HPA** to add replicas, **VPA** to adjust per-Pod requests, and **Cluster Autoscaler** to add Worker Nodes when supported and configured.
