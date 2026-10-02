# Kubernetes — Deploying a Node.js Application

## Folder Structure

```
32-Kubernetes-deployment/
├── app/
│   ├── app.js            ← Node.js application
│   └── package.json      ← Node.js dependencies
├── Dockerfile            ← Container image definition
├── deployment.yaml       ← Kubernetes Deployment manifest
├── service.yaml          ← Kubernetes Service manifest
├── configmap.yaml        ← Kubernetes ConfigMap (environment config)
└── README.md             ← This file
```

---

## Architecture Diagram

```
  Developer Machine
  ─────────────────
  kubectl apply -f deployment.yaml
  kubectl apply -f service.yaml
         │
         ▼
┌────────────────────────────────────────────────────────────────┐
│                          CLUSTER                               │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    MASTER NODE                           │  │
│  │  ┌─────────────┐  ┌───────────┐  ┌──────────────────┐  │  │
│  │  │  API Server │  │ Scheduler │  │ Controller Mgr   │  │  │
│  │  └──────┬──────┘  └─────┬─────┘  └────────┬─────────┘  │  │
│  │         │               │                 │             │  │
│  └─────────┼───────────────┼─────────────────┼─────────────┘  │
│            │ schedules     │ picks node      │ reconciles      │
│            ▼               ▼                 ▼                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   WORKER NODE                            │  │
│  │                                                          │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │               SERVICE (NodePort/LB)                │  │  │
│  │  │          Stable IP · Port 80 → 3000                │  │  │
│  │  └───────────────────────┬────────────────────────────┘  │  │
│  │                          │ routes traffic                │  │
│  │          ┌───────────────┼───────────────┐               │  │
│  │          ▼               ▼               ▼               │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐     │  │
│  │  │    POD 1     │ │    POD 2     │ │    POD 3     │     │  │
│  │  │ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ │     │  │
│  │  │ │ node-app │ │ │ │ node-app │ │ │ │ node-app │ │     │  │
│  │  │ │:3000     │ │ │ │:3000     │ │ │ │:3000     │ │     │  │
│  │  │ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ │     │  │
│  │  └──────────────┘ └──────────────┘ └──────────────┘     │  │
│  │          ▲               ▲               ▲               │  │
│  │          └───────────────┴───────────────┘               │  │
│  │                   ConfigMap (env vars)                   │  │
│  │                   Docker image pulled from               │  │
│  │                   registry (Docker Hub / ECR)            │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
         ▲
         │  external traffic (browser / API client)
         │  http://<node-ip>:30080  or  LoadBalancer IP
```

---

## Step-by-Step Deployment Process

### Step 1 — Write the Node.js Application

Create a simple HTTP server in [`app/app.js`](app/app.js) that listens on port **3000**.

See [`app/app.js`](app/app.js) and [`app/package.json`](app/package.json).

---

### Step 2 — Create a Dockerfile

The [`Dockerfile`](Dockerfile) defines how to build a container image for the Node.js app.

Key steps inside the Dockerfile:
1. Start from the official `node:18-alpine` base image.
2. Set the working directory to `/app`.
3. Copy `package.json` and run `npm install`.
4. Copy the rest of the app source code.
5. Expose port `3000`.
6. Set the start command to `node app.js`.

---

### Step 3 — Build and Push the Docker Image

```bash
# Build the image
docker build -t <your-dockerhub-username>/node-app:latest .

# Push to Docker Hub (or ECR / GCR / ACR)
docker push <your-dockerhub-username>/node-app:latest
```

> Kubernetes pulls the image from this registry when creating Pods. Update the image name in `deployment.yaml` to match.

---

### Step 4 — Apply the ConfigMap

The [`configmap.yaml`](configmap.yaml) stores environment variables separately from the container image, so config can change without rebuilding the image.

```bash
kubectl apply -f configmap.yaml
```

---

### Step 5 — Apply the Deployment

The [`deployment.yaml`](deployment.yaml) tells Kubernetes:
- Which container image to run.
- How many Pod replicas to maintain (3 in this example).
- Which environment variables (from the ConfigMap) to inject.
- Resource requests and limits for each Pod.

```bash
kubectl apply -f deployment.yaml
```

Verify the Pods are running:
```bash
kubectl get pods
```

Expected output:
```
NAME                        READY   STATUS    RESTARTS   AGE
node-app-6d7b9c8f4-abc12    1/1     Running   0          30s
node-app-6d7b9c8f4-def34    1/1     Running   0          30s
node-app-6d7b9c8f4-ghi56    1/1     Running   0          30s
```

---

### Step 6 — Apply the Service

The [`service.yaml`](service.yaml) exposes the Pods to external traffic via a stable IP and port.

```bash
kubectl apply -f service.yaml
```

Verify the Service:
```bash
kubectl get services
```

Expected output:
```
NAME           TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
node-app-svc   NodePort   10.100.200.10   <none>        80:30080/TCP   15s
```

Access the app at: `http://<node-ip>:30080`

---

### Step 7 — Verify the Full Deployment

```bash
# Check all resources
kubectl get all

# Describe a Pod for details
kubectl describe pod <pod-name>

# View logs from a Pod
kubectl logs <pod-name>

# Scale the deployment (e.g. to 5 replicas)
kubectl scale deployment node-app --replicas=5
```

---

### Step 8 — Update the Application (Rolling Update)

```bash
# Build and push a new image version
docker build -t <your-dockerhub-username>/node-app:v2 .
docker push <your-dockerhub-username>/node-app:v2

# Update the deployment image — triggers a rolling update
kubectl set image deployment/node-app node-app=<your-dockerhub-username>/node-app:v2

# Watch the rollout
kubectl rollout status deployment/node-app

# Rollback if needed
kubectl rollout undo deployment/node-app
```

---

### Step 9 — Tear Down

```bash
kubectl delete -f service.yaml
kubectl delete -f deployment.yaml
kubectl delete -f configmap.yaml
```

---

## Summary

| Step | Action | Command / File |
|---|---|---|
| 1 | Write app | `app/app.js`, `app/package.json` |
| 2 | Containerise | `Dockerfile` |
| 3 | Build & push image | `docker build` + `docker push` |
| 4 | Apply config | `kubectl apply -f configmap.yaml` |
| 5 | Deploy Pods | `kubectl apply -f deployment.yaml` |
| 6 | Expose via Service | `kubectl apply -f service.yaml` |
| 7 | Verify | `kubectl get all` |
| 8 | Update | `kubectl set image` + `kubectl rollout` |
| 9 | Tear down | `kubectl delete -f *.yaml` |
