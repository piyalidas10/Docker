# Kubernetes â€” Data & Volumes

---

## What is State?

**State = data created and used by your app that must not be lost.**

| Type | Examples | Typical Storage |
|---|---|---|
| User-generated data | User accounts, uploaded files, story text files | Databases, files |
| Intermediate results | Temp calculations, session data | Memory, temp DB tables/files |

Both types must **survive container restarts** â€” that is exactly what volumes are for.

---

## Why Volumes Still Matter in Kubernetes

- We already know volumes from Docker â€” the concept does not change
- With Kubernetes, **you no longer run containers directly** (`docker run` / Docker Compose)
- Kubernetes creates and manages Pods, which run your containers
- Therefore, volumes must be configured **inside Kubernetes** â€” not via Docker CLI flags
- This module covers how to instruct Kubernetes to create and mount volumes into containers

---

## Kubernetes Volume Support

Kubernetes has powerful, flexible volume support built in.

### Supported volume types (drivers)

| Type | Where data is stored |
|---|---|
| `emptyDir` | Temporary directory on the node â€” lives as long as the Pod |
| `hostPath` | A path on the worker node's filesystem |
| Cloud-specific | AWS EBS, Azure Disk, GCE Persistent Disk, etc. |
| `persistentVolumeClaim` | Abstracted persistent storage (covered later) |

> Because Kubernetes runs across **multiple nodes** on potentially different cloud providers, it needs this flexibility. Plain Docker, running on a single machine, does not.

---

## Volume Lifetime Rules

```
Pod
 â””â”€â”€ Volume
      â””â”€â”€ Container
```

| Event | Volume survives? |
|---|---|
| Container restarts / removed | âœ… Yes â€” volume is in the Pod, not the container |
| Pod is destroyed | âŒ No â€” volume is removed with the Pod |

- Volumes are **pod-specific** by default
- They survive container-level restarts and replacements
- They are **lost when the Pod is deleted**
- Persistent volumes (covered in the next step) solve the pod-removal problem

---

## Kubernetes Volumes vs Docker Volumes

| | Docker Volumes | Kubernetes Volumes |
|---|---|---|
| **Driver / Type support** | Basically none | Supports many different drivers and types |
| **Persistence** | Persist until manually cleared | Not necessarily persistent â€” tied to Pod lifetime by default |
| **Multi-node support** | No | Yes â€” works across nodes and cloud providers |
| **Configuration** | `-v` flag / Compose `volumes:` | Defined in Pod / Deployment spec |

### Kubernetes Volumes
- âœ… Supports **many different drivers and types** (local, cloud, network storage, etc.)
- âš ï¸ **Not necessarily persistent** â€” volumes survive container restarts but are removed when the Pod is destroyed

### Docker Volumes
- âš ï¸ Basically **no driver / type support** â€” storage is always on the local machine
- âœ… **Persist until manually cleared** â€” no concept of pod lifecycle to worry about

> Kubernetes **leverages the Docker volume system** but adds drivers, type flexibility, and multi-node support on top â€” because it needs to run across clusters, nodes, and cloud providers.

---

## Where to Define Volumes

- A volume's lifetime depends on a **Pod**, because volumes are **attached to Pods** and are Pod-specific
- Therefore, volumes must be defined **where the Pod is defined and configured**
- In a Deployment, that is the **Pod specification** (`spec.template.spec`)

---

## Demo: Seeing the Problem (Data Lost on Container Restart)

To prove that a volume makes a difference, first reproduce the problem.

### 1. Add an error route to `app.js`

```js
app.get('/error', () => {
  process.exit(1);   // crashes the container â†’ Kubernetes restarts it
});
```

### 2. Rebuild, tag and push the image

```bash
docker build -t <dockerhub-user>/kub-data-demo:1 .
docker push <dockerhub-user>/kub-data-demo:1
```

### 3. Use the new tag in `deployment.yaml`

```yaml
containers:
  - name: story
    image: <dockerhub-user>/kub-data-demo:1
```

### 4. Apply the configuration

```bash
kubectl apply -f=deployment.yaml
kubectl get pods
```

- The old Pod is `Terminating`, a new Pod is created with the new image
- The data is lost after this (new Pod, new container) â€” that is expected
- POST some data again â†’ GET returns it

### 5. Trigger the crash

- Send a request to `<service-url>/error` â†’ the container crashes
- Send a GET request afterwards â†’ it works again (Kubernetes restarted the container)
- **But the data is gone**
- `kubectl get pods` still shows **one Pod**, with `RESTARTS: 1` â†’ the *container* restarted, not the Pod

> Without a volume, data written inside the container's filesystem is lost whenever the container restarts.

---

## Adding an `emptyDir` Volume

### Step 1 â€” Define the volume in the Pod spec

`volumes` goes **on the same level as `containers`** (not nested inside it). All containers in the Pod can use the volumes defined here.

```yaml
spec:
  containers:
    - name: story
      image: <dockerhub-user>/kub-data-demo:1
  volumes:
    - name: story-volume
      emptyDir: {}
```

- `volumes` is a **list** â†’ each entry starts with `-`
- `name` is up to you (here `story-volume`, because it stores the stories)
- Next to `name`, set the **volume type** â€” depends on the type you choose, more options may be available
- `emptyDir: {}` â†’ an empty object means **default settings**, which typically suffice

### What `emptyDir` does

- Creates a **new empty directory whenever the Pod starts**
- Keeps the directory (and its data) alive **as long as the Pod is alive**
- Containers write into it; data **survives container restarts/removals**
- If the **Pod is removed**, the directory is removed too; a recreated Pod gets a **new empty directory**

### Step 2 â€” Mount the volume into the container

Defining a volume is not enough â€” it must be made available **inside a container** via `volumeMounts` in the container configuration.

```yaml
spec:
  containers:
    - name: story
      image: <dockerhub-user>/kub-data-demo:1
      volumeMounts:
        - mountPath: /app/story
          name: story-volume
  volumes:
    - name: story-volume
      emptyDir: {}
```

| Key | Meaning |
|---|---|
| `mountPath` | **Container-internal path** where the volume is mounted. Depends on your app â€” here it writes to `/app/story` (`/app` = `WORKDIR` from the Dockerfile, `story` = folder holding `text.txt`) |
| `name` | Which **volume** (from `volumes`) to mount at that path |

- `volumeMounts` is a list as well â†’ a container can mount multiple volumes at different paths
- `name` is required because a Pod may define several volumes / types
- Same idea as the `/app/story` named-volume path in a Docker Compose file â€” the difference is that here **you tell Kubernetes the volume type** (`emptyDir`) instead of getting an automatic named volume

### Step 3 â€” Apply and test

```bash
kubectl apply -f=deployment.yaml
```

The old Pod is terminated and a new one is started. Then:

1. **GET** â†’ fails with `failed to open file` (different error than before). The empty directory has no `text.txt` yet â€” not a real problem
2. **POST** â†’ `text was stored` (the file is created on write if missing)
3. **GET** â†’ data is returned; further POSTs are **appended**
4. Send a request to `/error` â†’ the container restarts
5. **GET** again â†’ **the data is still there** âœ…

> That is the difference compared to before: the volume lives in the Pod, so it survives container restarts.

---

## Downside of `emptyDir`: Multiple Replicas

`emptyDir` is a great basic volume, but it is **Pod-specific**.

### Reproducing the problem

1. Set `replicas: 2` in `deployment.yaml` and apply it
   ```bash
   kubectl apply -f=deployment.yaml
   kubectl get pods     # two Pods running
   ```
2. GET â†’ still returns the stored data (served by Pod A)
3. Send a request to `/error` â†’ the container in one Pod crashes and traffic is redirected to the other Pod
4. GET again â†’ `failed to open file` (request now hits Pod B, which has its **own** empty directory)
5. After the crashed container restarts, requests that reach Pod A still return the data (it is stored in Pod A's volume)

> Volumes are closely attached to Pods. If a request is sent to a **different Pod**, the data is not there.

---

## `hostPath` Volume

One way to work around this: switch from `emptyDir` (new empty directory **per Pod**) to the `hostPath` driver.

- Sets a **path on the host machine** (the worker node actually running the Pod)
- The data from that path is exposed to the Pods â†’ **multiple Pods share the same path** instead of having Pod-specific directories
- Similar to a **bind mount** in Docker: a host path is bound to a container-internal path

### Switching from `emptyDir` to `hostPath`

Replace `emptyDir: {}` with `hostPath` and nested configuration keys:

```yaml
volumes:
  - name: story-volume
    hostPath:
      path: /data
      type: DirectoryOrCreate
```

| Key | Meaning |
|---|---|
| `path` | Path on the **host machine** (not in the container) where data is stored. Up to you â€” just don't use paths reserved by Linux |
| `type` | How Kubernetes should handle the path |

The container side stays the same (`volumeMounts` â†’ `mountPath: /app/story`, `name: story-volume`) â€” everything in the host `/data` folder is shared with `/app/story` in the container.

### `type` values

| Value | Behavior |
|---|---|
| `DirectoryOrCreate` | Must be a directory; **created if it doesn't exist yet** (used here, since `/data` doesn't exist yet in the VM) |
| `Directory` | Must be an existing directory; **fails if it doesn't exist** |

### Apply and test

```bash
kubectl apply -f=deployment.yaml
kubectl get pods      # old Pods terminating, new Pods running
```

1. GET â†’ fails initially (`text.txt` doesn't exist yet)
2. Send several POST requests, then GET â†’ data is returned
3. Send a request to `/error` (crashes one container)
4. GET â†’ **data is still available**, because multiple Pods share the same path on the worker node

### `emptyDir` vs `hostPath`

| | `emptyDir` | `hostPath` |
|---|---|---|
| **Scope** | Pod-specific | Shared by all Pods on the same node |
| **Initial content** | Always a new, empty directory | Shares the path **and whatever is already inside it** |
| **Use for pre-existing data** | No | Yes â€” existing data in the host folder is available in the container from the start |
| **Good for** | Single replica, development, simple experiments | Pod-independent data on a single node |

### Limitations of `hostPath`

- Still **node-specific**: in a cluster with multiple worker nodes, Pods on different nodes do **not** share the data â€” only Pods on the same node do
- Here (Minikube) there is only one node, so it works; in a bigger cluster it would not
- It is an improvement for Pod independence, but a better solution follows (Persistent Volumes)

---

## Next Steps

- Use **Persistent Volumes (PV)** and **Persistent Volume Claims (PVC)** for data that survives Pod removal
- Explore the **CSI volume type** for flexible, third-party storage integration (covered below)

---

## The CSI Volume Type

### What is CSI?

**CSI** stands for **Container Storage Interface**.

It is a relatively new volume type added by the Kubernetes team to solve a specific problem: rather than adding more and more built-in volume types for every cloud provider and use case, Kubernetes exposes a clearly defined interface — and anyone can build **driver solutions** that plug into it.

> The existing built-in types (like `awsElasticBlockStore`, various Azure types, `nfs`) are each very specific. The CSI type is the **open, extensible alternative** that replaces the need for new built-ins.

---

### Why It Was Needed

Some built-in volume types are very provider-specific:

| Type | What it does |
|---|---|
| `awsElasticBlockStore` | Uses the AWS EBS service as storage |
| Azure volume types | Use various Azure storage services |
| `nfs` | Connects to any Network File System server |

The problem: not every storage solution has a dedicated built-in type. For example, **Amazon Elastic File System (EFS)** — an NFS-based AWS service — has no dedicated built-in Kubernetes type. You could try to make it work via the `nfs` type, but that requires extra effort and is not ideal.

---

### How CSI Solves This

Because the Kubernetes team exposed the CSI interface, third-party teams can build and publish their own **CSI drivers**:

- The **AWS team** built a CSI driver specifically for Amazon EFS
- Search for **"AWS EFS CSI"** to find the [official GitHub project](https://github.com/kubernetes-sigs/aws-efs-csi-driver) with installation instructions and usage examples
- Many other official CSI drivers already exist for various cloud and on-premise storage solutions
- You can also **write your own** driver (e.g. for a private data center)

---

### Summary

| Aspect | Detail |
|---|---|
| **Full name** | Container Storage Interface |
| **Purpose** | Attach *any* external storage solution via a standardised interface |
| **How** | Third-party teams publish CSI drivers; you reference the driver in your volume spec |
| **Example** | AWS EFS CSI driver → use EFS as a Kubernetes volume |
| **Extensibility** | Anyone can write a driver — cloud providers, on-prem, custom setups |
| **When to use locally** | Not needed for local dev / Minikube experimentation |
| **When to use in production** | Ideal for cloud deployments — e.g. using AWS EFS when deploying to AWS |

> For local development (Minikube), CSI is not required. When deploying to AWS later, the **AWS EFS CSI driver** will be used to provide persistent, shared storage for the cluster.
