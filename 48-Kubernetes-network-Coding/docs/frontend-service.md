# frontend-service.yaml

## Overview

Defines the Kubernetes **Service** for the **Frontend** microservice. It uses type `LoadBalancer`, which exposes the React application externally on port **80** — making it the primary entry point for users accessing the application via a browser.

---

## File Location

```
kubernetes/frontend-service.yaml
```

---

## Full YAML

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  selector:
    app: frontend
  type: LoadBalancer
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
```

---

## Field Reference

| Field                  | Value               | Description                                                                 |
|------------------------|---------------------|-----------------------------------------------------------------------------|
| `apiVersion`           | `v1`                | API version for core Service resources                                      |
| `kind`                 | `Service`           | Resource type                                                               |
| `metadata.name`        | `frontend-service`  | Name of this Service                                                        |
| `spec.selector`        | `app: frontend`     | Routes traffic to pods with this label (set by `frontend-deployment.yaml`)  |
| `spec.type`            | `LoadBalancer`      | Provisions an external load balancer; assigns a public IP on cloud clusters |
| `ports[0].protocol`    | `TCP`               | Transport protocol                                                          |
| `ports[0].port`        | `80`                | Port the Service listens on externally (standard HTTP)                      |
| `ports[0].targetPort`  | `80`                | Port the NGINX server inside the Frontend container listens on              |

---

## How It Works

- `LoadBalancer` exposes the React frontend on standard HTTP port **80** with a public IP on cloud providers.
- NGINX inside the container serves the compiled React app and handles routing.
- On **Minikube** or **Docker Desktop**, the `EXTERNAL-IP` will show `<pending>` until you use `minikube service` or a tunnel.

---

## Accessing the Service

### Cloud / Docker Desktop Kubernetes

```bash
kubectl get service frontend-service
# Note the EXTERNAL-IP, then open in a browser:
# http://<EXTERNAL-IP>
```

### Minikube

```bash
# Open directly in browser
minikube service frontend-service

# Get the URL only
minikube service frontend-service --url
```

---

## Related Files

| File | Purpose |
|------|---------|
| [`frontend-deployment.yaml`](./frontend-deployment.md) | Creates the Frontend pods that this Service routes traffic to |
| [`users-service.yaml`](./users-service.md) | Users API (port 8080) called by the frontend |
| [`tasks-service.yaml`](./tasks-service.md) | Tasks API (port 8000) called by the frontend |

---

## Apply / Delete

```bash
# Apply only this service
kubectl apply -f kubernetes/frontend-service.yaml

# Delete only this service
kubectl delete -f kubernetes/frontend-service.yaml
```
