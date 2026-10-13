# Kubernetes Worker Nodes: How Pods Share CPU and RAM

**Question:** Do Pods share the same resources (CPU, RAM) of a Worker Node? Are the resources shared in equal percentages?

**Answer:** Yes, all Pods running on the same Worker Node use that node's available CPU and RAM, but Kubernetes does **not** divide those resources into equal percentages by default.

The examples below use a banking enterprise application.

## 1. How Worker Node resources are shared

Suppose a Worker Node has **8 CPU cores** and **16 GB RAM**.

> Resources available to the node's workloads are less than or equal to total capacity, after accounting for system reservations and other overhead.

| Pod | CPU requested | RAM requested |
|---|---|---|
| Frontend Pod | 0.5 core | 512 MiB |
| Banking API Pod | 2 cores | 2 GiB |
| Authentication Pod | 1 core | 1 GiB |
| Background Worker Pod | 1 core | 2 GiB |

*Illustrative resource requests, not equal shares or production sizing recommendations. Other Pods and system processes may also use the node.*

Each Pod requests a different amount of CPU and RAM. Kubernetes does not automatically give every Pod 25% of the node's resources.

## 2. How Kubernetes manages CPU and RAM

| Resource concept | CPU | RAM |
|---|---|---|
| **Requests** | Amount used for scheduling and CPU allocation decisions | Amount used for scheduling and memory reservation decisions |
| **Limits** | Maximum CPU usage enforced through throttling | Maximum memory usage; exceeding it can cause the container to be terminated with an OOM kill |
| **Default sharing** | CPU time can be shared dynamically when workloads need it | Memory is consumed as applications use it; it is not divided into equal fixed portions |

> **Important:** A CPU request is not necessarily a hard maximum. A container can often use more CPU than its request if the node has spare CPU capacity and its CPU limit allows it.
>
> Memory behaves differently: Kubernetes does not automatically distribute the node's RAM equally among Pods.

## 3. What happens when the Banking API needs more CPU?

Imagine the Banking API suddenly receives a large volume of banking transactions.

- If spare CPU capacity exists, the API can use more CPU, subject to its configured limit.
- If a CPU limit is set, the container can be throttled when it reaches that limit.
- If memory usage exceeds its limit, the container may be killed.
- If the node becomes too full, Kubernetes may be unable to schedule additional Pods there and may need to place them on another Worker Node.

## 4. Can we allocate resources equally?

Yes, you can configure equal requests and limits, but equal resource allocation is a **configuration choice**, not Kubernetes' default behavior.

For example, with four Pods on a node with 8 CPU cores and 16 GB RAM, a simplistic equal split would be **2 CPU cores and 4 GB RAM per Pod**. In production, however, you must account for system resources, other workloads, application needs, and Kubernetes scheduling constraints.

## 5. Who requests Pod resource allocation?

**Question:** Who requests CPU and RAM for Pods? The DevOps engineer? The architect?

**Answer:** In an enterprise environment, the application development team, DevOps/platform engineers, and architects collaborate to decide how much CPU and RAM each Pod needs. Kubernetes then uses the configured resource requests to schedule Pods onto suitable Worker Nodes.

### 5.1 Who is responsible for resource allocation?

| Role | Responsibility |
|---|---|
| **Software Developer** | Understands application resource needs, performs profiling, and identifies CPU and memory usage. |
| **Solution Architect** | Defines the architecture, capacity requirements, availability, scalability, and performance targets. |
| **DevOps / Platform Engineer** | Configures CPU and memory requests and limits in Kubernetes manifests, Helm charts, or deployment pipelines. |
| **SRE / Performance Engineer** | Monitors production metrics, conducts load tests, and recommends resource adjustments. |
| **Kubernetes Scheduler** | Automatically selects a suitable Worker Node based on resource requests, available capacity, and scheduling constraints. |

The exact division of responsibilities varies by organization. In many companies, the platform team provides standard configurations, while application teams tune them within approved policies.

### 5.2 Real-world banking example

Suppose the platform team provides a Kubernetes cluster with Worker Nodes that each have **8 CPU cores** and **16 GB RAM**. The architect defines performance requirements, and the development and platform teams establish resource requests based on testing.

| Pod | CPU request | Memory request |
|---|---|---|
| Frontend Pod | 250m | 256 MiB |
| Banking API Pod | 1 CPU | 1 GiB |
| Authentication Pod | 500m | 512 MiB |
| Background Worker Pod | 1 CPU | 2 GiB |

*Illustrative requests only; actual values should be determined through measurement and load testing.*

The resource requests are written into Kubernetes configuration files. The scheduler does not ask the architect each time a Pod starts; it automatically evaluates the configuration.

### 5.3 Who actually writes the resource request?

A DevOps engineer or developer might define it in a Kubernetes Deployment manifest:

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

- `replicas: 3` means Kubernetes should maintain three Banking API Pods.
- `requests.cpu: "1"` means each Pod requests one CPU core for scheduling purposes.
- `requests.memory: "1Gi"` means each Pod requests 1 GiB of memory.
- `limits` define the configured upper bounds for CPU and memory.

The three replicas collectively request 3 CPU cores and 3 GiB of memory, before accounting for other workloads and system overhead.

### 5.4 Does the architect decide that every Worker Node must have 8 CPU cores and 16 GB RAM?

Not necessarily. There are two related decisions:

1. **Infrastructure capacity:** The cloud/platform/infrastructure team, guided by architecture and capacity planning, selects Worker Node sizes and the number of nodes.
2. **Pod resources:** Application and platform teams set CPU and memory requests and limits based on workload measurements, policies, and service requirements.

> **Key distinction:** The architect and engineering teams decide the requirements; the Kubernetes scheduler decides where eligible Pods run.

## Summary

The Worker Node provides the resources. Kubernetes schedules Pods based on resource requests. CPU and RAM usage depend on each container's configuration and actual workload.
