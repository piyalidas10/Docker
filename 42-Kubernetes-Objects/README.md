# Kubernetes Objects — Complete Study Guide

> A complete reference covering Kubernetes objects, their purpose, how to create them, and how they work together in an enterprise application.
>
> **Example application:** Angular frontend · FastAPI backend · Authentication service · PostgreSQL database

<img src="./Kubernetes Objects and Study Guide.png" width="90%" />

---

## A. Understand Each Kubernetes Object

### 1. The Four Main Kubernetes Objects

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      MAIN KUBERNETES OBJECTS                                 │
│                                                                             │
│  ┌──────────────────────────────┐   ┌──────────────────────────────────┐   │
│  │           1. Pod              │   │         2. Deployment             │   │
│  │                              │   │                                  │   │
│  │  Smallest deployable unit.   │   │  Manages stateless replicas via  │   │
│  │  Runs one or more containers │   │  ReplicaSets. Handles scaling,   │   │
│  │  sharing networking and      │   │  rolling updates, and failed     │   │
│  │  optionally storage.         │   │  Pod replacement.                │   │
│  │                              │   │                                  │   │
│  │  Example: One Pod running    │   │  Example: 3 replicas of the      │   │
│  │  your FastAPI container.     │   │  FastAPI backend.                │   │
│  │                              │   │                                  │   │
│  │  Resource: Pod               │   │  Resource: Deployment            │   │
│  └──────────────────────────────┘   └──────────────────────────────────┘   │
│                                                                             │
│  ┌──────────────────────────────┐   ┌──────────────────────────────────┐   │
│  │          3. Service           │   │   4. Volume & Persistent Storage  │   │
│  │                              │   │                                  │   │
│  │  Provides a stable network   │   │  Makes storage available to      │   │
│  │  endpoint for a set of Pods. │   │  containers. Temporary volumes   │   │
│  │  Distributes traffic across  │   │  die with the Pod; persistent    │   │
│  │  eligible replicas.          │   │  storage survives replacement.   │   │
│  │                              │   │                                  │   │
│  │  Example: Angular frontend   │   │  Example: PostgreSQL database    │   │
│  │  reaches backend via         │   │  files on persistent storage.    │   │
│  │  http://backend-service.     │   │                                  │   │
│  │                              │   │  Resources: Volume, PV, PVC      │   │
│  │  Resource: Service           │   │                                  │   │
│  └──────────────────────────────┘   └──────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

> **Important distinction:**
> - A **Pod** is where the container runs.
> - A **Deployment** manages the desired number and lifecycle of stateless Pods.
> - A **Service** gives those Pods a stable network endpoint.

#### Why Do We Need a Deployment?

The **Deployment** is one of the key objects you work with in Kubernetes. You typically **don't create Pods yourself** and manually move them to a worker node. Instead, you create a Deployment and give it instructions about the number of Pods and the containers it should create and manage for you. A Deployment can control one or multiple Pods, so it can create several Pods at once.

**Core philosophy — desired target state:**

- Under the hood a Deployment is a controller object, but for our purposes it is enough to know it is a Deployment.
- You declare a target state (e.g. *"two Pods with this container up and running"*), and Kubernetes does whatever it takes to reach and maintain it.
- You define **what** you want; Kubernetes figures out **how** to get there.

**Advantages:**

- **Automatic Pod creation and placement:** Kubernetes creates the Pods, starts the containers, and places the Pods on worker nodes with sufficient CPU and memory. You never pick a remote machine by hand.
- **Pause, delete, and roll back:** if a change breaks the application, you don't have to rush a code fix and replace the failing Pod. Roll back to the previous working Deployment, fix the bug calmly, then start a new Deployment with the updated code and container image.
- **Scaling:** tell Kubernetes you want more or fewer Pods at any time.
- **Autoscaling:** set metrics such as incoming traffic or CPU utilization. When they are exceeded, Kubernetes creates more Pods (more container instances to handle requests); when load drops, the unnecessary Pods are removed again.

```
You (desired state)             Kubernetes
───────────────────             ──────────────────────────────────────────
Deployment: 2 Pods   ───────▶   creates Pods ─▶ starts containers ─▶ picks Worker Nodes
                                with enough CPU / memory
                                keeps 2 Pods running; can scale, roll back
```

> **Key takeaway:** One Deployment manages one set of Pods, but you can create multiple Deployments to have multiple Pods managed by Kubernetes. We typically don't create or manage Pods directly — we create Deployment objects and send them to the cluster.

#### Why Do We Need a Service?

To reach a Pod (and the container running in it), we need a **Service**. A Service is a Kubernetes object responsible for exposing Pods to other Pods in the cluster and — very importantly — to visitors **outside** the cluster (the entire world).

Pods already get an internal IP address by default (visible in the dashboard), but that IP has two problems:

1. **It cannot be used from outside the cluster** — so the containerized app is unreachable by external visitors.
2. **It changes whenever a Pod is replaced** — this happens often, especially with scaling, so you cannot rely on a Pod keeping its IP. Even for cluster-internal communication, the IP is an unreliable way to find a Pod.

**What a Service does:**

- **Groups Pods together** and gives them a **shared, stable IP address** that does not change.
- Multiple Pods can sit behind the Service and be reached through that one unchanging address.
- Can expose this address **inside the cluster only** (the default) or **outside the cluster** too, so the containerized Node.js web app can be visited from the outside world.

```
Without a Service                       With a Service
─────────────────                       ──────────────
Outside world ──X──▶ Pod (IP changes)   Outside world ──▶ Service (stable IP) ──┬─▶ Pod 1
Other Pods   ──?──▶ Pod (IP changes)    Other Pods   ──▶ Service (stable IP) ──┴─▶ Pod 2
```

> **Key takeaway:** Without Services, Pods are very hard to reach even internally (because of the changing IP), and containerized apps are not reachable from outside the cluster at all. The default is internal-only, but a Service lets us override that.

#### Creating a Service with `kubectl expose`

We can create a Service from the command line with `kubectl`. Keep the dashboard process running and open a **new terminal window** for these commands.

`kubectl create` does offer a `service` subcommand, and that would work. A more convenient command for exposing the Pods created by a Deployment is **`kubectl expose`**: it creates a Service that exposes the Deployment's Pods.

```bash
kubectl expose deployment first-app --port=8080 --type=LoadBalancer
```

You tell Kubernetes you want to expose a **deployment**, give the **deployment name**, and add two important options (assign values with `=`):

| Option | Meaning |
|--------|---------|
| `--port=8080` | The port to expose. Here it is 8080, because that is the port the containerized app listens on. |
| `--type=...` | The type of Service, i.e. how it is exposed. |

**Built-in Service types:**

| Type | Behavior |
|------|----------|
| `ClusterIP` | The **default**. Reachable only from **inside** the cluster. You still get a stable address, but it is not enough when outside access is needed. |
| `NodePort` | Exposes the Deployment through the **IP address of the worker node** it runs on, so it is accessible from outside. |
| `LoadBalancer` | Uses a load balancer that must exist in the **infrastructure the cluster runs on**. It generates a **unique address** for the Service and **evenly distributes incoming traffic** across all Pods in the Service. |

> **Note:** Load balancing doesn't matter with a single Pod, but it matters once you scale and run multiple Pod instances. `LoadBalancer` is only available if the cluster's infrastructure supports it. AWS does, and Minikube does too, so we can use it here.

**Verify the Service was created:**

```bash
kubectl get services
```

- The `kubernetes` Service (type `ClusterIP`) is a default Service created automatically, not by us.
- The `first-app` Service is ours. You see its type and its cluster-internal IP, which doesn't help us reach it from outside.
- On a cloud provider you would see an **external IP**. On Minikube, `EXTERNAL-IP` always stays **`<pending>`**, because Minikube is a virtual machine on your local machine and has no public IPs of its own.

**Accessing the Service on Minikube:**

```bash
minikube service first-app
```

- This Minikube-specific command **maps a special port to an IP** that is reachable from your local machine and identifies the Minikube VM.
- It prints a table with an address and normally opens it in the browser automatically.
- On a cloud provider that supports `LoadBalancer`, you would find an external address in `kubectl get services` and **would not need this command** (it wouldn't work there, because it is Minikube-specific).

If everything worked, that address shows your running Node.js application, in a container, in a Pod, created by Kubernetes from the Deployment we sent to the cluster. The Service is what makes it viewable from outside.

> **Key takeaway:** We are using the **imperative** approach here and will move away from it later. Even so, the **Pod**, **Deployment**, and **Service** are some of the most important object types we will use all the time when working with Kubernetes.

#### Updating Deployments

Letting Kubernetes manage Deployments is useful, and changing your code, updating the Deployment, and even rolling back are all easy.

**Scenario:** you change the source code (e.g. more exclamation marks and a new paragraph) and save the file.

**Step 1 — Rebuild the image (with a new tag).** The code lives in the image, so whenever the code changes the image must be rebuilt before any container, on any machine, can be updated.

```bash
docker build -t academind/kub-first-app:2 .
```

**Step 2 — Push the image to Docker Hub.** Kubernetes pulls the image from the registry, so the updated image has to be pushed first.

```bash
docker push academind/kub-first-app:2
```

**Step 3 — Update the Deployment with `kubectl set image`.** First check the Deployment still exists with `kubectl get deployments`, then run:

```bash
kubectl set image deployment/first-app kub-first-app=academind/kub-first-app:2
```

Syntax breakdown:

| Part | Meaning |
|------|---------|
| `deployment/first-app` | Resource type, then `/`, then the **name of the Deployment** to update. |
| `kub-first-app` | The **current container name** to update (shown in the dashboard; here it matches the original image name). |
| `=academind/kub-first-app:2` | The **new image** the container should use. |

> **Why specify the container name and the image?** The image isn't hard-coded to the Deployment. Telling Kubernetes which container to update and which image to use keeps it flexible, so you can later switch to a different image with a different name or technology.

**Step 4 — Watch the rollout:**

```bash
kubectl rollout status deployment/first-app
```

It reports when the Deployment was rolled out successfully. After a little while, reloading the app in the browser shows the updated output.

**Verify in the dashboard:** open the Pod and look at **Events**. You can see the new image was pulled and a new container created from it. The Pod also shows the image currently in use.

> **Important: use a new tag.** If you re-push under the same tag (e.g. `latest`) and run `kubectl set image` again, nothing visibly happens: the Deployment shows no difference and the app looks unchanged. Kubernetes only downloads a new image **if the tag is different**. There are ways around this, but versioning your images with an incrementing tag (`:1`, `:2`, `:3`, ...) is good practice for production setups anyway. With a new tag, Kubernetes detects the change, re-downloads the image, and restarts the containers based on it.

**Summary of the update workflow:**

```
Change code ─▶ docker build -t <image>:<new-tag> ─▶ docker push ─▶ kubectl set image ─▶ kubectl rollout status
```

> **Key takeaway:** `kubectl set image` updates the image, and therefore the source code, of a container running in a Pod managed by a Deployment. Always change the tag to trigger Kubernetes to re-download the image.

---

### 2. Other Important Kubernetes Objects

| Object                       | Purpose                                                              | Enterprise Example                                  |
|------------------------------|----------------------------------------------------------------------|-----------------------------------------------------|
| **Namespace**                | Organizes resources into isolated groups                             | `development`, `staging`, `production`              |
| **ConfigMap**                | Stores non-sensitive configuration                                   | API endpoint settings                               |
| **Secret**                   | Holds sensitive configuration                                        | Database credentials or tokens                      |
| **StatefulSet**              | Manages stateful replicas with stable identities                     | Database cluster                                    |
| **DaemonSet**                | Runs a Pod on each eligible node                                     | Node monitoring agent                               |
| **Job**                      | Runs a task to completion                                            | Database migration                                  |
| **CronJob**                  | Runs tasks on a schedule                                             | Nightly cleanup                                     |
| **Ingress**                  | Defines HTTP/HTTPS routing into the cluster (requires a controller)  | Route `/api` to the backend service                 |
| **NetworkPolicy**            | Controls permitted network traffic (subject to CNI support)          | Restrict database access to backend Pods only       |
| **ServiceAccount**           | Provides an identity for workloads accessing the Kubernetes API      | Backend Pod with limited API permissions            |
| **HorizontalPodAutoscaler**  | Adjusts replica count based on configured metrics                    | Scale backend Pods under load                       |

---

### 3. How These Objects Work Together

```
┌─────────────────────────────────────────────────────────────────────────────┐
│               ENTERPRISE APPLICATION — OBJECT INTERACTIONS                   │
│                                                                             │
│   External Users                                                            │
│        │                                                                    │
│        ▼                                                                    │
│   ┌──────────────────────┐                                                  │
│   │       Ingress         │  HTTP/HTTPS routing rules                       │
│   └──────────┬───────────┘                                                  │
│              │                                                              │
│   ┌──────────▼───────────┐                                                  │
│   │   Angular Frontend   │                                                  │
│   │                      │                                                  │
│   │  Frontend Deployment │                                                  │
│   │  └─► Frontend Pods   │                                                  │
│   └──────────┬───────────┘                                                  │
│              │  calls                                                       │
│              ▼                                                              │
│   ┌──────────────────────┐     ┌──────────────────────┐                    │
│   │    Backend Service   │────►│   FastAPI Deployment  │                    │
│   │  Stable internal     │     │   Backend Pods × 3   │                    │
│   │  endpoint            │     │                      │                    │
│   └──────────────────────┘     └──────────┬───────────┘                    │
│                                           │  calls                         │
│              ┌────────────────────────────┘                                │
│              ▼                                                              │
│   ┌──────────────────────┐     ┌──────────────────────┐                    │
│   │   Database Service   │────►│  Database Pod(s)      │                    │
│   │                      │     │                      │                    │
│   └──────────────────────┘     │  ┌────────────────┐  │                    │
│                                │  │  PVC → PV       │  │                    │
│                                │  │  Persistent     │  │                    │
│                                │  │  Storage        │  │                    │
│                                │  └────────────────┘  │                    │
│                                └──────────────────────┘                    │
│                                                                             │
│  ConfigMap ── non-sensitive config (API URLs, feature flags)               │
│  Secret    ── sensitive config (DB passwords, API keys)                    │
│  Namespace ── logical isolation (dev / staging / prod)                     │
│                                                                             │
│  Note: This is a simplified logical view. Actual ingress routing,          │
│  frontend delivery, database topology, and network policies depend          │
│  on the deployment design.                                                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## B. Imperative vs. Declarative

There are two common ways to create and manage Kubernetes resources.

```
┌──────────────────────────────────────┬──────────────────────────────────────┐
│          IMPERATIVE APPROACH          │         DECLARATIVE APPROACH          │
│      "Tell Kubernetes what to do"     │      "Define the desired state"       │
├──────────────────────────────────────┼──────────────────────────────────────┤
│  You execute commands directly        │  You describe resources in YAML       │
│  using kubectl.                       │  files and apply them.                │
│                                      │                                      │
│  kubectl create deployment web \      │  kubectl apply -f deployment.yaml     │
│    --image=nginx --replicas=3         │                                      │
│                                      │                                      │
│  Best for:                           │  Best for:                           │
│  • Learning                          │  • Repeatable deployments            │
│  • Quick tasks                       │  • Git version control               │
│  • Troubleshooting                   │  • CI/CD pipelines                   │
│  • Operations & diagnostics          │  • Production operations             │
└──────────────────────────────────────┴──────────────────────────────────────┘
```

---

### Example 1 — Create a Pod Imperatively

```bash
# Create a Pod named nginx
kubectl run nginx --image=nginx --port=80

# Inspect it
kubectl get pods
kubectl describe pod nginx
kubectl logs nginx

# Delete it
kubectl delete pod nginx
```

---

### Example 2 — Create a Deployment Imperatively

```bash
# Create a Deployment with 3 replicas
kubectl create deployment web --image=nginx --replicas=3

# Inspect the objects Kubernetes created
kubectl get deployments
kubectl get replicasets
kubectl get pods

# Scale up to 5 replicas
kubectl scale deployment web --replicas=5
```

> Kubernetes attempts to maintain five replicas, provided the cluster has sufficient resources and the Pods can be scheduled.

---

### Example 3 — Create a Deployment Declaratively

Create a file named `deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:stable
          ports:
            - containerPort: 80
```

Apply and verify:

```bash
kubectl apply -f deployment.yaml
kubectl get deployment web
kubectl get pods -l app=web
```

To scale, change `replicas: 3` to `replicas: 5` in the file and re-apply:

```bash
kubectl apply -f deployment.yaml
```

> Kubernetes **reconciles** the live resources toward the desired state specified in the file.

---

### Imperative vs. Declarative Comparison

| Feature               | Imperative                                  | Declarative                                      |
|-----------------------|---------------------------------------------|--------------------------------------------------|
| **Input**             | Commands                                    | YAML manifests                                   |
| **Example**           | `kubectl scale ...`                         | Edit `replicas` and `kubectl apply`              |
| **Repeatability**     | Depends on saved commands and scripts       | Configuration can be version-controlled          |
| **Team collaboration**| Requires disciplined command history        | Works well with Git-based workflows              |
| **Production use**    | Useful for operations and debugging         | Common for application delivery                  |

> **Enterprise recommendation:** Keep Kubernetes manifests in Git, review changes through pull requests, and deploy them through a CI/CD pipeline or GitOps tool. Imperative commands remain useful for inspection, diagnostics, and deliberate operational tasks.

> **One important nuance:** `kubectl apply` is declarative in how it manages the described resources, but it does not by itself provide GitOps, automatic drift correction, or a full deployment pipeline.

---

## C. Object Hierarchy Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        KUBERNETES OBJECT HIERARCHY                           │
│                                                                             │
│                           Deployment                                        │
│                    Desired replicas, updates, rollback                      │
│                                │                                            │
│                                ▼                                            │
│                           ReplicaSet                                        │
│                  Maintains the desired number of Pods                       │
│                                │                                            │
│               ┌────────────────┼────────────────┐                          │
│               ▼                ▼                ▼                          │
│            Pod 1             Pod 2            Pod 3                        │
│          [Container]       [Container]       [Container]                   │
│               │                │                │                          │
│               └────────────────┼────────────────┘                          │
│                                │                                            │
│                                ▼                                            │
│                            Service                                          │
│           Selects matching Pods and provides a stable endpoint              │
│                                                                             │
│  Note: A Service selects eligible Pods using labels and routes traffic     │
│  to them. It does NOT create or manage Pods.                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## D. Complete Kubernetes Study Notes

### 1. Core Concepts

| Term             | Definition                                                                        |
|------------------|-----------------------------------------------------------------------------------|
| **Kubernetes (K8s)** | A container orchestration platform                                            |
| **Cluster**      | The overall Kubernetes environment — control plane + worker nodes                 |
| **Control Plane**| Coordinates the cluster, schedules Pods, maintains desired state                  |
| **Worker Node**  | Runs application Pods                                                             |
| **Object**       | An API resource representing desired configuration or state of a workload         |
| **Controller**   | Watches resources and works to bring actual state toward desired state            |
| **kubectl**      | The command-line tool used to interact with the Kubernetes API                    |

---

### 2. Important Object Relationships

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       OBJECT RELATIONSHIPS                                   │
│                                                                             │
│   Deployment                                                                │
│   └── Desired replicas, update strategy, rollback                          │
│        │                                                                    │
│        └── ReplicaSet                                                       │
│             └── Maintains the desired number of Pod replicas                │
│                  │                                                          │
│                  ├── Pod 1  [Container(s)]                                  │
│                  ├── Pod 2  [Container(s)]                                  │
│                  └── Pod 3  [Container(s)]                                  │
│                       │                                                     │
│                       └── Labeled: app=web                                  │
│                                                                             │
│   Service                                                                   │
│   └── selector: app=web  ────────────────────► Routes traffic to Pod 1/2/3 │
│   └── Stable ClusterIP + DNS name                                           │
│                                                                             │
│   A Service and a Deployment are INDEPENDENT objects linked by labels.     │
│   A Service does not create or own Pods.                                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### 3. Common Kubernetes Commands

| Task                        | Command                                             |
|-----------------------------|-----------------------------------------------------|
| Show cluster nodes          | `kubectl get nodes`                                 |
| Show Pods                   | `kubectl get pods`                                  |
| Show Deployments            | `kubectl get deployments`                           |
| Show Services               | `kubectl get services`                              |
| Show all common resources   | `kubectl get all`                                   |
| Inspect a Pod               | `kubectl describe pod <pod-name>`                   |
| View logs                   | `kubectl logs <pod-name>`                           |
| Apply YAML                  | `kubectl apply -f app.yaml`                         |
| Delete resources from YAML  | `kubectl delete -f app.yaml`                        |
| Scale a Deployment          | `kubectl scale deployment web --replicas=3`         |
| Check rollout status        | `kubectl rollout status deployment/web`             |
| Undo a rollout              | `kubectl rollout undo deployment/web`               |
| See current namespace       | `kubectl config view --minify`                      |

> **Note:** `kubectl get all` does not literally list every Kubernetes resource type.

---

### 4. Common YAML Structure

Most Kubernetes manifests follow this pattern:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: app
          image: nginx:stable
          ports:
            - containerPort: 80
```

**The four key fields:**

| Field          | Description                                                                  |
|----------------|------------------------------------------------------------------------------|
| `apiVersion`   | API group and version used by the resource (e.g., `apps/v1`, `v1`)         |
| `kind`         | Type of resource — `Deployment`, `Service`, `Pod`, `ConfigMap`, etc.        |
| `metadata`     | Name, namespace, labels, and annotations                                    |
| `spec`         | Desired configuration — meaning varies by resource type                     |

> For a Deployment, `spec` includes replica count and Pod-template configuration.

---

### 5. Production Best Practices

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       PRODUCTION BEST PRACTICES                              │
│                                                                             │
│  1. Use Deployments for stateless applications                              │
│     Rather than managing long-running Pods manually.                        │
│                                                                             │
│  2. Use Services for stable communication                                   │
│     Between all application components.                                     │
│                                                                             │
│  3. Set CPU and memory requests and limits                                  │
│     Appropriate for your workloads to ensure fair scheduling.               │
│                                                                             │
│  4. Use ConfigMaps for non-sensitive config                                 │
│     Use Secrets with appropriate access controls for sensitive values.      │
│                                                                             │
│  5. Use PV and PVC when data must survive Pod replacement                   │
│     Do not rely on container filesystems for persistent data.               │
│                                                                             │
│  6. Keep YAML manifests in Git                                              │
│     Review all infrastructure changes through pull requests.                │
│                                                                             │
│  7. Configure health probes                                                 │
│     Readiness, liveness, and startup probes when appropriate.               │
│                                                                             │
│  8. Use namespaces, RBAC, and network policies                              │
│     To isolate workloads and restrict access.                               │
│                                                                             │
│  9. Monitor health, resources, rollout status, and logs                     │
│     Continuously, not only when problems arise.                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### 6. Important Clarification About Volumes

While **Volume** is often grouped alongside Pods, Deployments, and Services as a conceptual introduction, there is a technical distinction:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      VOLUME VS. PERSISTENT STORAGE                           │
│                                                                             │
│  Pod spec.volumes          Defines volumes that containers can mount.       │
│                            These may be temporary (emptyDir) or backed     │
│                            by persistent storage.                           │
│                                                                             │
│  PersistentVolume (PV)     A Kubernetes API object representing storage    │
│                            capacity in the cluster.                         │
│                                                                             │
│  PersistentVolumeClaim     A request for storage — the Pod does not        │
│  (PVC)                     talk to the cloud provider directly.             │
│                                                                             │
│  StorageClass (SC)         Describes how storage can be dynamically        │
│                            provisioned.                                     │
│                                                                             │
│  For a persistent database, the relationship is:                           │
│                                                                             │
│  Database Pod → PVC → PV → Storage backend (EBS / GCE PD / Azure Disk)    │
│                                                                             │
│  The provisioning flow depends on the configured storage driver and        │
│  StorageClass.                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Enterprise Application — Full Object Map

```
┌─────────────────────────────────────────────────────────────────────────────┐
│            FULL KUBERNETES OBJECT MAP: BANKING APPLICATION                   │
│                                                                             │
│  Namespace: banking-prod                                                    │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  Ingress                                                              │   │
│  │  / → Angular frontend   /api → FastAPI backend   /auth → Auth svc    │   │
│  └────────────────────────────────────┬─────────────────────────────────┘   │
│                                       │                                     │
│  ┌────────────────────┐  ┌────────────┴───────────┐  ┌───────────────────┐  │
│  │  Angular Frontend  │  │    FastAPI Backend     │  │  Auth Service     │  │
│  │  Deployment × 2   │  │    Deployment × 3      │  │  Deployment × 2   │  │
│  │  (stateless)       │  │    (stateless)         │  │  (stateless)      │  │
│  │  Service (ClusterIP│  │    Service (ClusterIP) │  │  Service          │  │
│  │  or NodePort)      │  │                        │  │  (ClusterIP)      │  │
│  └────────────────────┘  └──────────────┬─────────┘  └───────────────────┘  │
│                                         │                                   │
│                          ┌──────────────▼─────────────┐                    │
│                          │      PostgreSQL Database     │                   │
│                          │      StatefulSet × 1        │                   │
│                          │      (stateful)             │                   │
│                          │      Service (ClusterIP)    │                   │
│                          │      PVC → PV → Cloud Disk  │                   │
│                          └─────────────────────────────┘                   │
│                                                                             │
│  ConfigMap  ── DB_HOST, API_URL, FEATURE_FLAGS                              │
│  Secret     ── DB_PASSWORD, JWT_SECRET, API_KEYS                           │
│  NetworkPolicy ── Only backend Pods may reach the database                 │
│  HPA        ── Scale FastAPI backend Pods 3–10 based on CPU                │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Quick Knowledge Check

| Question | Answer |
|----------|--------|
| Which object maintains three desired replicas of a stateless backend? | **Deployment** |
| Which object provides a stable endpoint for matching Pods? | **Service** |
| Which approach stores desired resource configuration in YAML? | **Declarative** |
| What should you use to retain database data when a Pod is replaced? | **PersistentVolumeClaim (PVC) with suitable persistent storage** |

---

## Final Takeaway

> Kubernetes objects describe **what you want running** and **how it should behave**. You can create them imperatively with commands or declaratively with manifests. For enterprise applications, understanding how **Pods**, **Deployments**, **Services**, and **persistent storage** work together is the foundation for everything that follows.
