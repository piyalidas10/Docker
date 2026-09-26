# 06 — Utility Containers

**Utility containers** are short-lived containers used to run tools or one-off commands without installing anything on the host machine. They are started, do their job, and are removed.

---

## Concept

Instead of installing Node, Python, or other runtimes locally, you can use a container as an isolated execution environment:

```
docker run --rm <image> <command>
```

The `--rm` flag automatically removes the container after it exits, keeping your system clean.

---

## Common Use Cases

| Use case | Example |
|---|---|
| Scaffold a project | `docker run --rm -v $(pwd):/app node:20-alpine npx create-react-app my-app` |
| Run a linter | `docker run --rm -v $(pwd):/app python:3.12 pylint src/` |
| Execute a one-off script | `docker run --rm -v $(pwd):/app node:20-alpine node scripts/seed.js` |
| Install npm packages | `docker run --rm -v $(pwd):/app node:20-alpine npm install` |
| Run database migrations | `docker run --rm --network app-net my-app python manage.py migrate` |

---

## Pattern: Use the Project Directory as Workdir

```bash
docker run --rm \
  -v $(pwd):/app \
  -w /app \
  node:20-alpine \
  npm install
```

- `-v $(pwd):/app` — bind-mounts the current directory so output is written back to the host.
- `-w /app` — sets the working directory inside the container.
- `--rm` — cleans up the container on exit.

---

## docker-compose for Utility Containers

You can define utility containers in `docker-compose.yaml` and run them on demand with `docker compose run`:

```yaml
services:
  npm:
    image: node:20-alpine
    working_dir: /app
    volumes:
      - ./:/app
    entrypoint: ["npm"]   # fixes the entrypoint so only args change

  python:
    image: python:3.12-slim
    working_dir: /app
    volumes:
      - ./:/app
    entrypoint: ["python"]
```

Run them with:

```bash
# Install packages
docker compose run --rm npm install

# Run a specific npm script
docker compose run --rm npm run build

# Execute a Python script
docker compose run --rm python scripts/seed.py
```

---

## ENTRYPOINT vs CMD for Utility Containers

Using `ENTRYPOINT` in the Dockerfile (or in Compose) locks the executable, making it easy to pass arbitrary arguments:

```dockerfile
FROM node:20-alpine
WORKDIR /app
ENTRYPOINT ["npm"]
```

```bash
# Acts like "npm" is installed locally
docker run --rm -v $(pwd):/app my-npm-util install
docker run --rm -v $(pwd):/app my-npm-util run build
docker run --rm -v $(pwd):/app my-npm-util test
```

---

## Tips

- Always use `--rm` to avoid accumulating stopped containers.
- Combine with bind mounts so generated files land on the host.
- Pin tool versions via image tags to get reproducible results.
- Prefer `-it` when the tool needs interactive input.

---

## References

- [docker run reference](https://docs.docker.com/engine/reference/run/)
- [docker compose run](https://docs.docker.com/compose/reference/run/)
