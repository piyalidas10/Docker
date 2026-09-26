# 02 — Dockerfile

A **Dockerfile** is a plain-text script of instructions that Docker reads to build an image automatically. Each instruction creates a new layer in the image.

---

## Common Instructions

| Instruction | Purpose |
|---|---|
| `FROM` | Base image to start from (must be first). |
| `WORKDIR` | Set the working directory inside the image. |
| `COPY` | Copy files from the build context into the image. |
| `ADD` | Like `COPY` but also handles URLs and auto-extracts archives. |
| `RUN` | Execute a shell command during the build. |
| `ENV` | Set environment variables available at build and runtime. |
| `ARG` | Build-time variable (not persisted in the final image). |
| `EXPOSE` | Document which port the container listens on. |
| `CMD` | Default command to run when the container starts (overridable). |
| `ENTRYPOINT` | Fixed command that always runs; `CMD` becomes its default args. |

---

## Minimal Example — Node.js App

```dockerfile
# Use a specific, lightweight base image
FROM node:20-alpine

# Set the working directory
WORKDIR /app

# Copy dependency manifests first (layer-cache optimisation)
COPY package*.json ./

# Install dependencies
RUN npm ci --omit=dev

# Copy application source
COPY . .

# Expose the port the app listens on
EXPOSE 3000

# Start the application
CMD ["node", "server.js"]
```

---

## Build & Run

```bash
# Build an image and tag it
docker build -t my-app:1.0 .

# Build with a custom Dockerfile path
docker build -f docker/Dockerfile.prod -t my-app:prod .

# Pass a build argument
docker build --build-arg NODE_ENV=production -t my-app .

# Run the built image
docker run -p 3000:3000 my-app:1.0
```

---

## Layer Caching

Docker caches each layer. A layer is only rebuilt when the instruction **or any layer before it** changes.

**Best practice:** copy dependency files (`package.json`, `requirements.txt`, etc.) and install them **before** copying the rest of the source code. This way, dependencies are only re-installed when they actually change.

```dockerfile
# ✅ Good — dependencies cached separately from source
COPY package*.json ./
RUN npm ci
COPY . .

# ❌ Bad — any source change forces npm ci to re-run
COPY . .
RUN npm ci
```

---

## .dockerignore

Create a `.dockerignore` file to exclude files from the build context, keeping images small and preventing secrets from leaking in:

```
node_modules
.git
*.log
.env
dist
```

---

## Multi-Stage Builds

Use multiple `FROM` statements to keep the final image lean:

```dockerfile
# --- Build stage ---
FROM node:20 AS builder
WORKDIR /app
COPY . .
RUN npm ci && npm run build

# --- Production stage ---
FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
CMD ["node", "dist/server.js"]
```

---

## References

- [Dockerfile reference](https://docs.docker.com/engine/reference/builder/)
- [Best practices for writing Dockerfiles](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [Multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
