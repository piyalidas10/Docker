# 07 — Docker Compose

**Docker Compose** is a tool for defining and running multi-container Docker applications using a single `docker-compose.yaml` (or `compose.yaml`) file. With one command you spin up every service your application needs.

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
