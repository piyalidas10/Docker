# Imperative Approach — Kubernetes Objects

The **imperative approach** means running `kubectl` commands directly to create, update, and delete resources — instead of writing YAML files.

---

## The App

| File | Purpose |
|---|---|
| [`app.js`](./app.js) | Express server on port `8080` — `/` returns a greeting, `/error` calls `process.exit(1)` to simulate a crash |
| [`Dockerfile`](./Dockerfile) | Builds the Node.js app into a container image (`node:14-alpine`) |

---

## 1. Build & Push the Image

```sh
# Build the image
docker build -t academind/kub-first-app .

# Push to Docker Hub (must be logged in)
docker push academind/kub-first-app
```

> Kubernetes pulls the image from a registry — it cannot use a locally-built image directly (unless using minikube's Docker daemon).

---

## 2. Create a Deployment

```sh
kubectl create deployment second-app-deployment --image=academind/kub-first-app:2
```

- `create deployment` — creates a Deployment object that manages Pods
- `--image` — the container image to run (tag `:2` for version 2)
- Kubernetes automatically keeps **1 replica** running by default

Verify:

```sh
kubectl get deployments
kubectl get pods
```

---

## 3. Expose the Deployment (Create a Service)

A Deployment is not reachable from outside the cluster on its own. You need a **Service**:

```sh
kubectl expose deployment second-app-deployment \
  --type=LoadBalancer \
  --port=80 \
  --target-port=8080 \
  --name=backend
```

| Flag | Meaning |
|---|---|
| `--type=LoadBalancer` | Exposes the app externally via a cloud load balancer |
| `--port=80` | Port the Service listens on externally |
| `--target-port=8080` | Port the container listens on internally |
| `--name=backend` | Name of the Service resource |

Verify:

```sh
kubectl get services
```

On **minikube**, get the accessible URL:

```sh
minikube service backend
```

---

## 4. Scale Replicas

```sh
# Scale up to 3 pods
kubectl scale deployment/second-app-deployment --replicas=3

# Scale back down to 1
kubectl scale deployment/second-app-deployment --replicas=1
```

Watch Pods start/terminate:

```sh
kubectl get pods
```

---

## 5. Update the Container Image

```sh
kubectl set image deployment/second-app-deployment \
  second-node=academind/kub-first-app:1
```

- `second-node` — the container name inside the Pod (as defined in the Pod spec)
- `=academind/kub-first-app:1` — the new image to roll out

Kubernetes performs a **rolling update** — old Pods are replaced with new ones, zero downtime.

Check rollout status:

```sh
kubectl rollout status deployment/second-app-deployment
```

---

## 6. Rollback a Deployment

```sh
# Undo the last rollout
kubectl rollout undo deployment/second-app-deployment

# Roll back to a specific revision
kubectl rollout undo deployment/second-app-deployment --to-revision=1
```

View rollout history:

```sh
kubectl rollout history deployment/second-app-deployment

# Inspect a specific revision
kubectl rollout history deployment/second-app-deployment --revision=1
```

---

## 7. Delete Resources

```sh
# Delete by resource name
kubectl delete deployment second-app-deployment
kubectl delete service backend

# Delete both in one command
kubectl delete deployment second-app-deployment service backend
```

---

## Imperative vs Declarative — Quick Comparison

| | Imperative | Declarative |
|---|---|---|
| How | `kubectl` commands | YAML files + `kubectl apply` |
| Update | Run a new command with new values | Edit the file, re-apply |
| History/tracking | No built-in history | Version-control the YAML files |
| Repeatability | Must re-type full commands | Re-apply the same files |
| Best for | Quick tasks, one-off changes | Production, team environments |

> The imperative approach is useful for quick experimentation. For anything that needs to be repeatable or tracked, prefer the **declarative approach** (see [`README.md`](./README.md)).
