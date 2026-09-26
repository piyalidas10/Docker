# 08 — Multi-Container App

Real-world applications are rarely a single process. This section shows how to compose multiple specialized containers into a cohesive application stack.

---

## Why Multiple Containers?

- **Separation of concerns** — each container does one thing well.
- **Independent scaling** — scale only the bottleneck service.
- **Independent deployment** — update the API without touching the database.
- **Technology freedom** — mix Node.js, Python, Go, Nginx, and Postgres freely.

---

## Example Stack

```
┌─────────────────────────────────────────────────┐
│                    Docker Network                │
│                                                  │
│  ┌──────────┐    ┌──────────┐    ┌───────────┐  │
│  │  Nginx   │───►│   API    │───►│ Postgres  │  │
│  │ (proxy)  │    │ (Node.js)│    │   (DB)    │  │
│  └──────────┘    └──────────┘    └───────────┘  │
│       ▲               │                          │
│   port 80/443    ┌────▼────┐                    │
│                  │  Redis  │                     │
│                  │ (cache) │                     │
│                  └─────────┘                     │
└─────────────────────────────────────────────────┘
```

---

## Full compose.yaml Example

```yaml
services:

  nginx:
    image: nginx:1.25-alpine
    ports:
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - api

  api:
    build: ./api
    environment:
      DATABASE_URL: postgres://postgres:secret@db:5432/appdb
      REDIS_URL: redis://cache:6379
    depends_on:
      db:
        condition: service_healthy
      cache:
        condition: service_started
    volumes:
      - ./api:/app
      - /app/node_modules

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: appdb
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      retries: 5

  cache:
    image: redis:7-alpine
    volumes:
      - cache-data:/data

volumes:
  db-data:
  cache-data:
```

---

## Service Dependencies & Startup Order

`depends_on` controls **start order**, not readiness. Use `healthcheck` + `condition: service_healthy` to wait for a service to be truly ready.

```yaml
depends_on:
  db:
    condition: service_healthy   # wait for healthcheck to pass
  cache:
    condition: service_started   # just wait for container to start
```

---

## Inter-Service Communication

All services on the same Compose network communicate by **service name**:

```
# Inside the "api" container
DB host    → db
Cache host → cache
Nginx      → api (upstream)
```

No IPs are needed — Docker's embedded DNS resolves service names automatically.

---

## Useful Commands for Multi-Container Apps

```bash
# Start the whole stack
docker compose up -d

# Watch logs across all services
docker compose logs -f

# Check health of each service
docker compose ps

# Restart a single service without affecting others
docker compose restart api

# Scale a stateless service horizontally
docker compose up -d --scale api=3

# Run a migration before the API starts
docker compose run --rm api npx prisma migrate deploy

# Open a shell in the running DB container
docker compose exec db psql -U postgres appdb
```

---

## Tips

- Keep **one concern per service** (app, cache, DB, proxy are separate).
- Never expose the database port to the host in production — let only the API reach it via the internal network.
- Use named volumes for all stateful services.
- Use `healthcheck` on every service that other services depend on.
- Store secrets in `.env` and add `.env` to `.gitignore`.

---

## References

- [Compose networking](https://docs.docker.com/compose/networking/)
- [Compose healthchecks](https://docs.docker.com/compose/compose-file/05-services/#healthcheck)
- [Docker samples repository](https://github.com/dockersamples)
