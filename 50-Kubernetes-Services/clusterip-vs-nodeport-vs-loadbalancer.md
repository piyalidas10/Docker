# ClusterIP vs. NodePort vs. LoadBalancer

In Kubernetes, there are three commonly used Service types: **ClusterIP**, **NodePort**, and **LoadBalancer**. These Services provide different ways to make Pods accessible to other Pods within the cluster and to clients outside of it.

---

## What Is a Kubernetes Service?

Kubernetes assigns Pods **private IP addresses** as soon as they are created. However, these IPs are **not permanent** — if you delete or recreate a Pod, it gets a new IP address.

This is a problem for any client that needs to connect to a Pod. If the IP keeps changing, which one should the client track and connect to?

> Imagine a friend who changes their phone number every day — you'd have no way to call or text them.

**Kubernetes Services solve this.** A Service provides a **stable destination** that clients always connect to, regardless of how many times the underlying Pods are recreated. The client never needs to track Pod IP changes.

```
| Feature                  | ClusterIP                                        | NodePort                                                              | LoadBalancer                                                                                    |
| ------------------------ | ------------------------------------------------ | --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Communication            | Internal Pod-to-Pod / Service-to-Service         | External client-to-Pod via node IP and port                           | External client-to-Pod via external load balancer                                               |
| Load balancing           | Distributes traffic across eligible backend Pods | Can distribute traffic across eligible Pods, including on other nodes | External load balancer distributes incoming traffic; Kubernetes Service routes to eligible Pods |
| Cloud platform required? | No                                               | No                                                                    | Usually requires a cloud provider or another load-balancer implementation for external access   |
| External access          | Not directly                                     | `NodeIP:NodePort`                                                     | External IP or hostname and Service port                                                        |
| Typical use              | Internal APIs, databases, auth services          | Local testing and direct node access                                  | Public-facing applications and APIs                                                             |

```
Important clarification: NodePort does not inherently mean “no load balancing between nodes.” Kubernetes can route NodePort traffic to eligible Pods on other nodes, depending on the Service configuration and cluster networking.

---

## ClusterIP

The **ClusterIP** Service is used for **Pod-to-Pod communication within the same cluster**. A client outside the cluster — such as a browser user on the internet — **cannot directly access** a ClusterIP Service.

```
                  ┌─────────────────────────┐
                  │     ClusterIP Service   │
                  │      (back-end)         │
                  └────────────┬────────────┘
                               │
               ┌───────────────┼───────────────┐
               ▼               ▼               ▼
           back-end Pod    back-end Pod    back-end Pod
```

- When created, it is assigned a **static virtual IP** that never changes for its lifetime
- Incoming requests are **load-balanced (round-robin)** across all matching Pods
- Only accessible from **inside the cluster**

---

## NodePort

The **NodePort** Service exposes your application to **external clients** by opening a **static port (30000–32767)** on **every worker node** in the cluster.

```
External Client
      │
      ▼
Node IP : 30020  (any worker node)
      │
      ▼
NodePort Service
      │
      ▼
ClusterIP Service
      │
      ├──► Pod 1
      └──► Pod 2
```

- External clients connect using `http://<node-ip>:30020`
- NodePort **builds on top of ClusterIP** — Kubernetes automatically creates a ClusterIP Service alongside it
- Traffic path: `External Client → Node → NodePort → ClusterIP → Pod`
- Internal clients can **skip NodePort** and reach the ClusterIP directly

> **Limitation:** NodePort does **not** load-balance across nodes. Traffic goes to whichever node the client connected to — some nodes may get overwhelmed while others sit idle.

---

## LoadBalancer

The **LoadBalancer** Service exposes your application to external clients via a **cloud provider's load balancer**. It only works when Kubernetes is running on a cloud platform that supports it (AWS, GCP, Azure, etc.).

```
External Client
      │
      ▼
Cloud Load Balancer  (single public IP / DNS)
      │
      ├──► Node 1 → NodePort → ClusterIP → Pods
      └──► Node 2 → NodePort → ClusterIP → Pods
```

- Kubernetes detects the cloud platform and **automatically provisions a load balancer** (e.g. AWS Elastic Load Balancer)
- The load balancer gets a **unique, publicly accessible IP address or DNS name**
- LoadBalancer **builds on top of NodePort** — it adds cross-node load balancing on top
- Traffic path: `External Client → Load Balancer → Worker Node IP → NodePort → ClusterIP → Pod`

---

## Key Differences

| | ClusterIP | NodePort | LoadBalancer |
|--|-----------|----------|--------------|
| **Communication** | Pod-to-Pod (internal) | External client-to-Pod | External client-to-Pod |
| **Load balancing across nodes** | N/A | ❌ No | ✅ Yes |
| **Cloud platform required** | ❌ No | ❌ No | ✅ Yes |
| **Access from outside cluster** | ❌ No | ✅ Yes (via node IP + port) | ✅ Yes (via cloud LB IP/DNS) |
| **Builds on top of** | — | ClusterIP | NodePort → ClusterIP |

### How clients connect

- **NodePort:** Client connects directly to a node → `client → node`
- **LoadBalancer:** Client connects to the cloud LB, which picks a node → `client → load balancer → node`

With LoadBalancer, clients never connect directly to nodes. The LB sits in the middle and ensures even traffic distribution. If one node fails, the LB stops sending traffic to it (via health checks) and all future requests land on healthy nodes.

---

## When to Use Which

### ClusterIP

Use when you want to expose an application **inside the cluster** so other Pods can access it.

Examples: auth service, database, cache layer — anything that should not be reachable from the internet.

### NodePort

Use when you want to expose your application to **external clients via a specific port** on each worker node. NodePort is commonly used for **development and testing** purposes.

> Avoid in production — node IPs can change, there is no DNS name, and there is no cross-node load balancing.

### LoadBalancer

Use when you want to expose your application to external clients with **cloud-native load balancing across nodes**. This is the standard choice for **production environments**.

**Why LoadBalancer over NodePort in production?**

- With NodePort, if the specific node a client connects to fails, their requests fail entirely
- With LoadBalancer, if one node fails, the LB redistributes traffic to healthy nodes — only requests already hitting the failed node are lost

---

## Traffic Paths Summary

```
# ClusterIP (internal only)
Pod  ──►  ClusterIP Service  ──►  Pod

# NodePort (external, single node)
External Client  ──►  Node IP:NodePort  ──►  NodePort  ──►  ClusterIP  ──►  Pod

# LoadBalancer (external, cross-node)
External Client  ──►  Cloud LB  ──►  Node  ──►  NodePort  ──►  ClusterIP  ──►  Pod
```

---

## FAQ

**Does ClusterIP do load balancing?**
Yes — but only across **Pods**, not nodes. Kubernetes uses a round-robin algorithm to distribute requests evenly among all Pods behind the Service.

**Does NodePort automatically create a ClusterIP?**
Yes. When you create a NodePort Service, Kubernetes automatically creates a ClusterIP Service alongside it. The ClusterIP is what helps NodePort figure out which group of Pods to send traffic to. It also lets internal Pods reach the same group of Pods directly via the ClusterIP.

**Does NodePort have a single external IP?**
No. NodePort opens a port on **every worker node**, and each node has its own IP. A client can connect to any node's IP on that port. This is different from a LoadBalancer Service, which provides a **single** external IP or DNS name through the cloud provider.
