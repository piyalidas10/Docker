# 22 — Docker Logging & Monitoring Deep Dive

Observability is a foundational pillar for running Docker workloads reliably in production. It consists of two complementary disciplines:
- **Logging**: Capturing, formatting, and shipping discrete events and error traces.
- **Monitoring & Metrics**: Tracking real-time resource utilization, operational health, and event streams.

---

## The Centralized Logging Pipeline

In modern containerized environments, applications must follow **Twelve-Factor App** principles: write logs directly to `stdout` and `stderr` as an event stream. Docker intercepts these streams and forwards them via configured logging drivers to enterprise aggregation backends.

```
┌────────────────────────────────────────────────────────┐
│                      Application                       │
│    (Express, FastAPI, Spring Boot, Go, NGINX, etc.)    │
└───────────────────────────┬────────────────────────────┘
                            │ writes to
                            ▼
┌────────────────────────────────────────────────────────┐
│                     stdout / stderr                    │
│                 (Standard Output/Error)                │
└───────────────────────────┬────────────────────────────┘
                            │ intercepted by
                            ▼
┌────────────────────────────────────────────────────────┐
│                 Docker Logging Driver                  │
│    (json-file, local, syslog, fluentd, awslogs, gelf)  │
└───────────────────────────┬────────────────────────────┘
                            │ ships to
                            ▼
┌────────────────────────────────────────────────────────┐
│              Centralized Logging Platform              │
│       (ELK Stack, OpenSearch, Grafana Loki, etc.)      │
└────────────────────────────────────────────────────────┘
```

---

## Table of Contents

1. [Core CLI Observability Commands](#1-core-cli-observability-commands)
   - [`docker logs`](#1-docker-logs)
   - [`docker stats`](#2-docker-stats)
   - [`docker events`](#3-docker-events)
   - [`docker inspect`](#4-docker-inspect)
2. [Docker Logging Concepts & Architecture](#2-docker-logging-concepts--architecture)
   - [The `stdout` / `stderr` Rule](#the-stdout--stderr-rule)
   - [Supported Logging Drivers](#supported-logging-drivers)
   - [Log Rotation (Preventing Host Disk Exhaustion)](#log-rotation-preventing-host-disk-exhaustion)
3. [Configuring Logging Drivers](#3-configuring-logging-drivers)
   - [Per-Container via CLI](#per-container-via-cli)
   - [In Docker Compose](#in-docker-compose)
   - [Globally via `daemon.json`](#globally-via-daemonjson)
4. [Enterprise Logging & Monitoring Stacks](#4-enterprise-logging--monitoring-stacks)
   - [ELK Stack (Elasticsearch, Logstash, Kibana)](#elk-stack-elasticsearch-logstash-kibana)
   - [OpenSearch](#opensearch)
   - [Grafana Loki + Promtail](#grafana-loki--promtail)
   - [Prometheus + Grafana + cAdvisor](#prometheus--grafana--cadvisor)
5. [Complete Production Observability Compose Stack](#5-complete-production-observability-compose-stack)
6. [Best Practices & Production Checklist](#6-best-practices--production-checklist)

---

## 1. Core CLI Observability Commands

Docker provides four essential CLI tools for inspecting runtime state, logs, metrics, and lifecycle events:

### 1. `docker logs`
Fetches stdout and stderr emitted by a container's main process (PID 1).

```bash
# View all logs emitted by container
docker logs my-app

# Stream logs in real-time (like tail -f)
docker logs -f my-app

# Show only the last 50 lines
docker logs --tail 50 my-app

# Follow logs with timestamps
docker logs -f -t my-app

# View logs emitted since a specific timestamp or duration
docker logs --since 10m my-app
docker logs --since "2025-01-01T12:00:00Z" my-app

# Show logs until a specific point in time
docker logs --until 5m my-app
```

---

### 2. `docker stats`
Streams live resource usage metrics (CPU%, Memory Usage, Memory %, Network I/O, Block I/O, PIDs) for running containers.

```bash
# Stream live metrics for all running containers
docker stats

# Stream metrics for specific containers
docker stats api-service db-postgres

# Snapshot mode (non-streaming, ideal for scripts/cron)
docker stats --no-stream

# Format output using Go templates
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}"
```

---

### 3. `docker events`
Streams real-time operational events from the Docker daemon engine (e.g. container create, start, die, pause, kill, volume create, network connect).

```bash
# Stream all real-time daemon events
docker events

# Filter events by container
docker events --filter 'container=api-service'

# Filter events by type and action (e.g., container deaths/crashes)
docker events --filter 'type=container' --filter 'event=die'

# Show events formatted as JSON
docker events --format '{{json .}}'

# View historical events within a specific time window
docker events --since '1h' --until '5m'
```

---

### 4. `docker inspect`
Returns complete low-level runtime metadata, configuration, network settings, health status, and resource limits in structured JSON format.

```bash
# Inspect all metadata for a container
docker inspect my-app

# Extract IP address
docker inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' my-app

# Extract current health check status
docker inspect --format '{{.State.Health.Status}}' my-app

# Extract restart count and exit code
docker inspect --format 'ExitCode: {{.State.ExitCode}}, Restarts: {{.RestartCount}}' my-app

# Inspect applied memory limits
docker inspect --format 'Memory Limit: {{.HostConfig.Memory}} bytes' my-app
```

---

## 2. Docker Logging Concepts & Architecture

### The `stdout` / `stderr` Rule
In containerized environments, **never write application logs to internal files** (e.g. `/var/log/app.log`) inside the container layer:
- Logs written to container files consume Copy-on-Write disk space.
- When the container is destroyed or rescheduled, those log files disappear.
- Docker cannot capture internal file logs without heavy file-watching sidecars.

Always configure application logging frameworks (Logback, Winston, Serilog, Zap, Loguru) to stream structured JSON directly to **`stdout`** and **`stderr`**.

---

### Supported Logging Drivers

| Logging Driver | Description | Best Suited For |
|---|---|---|
| **`json-file`** | Default driver. Writes JSON-formatted logs to local host disk. | Local development and standalone single-host servers. |
| **`local`** | Optimized binary local log driver with automatic rotation. | High-performance standalone hosts. |
| **`syslog`** | Forwards logs to a system syslog daemon / remote syslog server. | Traditional Linux VM and enterprise server infrastructures. |
| **`journald`** | Writes logs directly to systemd's `journald` service. | Linux distributions using systemd logging. |
| **`fluentd`** | Forwards logs via forward protocol to a Fluentd / Fluent Bit collector. | High-throughput distributed microservice clusters. |
| **`awslogs`** | Streams logs directly to AWS CloudWatch Logs. | Containers running in AWS (EC2, ECS). |
| **`gelf`** | Graylog Extended Log Format (works with Graylog, Logstash). | Enterprise log management platforms. |

---

### Log Rotation (Preventing Host Disk Exhaustion)

By default, the `json-file` driver does not limit log file size. An active production service can generate gigabytes of logs and crash the host by filling the root disk partition.

**Golden Rule:** Always enforce log rotation limits (`max-size` and `max-file`):
- `max-size`: Maximum file size before rotating (e.g., `10m`, `50m`).
- `max-file`: Maximum number of rotated archive files to retain (e.g., `3`, `5`).

---

## 3. Configuring Logging Drivers

### Per-Container via CLI:
```bash
docker run -d \
  --name web-app \
  --log-driver json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  -p 8080:80 \
  nginx:alpine
```

### In Docker Compose (`compose.yaml`):
```yaml
services:
  api:
    image: my-api:1.0
    logging:
      driver: "json-file"
      options:
        max-size: "20m"
        max-file: "5"
```

### Globally for All Containers via `/etc/docker/daemon.json`:
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  }
}
```
*Reload daemon after updating:* `sudo systemctl reload docker`

---

## 4. Enterprise Logging & Monitoring Stacks

In production environments, individual container logs and host metrics must be aggregated into centralized observability suites:

```
                  ┌──────────────────────────────────────────────┐
                  │          ENTERPRISE OBSERVABILITY            │
                  └──────────────────────┬───────────────────────┘
                                         │
                 ┌───────────────────────┴───────────────────────┐
                 │                                               │
                 ▼                                               ▼
     ┌───────────────────────┐                       ┌───────────────────────┐
     │   LOG AGGREGATION     │                       │  METRICS & MONITORING │
     ├───────────────────────┤                       ├───────────────────────┤
     │ • ELK Stack           │                       │ • Prometheus          │
     │ • OpenSearch          │                       │ • cAdvisor            │
     │ • Grafana Loki        │                       │ • Node Exporter       │
     │ • Fluent Bit          │                       │ • Grafana Dashboards  │
     └───────────────────────┘                       └───────────────────────┘
```

### ELK Stack (Elasticsearch, Logstash, Kibana)
- **Logstash / Filebeat**: Ships and parses logs from Docker hosts.
- **Elasticsearch**: Distributed search and analytics engine for log indexing.
- **Kibana**: Web UI for searching logs, building visual query dashboards, and tracing errors.

### OpenSearch
- Community-driven, open-source fork of Elasticsearch and Kibana (maintained by AWS and the Linux Foundation).
- Full compatibility with existing Logstash and Fluent Bit forwarders with built-in security features.

### Grafana Loki + Promtail
- **Loki**: "Like Prometheus, but for logs". Only indexes log labels and metadata rather than full-text indexing, drastically reducing RAM and storage costs.
- **Promtail**: Lightweight agent that reads container logs from `/var/lib/docker/containers/*/*.log` and ships them to Loki.
- **Grafana**: Unified UI to query logs side-by-side with metrics.

### Prometheus + Grafana + cAdvisor
- **cAdvisor (Container Advisor)**: Google tool running in a container that analyzes and exposes CPU, memory, filesystem, and network stats for all running containers on the host.
- **Node Exporter**: Collects host OS hardware metrics (disk space, kernel stats, network interfaces).
- **Prometheus**: Time-series database that scrapes metrics from cAdvisor and Node Exporter every 15s.
- **Grafana**: Visualizes real-time metrics, sets up threshold alert triggers (e.g., Slack, PagerDuty when container memory > 85%).

---

## 5. Complete Production Observability Compose Stack

Below is a complete, self-contained `compose.yaml` demonstrating Prometheus, cAdvisor, and Grafana monitoring Docker containers:

```yaml
services:
  # 1. cAdvisor - Collects container resource usage
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    privileged: true
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    ports:
      - "8080:8080"
    networks:
      - monitoring_net

  # 2. Prometheus - Scrapes and stores time-series metrics
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    ports:
      - "9090:9090"
    networks:
      - monitoring_net
    depends_on:
      - cadvisor

  # 3. Grafana - Visualizes metrics and dashboards
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=adminpassword
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - "3000:3000"
    networks:
      - monitoring_net
    depends_on:
      - prometheus

networks:
  monitoring_net:
    driver: bridge

volumes:
  prometheus_data:
  grafana_data:
```

### Corresponding `prometheus.yml`:
```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
```

---

## 6. Best Practices & Production Checklist

- [ ] **Stream to standard streams**: All apps write to `stdout` (normal/info logs) and `stderr` (errors).
- [ ] **Structured JSON logs**: Logs formatted as JSON with timestamps, correlation IDs, and severity levels.
- [ ] **Log rotation enforced**: Global `/etc/docker/daemon.json` sets `max-size: 50m` and `max-file: 5`.
- [ ] **cAdvisor + Prometheus deployed**: Continuous metric scraping for CPU, RAM, and network I/O.
- [ ] **Grafana Dashboards & Alerts**: Configured alerts for container restarts, OOM kills, and high memory pressure.
- [ ] **Real-time audit monitoring**: Monitoring daemon lifecycle events via `docker events` or webhook forwarders.

---

## References

- [Docker Logging Architecture Overview](https://docs.docker.com/config/containers/logging/)
- [Docker Configure Logging Drivers](https://docs.docker.com/config/containers/logging/configure/)
- [Prometheus Monitoring System](https://prometheus.io/docs/introduction/overview/)
- [Google cAdvisor](https://github.com/google/cadvisor)
- [Grafana Loki Log Aggregation](https://grafana.com/oss/loki/)
