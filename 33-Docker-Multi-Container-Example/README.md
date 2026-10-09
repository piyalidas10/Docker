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

This section adds two goals to the Node backend container:
1. **Persist log files** so they survive container tear-down.
2. **Live source code updates** so changes on the host are reflected inside the container automatically.

---

### Step 1 — Stop the running backend container

Before adding volumes, stop the existing container so it can be restarted with a new configuration:

```bash
docker stop goals-backend
```

---

### Step 2 — Add volumes for logs and live source code

Three `-v` flags are needed when restarting the container.

#### Volume 1 — Named volume for log files

```
-v logs:/app/logs
```

- `/app` is the `WORKDIR` defined in [`backend/Dockerfile`](backend/Dockerfile).
- The application writes logs to `/app/logs` inside the container.
- A **named volume** (`logs`) is used so the data survives container tear-down without needing to know the exact location on the host machine. (A bind mount would also work and would let you read the logs directly from the host.)

#### Volume 2 — Bind mount for live source code

```
-v /full/path/to/backend:/app
```

- Binds the entire local `backend/` folder to `/app` inside the container.
- Any source code change on the host is immediately reflected inside the container.
- Use the full absolute path on the host (right-click `app.js` → Copy Path, then remove the filename).

#### Volume 3 — Anonymous volume to protect `node_modules`

```
-v /app/node_modules
```

- The bind mount above overlays the entire `/app` directory — including `node_modules`.
- If the host machine has no `node_modules` (or a different platform build), this would wipe the container's installed dependencies and crash the app.
- **Longer container-internal paths take precedence** over shorter ones. So `/app/node_modules` (longer) wins over `/app` (shorter), keeping the container's own `node_modules` intact.

#### Full run command with all three volumes

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

---

### Step 3 — Add nodemon for automatic server restarts

Even with the bind mount in place, the running Node process loads code once at startup and does not react to file changes. To automatically restart the server when source files change, add **nodemon**.

#### Update `package.json`

In [`backend/package.json`](backend/package.json), add `nodemon` as a dev dependency and a `start` script:

```json
{
  "scripts": {
    "start": "nodemon app.js"
  },
  "devDependencies": {
    "nodemon": "^2.0.4"
  }
}
```

#### Update the Dockerfile

In [`backend/Dockerfile`](backend/Dockerfile), use `npm start` so nodemon is invoked:

```dockerfile
CMD ["npm", "start"]
```

#### Rebuild the image and restart the container

Because `package.json` and the Dockerfile changed, a rebuild is required:

```bash
docker build -t goals-node ./backend

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

#### Verify nodemon is running

```bash
docker logs goals-backend
```

You should see nodemon output in the logs. Now edit any `.js` file in the `backend/` folder (e.g., change a log message in [`backend/app.js`](backend/app.js)), save it, and re-run `docker logs goals-backend` — you will see the server restarted automatically.

---

### Step 4 — Use environment variables for MongoDB credentials

Instead of hard-coding the username and password in the connection string, inject them via environment variables so they can be changed at container startup without touching the source code.

#### Add `ENV` instructions to the Dockerfile

In [`backend/Dockerfile`](backend/Dockerfile):

```dockerfile
ENV MONGODB_USERNAME=root
ENV MONGODB_PASSWORD=secret
```

#### Use the variables in `app.js`

In [`backend/app.js`](backend/app.js), replace hard-coded values with `process.env`:

```js
mongoose.connect(
  `mongodb://${process.env.MONGODB_USERNAME}:${process.env.MONGODB_PASSWORD}@mongodb:27017/course-goals?authSource=admin`
);
```

The backtick syntax (template literal) is standard JavaScript — it has nothing to do with Docker.

#### Pass values at runtime with `-e`

```bash
docker run --name goals-backend \
  -e MONGODB_USERNAME=root \
  -e MONGODB_PASSWORD=secret \
  ...
  goals-node
```

- The `-e` flags override the default values set in the Dockerfile.
- If the defaults already match your MongoDB credentials, `-e` flags are optional.
- After changing the Dockerfile, **rebuild the image** before running the container.

---

### Step 5 — Add a `.dockerignore` file

A [`.dockerignore`](backend/.dockerignore) file prevents unnecessary files from being copied into the image during the `COPY . .` instruction.

```
node_modules
Dockerfile
.git
```

- `node_modules` — already installed inside the container via `RUN npm install`; copying them again from the host is redundant and slow.
- `Dockerfile` — no need to ship the build instructions inside the image itself.
- `.git` — version control metadata is not needed at runtime.

After adding `.dockerignore`, rebuild the image to apply the change:

```bash
docker build -t goals-node ./backend
```

---

### Summary — what we achieved

| Goal | Solution |
|------|----------|
| Persist log files | Named volume `-v logs:/app/logs` |
| Live source code updates | Bind mount `-v $(pwd)/backend:/app` |
| Protect container `node_modules` | Anonymous volume `-v /app/node_modules` |
| Auto-restart on code change | nodemon via `npm start` |
| Dynamic MongoDB credentials | `ENV` in Dockerfile + `process.env` in code |
| Lean image build | `.dockerignore` excludes `node_modules`, `Dockerfile`, `.git` |

---

## 9. Live Source Code Updates for the React Container (with Bind Mounts)

Now that the MongoDB and backend containers are polished, the final step is giving the React frontend container live source code updates — so any change to the source is automatically reflected in the running container without a rebuild.

---

### Step 1 — Stop the running frontend container

The frontend was started with `-it` (interactive mode), so it can be stopped with **Ctrl + C** directly in the terminal where it is running. This also removes the container (because `--rm` was passed).

> **Why `-it` matters here:** Unlike the Node backend container (started with `-d` detached), the frontend container was started interactively. `Ctrl + C` works because the terminal is attached. The backend requires `docker stop goals-backend` instead.

---

### Step 2 — Bind mount only the `src/` folder

The [`frontend/Dockerfile`](frontend/Dockerfile) sets `WORKDIR /app`, so the entire application lives at `/app` inside the container. We only need to bind the `src/` folder — that is where all React component code lives and where changes happen during development.

```bash
docker run --name goals-frontend \
  -v $(pwd)/frontend/src:/app/src \
  --rm -it \
  -p 3000:3000 \
  goals-react
```

> **Windows PowerShell:** replace `$(pwd)` with `${PWD}`.

| Flag | Purpose |
|------|---------|
| `-v $(pwd)/frontend/src:/app/src` | Bind mount: syncs local `src/` into `/app/src` inside the container |
| `--rm` | Removes the container automatically when stopped |
| `-it` | Required — `react-scripts start` needs an interactive TTY to keep the process alive |
| `-p 3000:3000` | Exposes the CRA dev server to the host on port 3000 |

**Why only `src/` and not the whole folder?**
Binding the entire `frontend/` folder would overlay `node_modules` inside the container with the host's copy (or the absence of one), breaking the dev server — the same problem as with the Node backend. Since we only need live updates for component code, binding `src/` alone is sufficient. `public/`, `package.json`, and `node_modules` stay untouched from the image.

**Why no anonymous volume for `node_modules`?**
Unlike the Node backend where we bound the full `/app` directory, here we only bind `/app/src` — a sub-path that does not include `node_modules`. Docker never touches `/app/node_modules`, so no anonymous volume is needed.

---

### Step 3 — Verify live reload works

The Create React App development server (`react-scripts start`) has a built-in file watcher. It monitors the `src/` directory and automatically recompiles and reloads the browser when any file changes.

To test this:

1. Start the container with the command above.
2. Open [`frontend/src/components/goals/CourseGoals.js`](frontend/src/components/goals/CourseGoals.js) on your host machine.
3. Add or edit any JSX, e.g. add an `<h2>` tag, and save the file.
4. Watch the terminal — you will see `Compiled successfully.` printed by the dev server inside the container.
5. Reload the browser — the change appears immediately.

No `docker build`, no container restart required.

---

### Step 4 — Windows / WSL 2 note

If you are on **Windows with WSL 2** and file changes are **not** being picked up by the dev server inside the container:

- This is a known limitation of the Windows file system and Docker's inotify watch mechanism.
- **Solution:** Create and work on your project inside the **Linux file system** (e.g. `~/projects/`) provided by WSL 2, not the Windows file system (`/mnt/c/...`).
- Changes made to files inside the Linux file system are correctly propagated to the Docker container and picked up by the file watcher.

---

### Step 5 — Add a `.dockerignore` to speed up image builds

Without a `.dockerignore`, the `COPY . .` instruction in [`frontend/Dockerfile`](frontend/Dockerfile) copies the entire `frontend/` folder into the image — including the local `node_modules` folder if it exists on the host. This causes two problems:

1. **Slow builds** — copying thousands of dependency files takes a long time.
2. **Potentially outdated dependencies** — the host's `node_modules` may not match what `RUN npm install` installed inside the container, risking subtle version mismatches.

Create [`frontend/.dockerignore`](frontend/.dockerignore) with:

```
node_modules
Dockerfile
.git
```

Then rebuild the image — it will be noticeably faster:

```bash
docker build -t goals-react ./frontend
```

After the rebuild, start the container again with the same bind mount command and everything continues to work.

---

### Summary — what we achieved

| Goal | Solution |
|------|----------|
| Live source code updates | Bind mount `-v $(pwd)/frontend/src:/app/src` |
| No broken `node_modules` | Only `src/` is mounted, not the full folder |
| Auto browser reload | Built-in CRA file watcher (`react-scripts start`) |
| Faster image builds | `.dockerignore` excludes `node_modules`, `Dockerfile`, `.git` |
| Windows WSL 2 compatibility | Work in the Linux file system, not `/mnt/c/...` |

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
