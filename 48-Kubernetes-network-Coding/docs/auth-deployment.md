# auth-deployment.yaml

## Overview

Defines the Kubernetes **Deployment** for the **Auth** microservice. This service handles internal token-based authentication. It is not exposed to the outside world — only other pods within the cluster communicate with it.

---

## File Location

```
kubernetes/auth-deployment.yaml
```

---

## Full YAML

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

---

## Field Reference

| Field                          | Value                              | Description                                                   |
|--------------------------------|------------------------------------|---------------------------------------------------------------|
| `apiVersion`                   | `apps/v1`                          | API version for Deployment resources                          |
| `kind`                         | `Deployment`                       | Resource type                                                 |
| `metadata.name`                | `auth-deployment`                  | Name of this Deployment                                       |
| `spec.replicas`                | `1`                                | Number of pod instances to run                                |
| `spec.selector.matchLabels`    | `app: auth`                        | Selects pods with this label to manage                        |
| `template.metadata.labels`     | `app: auth`                        | Label applied to pods created by this Deployment              |
| `containers[0].name`           | `auth`                             | Name of the container inside the pod                         |
| `containers[0].image`          | `academind/kub-demo-auth:latest`   | Docker image pulled from Docker Hub                           |

---

## How It Works

- The Deployment controller ensures **1 replica** of the Auth pod is always running.
- The pod selector (`app: auth`) links this Deployment to the pods it manages.
- The same label (`app: auth`) is used by [`auth-service.yaml`](./auth-service.md) to route traffic to these pods.
- No environment variables or volume mounts are needed — the Auth service is self-contained.

---

## Related Files

| File | Purpose |
|------|---------|
| [`auth-service.yaml`](./auth-service.md) | Exposes this Deployment as a ClusterIP Service inside the cluster |

---

## Apply / Delete

```bash
# Apply only this deployment
kubectl apply -f kubernetes/auth-deployment.yaml

# Delete only this deployment
kubectl delete -f kubernetes/auth-deployment.yaml
```
