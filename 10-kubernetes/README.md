# 10 — Kubernetes

**Kubernetes (K8s)** is an open-source container orchestration platform that automates deployment, scaling, and management of containerised applications. Docker builds the images; Kubernetes runs them at scale.

---

## Core Concepts

| Object | Description |
|---|---|
| **Pod** | Smallest deployable unit — one or more tightly coupled containers. |
| **Deployment** | Declares desired state (replicas, image, update strategy) for Pods. |
| **Service** | Stable network endpoint (DNS + load balancer) in front of Pods. |
| **Namespace** | Virtual cluster for resource isolation. |
| **ConfigMap** | Injects non-sensitive configuration into Pods. |
| **Secret** | Injects sensitive data (passwords, tokens) into Pods. |
| **PersistentVolume (PV)** | Cluster-level storage resource. |
| **PersistentVolumeClaim (PVC)** | Pod's request for storage from a PV. |
| **Ingress** | HTTP/HTTPS routing rules into the cluster. |

---

## Architecture Overview

```
┌─────────────────── Kubernetes Cluster ───────────────────┐
│                                                           │
│  Control Plane                  Worker Nodes             │
│  ┌─────────────┐               ┌──────────────────────┐  │
│  │ API Server  │◄──kubectl────►│  kubelet             │  │
│  │ Scheduler   │               │  kube-proxy          │  │
│  │ etcd        │               │  ┌────┐ ┌────┐       │  │
│  │ Controller  │               │  │Pod │ │Pod │  ...  │  │
│  └─────────────┘               │  └────┘ └────┘       │  │
│                                └──────────────────────┘  │
└───────────────────────────────────────────────────────────┘
```

---

## kubectl — Essential Commands

```bash
# Cluster info
kubectl cluster-info
kubectl get nodes

# Namespaces
kubectl get namespaces
kubectl create namespace my-app

# Pods
kubectl get pods -n my-app
kubectl describe pod <pod-name> -n my-app
kubectl logs <pod-name> -n my-app -f
kubectl exec -it <pod-name> -n my-app -- sh

# Apply a manifest
kubectl apply -f deployment.yaml

# Delete a resource
kubectl delete -f deployment.yaml

# Scale a deployment
kubectl scale deployment my-app --replicas=5 -n my-app

# Rolling restart
kubectl rollout restart deployment/my-app -n my-app

# Check rollout status
kubectl rollout status deployment/my-app -n my-app

# Rollback
kubectl rollout undo deployment/my-app -n my-app
```

---

## Deployment Manifest

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-api
  namespace: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-api
  template:
    metadata:
      labels:
        app: my-api
    spec:
      containers:
        - name: api
          image: my-api:1.4.2       # always use a specific tag
          ports:
            - containerPort: 3000
          env:
            - name: NODE_ENV
              value: production
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-secret
                  key: password
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: /ready
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 10
```

---

## Service Manifest

```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: my-api
  namespace: my-app
spec:
  selector:
    app: my-api          # targets pods with this label
  ports:
    - protocol: TCP
      port: 80
      targetPort: 3000
  type: ClusterIP        # internal only; use LoadBalancer or NodePort to expose
```

---

## ConfigMap & Secret

```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  LOG_LEVEL: "info"
  CACHE_TTL: "300"

---
# secret.yaml (values must be base64-encoded)
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
data:
  password: c2VjcmV0MTIz   # echo -n 'secret123' | base64
```

---

## PersistentVolumeClaim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: db-storage
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: standard
```

---

## Docker → Kubernetes Mental Map

| Docker | Kubernetes Equivalent |
|---|---|
| `docker run` | Pod / Deployment |
| `docker-compose up` | `kubectl apply -f` |
| Named volume | PersistentVolumeClaim |
| `--network` | Service / Namespace |
| Port mapping (`-p`) | Service (NodePort / LoadBalancer) |
| `.env` file | ConfigMap / Secret |
| `docker ps` | `kubectl get pods` |
| `docker logs` | `kubectl logs` |
| `docker exec` | `kubectl exec` |

---

## Local Kubernetes Clusters

| Tool | Notes |
|---|---|
| **Docker Desktop** | Enable in Settings → Kubernetes |
| **minikube** | `minikube start` — single-node cluster in a VM/container |
| **kind** | Kubernetes-in-Docker — great for CI |
| **k3d** | Lightweight k3s inside Docker |

---

## References

- [Kubernetes documentation](https://kubernetes.io/docs/home/)
- [kubectl cheat sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Learn Kubernetes basics (interactive)](https://kubernetes.io/docs/tutorials/kubernetes-basics/)
- [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)
