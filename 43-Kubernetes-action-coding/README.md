# kub-action-05-finished

This folder demonstrates the **declarative approach** to managing Kubernetes objects using YAML manifest files. The same application resources (a Deployment and a Service) are expressed in two different organizational styles so you can compare them side-by-side.

---

## Files Overview

| File | Kind(s) | Purpose |
|---|---|---|
| [`deployment.yaml`](./deployment.yaml) | `Deployment` | Annotated, standalone Deployment definition |
| [`service.yaml`](./service.yaml) | `Service` | Annotated, standalone Service definition |
| [`master-deployment.yaml`](./master-deployment.yaml) | `Service` + `Deployment` | Both resources combined in one file |

---

## Why Three Separate Files?

### Approach 1 — Two separate files (`deployment.yaml` + `service.yaml`)

Each Kubernetes object lives in its own file. Apply them individually:

```sh
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

**Why useful:**
- Update or delete one resource without touching the other
- Easier to read and reason about in isolation
- Common real-world convention for medium and large projects

---

### Approach 2 — One combined file (`master-deployment.yaml`)

Both objects are merged into a single file, separated by the YAML document separator `---`:

```yaml
kind: Service      # first document
...
---                # separator — tells kubectl "new object starts here"
kind: Deployment   # second document
```

Apply everything in one command:

```sh
kubectl apply -f master-deployment.yaml
```

**Why useful:**
- Single command deploys the entire app
- Good for simple demos, tutorials, or small projects
- Easy to distribute as one self-contained file

---

## What Each File Contains

### `deployment.yaml`
- **Kind:** `Deployment` (API group `apps/v1`)
- **Name:** `second-app-deployment`
- **Replicas:** 1
- **Container image:** `academind/kub-first-app:2`
- **`imagePullPolicy: Always`** — pulls a fresh image from the registry on every Pod start
- **`livenessProbe`** — HTTP GET on `/` port `8080` every 10 s (first check after 5 s); Kubernetes restarts the container if it fails
- **Pod selector labels:** `app: second-app`, `tier: backend`

### `service.yaml`
- **Kind:** `Service` (API version `v1`)
- **Name:** `backend`
- **Type:** `LoadBalancer` — exposes the app externally via a cloud load balancer
- **Port mapping:** external port `80` → container port `8080` (TCP)
- **Selector:** targets Pods with label `app: second-app`

### `master-deployment.yaml`
- Contains the **same Service and Deployment** as the two files above, combined with `---`
- Intentionally **minimal** — no `imagePullPolicy`, no `livenessProbe`, no extra labels
- Shows the **clean, production-style** minimum required spec

> **Note:** `deployment.yaml` and `service.yaml` are the fully annotated **teaching versions** with comments explaining every field. `master-deployment.yaml` is the concise reference version.

---

## Making Changes with the Declarative Approach

One of the key advantages of the declarative approach is how easy it is to **update** your running resources. Simply edit your YAML file, save it, and re-apply — Kubernetes figures out what changed and applies only the diff.

### Example 1 — Scale replicas up

Open [`deployment.yaml`](./deployment.yaml) and change `replicas`:

```yaml
spec:
  replicas: 3   # was 1
```

Then re-apply:

```sh
kubectl apply -f deployment.yaml
```

Check the result:

```sh
kubectl get pods
# You will now see 3 running pods
```

### Example 2 — Scale back down

Change `replicas` back to `1`, re-apply, and watch the extra Pods terminate:

```sh
kubectl apply -f deployment.yaml
kubectl get pods
# Two pods will show STATUS = Terminating, one will remain Running
```

### Example 3 — Change the container image

Open [`deployment.yaml`](./deployment.yaml) and update the image tag:

```yaml
containers:
  - name: second-node
    image: academind/kub-first-app:1   # changed from :2
```

Re-apply:

```sh
kubectl apply -f deployment.yaml
```

Kubernetes performs a rolling update — the old Pods are replaced with new ones running the updated image, with zero downtime.

> **Key advantage:** You never have to repeat a long `kubectl` command just to change one option. Edit the file, re-apply, and only the changed fields are reconciled.

---

## Tracking Changes with Git

Because the desired state lives in YAML files, you can commit them to source control:

```sh
git add deployment.yaml service.yaml
git commit -m "scale to 3 replicas"
```

This gives you:
- A full **history of every configuration change**
- The ability to **roll back** by checking out an older version and re-applying
- **Team collaboration** — PRs and code reviews for infrastructure changes

---

## Deleting Resources

### Declarative delete (using the file)

Point `kubectl delete` at the same file(s) used to create the resources. It is the **resource** described in the file that gets deleted, not the file itself:

```sh
# Delete a single resource
kubectl delete -f deployment.yaml

# Delete multiple resources — use multiple -f flags
kubectl delete -f deployment.yaml -f service.yaml

# Or comma-separate the file names
kubectl delete -f deployment.yaml,service.yaml
```

### Imperative delete (using the resource name)

Even if you created resources declaratively, you can still delete them imperatively by name:

```sh
kubectl delete deployment second-app-deployment
kubectl delete service backend
```

Both approaches work — use whichever is more convenient in the moment.

---

## Apply Commands

```sh
# Option A — apply resources individually
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# Option B — apply both resources at once
kubectl apply -f master-deployment.yaml
```

---

## Resource Relationship

```
LoadBalancer (Service: backend)
    port 80  →  targetPort 8080
         |
         ▼
   Pod  [app: second-app, tier: backend]
         |
         └─ container: second-node
              image: academind/kub-first-app:2
              port: 8080
```

The **Service** selects Pods by label (`app: second-app`) and forwards external traffic to them. The **Deployment** ensures exactly 1 replica of that Pod is always running.

---

## Liveness Probes

Kubernetes needs to know whether a container is healthy. By default it uses a basic process check, but you can define your own **liveness probe** inside the container spec.

### How it works

- Kubernetes periodically sends a request to the running container
- If the check fails, the container is **restarted automatically**
- You configure it under `containers[].livenessProbe` in [`deployment.yaml`](./deployment.yaml)

### Configuration (already set in `deployment.yaml`)

```yaml
livenessProbe:
  httpGet:
    path: /          # URL path to probe (can be /healthz or any app route)
    port: 8080       # port the container exposes
  periodSeconds: 10        # how often to run the check
  initialDelaySeconds: 5   # wait before the first check (gives app time to boot)
```

### Key points

| Field | Purpose |
|---|---|
| `httpGet.path` | The URL path Kubernetes hits — use any valid route your app exposes |
| `httpGet.port` | Must match the port the container listens on |
| `periodSeconds` | Probe frequency in seconds |
| `initialDelaySeconds` | Grace period after container start before first probe |

- If a container crashes or the probe fails, Kubernetes **restarts it** — visible via `kubectl get pods` (`RESTARTS` column increments)
- Defining a custom liveness probe is especially useful when your app's health cannot be inferred from the process state alone
- Re-apply after any change: `kubectl apply -f deployment.yaml`

---

## Selectors & Labels — A Closer Look

### Two selector styles

| Style | Used by | Syntax |
|---|---|---|
| Simple `selector` | `Service` | flat key/value pairs |
| `selector.matchLabels` | `Deployment` | nested under `matchLabels` |
| `selector.matchExpressions` | `Deployment` | list of expression objects |

Both `matchLabels` (Deployment) and `selector` (Service) ultimately match the same **Pod labels** defined in `template.metadata.labels`.

---

### `matchLabels` vs `matchExpressions`

**`matchLabels`** — simple, most common:

```yaml
selector:
  matchLabels:
    app: second-app
    tier: backend
```

**`matchExpressions`** — more powerful, supports operators:

```yaml
selector:
  matchExpressions:
    - { key: app, operator: In, values: [second-app, first-app] }
```

Allowed operators: `In`, `NotIn`, `Exists`, `DoesNotExist`

> A Deployment **must** select the exact Pods it creates. Using `NotIn` to exclude your own Pod labels would be an invalid configuration.

---

### Selecting by label at the command line (`-l`)

You can target resources by label with the `-l` flag. This requires the resource to have a matching label in its `metadata`:

```yaml
# deployment.yaml & service.yaml — metadata section
metadata:
  labels:
    group: example
```

Delete all resources with that label in one command:

```sh
kubectl delete deployments,services -l group=example
```

- `-l group=example` — selects resources whose metadata has `group: example`
- `deployments,services` — scopes the delete to those resource types (safety guard)
- Selectors **always** match on `metadata.labels`, never on the resource name

---

### Delete by name (imperative, still works for declaratively-created resources)

```sh
kubectl delete deployment second-app-deployment
kubectl delete service backend
```

Use whichever is more convenient — the creation method (declarative vs imperative) does not restrict how you delete.

---

## Merging Multiple Resources into One File

You can combine as many resource definitions as you like into a single YAML file. The result is [`master-deployment.yaml`](./master-deployment.yaml).

### The `---` separator

```yaml
apiVersion: v1
kind: Service
# ... service config ...
---                   # exactly three dashes — YAML "new document" syntax
apiVersion: apps/v1
kind: Deployment
# ... deployment config ...
```

- Must be **exactly three dashes** (`---`) — two or four won't work
- Tells `kubectl` (and the YAML parser) that a new resource definition starts after the separator
- You can chain as many resources as needed this way

### Put the Service first

When combining a Service and a Deployment, **define the Service above the Deployment**:

- Resources are created top-to-bottom
- The Service continuously monitors the cluster for Pods matching its selector — it will pick up Pods created after it
- Creating the Service first is therefore safe and is the recommended practice

### Workflow — switch from separate files to a merged file

```sh
# 1. Delete the individually-deployed resources
kubectl delete -f deployment.yaml -f service.yaml

# 2. Apply the merged file (creates both Service and Deployment at once)
kubectl apply -f master-deployment.yaml

# 3. (local/minikube only) Expose the service URL
minikube service backend
```

### When to use each approach

| Separate files | Single merged file |
|---|---|
| Update/delete one resource independently | Deploy the whole app in one command |
| Easier to navigate in large projects | Convenient for demos and small apps |
| Standard convention for teams | Simpler to hand off as one file |
