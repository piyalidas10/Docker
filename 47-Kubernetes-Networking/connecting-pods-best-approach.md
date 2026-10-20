# Connecting Pods — Best Approach & Finalizing the Architecture

## Which Approach is Best?

Now that we've seen all the different ways of connecting pods and containers, here is a summary of when to use each approach.

---

## Should You Put Multiple Containers in One Pod?

In most cases — **no**.

You can have multiple containers in one pod, but you should only do that if the containers are **tightly coupled** and truly need to share the same network namespace (e.g. a sidecar proxy).

If a container also interacts with containers in **other pods**, it should be in its **own separate pod**. That is why this project ends up with **three separate pods** (auth, users, tasks) rather than two.

| Scenario | Recommendation |
|---|---|
| Two containers always deployed together, sharing localhost | Same Pod |
| Container also communicates with Pods in other Deployments | Separate Pod |

---

## Three Ways to Connect Pods

Regardless of approach, **Services are always required** — they provide stable IP addresses (cluster-internal or external), even when Pods are recreated.

Once you have a Service, there are three ways to address it from code:

### Option 1 — Manual ClusterIP Lookup

Look up the Service's ClusterIP with `kubectl get services` and hardcode it as an environment variable.

```yaml
# users-deployment.yaml
env:
  - name: AUTH_ADDRESS
    value: "10.99.104.252"   # ClusterIP of auth-service
```

| | |
|---|---|
| ✅ Stable | ClusterIP doesn't change for the Service's lifetime |
| ❌ Inconvenient | Must manually look it up each time the Service is recreated |

---

### Option 2 — Auto-Generated Environment Variables

Kubernetes automatically injects environment variables into every Pod for all Services running at startup time.

```yaml
# users-deployment.yaml
env:
  - name: AUTH_ADDRESS
    value: "$(AUTH_SERVICE_SERVICE_HOST)"   # auto-injected by Kubernetes
```

Or directly in code:

```js
`http://${process.env.AUTH_SERVICE_SERVICE_HOST}/verify-token/...`
```

| | |
|---|---|
| ✅ No manual lookup | IP address is always current |
| ⚠️ Startup order matters | Service must exist before the Pod starts |
| ⚠️ Verbose | Naming pattern is harder to read and remember |

---

### Option 3 — CoreDNS Domain Names ✅ Recommended

Kubernetes includes **CoreDNS** which auto-generates cluster-internal domain names for every Service. The pattern is:

```
<service-name>.<namespace>
```

```yaml
# users-deployment.yaml
env:
  - name: AUTH_ADDRESS
    value: "auth-service.default"
```

```js
`http://${process.env.AUTH_ADDRESS}/hashed-password/...`
```

| | |
|---|---|
| ✅ Easy to remember | Just the service name + namespace |
| ✅ No manual lookup | Always resolves to the correct Pod |
| ✅ No startup order issue | DNS resolution happens at request time, not Pod start |
| ✅ Works like Docker Compose names | Familiar mental model |

> **Domain names are the most common and recommended way** to connect Pods in Kubernetes.

---

## Comparison Summary

| Approach | Example | Stable? | Convenient? |
|---|---|---|---|
| Pod IP directly | `10.0.0.4` | ❌ Changes on restart | ❌ |
| Service ClusterIP (manual) | `10.99.104.252` | ✅ | ⚠️ Manual lookup |
| Auto-generated env var | `AUTH_SERVICE_SERVICE_HOST` | ✅ | ⚠️ Verbose, startup order |
| **CoreDNS name** | `auth-service.default` | ✅ | ✅ **Best choice** |

---

## Finalizing the Architecture — Adding the Tasks API

With the Users and Auth APIs working, the next step is to deploy the **Tasks API** in its own Pod. The Tasks API must:

1. Be reachable **from outside the cluster** (for frontend / API clients to call `/tasks`)
2. Be able to **talk to the Auth API internally** (to verify tokens on every request)

### What you need to create

| File | Kind | Purpose |
|---|---|---|
| `kubernetes/tasks-deployment.yaml` | Deployment | Runs the tasks container with `AUTH_ADDRESS` and `TASKS_FOLDER` env vars |
| `kubernetes/tasks-service.yaml` | Service (LoadBalancer) | Exposes the Tasks API externally on port 8000 |

### `tasks-deployment.yaml`

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
              value: "auth-service.default"   # CoreDNS name
            - name: TASKS_FOLDER
              value: tasks
```

### `tasks-service.yaml`

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

### Apply everything

```bash
kubectl apply -f kubernetes/tasks-deployment.yaml
kubectl apply -f kubernetes/tasks-service.yaml

# Verify all pods are running
kubectl get pods

# Verify all services are up
kubectl get services
```

---

## Final Architecture

```
                        [ Browser / API Client ]
                                  │
                 ┌────────────────┴────────────────┐
                 │                                  │
          port 8080                           port 8000
          (external)                         (external)
                 │                                  │
        [ users-service ]                  [ tasks-service ]
          LoadBalancer                       LoadBalancer
                 │                                  │
        [ users Pod ]                      [ tasks Pod ]
                 │                                  │
                 └──────────────┬───────────────────┘
                                │
                    auth-service.default (port 80)
                                │
                       [ auth-service ]
                          ClusterIP
                       (internal only)
                                │
                         [ auth Pod ]
```

> The Auth Service uses `ClusterIP` — it is **never exposed externally**. Only the Users and Tasks Pods can reach it, using the CoreDNS name `auth-service.default`.
