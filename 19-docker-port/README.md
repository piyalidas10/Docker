# 19 — Docker Ports & Port Forwarding

Network port routing bridges isolated container networks with the external host operating system and internet.

---

## The Core Concept: Port Forwarding Path

When you execute:

```bash
docker run -p 8080:80 nginx
```

It creates the following direct routing pipeline:

```
┌────────────────────────────────────────────────────────┐
│                      Host Machine                      │
│                                                        │
│  External Traffic / Client                             │
│  http://localhost:8080                                 │
│                         │                              │
│                         ▼                              │
│  ┌─────────────────────────────┐                       │
│  │       Host Port: 8080       │                       │
│  └──────────────┬──────────────┘                       │
│                 │ (Docker NAT / iptables forwarding)   │
│                 ▼                                      │
│  ┌─────────────────────────────┐                       │
│  │    Container Port: 80       │                       │
│  └──────────────┬──────────────┘                       │
│                 │                                      │
│                 ▼                                      │
│  ┌─────────────────────────────┐                       │
│  │            NGINX            │                       │
│  │    (Listening on port 80)   │                       │
│  └─────────────────────────────┘                       │
└────────────────────────────────────────────────────────┘
```

---

## Table of Contents

1. [Understanding the Four Port Concepts](#1-understanding-the-four-port-concepts)
   - [Container Port](#container-port)
   - [Host Port](#host-port)
   - [Published Port](#published-port)
   - [Exposed Port](#exposed-port)
2. [Comparison Table](#2-comparison-table)
3. [Syntax Reference & Practical Examples](#3-syntax-reference--practical-examples)
4. [Publishing All Ports (`-P`)](#4-publishing-all-ports--p)
5. [Docker Compose Port Configuration](#5-docker-compose-port-configuration)
6. [Common Issues & Debugging](#6-common-issues--debugging)

---

## 1. Understanding the Four Port Concepts

### Container Port
- **Definition**: The internal port on which the server application inside the container is actively listening (e.g. `3000` for Express, `5432` for Postgres, `80` for NGINX).
- **Scope**: Private to the container's isolated network.
- **Example**: In `-p 8080:80`, `80` is the **container port**.

---

### Host Port
- **Definition**: The port opened on the physical host machine or VM where Docker runs.
- **Scope**: Accessible from outside the host (browser, API clients, public network).
- **Example**: In `-p 8080:80`, `8080` is the **host port**.

---

### Published Port
- **Definition**: An active network rule created via `-p` or `-P` where Docker configures Linux `iptables` / NAT routing to map a host port directly to a container port.
- **Result**: Allows external clients to reach the containerized service.

---

### Exposed Port
- **Definition**: An informational metadata declaration in the `Dockerfile` (`EXPOSE 80`) or compose file.
- **Result**: Does **NOT** publish the port to the host or open host firewall ports. Acts solely as documentation and as default hints when `-P` is used.

---

## 2. Comparison Table

| Concept | Location | Defined In | Makes Service Reachable from Outside? |
|---|---|---|---|
| **Container Port** | Container | Application Code (`listen(80)`) | ❌ No |
| **Host Port** | Host OS | `docker run -p <host>:<container>` | ✅ Yes |
| **Published Port** | Docker / iptables | CLI `-p` or Compose `ports:` | ✅ Yes |
| **Exposed Port** | Image Metadata | Dockerfile `EXPOSE` or Compose `expose:` | ❌ No |

---

## 3. Syntax Reference & Practical Examples

```bash
# Standard mapping: Host 8080 -> Container 80
docker run -d -p 8080:80 nginx

# Symmetrical mapping: Host 3000 -> Container 3000
docker run -d -p 3000:3000 node-api

# Bind to localhost ONLY (prevents external access)
docker run -d -p 127.0.0.1:5432:5432 postgres

# Random available host port allocated automatically
docker run -d -p 80 nginx

# Map UDP port
docker run -d -p 53:53/udp coredns
```

---

## 4. Publishing All Ports (`-P`)

The uppercase `-P` flag automatically maps all `EXPOSE` ports from the Dockerfile to random high-numbered ports on the host:

```bash
docker run -d -P --name web-app nginx
```

Check the assigned mappings:
```bash
docker port web-app
```

---

## 5. Docker Compose Port Configuration

```yaml
services:
  # Public web service
  web:
    image: nginx:alpine
    ports:
      # Published: host:container
      - "80:80"
      - "127.0.0.1:8080:80"

  # Internal microservice (only accessible inside the network)
  api:
    image: my-api:1.0
    expose:
      # Exposed metadata only — NO host port opened
      - "3000"
```

---

## 6. Common Issues & Debugging

```bash
# 1. View active port mappings for a container
docker port <container_name>

# 2. Check all container ports in table view
docker ps --format "table {{.Names}}\t{{.Ports}}"

# 3. Address already in use error
# Cause: Another process or container is already using that host port.
# Fix: Change the host port (e.g. -p 8081:80).
```

---

## References

- [Docker run published ports](https://docs.docker.com/engine/reference/commandline/run/#publish-or-expose-ports--p---publish-all)
- [Dockerfile EXPOSE instruction](https://docs.docker.com/engine/reference/builder/#expose)
