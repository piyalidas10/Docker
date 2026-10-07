# Multi-Stage Builds: Targeting Specific Build Stages

## Overview

When working with multi-stage `Dockerfile`s, by default Docker executes all stages defined in the file from top to bottom, producing a final image based on the last stage. 

However, Docker also provides the flexibility to build **only up to a specific stage** rather than executing the entire `Dockerfile`. This is achieved using the `--target` flag with `docker build`.

---

## The `--target` Flag

You can instruct Docker to stop the build process after a specific named stage is completed.

### Syntax

```bash
docker build --target <stage-name> -t <image-name> -f <dockerfile-path> .
```

### Example: Multi-Stage Frontend Dockerfile

Consider a multi-stage production `Dockerfile` (e.g. `Dockerfile.prod` for a frontend app):

```dockerfile
# Stage 1: Build Stage
FROM node:22 AS build

WORKDIR /app
COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# Stage 2: Production Server Stage
FROM nginx:alpine

COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### What Ends Up in the Final Image?

Multi-stage builds create clean separation between the build environment and the production artifact:

| Included in Final Production Image | Excluded from Final Image (Discarded) |
|---|---|
| `nginx:alpine` runtime | Node.js runtime & npm CLI |
| Compiled frontend assets (`/app/dist` $\rightarrow$ `/usr/share/nginx/html`) | Entire raw source code files |
| Minimal OS layers | `node_modules` and heavy dev tools |
| Web server config (`nginx.conf`) | Unit test files, linters, and build tooling |

This separation ensures:
- **Smaller Image Sizes:** Final images drop from hundreds of MBs down to tens of MBs.
- **Reduced Attack Surface:** No compilers, package managers, or dev dependencies live on the production server.
- **Cleaner Production Deployments:** Only the web server and optimized static assets are shipped to remote machines.

---

### Building Only the First Stage

To stop the build after the `build` stage and skip the `nginx` web server stage:

```bash
docker build --target build -t frontend-build -f Dockerfile.prod .
```

**What happens:**
1. Docker processes the `build` stage (installs dependencies, copies source code, and runs `npm run build`).
2. Docker **stops** immediately after completing the `build` stage.
3. The resulting image contains the built code, but does **not** include the Nginx server or proceed to stage 2.

---

## Practical Use Cases for Multi-Stage Targeting

Targeting individual build stages is especially valuable in complex projects and CI/CD pipelines:

| Scenario | Example Multi-Stage Setup | Targeted Build Command |
|---|---|---|
| **Testing / CI** | Stage 1: `base` → Stage 2: `test` → Stage 3: `prod` | `docker build --target test ...` |
| **Development** | Stage 1: `base` → Stage 2: `dev` (with hot-reload) → Stage 3: `prod` | `docker build --target dev ...` |
| **Artifact Extraction** | Stage 1: `build` (compiles binaries/bundles) | `docker build --target build ...` |

### Benefits

- **Faster CI/CD Pipelines:** Run unit/integration tests in dedicated test stages without building heavy production images or launching web servers.
- **Single Dockerfile Maintenance:** Maintain a single `Dockerfile` that supports local testing, development, and production builds without duplication.
- **Granular Control:** Build only the layers and environments required for the task at hand.
