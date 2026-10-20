# Kubernetes Services — Life of a Pod & Service Types

---

## The Problem: Life of a Simple Pod

Pods in Kubernetes have **mortal, ephemeral IP addresses**. Consider this setup:

```
Node 1 (IP: 10.16.10.1)          Node 2 (IP: 10.18.10.1)
┌──────────────────────┐          ┌──────────────────────┐
│  nginx Pod  10.0.0.1 │          │  mysql Pod  10.0.0.5 │
│  nginx Pod  10.0.0.2 │          │  mysql Pod  10.0.0.6 │
└──────────────────────┘          └──────────────────────┘
```

- The nginx Pods need to talk to the mysql Pods
- If a mysql Pod **crashes**, the ReplicaSet brings up a new one — but with a **different IP**
- If an entire **Node dies**, a new node comes up with new IPs entirely
- The nginx Pods have **no way to discover** the new mysql Pods

> Hardcoding Pod IPs for communication is always broken — IPs change on every restart or reschedule.

---

## The Solution: Kubernetes Services

A **Service** is an abstraction that provides a **stable network endpoint** in front of a group of Pods.

```
Internet users
      │
      ▼
frontend-service  (stable name + IP)
      │
      ├──► nginx Pod 1
      └──► nginx Pod 2

nginx Pods
      │
      ▼
backend-service  (stable name + IP)
      │
      ├──► mysql Pod 1
      └──► mysql Pod 2
```

- Each Service has a **stable name and IP** — it never changes
- The Service **automatically discovers** Pods using **label selectors**
- If a Pod goes down and a new one comes up with the same label, the Service **automatically routes traffic to it**
- If a new Node comes up with new Pods (same labels), the Service **discovers and includes them** too

### How does a Service discover Pods?

When you define a Service, you specify a **label selector**:

```yaml
selector:
  app: frontend
```

Any Pod with the label `app: frontend` — regardless of which node it runs on — will be managed by this Service. New Pods with matching labels are automatically added.

> Think of a Service like an **AWS Elastic Load Balancer** — it distributes traffic to a group of EC2 instances (or in this case, Pods).

---

## The Motto of All Service Types

> **All Service types — ClusterIP, NodePort, LoadBalancer — share the same core job: discover Pods via labels and distribute traffic across them.**

The difference is only in *where* and *how* they are accessible.

---

## Service Types

### 1. ClusterIP (Default)

- **Internal access only** — accessible only from within the cluster
- Default type — if you don't specify `type`, Kubernetes uses `ClusterIP`
- Pods inside the cluster use the Service name or its internal IP to communicate

```
Web Server Pod ──► backend-service (ClusterIP) ──► mysql Pod 1
                                                ──► mysql Pod 2
```

**Use case:** Backend services, databases, auth APIs — anything that should **not** be reachable from outside the cluster.

**Manifest:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  # No type field = defaults to ClusterIP
  selector:
    app: app-server
  ports:
    - protocol: TCP   # optional — TCP is the default
      port: 80        # port other Pods use to reach this Service
      targetPort: 80  # port the container accepts traffic on
```

```yaml
# Matching Deployment
spec:
  template:
    metadata:
      labels:
        app: app-server   # must match selector above
    spec:
      containers:
        - name: app
          image: nginx
          ports:
            - containerPort: 80
```

---

### 2. NodePort

- **External access** — accessible from outside the cluster
- Opens a **static port (30000–32767)** on **every node** in the cluster
- External clients use `http://<node-ip>:<node-port>` to reach the Pods

```
External Client
      │
      ▼
Node IP : 32000  (nodePort)
      │
      ▼
Service port : 80  (port)
      │
      ▼
Container port : 80  (targetPort)
      │
      ├──► Pod 1
      └──► Pod 2
```

**Three ports to understand:**

| Field | Description | Example |
|-------|-------------|---------|
| `nodePort` | Port opened on every node — used by external clients | `32000` |
| `port` | Port the Service itself listens on inside the cluster | `80` |
| `targetPort` | Port the container/Pod accepts traffic on | `80` |

**Multi-node behaviour:**

Even if you type the IP of **Node 1**, the NodePort Service distributes traffic across Pods on **all nodes** because the NodePort is exposed on every node in the cluster.

```
Node 1 (10.16.10.1:32000) ──┐
                              ├──► Service ──► Pods on Node 1 AND Node 2
Node 2 (10.18.10.1:32000) ──┘
```

**Manifest:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  type: NodePort
  selector:
    app: app-server
  ports:
    - nodePort: 32000   # external port on every node (30000–32767)
      port: 80          # Service's internal port
      targetPort: 80    # container port
```

**Use case:** Development, testing, or environments without a cloud load balancer. **Rarely used in production** because node IPs can change.

---

### 3. LoadBalancer

- **External access** via a **cloud provider's load balancer**
- Cloud-specific: AWS → Elastic Load Balancer, GCP → Cloud Load Balancer, Azure → Azure LB
- Gets a **DNS name or public IP** — clients use that instead of a node IP
- Distributes traffic across all nodes (solves NodePort's limitation)

```
External Client
      │
      ▼
Cloud Load Balancer (DNS / public IP)
      │
      ├──► Node 1 ──► NodePort ──► Pods
      └──► Node 2 ──► NodePort ──► Pods
```

**Extra features on AWS ELB:**
- DNS name (no need to track node IPs)
- SSL/TLS termination
- Web Application Firewall (WAF) integration
- Access logs
- Health checks

**Manifest:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  type: LoadBalancer
  selector:
    app: frontend
  ports:
    - port: 80
      targetPort: 80
```

**Use case:** Production environments on cloud platforms — the standard way to expose applications to external users.

---

## Comparison Table

| Feature | ClusterIP | NodePort | LoadBalancer |
|---------|-----------|----------|--------------|
| **Default type?** | ✅ Yes | ❌ No | ❌ No |
| **External access** | ❌ No | ✅ Yes (node IP + port) | ✅ Yes (cloud LB DNS/IP) |
| **Port range** | Any | 30000–32767 | Any |
| **Load balances across nodes** | N/A | ❌ No (client picks a node) | ✅ Yes |
| **Cloud provider required** | ❌ No | ❌ No | ✅ Yes |
| **Typical use** | Internal APIs, databases | Dev/test external access | Production external access |
| **DNS name** | Cluster-internal only | ❌ No | ✅ Yes (from cloud provider) |

---

## Summary

```
ClusterIP   → internal only         → stable virtual IP inside the cluster
NodePort    → external via node IP  → node-ip:nodePort (30000–32767)
LoadBalancer → external via cloud LB → public DNS/IP from cloud provider
```

> A Service is the **always-on front door** to your Pods. No matter how many Pods die and come back, the Service always knows where to route traffic — because it tracks **labels, not IPs**.
