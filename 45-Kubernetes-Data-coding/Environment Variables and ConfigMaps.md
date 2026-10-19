# Environment Variables and ConfigMaps in Kubernetes

---

## Overview

Environment variables can be set directly inside a container spec — but Kubernetes also provides a better approach for sharing configuration across multiple Pods: the **ConfigMap**.

A ConfigMap is a standalone Kubernetes resource that holds key-value pairs. Any container in any Pod can pull values from it, avoiding duplication and keeping configuration centralised.

---

## Two Ways to Set an Environment Variable

### Option A — Inline value (directly in container spec)

```yaml
env:
  - name: STORY_FOLDER
    value: 'story'
```

Simple. Works fine for a single Pod. Becomes repetitive when the same variable is needed in multiple Pods.

### Option B — Value from a ConfigMap

```yaml
env:
  - name: STORY_FOLDER
    valueFrom:
      configMapKeyRef:
        name: data-store-env
        key: folder
```

The value is pulled from a ConfigMap resource. The variable name (`STORY_FOLDER`) stays the same in code — only the source of the value changes.

> **Use one or the other — not both.** Either set `value:` directly or use `valueFrom:` pointing at a ConfigMap. Combining them on the same variable will not work.

---

## The ConfigMap Resource (`environment.yaml`)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: data-store-env
data:
  folder: 'story'
  # key: value..
```

### Field-by-field explanation

| Field | Value | Meaning |
|---|---|---|
| `apiVersion` | `v1` | ConfigMap is a core v1 resource |
| `kind` | `ConfigMap` | Tells Kubernetes this is a configuration map resource |
| `metadata.name` | `data-store-env` | The name used to reference this ConfigMap from container specs |
| `data` | key-value pairs | Not `spec` — ConfigMap uses `data` to hold its key-value pairs |
| `data.folder` | `'story'` | The value that will be injected as the `STORY_FOLDER` environment variable |

### Key points about `data`

- The `data` section uses plain nested key-value pairs — **no dashes**, unlike lists
- You can add as many key-value pairs as needed
- Multiple containers across different Pods can reference the same ConfigMap

---

## Updated `deployment.yaml` — Using the ConfigMap

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
              # value: 'story'          ← replaced by valueFrom below
              valueFrom:
                configMapKeyRef:
                  name: data-store-env  # ← ConfigMap name
                  key: folder           # ← key inside the ConfigMap
          volumeMounts:
            - mountPath: /app/story
              name: story-volume
      volumes:
        - name: story-volume
          persistentVolumeClaim:
            claimName: host-pvc
```

### How `configMapKeyRef` works

| Field | Value | Meaning |
|---|---|---|
| `valueFrom.configMapKeyRef.name` | `data-store-env` | The name of the ConfigMap to look up |
| `valueFrom.configMapKeyRef.key` | `folder` | The specific key inside that ConfigMap whose value to use |

The container receives `STORY_FOLDER=story` — exactly as if `value: 'story'` had been written directly. The application code does not change at all.

---

## Applying the ConfigMap and Updated Deployment

Apply the ConfigMap **before** the Deployment that references it:

```bash
kubectl apply -f environment.yaml
kubectl apply -f deployment.yaml
```

Verify the ConfigMap was created:

```bash
kubectl get configmap
```

Expected output:

```
NAME               DATA   AGE
data-store-env     1      <age>
```

`DATA: 1` confirms one key-value pair is stored.

Check the Deployment:

```bash
kubectl get deployments
kubectl get pods
```

The old Pods terminate and new Pods start with the updated environment variable source. The application behaviour is unchanged — only the *origin* of the `STORY_FOLDER` value has moved from the container spec to the ConfigMap.

---

## Why Use a ConfigMap?

| | Inline `value:` | ConfigMap + `valueFrom:` |
|---|---|---|
| **Where config lives** | Inside the container spec | Standalone cluster resource |
| **Reusable across Pods** | ❌ Must copy the value into each Pod template | ✅ Multiple Pods reference the same ConfigMap |
| **Change requires** | Editing every Deployment YAML that uses it | Editing the ConfigMap once — all Pods pick it up |
| **Separation of concerns** | Config mixed with Pod definition | Config separated from Pod definition |
| **Best for** | Single Pod, simple one-off values | Shared config, team environments, multiple Pods |

---

## ConfigMap vs Volume — Which for What?

| | ConfigMap | Volume / PersistentVolume |
|---|---|---|
| **Used for** | Configuration values, environment variables, feature flags | File storage — data written by the application at runtime |
| **Accessed as** | Environment variables (or mounted as files) | Mounted directory inside the container |
| **Changed by** | Administrators / developers updating the YAML | Application writing files at runtime |
| **Persists app data?** | No | Yes (with appropriate volume type) |

---

## Summary

```
environment.yaml
    │
    └── ConfigMap: data-store-env
            │  data:
            │    folder: 'story'
            │
            ▼
deployment.yaml → container spec → env:
    - name: STORY_FOLDER
      valueFrom:
        configMapKeyRef:
          name: data-store-env   ← points to the ConfigMap
          key: folder            ← pulls the 'story' value

Apply order:
    kubectl apply -f environment.yaml    # ConfigMap first
    kubectl apply -f deployment.yaml     # Deployment second
```

ConfigMaps give you the same flexibility as inline environment variables — but with centralisation, reusability, and a clean separation between configuration and Pod definition. Combined with volumes and PersistentVolumes for file storage, you now have full control over how data flows in and out of your Kubernetes containers.
