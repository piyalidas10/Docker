# users-service.yaml

## Overview

Defines the Kubernetes **Service** for the **Users** microservice. It uses type `LoadBalancer`, which exposes the Users API externally on port **8080** so clients (e.g. the frontend or API tools) can reach it from outside the cluster.

---

## File Location

```
kubernetes/users-service.yaml
```

---

## Full YAML

```yaml
apiVersion: v1
kind: Service
metadata:
  name: users-service
spec:
  selector:
    app: users
  type: LoadBalancer
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
```

---

## Field Reference

| Field                  | Value            | Description                                                                 |
|------------------------|------------------|-----------------------------------------------------------------------------|
| `apiVersion`           | `v1`             | API version for core Service resources                                      |
| `kind`                 | `Service`        | Resource type                                                               |
| `metadata.name`        | `users-service`  | Name of this Service                                                        |
| `spec.selector`        | `app: users`     | Routes traffic to pods with this label (set by `users-deployment.yaml`)     |
| `spec.type`            | `LoadBalancer`   | Provisions an external load balancer; assigns a public IP on cloud clusters |
| `ports[0].protocol`    | `TCP`            | Transport protocol                                                          |
| `ports[0].port`        | `8080`           | Port the Service listens on externally                                      |
| `ports[0].targetPort`  | `8080`           | Port the Users container listens on inside the pod                          |

---

## How It Works

- `LoadBalancer` is the standard way to expose a service to external traffic on cloud providers (AWS, GCP, Azure).
- On **Minikube** or **Docker Desktop**, the `EXTERNAL-IP` will show `<pending>` until you use `minikube service` or a tunnel.
- The Users API listens on port **8080** both inside the pod and externally.

---

## Accessing the Service

### Cloud / Docker Desktop Kubernetes

```bash
kubectl get service users-service
# Note the EXTERNAL-IP, then access:
# http://<EXTERNAL-IP>:8080
```

### Minikube

```bash
# Open in browser
minikube service users-service

# Get the URL only
minikube service users-service --url
```

---

## Related Files

| File | Purpose |
|------|---------|
| [`users-deployment.yaml`](./users-deployment.md) | Creates the Users pods that this Service routes traffic to |

---

## Apply / Delete

```bash
# Apply only this service
kubectl apply -f kubernetes/users-service.yaml

# Delete only this service
kubectl delete -f kubernetes/users-service.yaml
```
