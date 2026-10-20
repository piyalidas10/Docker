# auth-service.yaml

## Overview

Defines the Kubernetes **Service** for the **Auth** microservice. It uses type `ClusterIP`, which means it is **only reachable from within the cluster** — not from the internet. Other services (Users, Tasks) communicate with Auth using its internal DNS name `auth-service.default`.

---

## File Location

```
kubernetes/auth-service.yaml
```

---

## Full YAML

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

---

## Field Reference

| Field                  | Value           | Description                                                                 |
|------------------------|-----------------|-----------------------------------------------------------------------------|
| `apiVersion`           | `v1`            | API version for core Service resources                                      |
| `kind`                 | `Service`       | Resource type                                                               |
| `metadata.name`        | `auth-service`  | Name of this Service; also forms the DNS name used by other pods            |
| `spec.selector`        | `app: auth`     | Routes traffic to pods with this label (set by `auth-deployment.yaml`)      |
| `spec.type`            | `ClusterIP`     | Internal-only service; not accessible from outside the cluster              |
| `ports[0].protocol`    | `TCP`           | Transport protocol                                                          |
| `ports[0].port`        | `80`            | Port the Service listens on inside the cluster                              |
| `ports[0].targetPort`  | `80`            | Port the Auth container listens on inside the pod                           |

---

## How It Works

- `ClusterIP` is the default and most restrictive Service type — it creates a **virtual IP** accessible only within the cluster.
- Kubernetes automatically creates a **DNS record** for this Service:
  - Short form: `auth-service` (works within the same namespace)
  - Fully qualified: `auth-service.default.svc.cluster.local`
  - Used by other deployments as: **`auth-service.default`**
- The Users and Tasks deployments reference this DNS name via their `AUTH_ADDRESS` environment variable.

---

## DNS Resolution Inside the Cluster

```
AUTH_ADDRESS=auth-service.default
         │
         ▼
  auth-service (ClusterIP)
         │
         ▼
   auth pod (port 80)
```

---

## Related Files

| File | Purpose |
|------|---------|
| [`auth-deployment.yaml`](./auth-deployment.md) | Creates the Auth pods that this Service routes traffic to |
| [`users-deployment.yaml`](./users-deployment.md) | Consumes `auth-service.default` via `AUTH_ADDRESS` env var |
| [`tasks-deployment.yaml`](./tasks-deployment.md) | Consumes `auth-service.default` via `AUTH_ADDRESS` env var |

---

## Apply / Delete

```bash
# Apply only this service
kubectl apply -f kubernetes/auth-service.yaml

# Delete only this service
kubectl delete -f kubernetes/auth-service.yaml
```
