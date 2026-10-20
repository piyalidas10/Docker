# Kubernetes Networking – Demo Application

This project demonstrates **Kubernetes pod-to-pod networking** using a multi-service Node.js application composed of four microservices: **Auth**, **Users**, **Tasks**, and **Frontend**. Each service has its own Kubernetes Deployment and Service defined inside the [`kubernetes/`](./kubernetes/) folder.

---

## Project Structure

```
48-Kubernetes-network-Coding/
├── auth-api/               # Auth microservice source
├── users-api/              # Users microservice source
├── tasks-api/              # Tasks microservice source
├── frontend/               # React frontend source
├── docker-compose.yaml     # Local Docker Compose setup
└── kubernetes/             # Kubernetes manifests (Deployments + Services)
    ├── auth-deployment.yaml
    ├── auth-service.yaml
    ├── frontend-deployment.yaml
    ├── frontend-service.yaml
    ├── tasks-deployment.yaml
    ├── tasks-service.yaml
    ├── users-deployment.yaml
    └── users-service.yaml
```

---

## Kubernetes Manifests

### 1. `auth-deployment.yaml`

Deploys the **Auth** service — a lightweight internal authentication API. It is not exposed externally; other services reach it via the cluster-internal DNS name.

| Field        | Value                              |
|--------------|------------------------------------|
| Kind         | Deployment                         |
| Name         | `auth-deployment`                  |
| Replicas     | 1                                  |
| Label        | `app: auth`                        |
| Container    | `auth`                             |
| Image        | `academind/kub-demo-auth:latest`   |

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

### 2. `auth-service.yaml`

Exposes the Auth Deployment **only inside the cluster** using a `ClusterIP` Service. Other pods reach the auth API via the DNS name `auth-service.default`.

| Field        | Value           |
|--------------|-----------------|
| Kind         | Service         |
| Name         | `auth-service`  |
| Type         | `ClusterIP`     |
| Selector     | `app: auth`     |
| Port         | 80 → 80 (TCP)   |

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

### 3. `users-deployment.yaml`

Deploys the **Users** service, which handles user sign-up and login. It communicates with the Auth service internally using the Kubernetes DNS name `auth-service.default` via the `AUTH_ADDRESS` environment variable.

| Field        | Value                                |
|--------------|--------------------------------------|
| Kind         | Deployment                           |
| Name         | `users-deployment`                   |
| Replicas     | 1                                    |
| Label        | `app: users`                         |
| Container    | `users`                              |
| Image        | `academind/kub-demo-users:latest`    |
| Env Vars     | `AUTH_ADDRESS=auth-service.default`  |

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

> **Note:** The commented-out IP (`10.99.104.252`) shows the earlier approach using a static ClusterIP. The DNS-based name `auth-service.default` is the recommended approach.

---

### 4. `users-service.yaml`

Exposes the Users Deployment externally via a `LoadBalancer` Service on port **8080**.

| Field        | Value              |
|--------------|--------------------|
| Kind         | Service            |
| Name         | `users-service`    |
| Type         | `LoadBalancer`     |
| Selector     | `app: users`       |
| Port         | 8080 → 8080 (TCP)  |

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

### 5. `tasks-deployment.yaml`

Deploys the **Tasks** service, which manages task creation and retrieval. Like the Users service, it reaches the Auth API using `AUTH_ADDRESS=auth-service.default` and also uses a `TASKS_FOLDER` env variable to define where tasks are stored.

| Field        | Value                                |
|--------------|--------------------------------------|
| Kind         | Deployment                           |
| Name         | `tasks-deployment`                   |
| Replicas     | 1                                    |
| Label        | `app: tasks`                         |
| Container    | `tasks`                              |
| Image        | `academind/kub-demo-tasks:latest`    |
| Env Vars     | `AUTH_ADDRESS=auth-service.default`, `TASKS_FOLDER=tasks` |

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

### 6. `tasks-service.yaml`

Exposes the Tasks Deployment externally via a `LoadBalancer` Service on port **8000**.

| Field        | Value              |
|--------------|--------------------|
| Kind         | Service            |
| Name         | `tasks-service`    |
| Type         | `LoadBalancer`     |
| Selector     | `app: tasks`       |
| Port         | 8000 → 8000 (TCP)  |

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

### 7. `frontend-deployment.yaml`

Deploys the **Frontend** React application served via NGINX.

| Field        | Value                                  |
|--------------|----------------------------------------|
| Kind         | Deployment                             |
| Name         | `frontend-deployment`                  |
| Replicas     | 1                                      |
| Label        | `app: frontend`                        |
| Container    | `frontend`                             |
| Image        | `academind/kub-demo-frontend:latest`   |

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

### 8. `frontend-service.yaml`

Exposes the Frontend Deployment externally via a `LoadBalancer` Service on port **80**.

| Field        | Value               |
|--------------|---------------------|
| Kind         | Service             |
| Name         | `frontend-service`  |
| Type         | `LoadBalancer`      |
| Selector     | `app: frontend`     |
| Port         | 80 → 80 (TCP)       |

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

## Service Summary

| Service    | Deployment Name       | Service Name       | Service Type  | Exposed Port |
|------------|-----------------------|--------------------|---------------|--------------|
| Auth       | `auth-deployment`     | `auth-service`     | `ClusterIP`   | 80 (internal only) |
| Users      | `users-deployment`    | `users-service`    | `LoadBalancer`| 8080         |
| Tasks      | `tasks-deployment`    | `tasks-service`    | `LoadBalancer`| 8000         |
| Frontend   | `frontend-deployment` | `frontend-service` | `LoadBalancer`| 80           |

---

## Networking Architecture

```
                        [ Browser ]
                            |
                     port 80 (HTTP)
                            |
                   [ frontend-service ]   ← LoadBalancer
                            |
                  [ frontend-deployment ]
                            |
               (API calls to users + tasks)
                    /                 \
         port 8080                  port 8000
              |                         |
    [ users-service ]          [ tasks-service ]  ← LoadBalancer
              |                         |
   [ users-deployment ]      [ tasks-deployment ]
              |                         |
              └──────────┬─────────────┘
                         |
              auth-service.default (port 80)
                         |
                [ auth-service ]   ← ClusterIP (internal)
                         |
               [ auth-deployment ]
```

> The Auth service is intentionally **not exposed externally**. Only Users and Tasks pods can reach it using Kubernetes internal DNS (`auth-service.default`).

---

## Running the Application

### Prerequisites

Make sure the following tools are installed and configured on your machine:

- [Docker](https://docs.docker.com/get-docker/) — to build and push container images
- [kubectl](https://kubernetes.io/docs/tasks/tools/) — Kubernetes CLI
- A running Kubernetes cluster — e.g. [Minikube](https://minikube.sigs.k8s.io/docs/start/), [Docker Desktop K8s](https://docs.docker.com/desktop/kubernetes/), or a cloud cluster (EKS / GKE / AKS)

---

### Option A — Use Pre-built Images (Quickest)

The manifests already reference pre-built public images (`academind/kub-demo-*:latest`). Just apply them directly:

```bash
# 1. Make sure your cluster is running
kubectl cluster-info

# 2. Deploy all services
kubectl apply -f kubernetes/

# 3. Verify all pods are running
kubectl get pods

# 4. Verify all services are created
kubectl get services
```

---

### Option B — Build & Push Your Own Images

If you want to build the images yourself, follow these steps for each microservice.

#### Step 1 — Build Docker images

```bash
# From the project root (48-Kubernetes-network-Coding/)

docker build -t <your-dockerhub-username>/kub-demo-auth:latest ./auth-api
docker build -t <your-dockerhub-username>/kub-demo-users:latest ./users-api
docker build -t <your-dockerhub-username>/kub-demo-tasks:latest ./tasks-api
docker build -t <your-dockerhub-username>/kub-demo-frontend:latest ./frontend
```

#### Step 2 — Push images to Docker Hub

```bash
docker push <your-dockerhub-username>/kub-demo-auth:latest
docker push <your-dockerhub-username>/kub-demo-users:latest
docker push <your-dockerhub-username>/kub-demo-tasks:latest
docker push <your-dockerhub-username>/kub-demo-frontend:latest
```

#### Step 3 — Update image references in the manifests

Replace `academind` with your Docker Hub username in each deployment file:

```bash
# Example for users-deployment.yaml
image: <your-dockerhub-username>/kub-demo-users:latest
```

#### Step 4 — Apply the manifests

```bash
kubectl apply -f kubernetes/
```

---

### Verify the Deployment

```bash
# Check all pods are in Running state
kubectl get pods

# Check all services and their external IPs / ports
kubectl get services

# View logs for a specific pod (replace <pod-name> with actual name from kubectl get pods)
kubectl logs <pod-name>
```

Expected output of `kubectl get services`:

```
NAME               TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)          AGE
auth-service       ClusterIP      10.x.x.x         <none>        80/TCP           Xs
frontend-service   LoadBalancer   10.x.x.x         <pending>     80:xxxxx/TCP     Xs
tasks-service      LoadBalancer   10.x.x.x         <pending>     8000:xxxxx/TCP   Xs
users-service      LoadBalancer   10.x.x.x         <pending>     8080:xxxxx/TCP   Xs
```

> On **Minikube**, `EXTERNAL-IP` stays `<pending>`. Use `minikube service <service-name>` to open the service in your browser.

```bash
# Minikube — open frontend in browser
minikube service frontend-service

# Minikube — get the URL for users-service
minikube service users-service --url
```

---

### Access the Application

| Service  | URL (cloud / Docker Desktop)          | Minikube command                          |
|----------|---------------------------------------|-------------------------------------------|
| Frontend | `http://<EXTERNAL-IP>:80`             | `minikube service frontend-service`       |
| Users    | `http://<EXTERNAL-IP>:8080`           | `minikube service users-service --url`    |
| Tasks    | `http://<EXTERNAL-IP>:8000`           | `minikube service tasks-service --url`    |
| Auth     | Internal only (`auth-service.default`)| Not accessible from outside the cluster   |

---

### Run Locally with Docker Compose (No Kubernetes)

To test the backend services locally without a Kubernetes cluster:

```bash
docker-compose up --build
```

This starts the **Auth**, **Users**, and **Tasks** services with their ports mapped:

| Service | Local URL                   |
|---------|-----------------------------|
| Users   | `http://localhost:8080`     |
| Tasks   | `http://localhost:8000`     |
| Auth    | Internal only (no port map) |

---

### Tear Down

```bash
# Remove all deployed Kubernetes resources
kubectl delete -f kubernetes/
```
