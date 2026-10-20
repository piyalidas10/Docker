# frontend-deployment.yaml

## Overview

Defines the Kubernetes **Deployment** for the **Frontend** service — a React application served via NGINX. This is the user-facing layer of the application. It communicates with the Users and Tasks APIs from the browser side.

---

## File Location

```
kubernetes/frontend-deployment.yaml
```

---

## Full YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: frontend
          image: academind/kub-demo-frontend:latest
```

---

## Field Reference

| Field                          | Value                                 | Description                                                   |
|--------------------------------|---------------------------------------|---------------------------------------------------------------|
| `apiVersion`                   | `apps/v1`                             | API version for Deployment resources                          |
| `kind`                         | `Deployment`                          | Resource type                                                 |
| `metadata.name`                | `frontend-deployment`                 | Name of this Deployment                                       |
| `spec.replicas`                | `1`                                   | Number of pod instances to run                                |
| `spec.selector.matchLabels`    | `app: frontend`                       | Selects pods with this label to manage                        |
| `template.metadata.labels`     | `app: frontend`                       | Label applied to pods created by this Deployment              |
| `containers[0].name`           | `frontend`                            | Name of the container inside the pod                         |
| `containers[0].image`          | `academind/kub-demo-frontend:latest`  | Docker image pulled from Docker Hub                           |

---

## How It Works

- The Frontend container serves the built React app using **NGINX** (configured via `frontend/conf/nginx.conf`).
- No environment variables are injected at the Kubernetes level — API URLs are configured within the React app's build or NGINX proxy config.
- The frontend is exposed externally via [`frontend-service.yaml`](./frontend-service.md) on port **80**.

---

## Related Files

| File | Purpose |
|------|---------|
| [`frontend-service.yaml`](./frontend-service.md) | Exposes this Deployment externally via LoadBalancer on port 80 |
| [`users-service.yaml`](./users-service.md) | Users API consumed by the frontend (port 8080) |
| [`tasks-service.yaml`](./tasks-service.md) | Tasks API consumed by the frontend (port 8000) |

---

## Apply / Delete

```bash
# Apply only this deployment
kubectl apply -f kubernetes/frontend-deployment.yaml

# Delete only this deployment
kubectl delete -f kubernetes/frontend-deployment.yaml
```
