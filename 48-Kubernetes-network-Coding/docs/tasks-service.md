# tasks-service.yaml

## Overview

Defines the Kubernetes **Service** for the **Tasks** microservice. It uses type `LoadBalancer`, which exposes the Tasks API externally on port **8000** so clients (e.g. the frontend) can interact with tasks from outside the cluster.

---

## File Location

```
kubernetes/tasks-service.yaml
```

---

## Full YAML

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

## Field Reference

| Field                  | Value            | Description                                                                 |
|------------------------|------------------|-----------------------------------------------------------------------------|
| `apiVersion`           | `v1`             | API version for core Service resources                                      |
| `kind`                 | `Service`        | Resource type                                                               |
| `metadata.name`        | `tasks-service`  | Name of this Service                                                        |
| `spec.selector`        | `app: tasks`     | Routes traffic to pods with this label (set by `tasks-deployment.yaml`)     |
| `spec.type`            | `LoadBalancer`   | Provisions an external load balancer; assigns a public IP on cloud clusters |
| `ports[0].protocol`    | `TCP`            | Transport protocol                                                          |
| `ports[0].port`        | `8000`           | Port the Service listens on externally                                      |
| `ports[0].targetPort`  | `8000`           | Port the Tasks container listens on inside the pod                          |

---

## How It Works

- `LoadBalancer` exposes the Tasks API on port **8000** with a public IP on cloud providers.
- On **Minikube** or **Docker Desktop**, the `EXTERNAL-IP` will show `<pending>` until you use `minikube service` or a tunnel.
- The Tasks API listens on port **8000** both inside the pod and externally.

---

## Accessing the Service

### Cloud / Docker Desktop Kubernetes

```bash
kubectl get service tasks-service
# Note the EXTERNAL-IP, then access:
# http://<EXTERNAL-IP>:8000
```

### Minikube

```bash
# Open in browser
minikube service tasks-service

# Get the URL only
minikube service tasks-service --url
```

---

## Related Files

| File | Purpose |
|------|---------|
| [`tasks-deployment.yaml`](./tasks-deployment.md) | Creates the Tasks pods that this Service routes traffic to |

---

## Apply / Delete

```bash
# Apply only this service
kubectl apply -f kubernetes/tasks-service.yaml

# Delete only this service
kubectl delete -f kubernetes/tasks-service.yaml
```
