# Docker Compose Example

This project demonstrates how to replace a set of individual `docker build` and `docker run` commands with a single **Docker Compose** configuration file, managing all three containers — MongoDB, Node/Express backend, and React frontend — with one command.

```
frontend (React SPA :3000)  →  backend (Node/Express :80)  →  mongodb (MongoDB :27017)
```

---

## What is Docker Compose?

Docker Compose is a tool that lets you replace multiple `docker build` and `docker run` commands with:

1. **One configuration file** (`docker-compose.yaml`) — written in a clearly defined YAML format that can be shared with anyone.
2. **One orchestration command** — to build all necessary images and start all containers at once.
3. **One command to stop everything** — bringing down the entire multi-container application cleanly.

### What Docker Compose is NOT

| Misconception | Reality |
|---|---|
| Replaces Dockerfiles | ❌ It works **together** with Dockerfiles, not instead of them |
| Replaces images or containers | ❌ It just makes launching them easier |
| Suited for multiple hosts | ❌ Its strength is managing multiple containers on **one and the same host** |

> Docker Compose is great for development, but also used beyond development. It shines most in multi-container setups, though it works fine for single-container apps too.

---

## Project Structure

```
34-Docker-Compose-Example/
├── docker-compose.yaml       ← the single source of truth
├── docker-commands.txt       ← equivalent manual docker commands (for reference)
├── env/
│   ├── mongo.env             ← MongoDB credentials
│   └── backend.env           ← Node backend credentials
├── backend/
│   ├── app.js
│   ├── Dockerfile
│   ├── package.json
│   ├── .dockerignore
│   └── models/
└── frontend/
    ├── src/
    ├── public/
    ├── Dockerfile
    ├── package.json
    └── .dockerignore
```

---

## The Docker Compose File

**[`docker-compose.yaml`](docker-compose.yaml)** is the heart of this setup. Every key in the file maps directly to a flag you would otherwise pass to `docker run`.

```yaml
version: "3.8"
services:
  mongodb:
    image: 'mongo'
    volumes:
      - data:/data/db
    env_file:
      - ./env/mongo.env
  backend:
    build: ./backend
    ports:
      - '80:80'
    volumes:
      - logs:/app/logs
      - ./backend:/app
      - /app/node_modules
    env_file:
      - ./env/backend.env
    depends_on:
      - mongodb
  frontend:
    build: ./frontend
    ports:
      - '3000:3000'
    volumes:
      - ./frontend/src:/app/src
    stdin_open: true
    tty: true
    depends_on:
      - backend

volumes:
  data:
  logs:
```

---

## Key Concepts Explained

### Services = Containers

Every entry under `services:` is one container. The service name (e.g. `mongodb`, `backend`, `frontend`) also becomes the **container hostname** on the automatically created Docker network — so `backend/app.js` can reach MongoDB at the hostname `mongodb` without any manual `docker network create`.

### `image` vs `build`

| Key | When to use | Example |
|-----|-------------|---------|
| `image` | Use an existing image from Docker Hub | `image: 'mongo'` |
| `build` | Build a custom image from a local Dockerfile | `build: ./backend` |

The `build` key can also be expanded for more control:

```yaml
build:
  context: ./backend
  dockerfile: Dockerfile
  args:
    some-arg: 1
```

### `volumes`

Three volume types are used across the services:

| Declaration | Type | Purpose |
|---|---|---|
| `data:/data/db` | Named volume | Persists MongoDB data across restarts |
| `logs:/app/logs` | Named volume | Persists backend log files |
| `./backend:/app` | Bind mount | Live source code updates for the Node backend |
| `/app/node_modules` | Anonymous volume | Protects container `node_modules` from host overlay |
| `./frontend/src:/app/src` | Bind mount | Live source code updates for the React frontend |

Named volumes used in services must be **declared at the top level** under `volumes:` at the bottom of the file:

```yaml
volumes:
  data:
  logs:
```

### `env_file`

Instead of listing environment variables inline, an external `.env` file is referenced:

```yaml
env_file:
  - ./env/mongo.env
```

**[`env/mongo.env`](env/mongo.env)**
```
MONGO_INITDB_ROOT_USERNAME=max
MONGO_INITDB_ROOT_PASSWORD=secret
```

**[`env/backend.env`](env/backend.env)**
```
MONGODB_USERNAME=max
MONGODB_PASSWORD=secret
```

These values are injected into the container at runtime, equivalent to passing `-e KEY=VALUE` flags to `docker run`.

> Alternatively, environment variables can be listed inline using `environment:`:
> ```yaml
> environment:
>   MONGO_INITDB_ROOT_USERNAME: max
>   MONGO_INITDB_ROOT_PASSWORD: secret
> ```

### `depends_on`

Controls startup order. `backend` waits for `mongodb` to start before it is launched, and `frontend` waits for `backend`.

```yaml
depends_on:
  - mongodb
```

> `depends_on` ensures the **container starts**, not that the service inside it is fully ready. For production-grade readiness checks, health checks are needed.

### `stdin_open` and `tty`

Required for the React frontend container because `react-scripts start` needs an interactive terminal to keep the process alive — equivalent to `-it` in `docker run`:

```yaml
stdin_open: true   # equivalent to -i (stdin open)
tty: true          # equivalent to -t (allocate TTY)
```

### Automatic networking

Docker Compose automatically creates a **shared network** for all services in the file. No `docker network create` command is needed. Each service is reachable by its service name from any other service in the same Compose file.

---

## Equivalent Manual Commands (Without Compose)

The [`docker-commands.txt`](docker-commands.txt) file shows all the individual commands that this single `docker-compose.yaml` replaces:

```bash
# 1. Create network
docker network create goals-net

# 2. Run MongoDB
docker run --name mongodb \
  -e MONGO_INITDB_ROOT_USERNAME=max \
  -e MONGO_INITDB_ROOT_PASSWORD=secret \
  -v data:/data/db \
  --rm -d \
  --network goals-net \
  mongo

# 3. Build & run Node backend
docker build -t goals-node ./backend
docker run --name goals-backend \
  -e MONGODB_USERNAME=max \
  -e MONGODB_PASSWORD=secret \
  -v logs:/app/logs \
  -v $(pwd)/backend:/app \
  -v /app/node_modules \
  --rm -d \
  --network goals-net \
  -p 80:80 \
  goals-node

# 4. Build & run React frontend
docker build -t goals-react ./frontend
docker run --name goals-frontend \
  -v $(pwd)/frontend/src:/app/src \
  --rm -it \
  -p 3000:3000 \
  goals-react

# 5. Stop everything
docker stop mongodb goals-backend goals-frontend
```

With Docker Compose, all of the above becomes just two commands (see below).

---

## Docker Compose Commands

### Start all containers (build images if needed)

```bash
docker compose up
```

- Builds images for services that use `build:` (if not already built).
- Creates and starts all containers.
- Creates the shared network automatically.
- Creates named volumes automatically.

Run in **detached mode** (background):

```bash
docker compose up -d
```

Force a **rebuild** of all images:

```bash
docker compose up --build
```

### Stop and remove all containers

```bash
docker compose down
```

- Stops and removes all containers defined in the file.
- Removes the automatically created network.
- **Does not** remove named volumes by default (data is preserved).

To also remove named volumes:

```bash
docker compose down -v
```

### Other useful commands

```bash
# View logs for all services
docker compose logs

# View running services
docker compose ps

# Rebuild a specific service image
docker compose build backend
```

---

## Summary

| Without Compose | With Compose |
|---|---|
| `docker network create goals-net` | Automatic |
| 3 × `docker build` | `docker compose up --build` |
| 3 × `docker run` with all flags | `docker compose up` |
| `docker stop mongodb goals-backend goals-frontend` | `docker compose down` |
| Manage credentials inline in commands | `env_file` pointing to `.env` files |
| Manually coordinate startup order | `depends_on` |
