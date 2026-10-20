# users-deployment.yaml

## Overview

Defines the Kubernetes **Deployment** for the **Users** microservice. This service handles user registration and login. It communicates with the Auth service internally via Kubernetes DNS to validate or issue tokens.

---

## File Location

```
kubernetes/users-deployment.yaml
```

---

## Full YAML

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
              # value: "10.99.104.252"
              value: "auth-service.default"
```

---

## Field Reference

| Field                          | Value                               | Description                                                         |
|--------------------------------|-------------------------------------|---------------------------------------------------------------------|
| `apiVersion`                   | `apps/v1`                           | API version for Deployment resources                                |
| `kind`                         | `Deployment`                        | Resource type                                                       |
| `metadata.name`                | `users-deployment`                  | Name of this Deployment                                             |
| `spec.replicas`                | `1`                                 | Number of pod instances to run                                      |
| `spec.selector.matchLabels`    | `app: users`                        | Selects pods with this label to manage                              |
| `template.metadata.labels`     | `app: users`                        | Label applied to pods created by this Deployment                    |
| `containers[0].name`           | `users`                             | Name of the container inside the pod                               |
| `containers[0].image`          | `academind/kub-demo-users:latest`   | Docker image pulled from Docker Hub                                 |
| `env.AUTH_ADDRESS`             | `auth-service.default`              | DNS name of the Auth Service used to reach the Auth pod             |

---

## Environment Variables

| Variable       | Value                    | Purpose                                                                                  |
|----------------|--------------------------|------------------------------------------------------------------------------------------|
| `AUTH_ADDRESS` | `auth-service.default`   | Tells the Users app where to reach the Auth API inside the cluster via Kubernetes DNS   |

### Note on the commented-out IP

```yaml
# value: "10.99.104.252"
value: "auth-service.default"
```

The commented line shows an earlier approach where the **static ClusterIP** of the Auth Service was hardcoded. This is fragile — if the Service is recreated, the IP changes. The DNS-based name `auth-service.default` is the **recommended and stable** approach.

---

## How It Works

1. The Users pod starts and reads `AUTH_ADDRESS=auth-service.default` from its environment.
2. When a user signs up or logs in, the Users app calls the Auth API at `http://auth-service.default/...`.
3. Kubernetes DNS resolves `auth-service.default` → ClusterIP of `auth-service` → Auth pod on port 80.
4. The Users app is exposed externally via [`users-service.yaml`](./users-service.md) on port **8080**.

---

## Related Files

| File | Purpose |
|------|---------|
| [`users-service.yaml`](./users-service.md) | Exposes this Deployment externally via LoadBalancer on port 8080 |
| [`auth-service.yaml`](./auth-service.md) | Internal ClusterIP service resolved by `auth-service.default` |
| [`auth-deployment.yaml`](./auth-deployment.md) | Auth pods that handle token validation |

---

## Apply / Delete

```bash
# Apply only this deployment
kubectl apply -f kubernetes/users-deployment.yaml

# Delete only this deployment
kubectl delete -f kubernetes/users-deployment.yaml
```
