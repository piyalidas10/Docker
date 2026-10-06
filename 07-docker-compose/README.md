# 07 — Docker Compose

**Docker Compose** is a tool for defining and running multi-container Docker applications using a single `docker-compose.yaml` (or `compose.yaml`) file. With one command you spin up every service your application needs.

Docker Compose is a powerful tool designed to define and run multi-container applications using a single YAML configuration file. Instead of manually running multiple docker run commands for each part of your app (like a web server and a database), Compose orchestrates them as a unified "stack".

Compose simplifies the control of your entire application stack, making it easy to manage services, networks, and volumes in a single YAML configuration file. Then, with a single command, you create and start all the services from your configuration file.

Compose works in all environments - production, staging, development, testing, as well as CI workflows. 

---

## Core Concepts

| Concept | Description |
|---|---|
| **Service** | A container definition (image, ports, env, volumes, …). |
| **Volume** | Named storage shared across services or persisted after restart. |
| **Network** | Virtual network connecting services (auto-created by Compose). |
| **Profile** | Optional grouping to enable services selectively. |

---

## File Structure

```yaml
# compose.yaml  (or docker-compose.yaml)
services:
  <service-name>:
    image: <image>              # use a pre-built image, OR
    build: <path>               # build from a Dockerfile
    ports:
      - "<host>:<container>"
    environment:
      KEY: value
    env_file:
      - .env
    volumes:
      - <named-vol>:<container-path>
      - ./<host-path>:<container-path>
    depends_on:
      - <other-service>
    networks:
      - <network-name>
    restart: unless-stopped

volumes:
  <named-vol>:

networks:
  <network-name>:
```

---

## Essential Commands

```bash
# Start all services (build images if needed, run detached)
docker compose up -d

# Build (or rebuild) images without starting containers
docker compose build

# Force rebuild even if cache is valid
docker compose build --no-cache

# Start specific services
docker compose up -d api db

# View logs for all services
docker compose logs -f

# View logs for a specific service
docker compose logs -f api

# List running services
docker compose ps

# Run a one-off command in a service container
docker compose run --rm api python manage.py migrate

# Execute a command in a running service container
docker compose exec api sh

# Stop and remove containers (keeps volumes)
docker compose down

# Stop and remove containers AND volumes
docker compose down -v
```

---

## Basic Docker Compose lifecycle
### 1. docker compose up
From the directory containing compose.yaml / docker-compose.yml:
docker compose up

**Docker Compose will generally:**
```
docker-compose.yml
       │
       ├── Build required images
       ├── Pull required images
       ├── Create network
       ├── Create volumes
       └── Create & start containers
```

**For example:**
```
services:
  backend:
    build: ./backend

  database:
    image: postgres:16
    volumes:
      - data:/var/lib/postgresql/data

volumes:
  data:
```

**Running:**
```
docker compose up
```

**can result in:**
```
Image:
  backend image ───────────┐
                           │
Containers:                ▼
  backend container     Network
  postgres container       │
                           │
Volume:                    │
  data volume ─────────────┘
```

### 2. Attached mode vs detached mode
**By default:**
```
docker compose up
```
runs in attached mode.

**Your terminal stays attached to the Compose services' logs:**
```
backend  | Server started on port 3000
database | database system is ready
```

**Pressing:**
```
Ctrl + C
```
stops the Compose application.

**With:**
```
docker compose up -d
```
**-d means detached mode.**
```
Terminal
   │
   └──> immediately available again

Docker
   │
   ├── backend container  RUNNING
   └── database container RUNNING
```
This is very common when running a multi-container application locally.

**You can then inspect logs with:**
```
docker compose logs
```
or:
```
docker compose logs -f
```

### 3. docker compose down
```
docker compose down
```
This stops and removes the containers created by Compose.

**Typically:**
```
docker compose down

Containers  → removed
Network     → removed
Images      → NOT removed
Volumes     → NOT removed
```
This distinction is very important.

### 4. Why doesn't down remove volumes?
**Suppose PostgreSQL has:**
```
volumes:
  - data:/var/lib/postgresql/data
```

**You run:**
```
docker compose up
```

**and PostgreSQL stores:**
```
Customer data
Account data
Transaction data
```

**Then:**
```
docker compose down
```

**removes the PostgreSQL container, but keeps:**
```
data volume
```

**So when you later run:**
```
docker compose up
```
a new PostgreSQL container can mount the same volume and recover the existing database data. That's exactly why volumes are useful.

### 5. docker compose down -v

**If you run:**
```
docker compose down -v
```
then Compose also removes the Compose-managed volumes.

**So:**
```
docker compose down
        │
        ├── Remove containers
        └── Remove network

docker compose down -v
        │
        ├── Remove containers
        ├── Remove network
        └── Remove volumes  ← DATA CAN BE LOST
```
For a database, be careful with -v.

### 6. One correction

- If a service has build:, Compose builds its image when needed.
- If a service has image:, Compose can pull the image when it isn't available locally (depending on pull/build configuration).
- Then Compose creates/starts the containers.

**Also, modern Docker uses:**
```
docker compose
```
**rather than the older:**
```
docker-compose
```

**So prefer:**
```
docker compose up
docker compose up -d
docker compose down
docker compose down -v
```

**The mental model to remember**
```
                 docker compose up
                         │
                         ▼
                ┌─────────────────┐
                │ Compose YAML     │
                └────────┬────────┘
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
       Images         Network        Volumes
          │
          ▼
      Containers
          │
          ▼
       Services


docker compose down
          │
          ├── Containers → REMOVE
          ├── Network    → REMOVE
          ├── Images     → KEEP
          └── Volumes    → KEEP

docker compose down -v
          │
          └── Volumes    → REMOVE
```

**So the simplest rule is:**
- up = create/start the application stack
- up -d = create/start it in the background
- down = stop/remove the Compose containers and network
down -v = same, but also remove volumes/data.


## Minimal Example — Node API + PostgreSQL

```yaml
services:
  api:
    build: ./api
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgres://postgres:secret@db:5432/mydb
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - ./api:/app           # bind mount for development
      - /app/node_modules

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: mydb
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  db-data:
```

---

## Environment Variables

```bash
# .env file (auto-loaded by Compose)
POSTGRES_PASSWORD=secret
NODE_ENV=development
```

Reference in `compose.yaml`:
```yaml
environment:
  - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
```

---

## Multiple Compose Files (Override Pattern)

```bash
# Base file + development overrides
docker compose -f compose.yaml -f compose.dev.yaml up -d

# Base file + production overrides
docker compose -f compose.yaml -f compose.prod.yaml up -d
```

---

## References

- [Docker Compose overview](https://docs.docker.com/compose/)
- [Compose file reference](https://docs.docker.com/compose/compose-file/)
- [Compose CLI reference](https://docs.docker.com/compose/reference/)
