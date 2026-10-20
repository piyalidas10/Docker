# tasks-deployment.yaml

## Overview

Defines the Kubernetes **Deployment** for the **Tasks** microservice. This service manages task creation and retrieval. It communicates with the Auth service internally for token validation and uses a configurable folder path to store tasks.

---

## File Location

```
kubernetes/tasks-deployment.yaml
```

---

## Full YAML

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
              # value: "10.99.104.252"
              value: "auth-service.default"
            - name: TASKS_FOLDER
              value: tasks
```

---

## Field Reference

| Field                          | Value                               | Description                                                          |
|--------------------------------|-------------------------------------|----------------------------------------------------------------------|
| `apiVersion`                   | `apps/v1`                           | API version for Deployment resources                                 |
| `kind`                         | `Deployment`                        | Resource type                                                        |
| `metadata.name`                | `tasks-deployment`                  | Name of this Deployment                                              |
| `spec.replicas`                | `1`                                 | Number of pod instances to run                                       |
| `spec.selector.matchLabels`    | `app: tasks`                        | Selects pods with this label to manage                               |
| `template.metadata.labels`     | `app: tasks`                        | Label applied to pods created by this Deployment                     |
| `containers[0].name`           | `tasks`                             | Name of the container inside the pod                                |
| `containers[0].image`          | `academind/kub-demo-tasks:latest`   | Docker image pulled from Docker Hub                                  |
| `env.AUTH_ADDRESS`             | `auth-service.default`              | DNS name of the Auth Service used to reach the Auth pod              |
| `env.TASKS_FOLDER`             | `tasks`                             | Directory name inside the container where task files are stored      |

---

## Environment Variables

| Variable       | Value                    | Purpose                                                                                  |
|----------------|--------------------------|------------------------------------------------------------------------------------------|
| `AUTH_ADDRESS` | `auth-service.default`   | Tells the Tasks app where to reach the Auth API inside the cluster via Kubernetes DNS    |
| `TASKS_FOLDER` | `tasks`                  | Defines the folder name inside the container used to persist task data                   |

### Note on the commented-out IP

```yaml
# value: "10.99.104.252"
value: "auth-service.default"
```

The commented IP was a hardcoded ClusterIP — fragile if the service is recreated. `auth-service.default` uses **Kubernetes DNS** and is always stable.

---

## How It Works

1. The Tasks pod reads `AUTH_ADDRESS=auth-service.default` on startup.
2. For every incoming request that requires authentication, it calls the Auth API at `http://auth-service.default/...`.
3. Tasks are stored in a folder named `tasks` inside the container (as set by `TASKS_FOLDER`).
4. The Tasks app is exposed externally via [`tasks-service.yaml`](./tasks-service.md) on port **8000**.

---

## Related Files

| File | Purpose |
|------|---------|
| [`tasks-service.yaml`](./tasks-service.md) | Exposes this Deployment externally via LoadBalancer on port 8000 |
| [`auth-service.yaml`](./auth-service.md) | Internal ClusterIP service resolved by `auth-service.default` |
| [`auth-deployment.yaml`](./auth-deployment.md) | Auth pods that handle token validation |

---

## Apply / Delete

```bash
# Apply only this deployment
kubectl apply -f kubernetes/tasks-deployment.yaml

# Delete only this deployment
kubectl delete -f kubernetes/tasks-deployment.yaml
```
