# 04 — Bind Mounts

**Bind mounts** map a file or directory on the **host machine** directly into a container. Unlike volumes, the host path is fully controlled by you — not Docker.

> [!NOTE]
> you cannot add a new bind mount to an already-created container.
> You have to remove the existing container & recreate it with bind mount

---

## Volumes vs Bind Mounts

| Feature | Named Volume | Bind Mount |
|---|---|---|
| Managed by | Docker | You (host path) |
| Location on host | `/var/lib/docker/volumes/` | Any path you choose |
| Ideal for | Production data persistence | Local development / live reload |
| Cross-platform | ✅ | ⚠️ Path format differs on Windows |

---

## Basic Usage

```bash
# Short -v syntax  (host:container) in Linux/macOS Bash
docker run -v $(pwd)/src:/app/src my-image

# Short -v syntax  (host:container) in Windows PowerShell
docker run -v ${PWD}/src:/app/src my-image

# Long --mount syntax (preferred for clarity) in Linux/macOS Bash
docker run --mount "type=bind,source=$(pwd)/src,target=/app/src" my-image

# Long --mount syntax (preferred for clarity) in Windows PowerShell
docker run --mount "type=bind,source=${PWD}/src,target=/app/src" my-image

# Read-only bind mount in Linux/macOS Bash
docker run -v $(pwd)/config:/app/config:ro my-image

# Read-only bind mount in Windows PowerShell
docker run -v ${PWD}/config:/app/config:ro my-image
```

```
Linux/macOS Bash → $(pwd)
Windows PowerShell → ${PWD}
Windows CMD → %cd%
```

> **Both commands create the same type of Docker bind mount**
|                     | `-v`          | `--mount`     |
| ------------------- | ------------- | ------------- |
| Bind mount          | ✅             | ✅             |
| Host directory      | `${PWD}/src`  | `${PWD}/src`  |
| Container directory | `/app/src`    | `/app/src`    |
| Result              | Same          | Same          |
| Syntax              | Short         | Explicit      |
| Readability         | Less explicit | More explicit |

```
-v syntax
       │
       ▼
HOST/src ───────────────► CONTAINER:/app/src


--mount syntax
       │
       ▼
source=HOST/src ────────► target=/app/src
```

---

## Two common syntaxes for creating a Docker Bind Mount
```
┌─────────────────────────────────────────────────────────────────────┐
│                 BIND MOUNT — TWO SYNTAXES                          │
└─────────────────────────────────────────────────────────────────────┘

1️⃣ -v syntax + Node web application

docker run --rm -p 3000:3000 \
  -v $(pwd)/src:/app/src \
  my-node-image


2️⃣ --mount syntax + Node web application

docker run --rm -p 3000:3000 \
  --mount type=bind,source=$(pwd)/src,target=/app/src \
  my-node-image


3️⃣ -v syntax + normal container

docker run \
  -v $(pwd)/src:/app/src \
  my-image


4️⃣ --mount syntax + normal container

docker run \
  --mount type=bind,source=$(pwd)/src,target=/app/src \
  my-image
```

**The important thing is that -p and --rm have nothing to do with bind mounts.**
```
docker run
   │
   ├── --rm ──────────► Container lifecycle
   │
   ├── -p 3000:3000 ─► Network/port mapping
   │
   └── -v ... ────────► Bind mount
          OR
       --mount ... ───► Bind mount
```

**So the actual two bind-mount syntaxes are simply:**
```
-v $(pwd)/src:/app/src
```
and
```
--mount type=bind,source=$(pwd)/src,target=/app/src
```
Everything else in your commands is independent of the bind mount.

### 1. Short -v syntax
```bash
# Linux/macOS Bash, where $(pwd) expands to the current directory
docker run -v $(pwd)/src:/app/src my-image

# In Windows PowerShell
docker run -v "${PWD}/src:/app/src" my-image
```

Format:
```
-v <host-path>:<container-path>
```
So:
```
$(pwd)/src  →  /app/src
     HOST          CONTAINER
```
Docker mounts your host's src directory into /app/src inside the container.

### 2. Long --mount syntax
```bash
# Linux/macOS Bash, where $(pwd) expands to the current directory
docker run --mount "type=bind,source=${pwd}/src,target=/app/src" my-image

# In Windows PowerShell
docker run --mount "type=bind,source=${PWD}/src,target=/app/src" my-image
```
Here you explicitly specify:
```
type=bind
source=$(pwd)/src
target=/app/src
```
This is more verbose but makes the configuration easier to understand, especially in enterprise/Docker Compose environments.

### 3. Read-only bind mount

With -v:
```
docker run -v $(pwd)/config:/app/config:ro my-image
```
The :ro means read-only.
```
Host:       ./config
              │
              │  read-only
              ▼
Container:  /app/config
```
The container can read the configuration but cannot modify files in that mounted directory.

The equivalent --mount syntax is:
```
docker run \
  --mount type=bind,source=$(pwd)/config,target=/app/config,readonly \
  my-image
```

### Quick comparison
| Syntax                 | Example                                          | Main advantage        |
| ---------------------- | ------------------------------------------------ | --------------------- |
| `-v`                   | `-v ./src:/app/src`                              | Short and convenient  |
| `--mount`              | `--mount type=bind,source=./src,target=/app/src` | Explicit and readable |
| `-v ...:ro`            | `-v ./config:/app/config:ro`                     | Read-only             |
| `--mount ... readonly` | `--mount type=bind,...,readonly`                 | Read-only + explicit  |

> **Important: -v and --mount are not two different types of mounts. They are two syntaxes for configuring the same bind mount.**

---

## Live-Reload Development Workflow

Bind-mount source code into the container so changes on the host are instantly visible without rebuilding the image.

```bash
# Node.js with nodemon watching for file changes
docker run -it --rm \
  -v ${PWD}:/app \
  -v /app/node_modules \       # anonymous volume — keeps container's node_modules
  -p 3000:3000 \
  my-node-dev-image
```

> The anonymous volume `/app/node_modules` prevents the bind mount from overwriting the modules installed inside the image.

---

## Source Code Example
### A. Simple utility/container task
1. Check your existing images
```bash
docker images
```
It will give
```
IMAGE     ID             DISK USAGE   CONTENT SIZE   EXTRA
node:22   363e15874946       1.64GB          425MB    U
```

**or If you haven't created an image yet, create a Dockerfile & build the image**
```bash
docker build -t my-node-app .
```

2. Then use the actual image name:
```bash
docker run -v ${PWD}/src:/app/src node:22
```
Use when you don't need to access a network service from your host.

**Why created a container? i already have a container which was created from the image**
The important distinction is:
```
IMAGE
  ↓ docker run
NEW CONTAINER
  ↓
Mount your host directory
```
So when you execute:
```
docker run -v "${PWD}/src:/app/src" node:22
```
Docker does not modify or reuse your existing container. It creates another container from node:22 and applies the bind mount to that new container.

Suppose you already have:
```
node:22 IMAGE
    │
    ├── container-1   ← existing container
    │
    └── container-2   ← created by your new docker run
                         └── /app/src → Host/src
```
Your existing container-1 doesn't automatically get the new bind mount.

**If the existing container was created without the bind mount**

You generally need to recreate it:
```
docker rm my-node-container
```
Then create it again with the mount:
```
docker run -it --name my-node-container -v "${PWD}/src:/app/src" node:22
```

**This command retrieves detailed metadata about the container, including its storage and mount configurations.**
```
docker inspect <container_name_or_id>
```

> [!NOTE]
> you cannot add a new bind mount to an already-created container.

<img src="imgs/docker_bind_mount_1.png" width="90%" />

3. Then create mount again
```bash
docker run --mount "type=bind,source=${PWD}/src,target=/app/src" node:22
```
Another containe is created
<img src="imgs/docker_bind_mount_2.png" width="90%" />
<img src="imgs/docker_bind_mount_3.png" width="90%" />

### B. Node.js web application development

```bash
docker run --rm -p 3000:3000 -v $(pwd)/src:/app/src my-node-image
```

### Difference
| Option                   | First           | Second     | Purpose                                      |
| ------------------------ | --------------- | ---------- | -------------------------------------------- |
| `docker run`             | ✅               | ✅          | Create & start container                     |
| `--rm`                   | ✅               | ❌          | Automatically remove container when it stops |
| `-p 3000:3000`           | ✅               | ❌          | Host port → container port                   |
| `-v $(pwd)/src:/app/src` | ✅               | ✅          | Bind mount                                   |
| Image                    | `my-node-image` | `my-image` | Image to run                                 |

#### Use of -v

```bash
-v $(pwd)/src:/app/src
```

means:
```
Your computer                  Container

project/
└── src/  ──────────────────► /app/src/
```
So if you modify:
```
src/app.js
```
on your computer, the container sees the modified file at:
```
/app/src/app.js
```
This is useful for development.

#### What does -p 3000:3000 do?

Suppose your app.js has:
```
server.listen(3000);
```
The application is listening on port 3000 inside the container.

Without -p:
```
docker run -v $(pwd)/src:/app/src my-image
```

**you have:**
```
Browser
   X
   │
   │  cannot access container port
   ▼
Container
└── Node.js :3000
```
With:
```
-p 3000:3000
```

**you create:**
```
Browser
   │
   │ localhost:3000
   ▼
HOST :3000
   │
   │ Docker port mapping
   ▼
CONTAINER :3000
   │
   ▼
Node.js
```
Therefore:
```
docker run -p 3000:3000 -v $(pwd)/src:/app/src my-node-image
```
lets you open:
```
http://localhost:3000
```

#### What does --rm do?

**Without --rm:**
```
docker run -v $(pwd)/src:/app/src my-image
```
When the application stops, the container becomes:
```
Running
   ↓
Stopped
   ↓
Container still exists
```
You can see it with:
```
docker ps -a
```

**With:**
```
--rm
```
you get:
```
Running
   ↓
Stopped
   ↓
Container automatically deleted
```
This is very convenient for temporary development/test containers.


---


## docker-compose Example

```yaml
services:
  web:
    build: .
    ports:
      - "3000:3000"
    volumes:
      - ./src:/app/src                 # bind mount — live reload
      - /app/node_modules              # anonymous volume — preserve deps
    command: ["npm", "run", "dev"]
```

---

## Windows Path Notes

On Windows with PowerShell, use `${PWD}` instead of `$(pwd)`:

```powershell
docker run -v ${PWD}/src:/app/src my-image
```

With Docker Desktop on Windows, bind mounts go through WSL 2 or the Docker VM — file change notifications (inotify) may be slower than on Linux/macOS.

---

## Security Consideration

Bind mounts grant the container **direct access to the host filesystem** at the specified path. Avoid mounting sensitive directories (e.g. `/`, `/etc`, `~/.ssh`) and always use `:ro` (read-only) where write access is not needed.

---

## Common Patterns

| Use case | Mount |
|---|---|
| Live source code reload | `-v $(pwd):/app` |
| Inject config file | `-v $(pwd)/my.conf:/etc/app/my.conf:ro` |
| Share compiled artifacts | `-v $(pwd)/dist:/app/dist` |
| Preserve container deps | `-v /app/node_modules` (anonymous) |

---

## References

- [Bind mounts documentation](https://docs.docker.com/storage/bind-mounts/)
- [Use volumes vs bind mounts](https://docs.docker.com/storage/#choose-the-right-type-of-mount)
