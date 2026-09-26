# 05 — Networking

Docker networking allows containers to communicate with each other and with the outside world. Docker provides several built-in network drivers and lets you create custom networks.

---

## Network Drivers

| Driver | Description |
|---|---|
| `bridge` | Default for standalone containers. Isolated virtual network on the host. |
| `host` | Container shares the host's network stack (Linux only). |
| `none` | No networking — fully isolated. |
| `overlay` | Multi-host networking for Docker Swarm / distributed apps. |
| `macvlan` | Assigns a MAC address to the container (advanced / bare-metal use). |

---

## Key Commands

```bash
# List networks
docker network ls

# Inspect a network
docker network inspect bridge

# Create a custom bridge network
docker network create my-network

# Create with a specific subnet
docker network create --subnet 172.20.0.0/16 my-network

# Connect a running container to a network
docker network connect my-network <container>

# Disconnect a container from a network
docker network disconnect my-network <container>

# Remove a network
docker network rm my-network

# Remove all unused networks
docker network prune
```

---

## Default Bridge vs User-Defined Bridge

| Feature | Default `bridge` | User-defined bridge |
|---|---|---|
| DNS resolution by name | ❌ (IP only) | ✅ |
| Automatic isolation | ❌ | ✅ |
| Recommended for apps | ❌ | ✅ |

Always use a **user-defined bridge** for multi-container applications so containers can reach each other by name.

---

## Container-to-Container Communication

```bash
# Create a shared network
docker network create app-net

# Start a database container on that network
docker run -d --name db --network app-net postgres:16-alpine

# Start an app container on the same network
# The app can reach the DB at hostname "db"
docker run -d --name api --network app-net my-api-image
```

Inside the `api` container:
```bash
# Resolve the db container by name
ping db
curl http://db:5432
```

---

## Exposing Ports to the Host

```bash
# Map host port 8080 → container port 3000
docker run -p 8080:3000 my-image

# Map on a specific host interface only
docker run -p 127.0.0.1:8080:3000 my-image

# Map all exposed ports to random host ports
docker run -P my-image

# List port mappings for a container
docker port <container>
```

---

## docker-compose Networking

Compose automatically creates a user-defined bridge network for all services in a file, so every service can reach others by service name.

```yaml
services:
  api:
    build: ./api
    ports:
      - "3000:3000"

  db:
    image: postgres:16-alpine
    # No ports exposed to host — only reachable inside the network

# Compose auto-creates a default network; you can also declare custom ones:
networks:
  backend:
    driver: bridge
```

---

## References

- [Docker networking overview](https://docs.docker.com/network/)
- [Bridge network tutorial](https://docs.docker.com/network/network-tutorial-standalone/)
- [docker network reference](https://docs.docker.com/engine/reference/commandline/network/)
