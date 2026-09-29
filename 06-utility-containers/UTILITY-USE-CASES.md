# Utility Containers: Use Cases & Execution Patterns

A **Utility Container** (also known as a task or ephemeral container) is designed to run a specific command, tool, or script and exit immediately upon completion.

Instead of polluting the host machine with multiple language runtimes, package managers, database CLI tools, or build chains, you containerize the tooling itself.

---

## Core Use Cases

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Utility Container Uses                          │
│                                                                        │
│   📦 Dependency Installation       🛠️ Running CLI Tools                │
│   (npm install, pip install)       (aws-cli, terraform, curl, ffmpeg)  │
│                                                                        │
│   💻 Development Utilities         🗄️ Database Migrations             │
│   (linters, formatters, code-gen)  (Flyway, Prisma, Liquibase, Alembic)│
│                                                                        │
│   🧪 Automated Testing             ⚡ One-Time / Scheduled Jobs        │
│   (Jest, pytest, security scans)   (DB seeding, backups, batch exports)│
└────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Dependency Installation

Avoid installing language runtimes (Node, Python, Go, Ruby, PHP/Composer) on the host machine. Run the package manager in an ephemeral container with the project folder bind-mounted so artifacts (e.g. `node_modules`, lockfiles) are written directly to your host workspace.

### Examples:

#### Node.js / npm:
```bash
docker run --rm \
  -v "$(pwd):/app" \
  -w /app \
  node:20-alpine \
  npm install
```

#### Python / pip:
```bash
docker run --rm \
  -v "$(pwd):/app" \
  -w /app \
  python:3.12-slim \
  pip install -r requirements.txt -t ./libs
```

#### PHP / Composer:
```bash
docker run --rm \
  -v "$(pwd):/app" \
  composer:2 \
  composer install --ignore-platform-reqs
```

---

## 2. Running CLI Tools

Run specialized CLI tools without installing them or dealing with version conflicts across operating systems.

### Examples:

#### AWS CLI:
```bash
# Execute AWS commands using local AWS credentials
docker run --rm -it \
  -v ~/.aws:/root/.aws:ro \
  -v "$(pwd):/aws" \
  amazon/aws-cli s3 ls
```

#### Terraform:
```bash
docker run --rm -it \
  -v "$(pwd):/workspace" \
  -w /workspace \
  hashicorp/terraform:latest plan
```

#### Video / Audio Processing with FFmpeg:
```bash
docker run --rm \
  -v "$(pwd):/media" \
  -w /media \
  jrottenberg/ffmpeg:6.1-alpine \
  -i input.mp4 -c:v libx264 -crf 23 output.mp4
```

---

## 3. Development Utilities

Use containers for code linters, formatters, type-checkers, and code generators so every team member and CI pipeline runs the exact same toolchain version.

### Examples:

#### Code Formatting (Prettier / Black):
```bash
# Prettier for JavaScript/TypeScript
docker run --rm \
  -v "$(pwd):/app" \
  -w /app \
  tmknom/prettier --write "src/**/*.{js,ts,json,md}"

# Black for Python
docker run --rm \
  -v "$(pwd):/app" \
  -w /app \
  pyfound/black:latest_release black .
```

#### Project Scaffolding:
```bash
# Initialize a new NestJS or React project
docker run --rm -it \
  -v "$(pwd):/app" \
  -w /app \
  node:20-alpine \
  npx create-react-app client
```

---

## 4. Database Migrations

Run database schema migration tools that need access to the internal Docker network where the database runs, without exposing database ports to the host machine.

### Examples:

#### Prisma (Node.js):
```bash
docker run --rm \
  --network app-network \
  -v "$(pwd):/app" \
  -w /app \
  -e DATABASE_URL="postgresql://user:pass@postgres:5432/mydb" \
  node:20-alpine \
  npx prisma migrate deploy
```

#### Flyway (SQL Migrations):
```bash
docker run --rm \
  --network app-network \
  -v "$(pwd)/sql:/flyway/sql" \
  flyway/flyway:10 \
  -url=jdbc:postgresql://postgres:5432/mydb \
  -user=postgres \
  -password=secret \
  migrate
```

---

## 5. Automated Testing

Run test suites in clean, isolated, reproducible environments without test pollution or dependency conflicts.

### Examples:

#### Unit & Integration Tests:
```bash
# Node.js Jest test suite
docker run --rm \
  -v "$(pwd):/app" \
  -w /app \
  node:20-alpine \
  npm test -- --ci --coverage

# Python pytest
docker run --rm \
  -v "$(pwd):/app" \
  -w /app \
  python:3.12-slim \
  pytest tests/
```

#### Security Vulnerability Scan:
```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest \
  image myapp:1.0
```

---

## 6. One-Time Jobs & Administrative Tasks

Execute periodic or ad-hoc tasks such as database seed scripts, data exports, or backup routines.

### Examples:

#### Database Seeding:
```bash
docker run --rm \
  --network app-network \
  -v "$(pwd):/app" \
  -w /app \
  node:20-alpine \
  node scripts/seed-database.js
```

#### Database Backup & Dump:
```bash
docker run --rm \
  --network app-network \
  -v "$(pwd)/backups:/backups" \
  postgres:16-alpine \
  pg_dump -h postgres -U postgres -d mydb -f /backups/backup_$(date +%Y%m%d).sql
```

---

## 7. Docker Compose Utility Service Pattern

Declare utility containers as on-demand services in `docker-compose.yml`:

```yaml
services:
  # Main App Service
  app:
    build: .
    ports:
      - "3000:3000"
    networks:
      - backend

  # Database
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: mydb
    networks:
      - backend

  # Utility: Dependency Management
  npm:
    image: node:20-alpine
    working_dir: /app
    volumes:
      - ./:/app
    entrypoint: ["npm"]

  # Utility: Database Migrator
  migrate:
    image: node:20-alpine
    working_dir: /app
    volumes:
      - ./:/app
    environment:
      DATABASE_URL: postgres://postgres:secret@postgres:5432/mydb
    networks:
      - backend
    entrypoint: ["npx", "prisma", "migrate", "deploy"]
```

### Running Utility Services via Compose:
```bash
# 1. Install dependencies
docker compose run --rm npm install

# 2. Add a new package
docker compose run --rm npm install axios

# 3. Run database migrations
docker compose run --rm migrate
```

---

## Key Best Practices

1. **Always use `--rm`**: Ensures the container writable layer is immediately purged upon task completion.
2. **Bind-mount project workspace (`-v $(pwd):/app -w /app`)**: Guarantees output files (e.g. `package-lock.json`, generated code, logs) are saved back to the host filesystem.
3. **Set locked `ENTRYPOINT` in custom tooling images**: Allows the container to act syntactically like a local CLI binary.
4. **Attach to target network (`--network <name>`)**: Allows migration and seeding utility containers to reach private internal database containers without publishing ports to the host.
