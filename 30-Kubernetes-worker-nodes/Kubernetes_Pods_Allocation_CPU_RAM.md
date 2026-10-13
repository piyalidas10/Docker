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

## Summary

The Worker Node provides the resources. Kubernetes schedules Pods based on resource requests. CPU and RAM usage depend on each container's configuration and actual workload.
