# Kubernetes Services — ClusterIP vs NodePort vs LoadBalancer vs ExternalName

## Why Kubernetes Services Exist

Kubernetes assigns Pods **private IP addresses** as soon as they are created. However, these IPs are **not permanent** — if a Pod is deleted or recreated, it gets a new IP address.

This is a problem for any client that needs to connect to a Pod. If the IP keeps changing, which one should the client use?

**Kubernetes Services solve this** by providing a **stable, fixed endpoint** in front of one or more Pods. The client always talks to the Service — not directly to the Pod — so it never needs to track Pod IP changes.

---

## The Three Main Service Types

### 1. ClusterIP

**ClusterIP** is the **default** Service type. It exposes Pods **only within the cluster** — no external access.

```
External Client ❌ (cannot reach ClusterIP directly)

Pod A  ──►  ClusterIP Service  ──►  Pod B (back-end)
                                ──►  Pod C (back-end)
                                ──►  Pod D (back-end)
```

- Assigned a **static virtual IP** that never changes for the Service's lifetime
- When a request hits the ClusterIP, it is **load-balanced** across all matching Pods (round-robin)
- Only accessible by **other Pods inside the same cluster**
- Does **not** require a cloud provider

**Example YAML:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  selector:
    app: backend
  type: ClusterIP
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
```

**When to use:** Internal services that should not be reachable from outside the cluster (e.g. auth, database, caching layers).

---

### 2. NodePort

**NodePort** exposes the Service to **external clients** by opening a **static port (30000–32767)** on **every worker node** in the cluster.

```
External Client  ──►  Node IP : 30020  ──►  NodePort Service
                                              │
                                              ▼
                                         ClusterIP Service
                                              │
                                   ┌──────────┴──────────┐
                                   ▼                     ▼
                                 Pod A                 Pod B
```

- NodePort **builds on top of ClusterIP** — Kubernetes automatically creates a ClusterIP Service alongside it
- External clients connect to any worker node's IP on the chosen NodePort (e.g. `http://node-ip:30020`)
- Internal clients can still skip NodePort and access the ClusterIP directly
- Port range is **30000–32767**
- Does **not** require a cloud provider

> **Limitation:** NodePort does **not** load-balance across nodes. Traffic always goes to whichever node the client connected to — some nodes can get overloaded while others sit idle.

**Example YAML:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  selector:
    app: frontend
  type: NodePort
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 30020   # optional — Kubernetes assigns one if omitted
```

**When to use:** Development, testing, or simple environments where you need external access without a cloud load balancer.

---

### 3. LoadBalancer

**LoadBalancer** exposes the Service externally by provisioning a **cloud provider's load balancer** (e.g. AWS ELB, GCP Load Balancer, Azure LB). It gets a **single, public IP address** that external clients use.

```
External Client  ──►  Cloud Load Balancer (public IP)
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
                  Node 1             Node 2
                    │                   │
                    ▼                   ▼
              NodePort Service    NodePort Service
                    │                   │
                    ▼                   ▼
              ClusterIP Service   ClusterIP Service
                    │
              ┌─────┴─────┐
              ▼           ▼
            Pod A       Pod B
```

- LoadBalancer **builds on top of NodePort** — it adds a cloud load balancer in front of the nodes
- The cloud load balancer distributes traffic **across all nodes**, solving NodePort's single-node bottleneck
- Traffic path: `External client → Load Balancer → Node IP → NodePort → ClusterIP → Pod`
- **Requires** a cloud platform that supports this type (AWS, GCP, Azure, etc.)
- On **Minikube / local clusters**, `EXTERNAL-IP` stays `<pending>` — use `minikube service <name>` instead

**Example YAML:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: users-service
spec:
  selector:
    app: users
  type: LoadBalancer
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
```

**When to use:** Production environments on cloud platforms where you need reliable, load-balanced external access.

---

### 4. ExternalName (DNS Alias)

**ExternalName** is a special Service type that maps a Kubernetes Service name to an **external DNS name**. It does not proxy traffic or expose any ports — it simply returns a **CNAME DNS record** pointing to the external hostname.

```
Pod inside cluster
      │
      │  http://my-database  (Service DNS name)
      ▼
ExternalName Service
      │
      │  CNAME  →  my-database.example.com
      ▼
External resource (outside the cluster)
```

- **No selector, no ports, no ClusterIP** — it is purely a DNS alias
- Pods use the Service name (`my-database`) as if it were a cluster-internal Service
- Kubernetes DNS resolves it to the external hostname via a **CNAME record**
- Useful for **migrating workloads** — swap the external DNS for a cluster-internal Service later without changing any Pod config
- Works only with **DNS names**, not raw IP addresses

**Example YAML:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-database
spec:
  type: ExternalName
  externalName: my-database.prod.example.com
  # No selector — no Pods managed
  # No ports — no traffic proxying
```

Any Pod that calls `http://my-database` will have its DNS query resolved to `my-database.prod.example.com` by the cluster's DNS (CoreDNS).

**When to use:**
- Connecting to **external databases or APIs** (e.g. RDS, Cloud SQL) using a stable in-cluster name
- **Abstracting third-party services** so Pods never hardcode external hostnames
- **Migration strategy** — start with ExternalName pointing to an old external service, then switch to a real in-cluster Service when ready, with zero changes to consuming Pods

> **Note:** ExternalName does **not** perform any health checking, load balancing, or TLS termination. It is purely a DNS redirect.

---

## Key Differences at a Glance

| Feature | ClusterIP | NodePort | LoadBalancer | ExternalName |
|---------|-----------|----------|--------------|--------------|
| **External access** | ❌ No | ✅ Yes (node IP + port) | ✅ Yes (cloud LB IP) | ✅ DNS only (CNAME) |
| **Load balancing (Pods)** | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No |
| **Load balancing (Nodes)** | N/A | ❌ No | ✅ Yes | ❌ No |
| **Cloud provider required** | ❌ No | ❌ No | ✅ Yes | ❌ No |
| **Port range** | Any | 30000–32767 | Any | N/A |
| **Builds on top of** | — | ClusterIP | NodePort → ClusterIP | — |
| **Has selector / Pods** | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No |
| **Typical use** | Internal services | Dev/test external access | Production external access | DNS alias to external resource |

---

## Traffic Paths

```
# ClusterIP (internal only)
Pod  ──►  ClusterIP  ──►  Pod

# NodePort (external, no cross-node LB)
External Client  ──►  Node:Port  ──►  NodePort  ──►  ClusterIP  ──►  Pod

# LoadBalancer (external, with cross-node LB)
External Client  ──►  Cloud LB  ──►  Node  ──►  NodePort  ──►  ClusterIP  ──►  Pod

# ExternalName (DNS alias only)
Pod  ──►  ExternalName Service (CNAME)  ──►  external-hostname.example.com
```

---

## When to Use Which

| Service Type | Use when... |
|-------------|-------------|
| **ClusterIP** | You want Pods to talk to each other **inside** the cluster (e.g. auth, database, cache) |
| **NodePort** | You need **external access** for dev/testing and don't have a cloud provider |
| **LoadBalancer** | You need **production-grade external access** on a cloud platform with traffic distributed across nodes |
| **ExternalName** | You want Pods to reference an **external service by a stable in-cluster DNS name** (e.g. managed DB, third-party API) |

---

## FAQ

**Does ClusterIP do load balancing?**
Yes — but only across **Pods**, not nodes. Kubernetes uses a round-robin algorithm to distribute requests evenly among all Pods behind the Service.

**Does NodePort automatically create a ClusterIP?**
Yes. When you create a NodePort Service, Kubernetes automatically creates a ClusterIP Service alongside it. The NodePort uses it internally to route traffic to the right Pod group.

**Does NodePort have a single external IP?**
No. NodePort opens a port on **every worker node**, each with its own IP. A client can connect to any of those node IPs on the chosen port. This is different from LoadBalancer, which provides a **single** public IP via the cloud provider.

**What about Minikube?**
On Minikube, LoadBalancer Services will show `EXTERNAL-IP: <pending>` because there's no cloud provider. Use:
```bash
minikube service <service-name>         # opens in browser
minikube service <service-name> --url   # prints the URL
```
