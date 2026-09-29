# 05 — Container Networking Deep Dive

Docker networking allows containers to communicate with each other, with the host machine, and with external networks. Docker provides several built-in network drivers and enables isolated, DNS-driven service discovery across multi-container applications.

---

## The Critical Concept: What `localhost` Means in Docker

> ⚠️ **CRITICAL RULE:** **`localhost` (or `127.0.0.1`) inside a container refers ONLY to THAT SPECIFIC CONTAINER itself — NEVER the host machine, and NEVER another container.**

```
┌────────────────────────────────────────────────────────┐
│                      Host Machine                      │
│                                                        │
│   ┌────────────────────┐      ┌────────────────────┐   │
│   │   App Container    │      │ Database Container │   │
│   │                    │      │                    │   │
│   │ localhost = itself │  ❌  │ localhost = itself │   │
│   │ (port 3000)        │ ───► │ (port 5432)        │   │
│   │                    │      │                    │   │
│   └────────────────────┘      └────────────────────┘   │
│             │                            ▲             │
│             │                            │             │
│             └─────── connects to ────────┘             │
│                   "postgres:5432"                      │
│               via Custom Bridge Network                │
└────────────────────────────────────────────────────────┘
```

- If your backend code inside container `api` tries to connect to `localhost:5432` to reach PostgreSQL, it will fail because PostgreSQL is **not running in the `api` container**.
- To communicate between containers, you must place them on the same **custom bridge network** and connect using the target container's **service or container name** (e.g., `postgres:5432`).

---

## Table of Contents

1. [Network Drivers Overview](#1-network-drivers-overview)
   - [Default Bridge Network](#default-bridge-network)
   - [Custom (User-Defined) Bridge Network](#custom-user-defined-bridge-network)
   - [Host Network](#host-network)
   - [None Network](#none-network)
   - [Overlay & Macvlan Networks](#overlay--macvlan-networks)
2. [Default Bridge vs. Custom Bridge Comparison](#2-default-bridge-vs-custom-bridge-comparison)
3. [Container-to-Container Communication & Service Discovery](#3-container-to-container-communication--service-discovery)
4. [Three-Tier Architecture Example (`app-network`)](#4-three-tier-architecture-example-app-network)
5. [Port Mapping & Routing](#5-port-mapping--routing)
6. [Network Isolation & Security](#6-network-isolation--security)
7. [Networking in Docker Compose](#7-networking-in-docker-compose)
8. [CLI Commands Reference](#8-cli-commands-reference)

---

## 1. Network Drivers Overview

Docker includes multiple network drivers tailored for different isolation and connectivity requirements:

| Driver | Scope | Description | Typical Use Case |
|---|---|---|---|
| **`bridge`** (default) | Single Host | Creates an internal private software bridge (`docker0` or user-defined). | Standalone containers and microservices on a single host. |
| **`host`** | Single Host | Removes network isolation between container and host; container uses host's network stack directly. | Maximum network throughput, low-latency applications (Linux only). |
| **`none`** | Single Host | Disables all networking interfaces except the loopback (`lo`). Container has no external network access. | Air-gapped batch jobs, security-sensitive cryptographic tasks. |
| **`overlay`** | Multi-Host | Encapsulates network traffic across multiple Docker daemon hosts using VXLAN. | Docker Swarm clusters and distributed multi-host services. |
| **`macvlan`** | Single/Multi Host | Assigns a physical MAC address to the container, making it appear as a physical device on the LAN. | Legacy applications requiring direct physical subnet integration. |

---

### Default Bridge Network
When Docker starts, it creates a default bridge network named `bridge` (backed by the host's `docker0` virtual interface).
- Any container started without an explicit `--network` flag connects to this default network.
- **Limitation**: Containers on the default bridge can only communicate with each other via **IP addresses**. Automatic DNS service discovery by container name is **disabled**.
- **Limitation**: Lack of isolation — all unrelated containers share the same default bridge.

---

### Custom (User-Defined) Bridge Network
A user-defined bridge network created with `docker network create <network-name>`.
- **Automatic DNS Resolution**: Containers can resolve each other directly by **container name** or **network alias**.
- **Better Isolation**: Containers on different custom bridge networks cannot communicate with each other, even on the same host.
- **Dynamic Attachment**: Containers can be connected or disconnected from custom networks on the fly without stopping them.

```bash
docker network create my-bridge-net
```

---

### Host Network (`--network host`)
The container shares the host's networking namespace. It does not get its own private IP address, and port mapping (`-p`) is ignored.
- A service inside the container listening on port `8080` binds directly to port `8080` on the host machine.
- Provides maximum performance with zero NAT/iptables overhead (Linux only).

```bash
docker run -d --name web --network host nginx
```

---

### None Network (`--network none`)
Completely isolates the container from all incoming and outgoing network traffic.
- Has only the `lo` (loopback) interface.
- Cannot make outbound HTTP calls or receive inbound requests.

```bash
docker run -it --rm --network none alpine ifconfig
```

---

## 2. Default Bridge vs. Custom Bridge Comparison

| Feature | Default `bridge` | Custom Bridge (`docker network create`) |
|---|---|---|
| **DNS Resolution by Name** | ❌ Disabled (IP address only) | ✅ **Automatic Built-in DNS** |
| **Network Isolation** | ❌ All default containers share one pool | ✅ Isolated per user-defined network |
| **Live Connect / Disconnect** | ❌ Must recreate container | ✅ `docker network connect/disconnect` on live containers |
| **Environment Variable Sharing** | ⚠️ Legacy `--link` required | ✅ Built-in DNS service discovery |
| **Production Recommendation** | ❌ Avoid for multi-container apps | ✅ **Standard Best Practice** |

---

## 3. Container-to-Container Communication & Service Discovery

Docker contains an embedded DNS server at `127.0.0.11` that automatically resolves container names and network aliases on custom bridge networks.

```
                      app-network (Bridge)
 ┌────────────────────────────────────────────────────────┐
 │                                                        │
 │   ┌───────────────┐                  ┌─────────────┐   │
 │   │  backend api  │ ── DNS Query ──► │ Embedded    │   │
 │   │               │   "postgres"     │ DNS Server  │   │
 │   └───────┬───────┘                  │(127.0.0.11) │   │
 │           │                          └──────┬──────┘   │
 │           │ Resolves to 172.18.0.3          │          │
 │           ▼                                 │          │
 │   ┌───────────────┐                         │          │
 │   │ postgres db   │ ◄───────────────────────┘          │
 │   │ (172.18.0.3)  │                                    │
 │   └───────────────┘                                    │
 └────────────────────────────────────────────────────────┘
```

---

## 4. Three-Tier Architecture Example (`app-network`)

Here is the practical realization of the standard 3-tier pattern:

```
             app-network

 ┌─────────┐       ┌──────────┐
 │ frontend│ ────► │ backend  │
 └─────────┘       └────┬─────┘
                        │
                        ▼
                   ┌─────────┐
                   │ postgres│
                   └─────────┘
```

### Step 1: Create the Isolated Custom Network
```bash
docker network create app-network
```

### Step 2: Start the Database Container
```bash
# PostgreSQL listens on port 5432 internally. No host ports published!
docker run -d \
  --name postgres \
  --network app-network \
  -e POSTGRES_PASSWORD=dbsecret \
  -e POSTGRES_DB=myapp_db \
  postgres:16-alpine
```

### Step 3: Start the Backend API Container
```bash
# Connects to database at hostname "postgres:5432"
docker run -d \
  --name backend \
  --network app-network \
  -e DB_HOST=postgres \
  -e DB_PORT=5432 \
  -e DB_PASSWORD=dbsecret \
  my-backend-image
```

### Step 4: Start the Frontend Container (Published to Host)
```bash
# Connects to backend at hostname "backend:3000" and publishes port 80 to host
docker run -d \
  --name frontend \
  --network app-network \
  -p 80:80 \
  my-frontend-image
```

*Result:* The user visits `http://localhost:80` on the host to reach `frontend`. `frontend` routes API calls internally to `http://backend:3000`. `backend` queries `postgres:5432`. The database is never exposed to the host machine or external internet.

---

## 5. Port Mapping & Routing

To allow traffic from the outside host machine into a container, use port publishing (`-p`):

```bash
# Syntax: -p <host_port>:<container_port>
docker run -d -p 8080:80 --name web nginx:alpine
```

- **Traffic Flow**: Host incoming traffic on port `8080` &rarr; Docker `iptables` NAT forwarding &rarr; Container virtual interface port `80` &rarr; NGINX server.
- **Binding to Localhost Only (Security)**:
  ```bash
  docker run -d -p 127.0.0.1:8080:80 nginx:alpine
  ```

---

## 6. Network Isolation & Security

1. **Segment Services by Network**:
   Place services on separate networks based on tier. A reverse proxy should not be able to talk directly to a database:

```
 ┌──────────────────────┐         ┌──────────────────────┐
 │     frontend_net     │         │     backend_net      │
 │                      │         │                      │
 │  ┌───────┐  ┌──────┐ │         │ ┌──────┐  ┌────────┐ │
 │  │ Proxy │─►│ API  │─┼─────────┼─│ API  │─►│   DB   │ │
 │  └───────┘  └──────┘ │         │ └──────┘  └────────┘ │
 └──────────────────────┘         └──────────────────────┘
```

```bash
# Create two distinct networks
docker network create frontend_net
docker network create backend_net

# Database is only on backend_net
docker run -d --name db --network backend_net postgres:16-alpine

# API is on both networks (bridge between proxy and DB)
docker run -d --name api --network backend_net my-api
docker network connect frontend_net api

# Proxy is only on frontend_net (cannot reach db)
docker run -d --name proxy --network frontend_net -p 80:80 nginx:alpine
```

---

## 7. Networking in Docker Compose

Docker Compose automatically creates a shared user-defined bridge network for all services in the file:

```yaml
services:
  frontend:
    image: my-frontend:1.0
    ports:
      - "80:80"
    networks:
      - app-network
    depends_on:
      - backend

  backend:
    image: my-backend:1.0
    environment:
      DATABASE_URL: postgres://postgres:dbsecret@postgres:5432/myapp_db
    networks:
      - app-network
    depends_on:
      - postgres

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: dbsecret
      POSTGRES_DB: myapp_db
    networks:
      - app-network
    volumes:
      - pgdata:/var/lib/postgresql/data

networks:
  app-network:
    driver: bridge

volumes:
  pgdata:
```

---

## 8. CLI Commands Reference

```bash
# 1. List all networks on host
docker network ls

# 2. Inspect network configuration, IP subnets, and attached containers
docker network inspect app-network

# 3. Create a custom bridge network
docker network create --driver bridge app-network

# 4. Create network with explicit subnet and gateway
docker network create \
  --driver bridge \
  --subnet 172.28.0.0/16 \
  --gateway 172.28.0.1 \
  custom-net

# 5. Connect a running container to a second network
docker network connect frontend_net api

# 6. Disconnect a container from a network
docker network disconnect frontend_net api

# 7. Remove an unused network
docker network rm app-network

# 8. Remove all unused networks
docker network prune -f
```

---

## References

- [Docker Networking Overview](https://docs.docker.com/network/)
- [User-Defined Bridge Networks Tutorial](https://docs.docker.com/network/network-tutorial-standalone/)
- [Docker Network CLI Reference](https://docs.docker.com/engine/reference/commandline/network/)
