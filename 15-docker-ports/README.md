# 15 — Docker Ports Deep Dive

Network port publishing and routing are essential to connecting the outside world to services running inside isolated Docker containers.

---

## The Core Concept: How Traffic Flows

When you run:

```bash
docker run -p 8080:80 nginx
```

Traffic flows through the network layers as follows:

```
┌────────────────────────────────────────────────────────┐
│                      Host Machine                      │
│                                                        │
│  External Traffic / Browser                            │
│  http://localhost:8080                                 │
│                         │                              │
│                         ▼                              │
│  ┌─────────────────────────────┐                       │
│  │     Host Port: 8080         │                       │
│  │ (Published on Host Network) │                       │
│  └──────────────┬──────────────┘                       │
│                 │ (Docker NAT / iptables forwarding)   │
│                 ▼                                      │
│  ┌─────────────────────────────┐                       │
│  │      Docker Bridge (docker0)│                       │
│  │    Container IP: 172.17.0.2 │                       │
│  │                             │                       │
│  │   ┌──────────────────────┐  │                       │
│  │   │ Container Port: 80   │  │                       │
│  │   │                      │  │                       │
│  │   │          ▼           │  │                       │
│  │   │      NGINX           │  │                       │
│  │   │ (Listening on 80)    │  │                       │
│  │   └──────────────────────┘  │                       │
│  │                             │                       │
│  └─────────────────────────────┘                       │
└────────────────────────────────────────────────────────┘
```

---

## Table of Contents

1. [Key Terminology & Differences](#1-key-terminology--differences)
   - [Container Port](#container-port)
   - [Host Port](#host-port)
   - [Exposed Port (`EXPOSE`)](#exposed-port-expose)
   - [Published Port (`-p` / `-P`)](#published-port--p---p)
2. [Comparison Matrix](#2-comparison-matrix)
3. [Port Publishing Syntax & Variations](#3-port-publishing-syntax--variations)
4. [Publishing All Exposed Ports (`-P`)](#4-publishing-all-exposed-ports--p)
5. [Docker Network Isolation & Inter-Container Communication](#5-docker-network-isolation--inter-container-communication)
6. [Ports in Docker Compose](#6-ports-in-docker-compose)
7. [Troubleshooting & Verification Commands](#7-troubleshooting--verification-commands)

---

## 1. Key Terminology & Differences

### Container Port
- **What it is**: The internal network port on which the application process (e.g., NGINX, Node.js, PostgreSQL) listens inside the container's private network namespace.
- **Scope**: Private to the container's isolated network.
- **Example**: In `docker run -p 8080:80 nginx`, **`80`** is the container port.

---

### Host Port
- **What it is**: The port opened on the physical or virtual host machine running the Docker daemon.
- **Scope**: Accessible from outside the host (laptop, local network, or internet depending on firewall).
- **Example**: In `docker run -p 8080:80 nginx`, **`8080`** is the host port. Requests sent to `http://<host-ip>:8080` are forwarded to container port 80.

---

### Exposed Port (`EXPOSE`)
- **What it is**: An informational metadata declaration in the `Dockerfile` or compose file stating that the container intends to listen on a given port.
- **Key Behavior**: `EXPOSE` does **NOT** publish the port to the host machine. It does **NOT** open any ports on the host. It acts as documentation between the image author and the operator.
- **Syntax**:
  ```dockerfile
  EXPOSE 80/tcp
  EXPOSE 53/udp
  ```

---

### Published Port (`-p` / `-P`)
- **What it is**: An active NAT routing rule created by Docker via `iptables` that explicitly maps a host port to an internal container port.
- **Key Behavior**: Makes the container service accessible to the host machine and external network.
- **Syntax**:
  ```bash
  docker run -p <host_port>:<container_port> <image>
  ```

---

## 2. Comparison Matrix

| Term | Where it Lives | Who Configures It | Makes Port Externally Reachable? | Purpose |
|---|---|---|---|---|
| **Container Port** | Inside Container | Application Code (`server.listen(3000)`) | ❌ No | Port where process accepts connections inside container |
| **Host Port** | Host OS Network | Operator (`docker run -p 8080:...`) | ✅ Yes | Port on the host that receives external traffic |
| **Exposed Port** | Image Metadata | Dockerfile Author (`EXPOSE 80`) | ❌ No | Documentation & default hint for `-P` |
| **Published Port** | Docker / iptables | Operator (`-p` / `-P` flags) | ✅ Yes | The actual network bridge connecting Host & Container |

---

## 3. Port Publishing Syntax & Variations

Docker provides granular control over how ports bind to the host interface:

```
┌───────────────────────────────────────────────────────────────┐
│               docker run -p [IP:][HostPort:]ContainerPort     │
└───────────────────────────────────────────────────────────────┘
```

### 1. Standard Port Mapping
Binds to all host network interfaces (`0.0.0.0` and `[::]`):
```bash
# Host port 8080 maps to container port 80
docker run -d -p 8080:80 nginx
```

### 2. Same Port Mapping
When host port matches container port:
```bash
# Host port 3000 maps to container port 3000
docker run -d -p 3000:3000 node-app
```

### 3. Bind to Specific Host IP (Security Best Practice)
Restrict access so only the local host or a private network can reach the service:
```bash
# Accessible ONLY from localhost (127.0.0.1), preventing external internet access
docker run -d -p 127.0.0.1:5432:5432 postgres

# Accessible only via specific private network interface IP
docker run -d -p 192.168.1.50:8080:80 nginx
```

### 4. Dynamic / Random Host Port Allocation
Let Docker automatically pick an available ephemeral high port (e.g. 32768–60999) on the host:
```bash
# Docker assigns an available random host port to container port 80
docker run -d -p 80 nginx
```
Check which port was assigned using `docker port <container_name>`.

### 5. UDP Protocol Mapping
By default, port mappings use TCP. To map UDP traffic (e.g., DNS, VoIP, streaming):
```bash
# Map host UDP port 53 to container UDP port 53
docker run -d -p 53:53/udp coredns
```

---

## 4. Publishing All Exposed Ports (`-P`)

The uppercase `-P` (or `--publish-all`) flag publishes **all** ports declared in the image's `Dockerfile` via `EXPOSE` to random high-numbered ports on the host.

```bash
docker run -d -P --name my-nginx nginx
```

Inspect the mapped ports:
```bash
docker port my-nginx
# Output:
# 80/tcp -> 0.0.0.0:32769
# 80/tcp -> [::]:32769
```

---

## 5. Docker Network Isolation & Inter-Container Communication

### Important Rule: Containers on the Same Docker Network Do NOT Need Published Ports to Talk to Each Other

```
┌───────────────────────────────────────────────────────────────┐
│                   Custom Docker Network                       │
│                                                               │
│   ┌───────────────┐                 ┌────────────────────┐    │
│   │  API Backend  │ ──────────────► │  PostgreSQL DB     │    │
│   │  (Port 3000)  │  Connects to    │  (Port 5432)       │    │
│   │               │  "db:5432"      │  (NOT published)   │    │
│   └───────┬───────┘                 └────────────────────┘    │
│           │                                                   │
└───────────┼───────────────────────────────────────────────────┘
            │ Published Port (-p 8080:3000)
            ▼
   External User Traffic
```

- When two containers are on the same user-defined network, they can communicate directly using their internal **Container Ports** and service DNS names.
- **Security Best Practice**: Databases (PostgreSQL, MySQL, Redis) should **never** publish ports (`-p 5432:5432`) to the host in production if only the backend API needs to talk to them.

---

## 6. Ports in Docker Compose

In `compose.yaml`, you can specify both published `ports` and internal `expose` declarations:

```yaml
services:
  # Public-facing web service (Published to host)
  web:
    image: nginx:alpine
    ports:
      # host:container
      - "80:80"
      - "443:443"
      # Restrict to localhost only
      - "127.0.0.1:8080:80"
    depends_on:
      - api

  # Internal API service (Accessible by web via bridge network)
  api:
    image: my-node-api:1.0
    expose:
      # Documents internal port for services on the same network
      - "3000"
    environment:
      - DB_HOST=db
    depends_on:
      - db

  # Internal Database (NO host ports published for security)
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: secret
    # Notice: No `ports:` section, fully isolated from outside world
```

---

## 7. Troubleshooting & Verification Commands

### View Active Port Mappings:
```bash
# List port mapping for a specific container
docker port <container_name_or_id>

# View ports in docker ps output
docker ps --format "table {{.Names}}\t{{.Ports}}"
```

### Inspect Container IP and Port Configuration:
```bash
# Inspect all network and port metadata
docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}} {{$p}} -> {{(index $conf 0).HostPort}} {{end}}' <container_id>
```

### Common Issues & Solutions:

| Problem | Root Cause | Solution |
|---|---|---|
| `bind: address already in use` | Another process or container is using the specified host port | Use a different host port (e.g., `-p 8081:80`) or stop the conflicting process |
| Container runs, but browser gets `Connection Refused` | Application inside container is listening on `127.0.0.1` instead of `0.0.0.0` | Configure your app (Node, Flask, Django) to listen on `0.0.0.0` (all interfaces) |
| Can access locally but not from remote IP | Bound to `127.0.0.1` instead of `0.0.0.0` | Bind to `0.0.0.0` or simply omit host IP: `-p 8080:80` |

---

## References

- [Docker Container Networking Documentation](https://docs.docker.com/network/)
- [Docker run reference - Published ports](https://docs.docker.com/engine/reference/commandline/run/#publish-or-expose-ports--p---publish-all)
- [Dockerfile EXPOSE instruction reference](https://docs.docker.com/engine/reference/builder/#expose)
