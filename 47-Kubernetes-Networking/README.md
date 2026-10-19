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
