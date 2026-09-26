# 04 — Bind Mounts

**Bind mounts** map a file or directory on the **host machine** directly into a container. Unlike volumes, the host path is fully controlled by you — not Docker.

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
# Short -v syntax  (host:container)
docker run -v $(pwd)/src:/app/src my-image

# Long --mount syntax (preferred for clarity)
docker run \
  --mount type=bind,source=$(pwd)/src,target=/app/src \
  my-image

# Read-only bind mount
docker run -v $(pwd)/config:/app/config:ro my-image
```

---

## Live-Reload Development Workflow

Bind-mount source code into the container so changes on the host are instantly visible without rebuilding the image.

```bash
# Node.js with nodemon watching for file changes
docker run -it --rm \
  -v $(pwd):/app \
  -v /app/node_modules \       # anonymous volume — keeps container's node_modules
  -p 3000:3000 \
  my-node-dev-image
```

> The anonymous volume `/app/node_modules` prevents the bind mount from overwriting the modules installed inside the image.

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
