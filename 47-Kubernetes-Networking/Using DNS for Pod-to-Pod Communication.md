# Using DNS for Pod-to-Pod Communication - Kubernetes CoreDNS — Cluster-Internal Domain Names

## The Problem with Auto-Generated Environment Variables

While Kubernetes auto-generated environment variables like `AUTH_SERVICE_SERVICE_HOST` work, they have a limitation: they are only injected into a Pod if the Service **existed before the Pod started**. They are also harder to read and remember.

There is a more convenient approach built into every modern Kubernetes cluster.

---

## What is CoreDNS?

**CoreDNS** is a built-in DNS service that comes pre-installed in modern Kubernetes clusters. As the name suggests, it is a **Domain Name Service** — but for your cluster, not the internet.

> CoreDNS automatically creates **cluster-internal domain names** for every Service in your cluster.

These domain names:
- Are **not** registered with global DNS — you cannot type them into a browser from outside the cluster
- Are **only known inside the cluster** — just like ClusterIP addresses
- Are **automatically created** by Kubernetes — no manual configuration needed
- Work for **any programming language** that supports environment variables or HTTP requests

You can verify CoreDNS is running in your cluster:

```bash
kubectl get pods -n kube-system
# Look for: coredns-xxxxxxxxxx-xxxxx   1/1   Running
```

---

## The DNS Name Pattern

The automatically generated domain name for a Service follows this pattern:

```
<service-name>.<namespace>
```

### Full form (recommended)

```
auth-service.default
```

### Short form (works within the same namespace)

```
auth-service
```

### Fully qualified domain name (FQDN)

```
auth-service.default.svc.cluster.local
```

---

## Namespaces

A **namespace** is a way to group and isolate Kubernetes resources (Services, Deployments, etc.) within the same cluster — for example, to separate resources by team or project.

```bash
# View all namespaces in your cluster
kubectl get namespaces
```

Example output on Minikube:

```
NAME              STATUS   AGE
default           Active   10d
kube-node-lease   Active   10d
kube-public       Active   10d
kube-system       Active   10d
```

> If you do not assign a resource to a specific namespace, Kubernetes places it in the **`default`** namespace automatically.

So for all Services in this project, the namespace is `default`, and the DNS name is `<service-name>.default`.

---

## Using CoreDNS in Code

Instead of using a hardcoded IP or an auto-generated env var, pass the DNS name as the value of `AUTH_ADDRESS`:

### `users-deployment.yaml`

```yaml
env:
  - name: AUTH_ADDRESS
    value: "auth-service.default"   # CoreDNS cluster-internal domain
```

### In `users-app.js`

```js
// signup route — uses AUTH_ADDRESS (set to CoreDNS name in deployment YAML)
const hashedPW = await axios.get(
  `http://${process.env.AUTH_ADDRESS}/hashed-password/` + password
);

// login route — uses auto-generated Kubernetes env var
const response = await axios.get(
  `http://${process.env.AUTH_SERVICE_SERVICE_HOST}/token/` + hashedPassword + '/' + password
);
```

Both approaches work simultaneously — proving that the CoreDNS name resolves correctly inside the cluster.

---

## Applying the Change

Since only the env var **value** changed in the deployment YAML, simply re-apply:

```bash
kubectl apply -f kubernetes/users-deployment.yaml
```

No code change is needed — only the environment variable value was updated.

---

## Comparison: Three Ways to Address a Service

| Approach | Example value | Stable? | Convenient? | Notes |
|---|---|---|---|---|
| **Pod IP** | `10.0.0.4` | ❌ Changes on restart | ❌ | Never use for inter-service calls |
| **Service ClusterIP** | `10.99.104.252` | ✅ Stable | ⚠️ Manual lookup | Changes if Service is recreated |
| **Auto-generated env var** | `AUTH_SERVICE_SERVICE_HOST` | ✅ Stable | ⚠️ Verbose | Service must exist before Pod starts |
| **CoreDNS name** | `auth-service.default` | ✅ Always stable | ✅ Clean & readable | **Recommended approach** |

---

## CoreDNS vs Docker Compose Service Names

The CoreDNS pattern is very similar to how Docker Compose networking works:

| Environment | How services find each other |
|---|---|
| **Docker Compose** | Use the Compose service name: `auth` |
| **Kubernetes (CoreDNS)** | Use `<service-name>.<namespace>`: `auth-service.default` |

Both allow services to reference each other by name rather than by IP — making configuration portable and readable.

---

## Summary

```
Kubernetes CoreDNS automatically creates:

  auth-service.default   →  ClusterIP of auth-service  →  auth Pod
  users-service.default  →  ClusterIP of users-service →  users Pod
  tasks-service.default  →  ClusterIP of tasks-service →  tasks Pod
```

> Use `<service-name>.default` as the value for any environment variable that holds a service address. It is the most stable, readable, and idiomatic way to do inter-service communication in Kubernetes.
