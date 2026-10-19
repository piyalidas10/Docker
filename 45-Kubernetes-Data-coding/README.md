# Kubernetes Data & Volumes — Coding Example

A small Node.js/Express "story" app deployed to Kubernetes. It demonstrates how to keep data alive across container restarts and across multiple replicas, using a **PersistentVolume (PV)** and **PersistentVolumeClaim (PVC)**, with the folder name supplied through a **ConfigMap**.

---

## Project Structure

```
45-Kubernetes-Data-coding/
├── app.js               # Express app (GET/POST /story, GET /error)
├── package.json         # Dependencies: express, body-parser
├── Dockerfile           # Image build (node:14-alpine, WORKDIR /app)
├── .dockerignore        # node_modules, Dockerfile, .git
├── docker-compose.yaml  # Local run with a Docker named volume
├── story/text.txt       # Local story file (empty)
├── deployment.yaml      # Deployment: 2 replicas, env from ConfigMap, PVC volume
├── service.yaml         # LoadBalancer Service (80 → 3000)
├── environment.yaml     # ConfigMap holding the story folder name
├── host-pv.yaml         # PersistentVolume (hostPath /data, 1Gi)
└── host-pvc.yaml        # PersistentVolumeClaim bound to host-pv
```

---

## The Application (`app.js`)

The story file path is built from the `STORY_FOLDER` environment variable:

```js
const filePath = path.join(__dirname, process.env.STORY_FOLDER, 'text.txt');
```

| Route | Behavior |
|---|---|
| `GET /story` | Reads `text.txt` → `{ story: "..." }`. Returns `500 Failed to open file.` if the file doesn't exist yet |
| `POST /story` | Body `{ "text": "..." }` → appends text + newline to `text.txt`. `422` if text is empty, `500` if storing fails, `201` on success |
| `GET /error` | Calls `process.exit(1)` → **crashes the container** so Kubernetes restarts it (used to prove that data survives) |

The server listens on port **3000**.

---

## Dockerfile

```dockerfile
FROM node:14-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
EXPOSE 3000
CMD [ "node", "app.js" ]
```

`WORKDIR /app` is why the story folder inside the container is **`/app/story`**.

### Docker Compose (local, non-Kubernetes)

```yaml
services:
  stories:
    build: .
    volumes:
      - stories:/app/story     # named volume → /app/story
    ports:
      - 80:3000
volumes:
  stories:
```

> `STORY_FOLDER` is not set in `docker-compose.yaml`, so the app needs it supplied when run this way (in Kubernetes it comes from the ConfigMap).

---

## Kubernetes Resources

### 1. ConfigMap — `environment.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: data-store-env
data:
  folder: 'story'
```

Provides the folder name (`story`) used for `STORY_FOLDER`.

### 2. PersistentVolume — `host-pv.yaml`

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: host-pv
spec:
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  storageClassName: standard
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /data
    type: DirectoryOrCreate
```

| Field | Meaning |
|---|---|
| `capacity.storage` | Size of the volume (1 GiB) |
| `volumeMode: Filesystem` | Exposed as a directory (not a raw block device) |
| `storageClassName: standard` | Default storage class in Minikube |
| `accessModes: ReadWriteOnce` | Mountable read-write by a **single node** (multiple Pods on that node can use it) |
| `hostPath.path: /data` | Directory on the **worker node** where data is stored |
| `hostPath.type: DirectoryOrCreate` | Use `/data` if it exists, otherwise create it |

A PV is a **cluster-level resource**, independent of any Pod.

### 3. PersistentVolumeClaim — `host-pvc.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: host-pvc
spec:
  volumeName: host-pv
  accessModes:
    - ReadWriteOnce
  storageClassName: standard
  resources:
    requests:
      storage: 1Gi
```

The claim is how a Pod asks for storage. `volumeName: host-pv` binds it explicitly to the PV above; `accessModes`, `storageClassName` and the requested size must be compatible with the PV.

### 4. Deployment — `deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: story-deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: story
  template:
    metadata:
      labels:
        app: story
    spec:
      containers:
        - name: story
          image: academind/kub-data-demo:2
          env:
            - name: STORY_FOLDER
              # value: 'story'
              valueFrom:
                configMapKeyRef:
                  name: data-store-env
                  key: folder
          volumeMounts:
            - mountPath: /app/story
              name: story-volume
      volumes:
        - name: story-volume
          # emptyDir: {}
          persistentVolumeClaim:
            claimName: host-pvc
```

Walkthrough:

| Part | Explanation |
|---|---|
| `replicas: 2` | Two Pods run the app. With `emptyDir` each would have its own data; with the PVC both share it |
| `selector.matchLabels` / `template.labels` | `app: story` ties the Deployment to its Pods (and to the Service) |
| `image: academind/kub-data-demo:2` | Image containing this app, including the `/error` route (tag `2`) |
| `env` → `STORY_FOLDER` | Value is read from the ConfigMap `data-store-env`, key `folder` (the commented-out `value: 'story'` is the hard-coded alternative) |
| `volumeMounts` | Mounts the volume `story-volume` at **`/app/story`** inside the container |
| `volumes` | Defined on the same level as `containers` (Pod spec) |
| `persistentVolumeClaim.claimName: host-pvc` | The volume is provided by the PVC. The commented `emptyDir: {}` is the earlier, Pod-specific approach |

**Connection chain:**

```
Container (/app/story)
   └─ volumeMounts: story-volume
        └─ volumes: story-volume → persistentVolumeClaim: host-pvc
             └─ PVC host-pvc → volumeName: host-pv
                  └─ PV host-pv → hostPath: /data (on the node)
```

### 5. Service — `service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: story-service
spec:
  selector:
    app: story
  type: LoadBalancer
  ports:
    - protocol: "TCP"
      port: 80
      targetPort: 3000
```

Exposes Pods labelled `app: story` externally on port **80**, forwarding to container port **3000**.

---

## Volume Approaches Compared

| Approach | In this folder | Survives container restart | Shared between replicas | Survives Pod deletion | Works across nodes |
|---|---|---|---|---|---|
| `emptyDir` | commented out in `deployment.yaml` | ✅ | ❌ (per Pod) | ❌ | ❌ |
| `hostPath` (in the Pod spec) | — | ✅ | ✅ (same node) | ✅ | ❌ |
| **PV + PVC (`hostPath` PV)** | **active** | ✅ | ✅ (same node) | ✅ (PV is independent of Pods) | ❌ (`hostPath` is node-specific) |

The PV/PVC pair separates **storage definition** (admin, cluster-level) from **storage request** (Pod/app-level). Here the PV still uses `hostPath`, so it is fine for Minikube (single node); a multi-node cluster would use a cloud/network-backed PV.

---

## How to Run

### Build and push the image (optional — if you change the code)

```bash
docker build -t academind/kub-data-demo:2 .
docker push academind/kub-data-demo:2
```

### Deploy to Kubernetes (Minikube)

Apply the storage and configuration first, then the Deployment and Service:

```bash
kubectl apply -f=host-pv.yaml
kubectl apply -f=host-pvc.yaml
kubectl apply -f=environment.yaml
kubectl apply -f=deployment.yaml -f=service.yaml
```

### Verify

```bash
kubectl get pv
kubectl get pvc
kubectl get pods
kubectl get deployments
```

### Access the service (Minikube)

```bash
minikube service story-service
```

### Test persistence

1. `GET  <url>/story` → `Failed to open file.` (file doesn't exist yet)
2. `POST <url>/story` with body `{ "text": "My first story" }` → `Text was stored!`
3. `GET  <url>/story` → returns the stored text
4. `GET  <url>/error` → one container crashes and restarts
5. `GET  <url>/story` → **data is still there**, no matter which Pod answers (both share the PVC)

### Clean up

```bash
kubectl delete -f=deployment.yaml -f=service.yaml
kubectl delete -f=host-pvc.yaml -f=host-pv.yaml
kubectl delete -f=environment.yaml
```

---

## Key Takeaways

- Volumes are defined in the **Pod spec** and mounted per container with `volumeMounts`
- `emptyDir` is Pod-specific → data is lost when requests hit a different replica or the Pod is removed
- A **PV + PVC** decouples storage from Pods, so data outlives Pods and is shared by all replicas on the node
- A **ConfigMap** keeps configuration (here the folder name) out of the image and the Deployment
