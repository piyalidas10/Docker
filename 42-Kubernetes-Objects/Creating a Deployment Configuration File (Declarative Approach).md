# Creating a Deployment Configuration File (Declarative Approach)

In the imperative approach we created a Deployment with `kubectl` commands. Here we define the same Deployment in a **YAML configuration file** instead: we describe how it should look, work, and be configured, and send that file to the cluster.

---

**deployment.yaml**
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: second-app-deployment
  labels:
    group: example
spec:
  replicas: 1
  selector:
    matchLabels:
      app: second-app
      tier: backend
    # matchExpressions: 
    #   - {key: app, operator: NotIn, values: [second-app, first-app]}
  template:
    metadata: 
      labels:
        app: second-app
        tier: backend
    spec: 
      containers:
        - name: second-node
          image: academind/kub-first-app:2
          imagePullPolicy: Always
          livenessProbe: 
            httpGet:
              path: /
              port: 8080
            periodSeconds: 10
            initialDelaySeconds: 5
        # - name: ...
        #   image: ...
```

## 1. Start from a Clean State

Before creating the config file, make sure nothing from earlier experiments is left over. We stick with the application used so far in the course.

| Check | Command | Expected result |
|-------|---------|-----------------|
| No Deployments | `kubectl get deployments` | Nothing listed. If something is listed, delete it with `kubectl delete deployment <name>`. |
| No Pods | `kubectl get pods` | Nothing listed (you shouldn't have Pods if you have no Deployments). |
| No Services (except the default) | `kubectl get services` | Only the default `kubernetes` Service, which is fine. |
| Minikube is running | `minikube status` | Running. If it weren't, the commands above would have failed anyway. |

```bash
kubectl get deployments
kubectl delete deployment <deployment-name>   # only if one exists
kubectl get pods
kubectl get services
```

---

## 2. Create the File

Add a new file to the project and name it `deployment.yaml`.

- The **file name is up to you**.
- The only thing that matters is that it is a **YAML file**.
- The file name does **not** tell Kubernetes what to create (see `kind` below).

In this file we specify how the Deployment should look, work, and be configured. Kubernetes config files use a **certain syntax** that you have to follow.

---

## 3. `apiVersion`

No matter which kind of resource you configure (Deployment, Service, ...), you must specify an `apiVersion`.

```yaml
apiVersion: apps/v1
```

- Different API versions exist, and Kubernetes is under active development.
- **How to find the right one:** look in the official docs, or search for something like *"Kubernetes deployment YAML"*. For a Service you would search *"service.yaml"*. The docs show an example snippet containing the current `apiVersion`.
- Keep in mind that if you always use the latest version, some features might change over time.
- For a **Deployment** we use `apps/v1`.

---

## 4. `kind`

Naming the file `deployment.yaml` does **not** make Kubernetes treat it as a Deployment. You could have chosen any file name. You must say what you want to create with the `kind` key.

```yaml
kind: Deployment
```

- `kind` defines the **type of Kubernetes object** to create.
- The value is **not up to you**. Only a certain set of values is allowed, such as `Deployment`, `Service`, or `Job`.
- This replaces the "deployment" word in the imperative command (`kubectl create deployment ...`).

> **Tip — official docs:** at the bottom left of the Kubernetes docs, open **Reference → latest API reference**. It lists all supported objects and configuration options. For example, the Deployment page shows `apps/v1` as the version and lists everything you can configure, including the `kind` (which should be `Deployment`).

---

## 5. `metadata`

Next you typically add **metadata**. This is not random data. It includes crucial information such as the **name** of the object. In the imperative approach we also gave the Deployment a name (`kubectl create deployment <name> ...`). Here we do the same inside the file.

```yaml
metadata:
  name: second-app-deployment
```

- `metadata` is a **key with nested content**. Since this is YAML, nesting is done by **indenting**.
- `name` identifies the object later. Its value is **up to you**. Here it is `second-app-deployment`.
- More metadata can be added. In the API reference, open the **ObjectMeta** type definition (reachable from the metadata field) to see what is supported, such as `name` and `labels`. It isn't available for every type, but it is for many.
- Most of these extra fields aren't needed for the vast majority of objects. They are introduced when an object makes use of them.

---

## 6. The File So Far

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: second-app-deployment
```

With this we tell Kubernetes:

1. We want to create a **Deployment** (`kind`), using API version **`apps/v1`**.
2. It will have the name **`second-app-deployment`** (`metadata.name`).

---

## 7. Key Fields at a Glance

| Field | Purpose | Value |
|-------|---------|-------|
| `apiVersion` | API group and version that defines the object type | Look it up in the docs (here `apps/v1`) |
| `kind` | Type of object to create | One of a fixed set (here `Deployment`) |
| `metadata.name` | Name used to identify the object | Your choice (here `second-app-deployment`) |
| `spec` | Specification of the desired state | Added next |

---

## 8. What Comes Next: `spec`

The next piece is the **`spec`**, the specification of the Deployment. This is the "meat" of the object. It is where we define **how the Deployment should be configured**, and where all the interesting settings are added.
