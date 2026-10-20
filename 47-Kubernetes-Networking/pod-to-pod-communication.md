# Pod-to-Pod Communication in Kubernetes

## Overview

Once the Users and Auth APIs are working together inside the same Pod, the next step is to **separate them into individual Pods** and also add the Tasks API as its own Pod. This requires moving from pod-internal `localhost` communication to **cluster-internal Pod-to-Pod communication using Kubernetes Services**.

The final architecture looks like this:

```
┌─────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                     │
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │  users Pod   │    │  tasks Pod   │    │  auth Pod    │  │
│  │  port 8080   │    │  port 8000   │    │  port 80     │  │
│  └──────┬───────┘    └──────┬───────┘    └──────▲───────┘  │
│         │                  │                   │           │
│         └──────────────────┴───────────────────┘           │
│                     auth-service                            │
│                  (ClusterIP — internal only)                │
│                                                             │
│  users-service          tasks-service                       │
│  (LoadBalancer)         (LoadBalancer)                      │
└──────────┬──────────────────┬──────────────────────────────┘
           │                  │
       Outside world      Outside world
```

---

## What Needs to Change

| Change | Reason |
|--------|--------|
| Split `auth` out of `users-deployment.yaml` into its own `auth-deployment.yaml` | Auth and Users should run in separate Pods |
| Remove `auth` container from `users-deployment.yaml` | Users Pod should only run the users container |
| Create `auth-service.yaml` with type `ClusterIP` | Auth must be reachable cluster-internally but **not** from the internet |
| Update `AUTH_ADDRESS` env var in Users and Tasks deployments | `localhost` no longer works — a Service DNS name is needed |
| Add `tasks-deployment.yaml` and `tasks-service.yaml` | Tasks API needs its own Pod and external exposure |

---

## Step 1 — Create `auth-deployment.yaml`

Separate the Auth container into its own Deployment. This creates a new, independent Pod for the Auth API.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: auth
  template:
    metadata:
      labels:
        app: auth
    spec:
      containers:
        - name: auth
          image: academind/kub-demo-auth:latest
```

> Auth needs no environment variables — it is self-contained.

---

## Step 2 — Update `users-deployment.yaml`

Remove the `auth` container from the Users Deployment. Users now runs alone in its own Pod.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: users-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: users
  template:
    metadata:
      labels:
        app: users
    spec:
      containers:
        - name: users
          image: academind/kub-demo-users:latest
          env:
            - name: AUTH_ADDRESS
              value: "auth-service.default"
```

> `AUTH_ADDRESS` changes from `"localhost"` to `"auth-service.default"` — the Kubernetes DNS name of the Auth Service.

---

## Step 3 — Create `auth-service.yaml` with `ClusterIP`

The Auth Service must be **reachable by other Pods inside the cluster** but **not exposed to the internet**. Use type `ClusterIP` for this.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: auth-service
spec:
  selector:
    app: auth
  type: ClusterIP
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
```

### Why `ClusterIP` and not `LoadBalancer`?

| Type | Accessible from outside cluster? | Use case |
|------|-----------------------------------|----------|
| `LoadBalancer` | ✅ Yes | Public-facing APIs (users, tasks, frontend) |
| `ClusterIP` | ❌ No — internal only | Internal services like auth |

Using `LoadBalancer` for Auth would expose token generation/verification to the public — a security risk. `ClusterIP` ensures only other Pods within the cluster can call it.

---

## Step 4 — The New `AUTH_ADDRESS`: From `localhost` to DNS

When Auth and Users were in the same Pod, `localhost` worked because they shared a network namespace. Now that they are in **separate Pods**, `localhost` no longer reaches Auth.

Instead, Kubernetes provides **automatic DNS resolution** for every Service:

```
auth-service          →  resolves within the same namespace
auth-service.default  →  fully qualified within the "default" namespace
```

So the new `AUTH_ADDRESS` value for both Users and Tasks deployments is:

```yaml
env:
  - name: AUTH_ADDRESS
    value: "auth-service.default"
```

### DNS resolution flow

```
users Pod
  │
  │  http://auth-service.default/verify-token
  ▼
auth-service (ClusterIP — stable virtual IP)
  │
  ▼
auth Pod (IP may change — but the Service always finds it)
```

---

## Step 5 — Add `tasks-deployment.yaml`

The Tasks API runs in its own Pod and also needs to reach Auth for token verification.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tasks-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tasks
  template:
    metadata:
      labels:
        app: tasks
    spec:
      containers:
        - name: tasks
          image: academind/kub-demo-tasks:latest
          env:
            - name: AUTH_ADDRESS
              value: "auth-service.default"
            - name: TASKS_FOLDER
              value: tasks
```

---

## Step 6 — Add `tasks-service.yaml`

The Tasks API needs to be reachable from outside the cluster (e.g. from the frontend or API clients), so use `LoadBalancer`.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: tasks-service
spec:
  selector:
    app: tasks
  type: LoadBalancer
  ports:
    - protocol: TCP
      port: 8000
      targetPort: 8000
```

---

## Final Deployment & Service Summary

| Resource | Kind | Type | Port | Accessible from outside? |
|----------|------|------|------|--------------------------|
| `auth-deployment` | Deployment | — | 80 | — |
| `auth-service` | Service | `ClusterIP` | 80 | ❌ No — internal only |
| `users-deployment` | Deployment | — | 8080 | — |
| `users-service` | Service | `LoadBalancer` | 8080 | ✅ Yes |
| `tasks-deployment` | Deployment | — | 8000 | — |
| `tasks-service` | Service | `LoadBalancer` | 8000 | ✅ Yes |

---

## Apply All Changes

```bash
kubectl apply -f kubernetes/auth-deployment.yaml
kubectl apply -f kubernetes/auth-service.yaml
kubectl apply -f kubernetes/users-deployment.yaml
kubectl apply -f kubernetes/tasks-deployment.yaml
kubectl apply -f kubernetes/tasks-service.yaml
```

Or apply everything at once:

```bash
kubectl apply -f kubernetes/
```

---

## Verify

```bash
# Check all pods are running (each should show 1/1)
kubectl get pods

# Check services — auth-service should have no EXTERNAL-IP
kubectl get services
```

Expected `kubectl get services` output:

```
NAME            TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
auth-service    ClusterIP      10.x.x.x        <none>        80/TCP           Xs
users-service   LoadBalancer   10.x.x.x        <pending>     8080:xxxxx/TCP   Xs
tasks-service   LoadBalancer   10.x.x.x        <pending>     8000:xxxxx/TCP   Xs
```

> `auth-service` has **no EXTERNAL-IP** by design — it is intentionally internal-only.

---

## Key Takeaways

| Scenario | Address |
|----------|---------|
| Two containers in the **same Pod** | `localhost` |
| Two containers in **different Pods** (same namespace) | `<service-name>.default` |
| Pod IP directly | ❌ Avoid — IPs are ephemeral and change on restart |
