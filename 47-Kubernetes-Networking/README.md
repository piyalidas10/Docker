# Kubernetes Networking

---

## Module Overview

This module is about **connecting services** — how containers and Pods communicate with each other inside a Kubernetes cluster, and how they are exposed to the outside world.

The focus is on **container and service interaction**, not data storage.

---

## The Demo Application

The demo application consists of **three independent Node.js back-end APIs** that work together. Each runs in its own container.

```
┌─────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                 │
│                                                     │
│   Pod 1                          Pod 2              │
│   ┌────────────────────────┐     ┌───────────────┐  │
│   │  users-api  (port 8080)│     │  tasks-api    │  │
│   │       │                │     │  (port 8000)  │  │
│   │       │ pod-internal   │     │       │       │  │
│   │       ▼                │     │       │       │  │
│   │  auth-api  (internal)  │◄────┼───────┘       │  │
│   └────────────────────────┘     └───────────────┘  │
│           ▲                              ▲           │
└───────────┼──────────────────────────────┼───────────┘
            │                              │
        Outside world                  Outside world
       (users-api only)              (tasks-api only)
```

---

## The Three APIs

### 1. `auth-api`

- Handles **token generation** and **token verification**
- Used internally — **not directly reachable from outside the cluster**
- Only other containers (users-api, tasks-api) communicate with it
- Runs in the **same Pod as users-api** (at least initially) — Pod-internal communication

### 2. `users-api`

- Handles **user creation** and **user login**
- Operates in dummy mode — no database, no file storage
- On login: reaches out to `auth-api` to generate a token, returns it in the response
- **Exposed publicly** — reachable from outside the cluster on port `8080`

### 3. `tasks-api`

- Returns a list of stored tasks and stores new tasks
- Uses a file as dummy storage (not a database — storage is not the focus)
- On task requests: receives a token and reaches out to `auth-api` to **verify** it
- **Exposed publicly** — reachable from outside the cluster on port `8000`

---

## Communication Patterns

| From | To | Type | Why |
|---|---|---|---|
| Outside world | `users-api` | External | Users log in / register |
| Outside world | `tasks-api` | External | Users fetch / create tasks |
| `users-api` | `auth-api` | Pod-internal | Generate token on login |
| `tasks-api` | `auth-api` | Cross-Pod | Verify token on task request |
| Outside world | `auth-api` | ❌ Not allowed | Auth is an internal service only |

---

## Running Locally with Docker Compose (Before Kubernetes)

The project includes a `Dockerfile` per service and a `docker-compose.yaml` for local testing.

### Start all three containers

```bash
docker compose up -d --build
```

### Test the endpoints

| Request | Endpoint | Expected result |
|---|---|---|
| `POST /login` with `{ email, password }` | `localhost:8080/login` | Returns a token |
| `GET /tasks` | `localhost:8000/tasks` | Returns stored tasks (empty initially) |
| `POST /tasks` with `{ text, title }` | `localhost:8000/tasks` | Stores a task |
| `GET /tasks` after POST | `localhost:8000/tasks` | Returns the stored task |
| Direct request to `auth-api` | — | ❌ Fails — not publicly exposed |

> Data is **not persisted** between `docker compose down` / `up` cycles. No volumes are used — this is intentional, as the focus is on service communication, not storage.

### Stop and remove containers

```bash
docker compose down
```

---

## Starting Point for Kubernetes

Rather than migrating all three services at once, the module starts simple and evolves:

```
Phase 1 — users-api only
    └── No auth-api communication yet
    └── Verify users-api handles incoming requests correctly

Phase 2 — users-api + auth-api in the same Pod
    └── Pod-internal communication between users-api and auth-api

Phase 3 — tasks-api in a separate Pod
    └── Cross-Pod communication: tasks-api → auth-api
    └── Both Pods exposed externally via Services
```

> The goal is to understand how Kubernetes handles **different types of networking** — Pod-internal, cluster-internal (Pod-to-Pod), and external — and when to use each.

---

## Key Networking Concepts Covered in This Module

| Concept | Description |
|---|---|
| **Pod-internal communication** | Containers in the same Pod communicate via `localhost` |
| **Cluster-internal communication** | Pods communicate via Kubernetes Services using DNS names |
| **External communication** | Services of type `LoadBalancer` or `NodePort` expose Pods outside the cluster |
| **Service discovery** | Kubernetes injects environment variables and DNS entries so Pods can find each other |

---

## Pod-Internal Communication

### What is it?

When **two containers run inside the same Pod**, they share the same network namespace. This means they can reach each other using **`localhost`** as the address — no Service, no DNS name, no IP needed.

> **Key rule:** `localhost` only works between containers **within the same Pod**. It does not work across Pods.

### How it works

```
┌──────────────────────────────────┐
│              Pod                 │
│                                  │
│  ┌─────────────┐  localhost  ┌──────────────┐
│  │  users-api  │ ──────────► │   auth-api   │
│  │  port 8080  │             │   port 80    │
│  └─────────────┘             └──────────────┘
│                                  │
└──────────────────────────────────┘
         ▲
    Outside world
  (users-api only)
```

- Both containers are **in the same Pod**
- `users-api` sends requests to `auth-api` using `localhost`
- `auth-api` is **not exposed outside** the Pod — it is entirely internal

### Setting it up in `users-deployment.yaml`

Both containers must be defined in the **same Pod spec** under a single Deployment, and `AUTH_ADDRESS` must be set to `"localhost"`:

```yaml
spec:
  containers:
    - name: users
      image: academind/kub-demo-users:latest
      env:
        - name: AUTH_ADDRESS
          value: "localhost"
    - name: auth
      image: academind/kub-demo-auth:latest
```

- Both `users` and `auth` containers are listed under the **same `containers` array**
- The `users-api` code reads `AUTH_ADDRESS` and uses it to call the `auth-api`

### Applying and verifying

```bash
# Apply the updated deployment
kubectl apply -f kubernetes/users-deployment.yaml

# Watch pods — look for 2/2 (two containers running in one pod)
kubectl get pods
```

Expected output:

```
NAME                                READY   STATUS    RESTARTS   AGE
users-deployment-xxxxxx-xxxxx       2/2     Running   0          10s
```

> **`2/2`** means two containers are running inside one Pod — both `users` and `auth` are up.

### Testing with Postman or curl

**Sign Up**

```
POST http://<minikube-ip>:<port>/signup
Content-Type: application/json

{ "email": "test@test.com", "password": "testers" }
```

Expected response: `"User created"`

**Login**

```
POST http://<minikube-ip>:<port>/login
Content-Type: application/json

{ "email": "test@test.com", "password": "testers" }
```

Expected response: `{ "token": "abc" }`

> The token value `"abc"` is generated inside `auth-app.js` — **not** inside the users service. Getting this response back proves that `users-api` successfully reached `auth-api` via `localhost` inside the Pod.

### Why `localhost` works here

| Reason | Explanation |
|--------|-------------|
| Shared network namespace | All containers in a Pod share the same network stack |
| Same IP address | Every container in a Pod has the same Pod IP |
| Port-based separation | Each container listens on a different port — no conflicts |
| No Service needed | Pod-internal traffic never leaves the Pod |

### Important limitation

`localhost` **only works inside the same Pod**. If `auth-api` is moved to a separate Pod, you must switch to a Kubernetes Service DNS name instead.

| Scenario | Address to use |
|----------|----------------|
| Both containers in the **same Pod** | `localhost` |
| Containers in **different Pods** | Kubernetes Service DNS name (e.g. `auth-service.default`) |

---

## Migrating users-api to Talk to auth-api in Kubernetes

### Step 1 — Use an environment variable for the auth address in `users-app.js`

In Docker Compose, the auth address was hardcoded as the service name `auth`. To keep the code flexible across environments (Docker Compose vs Kubernetes), replace the hardcoded string with an environment variable using JavaScript template literals:

```js
// Before (Docker Compose hardcoded service name)
`http://auth/...`

// After (flexible via environment variable)
`http://${process.env.AUTH_ADDRESS}/...`
```

Apply this change everywhere in `users-app.js` that calls the auth API — both the signup and login route handlers.

### Step 2 — Set `AUTH_ADDRESS` in `docker-compose.yaml`

For Docker Compose, set `AUTH_ADDRESS` to the Compose service name `auth`:

```yaml
services:
  users:
    build: ./users-api
    environment:
      AUTH_ADDRESS: auth
    ports:
      - "8080:8080"
```

### Step 3 — Build and push the auth-api image

```bash
# Navigate to the auth-api folder
cd auth-api

# Build the image (use your own Docker Hub username)
docker build -t <your-dockerhub-username>/kub-demo-auth:latest .

# Push to Docker Hub
docker push <your-dockerhub-username>/kub-demo-auth:latest
```

### Step 4 — Add the auth container to `users-deployment.yaml`

Do **not** create a new Deployment for auth. Instead, add it as a second container inside the existing `users-deployment`. Both containers then run in the **same Pod**, enabling pod-internal communication via `localhost`.

```yaml
spec:
  containers:
    - name: users
      image: <your-dockerhub-username>/kub-demo-users:latest
      env:
        - name: AUTH_ADDRESS
          value: "localhost"
    - name: auth
      image: <your-dockerhub-username>/kub-demo-auth:latest
```

> **Why not a new Deployment?** Each Deployment manages one kind of Pod. Creating a second Deployment would put `auth-api` in a separate Pod — meaning `localhost` would not work. Both containers must share the same Pod spec.

> **Why `latest` tag?** Kubernetes re-fetches the image when the deployment config changes, ensuring the newest code is always used.

### Step 5 — Do NOT expose the auth container port in the Service

The `users-service.yaml` should only expose the users-api port (`8080`). The auth-api port (`80`) must **not** be added to the Service — it should only be reachable pod-internally, not from outside.

```yaml
# users-service.yaml — only expose users-api port
ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
# auth-api port (80) is intentionally NOT listed here
```

### Step 6 — Rebuild and push the updated users-api image

The `users-app.js` source code changed (now uses `AUTH_ADDRESS` env var), so rebuild and push:

```bash
cd users-api
docker build -t <your-dockerhub-username>/kub-demo-users:latest .
docker push <your-dockerhub-username>/kub-demo-users:latest
```

### Step 7 — Apply the updated deployment

```bash
kubectl apply -f kubernetes/users-deployment.yaml
```

Kubernetes will terminate the old Pod and create a new one with both containers:

```bash
kubectl get pods
# NAME                                READY   STATUS    RESTARTS   AGE
# users-deployment-xxxxxx-xxxxx       2/2     Running   0          10s
```

`2/2` confirms both the `users` and `auth` containers are running in the same Pod.

---

## Does Each Pod Have Its Own IP?

Yes — every Pod in a Kubernetes cluster is assigned its **own unique IP address**. This is a core part of the Kubernetes networking model.

### Key Rules

| Rule | Detail |
|------|--------|
| Each Pod gets a **unique cluster-wide IP** | No two Pods share an IP, even across different nodes |
| Containers **inside the same Pod** share that IP | They communicate via `localhost`, differentiated only by port |
| Pods communicate with each other using **Pod IPs or Service DNS names** | Direct Pod-to-Pod traffic is possible but fragile (IPs change on restart) |
| Pod IPs are **ephemeral** | When a Pod is deleted and recreated, it gets a **new IP** |

### Visual Breakdown

```
Node
├── Pod A  →  IP: 10.0.0.4
│   ├── container: users-api  (port 8080)
│   └── container: auth-api   (port 80)   ← share 10.0.0.4, talk via localhost
│
└── Pod B  →  IP: 10.0.0.7
    └── container: tasks-api  (port 8000) ← different IP entirely
```

- `users-api` and `auth-api` are in **Pod A** → same IP → use `localhost`
- `tasks-api` is in **Pod B** → different IP → must use a **Service** to reach auth

### Why You Should Never Hardcode Pod IPs

Because Pod IPs change every time a Pod restarts or is rescheduled, hardcoding them is fragile:

```yaml
# ❌ Fragile — IP changes if Pod restarts
value: "10.0.0.4"

# ✅ Stable — Kubernetes DNS always resolves to the right Pod
value: "auth-service.default"
```

This is exactly why the `users-deployment.yaml` in this project moved from a hardcoded ClusterIP to the DNS name `auth-service.default`.

### Services Solve the Ephemeral IP Problem

A **Service** gets a **stable ClusterIP** (virtual IP) that never changes, and Kubernetes keeps it pointed at the correct Pod(s) regardless of restarts:

```
tasks-api  →  auth-service (stable ClusterIP: 10.99.x.x)  →  auth Pod (IP changes freely)
```

So the answer is: **yes, each Pod has its own IP**, but you should rely on **Service DNS names**, not Pod IPs, for any inter-Pod communication.
