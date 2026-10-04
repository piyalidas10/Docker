# Docker Multi-Container Application

A full-stack application with **React** (frontend), **Node/Express** (backend), and **MongoDB** — each running in its own Docker container and communicating over a shared Docker network.

```
frontend (React SPA)  →  backend (Node/Express :80)  →  mongodb (MongoDB :27017)
```

---

## Project Structure

```
33-Docker-Multi-Container/
├── backend/
│   ├── app.js
│   ├── Dockerfile
│   ├── package.json
│   ├── .dockerignore
│   ├── logs/
│   └── models/
└── frontend/
    ├── src/
    ├── public/
    ├── Dockerfile
    ├── package.json
    └── .dockerignore
```

---

## Step-by-Step Docker Run Commands

Below are all commands in order, from pulling MongoDB to running all three containers on a shared network with volumes and bind mounts.

### 1. Create the Docker Network

```bash
docker network create goals-net
```

### 2. Run MongoDB

```bash
docker run --name mongodb \
  -e MONGO_INITDB_ROOT_USERNAME=root \
  -e MONGO_INITDB_ROOT_PASSWORD=secret \
  -v data:/data/db \
  --rm -d \
  --network goals-net \
  mongo
```

### 3. Build & Run the Node Backend

```bash
# Build the image
docker build -t goals-node ./backend

# Run the container
docker run --name goals-backend \
  -e MONGODB_USERNAME=root \
  -e MONGODB_PASSWORD=secret \
  -v logs:/app/logs \
  -v $(pwd)/backend:/app \
  -v /app/node_modules \
  --rm -d \
  --network goals-net \
  -p 80:80 \
  goals-node
```

> **Windows PowerShell:** replace `$(pwd)` with `${PWD}`.

### 4. Build & Run the React Frontend

```bash
# Build the image
docker build -t goals-react ./frontend

# Run the container
docker run --name goals-frontend \
  -v $(pwd)/frontend/src:/app/src \
  --rm -it \
  -p 3000:3000 \
  goals-react
```

> The frontend does **not** need to join `goals-net` — it talks to the backend via the host machine on `localhost:80`.

---

## 2. Dockerizing the MongoDB Service

MongoDB is run from the official `mongo` image — no custom Dockerfile needed.

```bash
docker run --name mongodb \
  -e MONGO_INITDB_ROOT_USERNAME=root \
  -e MONGO_INITDB_ROOT_PASSWORD=secret \
  --rm -d \
  mongo
```

| Flag | Purpose |
|------|---------|
| `--name mongodb` | Names the container so other containers can reference it |
| `-e MONGO_INITDB_ROOT_USERNAME` | Creates the root user on first start |
| `-e MONGO_INITDB_ROOT_PASSWORD` | Sets the root password |
| `--rm` | Removes the container when stopped |
| `-d` | Runs in detached (background) mode |

---

## 3. Dockerizing the Node App

**`backend/Dockerfile`**

```dockerfile
FROM node

WORKDIR /app

COPY package.json .

RUN npm install

COPY . .

EXPOSE 80

ENV MONGODB_USERNAME=root
ENV MONGODB_PASSWORD=secret

CMD ["npm", "start"]
```

The backend connects to MongoDB using the environment variables:

```js
// backend/app.js
mongoose.connect(
  `mongodb://${process.env.MONGODB_USERNAME}:${process.env.MONGODB_PASSWORD}@mongodb:27017/course-goals?authSource=admin`
);
```

Build and run:

```bash
docker build -t goals-node ./backend

docker run --name goals-backend \
  -e MONGODB_USERNAME=root \
  -e MONGODB_PASSWORD=secret \
  --rm -d \
  -p 80:80 \
  goals-node
```

---

## 4. Moving the React SPA into a Container

**`frontend/Dockerfile`**

```dockerfile
FROM node

WORKDIR /app

COPY package.json .

RUN npm install

COPY . .

EXPOSE 3000

CMD ["npm", "start"]
```

Build and run:

```bash
docker build -t goals-react ./frontend

docker run --name goals-frontend \
  --rm -it \
  -p 3000:3000 \
  goals-react
```

> `-it` is required for `react-scripts start` to keep the process alive inside a container.

---

## 5. Adding Docker Networks for Efficient Cross-Container Communication

Without a network, containers cannot reach each other by name. Creating a custom bridge network lets the backend resolve `mongodb` as a hostname directly.

```bash
# Create the network
docker network create goals-net

# Start MongoDB on the network
docker run --name mongodb \
  -e MONGO_INITDB_ROOT_USERNAME=root \
  -e MONGO_INITDB_ROOT_PASSWORD=secret \
  --rm -d \
  --network goals-net \
  mongo

# Start the backend on the same network
docker run --name goals-backend \
  -e MONGODB_USERNAME=root \
  -e MONGODB_PASSWORD=secret \
  --rm -d \
  --network goals-net \
  -p 80:80 \
  goals-node
```

Inside `app.js`, the connection string uses the container name `mongodb` as the hostname:

```
mongodb://root:secret@mongodb:27017/course-goals?authSource=admin
```

Docker's built-in DNS resolves `mongodb` to the correct container IP automatically.

---

## 6. Fixing MongoDB Authentication Errors

If you see `MongoError: Authentication failed`, the most common causes are:

1. **Missing `authSource=admin`** — the root user lives in the `admin` database.  
   The connection string must include `?authSource=admin`:
   ```
   mongodb://root:secret@mongodb:27017/course-goals?authSource=admin
   ```

2. **Stale volume data** — if the volume was created without credentials and you later added them, MongoDB ignores the new env vars.  
   Fix by removing the old volume:
   ```bash
   docker volume rm data
   ```
   Then restart the MongoDB container so it initialises fresh with the correct credentials.

3. **Wrong env var values** — ensure `-e MONGODB_USERNAME` and `-e MONGODB_PASSWORD` passed to the backend match `MONGO_INITDB_ROOT_USERNAME` / `MONGO_INITDB_ROOT_PASSWORD` passed to the MongoDB container.

---

## 7. Adding Data Persistence to MongoDB with Volumes

By default, stopping the MongoDB container destroys all stored data. A named volume persists data across container restarts.

```bash
docker run --name mongodb \
  -e MONGO_INITDB_ROOT_USERNAME=root \
  -e MONGO_INITDB_ROOT_PASSWORD=secret \
  -v data:/data/db \
  --rm -d \
  --network goals-net \
  mongo
```

| Flag | Purpose |
|------|---------|
| `-v data:/data/db` | Maps the named volume `data` to MongoDB's data directory |

Similarly, persist backend logs with a named volume:

```bash
docker run --name goals-backend \
  -v logs:/app/logs \
  ...
  goals-node
```

List and inspect volumes:

```bash
docker volume ls
docker volume inspect data
```

---

## 8. Volumes, Bind Mounts & Polishing for the NodeJS Container

Three volume types work together to give the Node backend both live code reloading and durable log storage.

### Volume types used

| Volume | Type | Purpose |
|--------|------|---------|
| `-v logs:/app/logs` | Named volume | Persists access logs across container restarts |
| `-v $(pwd)/backend:/app` | Bind mount | Mirrors your local source into the container for live edits |
| `-v /app/node_modules` | Anonymous volume | Locks in the container-installed `node_modules`; prevents the bind mount above from wiping them |

### Why the anonymous volume is needed

When `-v $(pwd)/backend:/app` mounts your local folder, Docker overlays the entire `/app` directory — including `node_modules`. Since your host likely has no `node_modules` (or a different platform build), this would break the app. The anonymous volume `-v /app/node_modules` takes priority over the bind mount for that specific path, preserving the container's own installed packages.

### Polished run command

```bash
docker run --name goals-backend \
  -e MONGODB_USERNAME=root \
  -e MONGODB_PASSWORD=secret \
  -v logs:/app/logs \
  -v $(pwd)/backend:/app \
  -v /app/node_modules \
  --rm -d \
  --network goals-net \
  -p 80:80 \
  goals-node
```

> **Windows PowerShell:** replace `$(pwd)` with `${PWD}`.

### nodemon for auto-restart

The `start` script in [`backend/package.json`](backend/package.json) uses **nodemon**:

```json
"start": "nodemon app.js"
```

Nodemon watches for file changes inside the container. Because the bind mount keeps the container's `/app` in sync with your local `backend/` folder, every file save on the host triggers an automatic server restart — no image rebuild required.

### `.dockerignore` for the backend

Ensure [`backend/.dockerignore`](backend/.dockerignore) excludes `node_modules` and logs so they are never copied into the image layer:

```
node_modules
logs
```

---

## 9. Live Source Code Updates for the React Container (with Bind Mounts)

To reflect source code changes in the browser immediately without rebuilding the image, mount only the local `src/` folder into the running container using a **bind mount**.

### Run command with bind mount

```bash
docker run --name goals-frontend \
  -v $(pwd)/frontend/src:/app/src \
  --rm -it \
  -p 3000:3000 \
  goals-react
```

> **Windows PowerShell:** replace `$(pwd)` with `${PWD}`.

### How it works

| Volume | Type | Purpose |
|--------|------|---------|
| `$(pwd)/frontend/src:/app/src` | Bind mount | Syncs your local `src/` edits into the container in real time |

- Only `src/` is mounted — `public/`, `package.json`, and `node_modules` remain from the image, keeping the install intact.
- `react-scripts start` (Create React App) includes a file watcher that detects changes inside `src/` and triggers a **Hot Module Replacement (HMR)** reload in the browser automatically.
- `-it` is required: `react-scripts start` needs an interactive TTY to stay alive inside a container.

### `.dockerignore` for the frontend

Ensure [`frontend/.dockerignore`](frontend/.dockerignore) excludes `node_modules` so the image build stays fast and clean:

```
node_modules
```

### Workflow summary

1. Start the container once with the bind mount above.
2. Edit any file under `frontend/src/` on your host.
3. The browser reloads automatically — no `docker build` or container restart needed.

---

## Quick Reference — All Commands

```bash
# Network
docker network create goals-net

# MongoDB
docker run --name mongodb \
  -e MONGO_INITDB_ROOT_USERNAME=root \
  -e MONGO_INITDB_ROOT_PASSWORD=secret \
  -v data:/data/db \
  --rm -d --network goals-net \
  mongo

# Backend
docker build -t goals-node ./backend
docker run --name goals-backend \
  -e MONGODB_USERNAME=root \
  -e MONGODB_PASSWORD=secret \
  -v logs:/app/logs \
  -v $(pwd)/backend:/app \
  -v /app/node_modules \
  --rm -d --network goals-net \
  -p 80:80 goals-node

# Frontend
docker build -t goals-react ./frontend
docker run --name goals-frontend \
  -v $(pwd)/frontend/src:/app/src \
  --rm -it -p 3000:3000 \
  goals-react
```
