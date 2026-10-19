# Kubernetes Hands-on Lab: Verify PV/PVC Data Persistence

Creating a Pod that mounts a PVC, writing a file, deleting the Pod, and verifying that the file remains available to its replacement.

We'll perform this experiment on your Windows laptop using Docker Desktop Kubernetes.

---

## What You'll Prove

| Step | Action | Goal |
|---|---|---|
| 1 | Create PV + PVC + Pod | Mount persistent storage at `/data` |
| 2 | Write a file | `/data/message.txt` → `"Hello Kubernetes!"` |
| 3 | Delete the Pod | The Pod is removed; the PV and PVC remain |
| 4 | Create a replacement Pod | Mount the same PVC and read the original file |

---

## 1. Create the Kubernetes Configuration

Create a file named `pv-pvc-demo.yaml` in a folder on your Windows computer.

This single YAML file defines all three resources — PV, PVC, and Pod — separated by `---`.

```yaml
# 1. Persistent Volume
apiVersion: v1
kind: PersistentVolume
metadata:
  name: demo-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: /mnt/data/demo-pv
---
# 2. Persistent Volume Claim
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ""
  resources:
    requests:
      storage: 500Mi
---
# 3. Pod that mounts the PVC
apiVersion: v1
kind: Pod
metadata:
  name: storage-demo-pod
spec:
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: persistent-storage
          mountPath: /data
  volumes:
    - name: persistent-storage
      persistentVolumeClaim:
        claimName: demo-pvc
```

### Understanding the configuration

| Resource | Role |
|---|---|
| `demo-pv` | Represents 1Gi of storage backed by a directory on the Kubernetes node (`/mnt/data/demo-pv`) |
| `demo-pvc` | Requests 500Mi — the PV's 1Gi capacity satisfies this |
| `storage-demo-pod` | Runs a `busybox` container that simply sleeps, keeping the Pod alive for interaction |
| `mountPath: /data` | Makes the persistent storage accessible inside the container at `/data` |
| `Retain` reclaim policy | Keeps the underlying PV data when the PVC is released — does **not** mean deleting the Pod deletes the PV or PVC |

> **Note:** The `hostPath` configuration is for this local learning exercise. It stores data on the Kubernetes node's filesystem and is not a production multi-node storage solution.

---

## 2. Apply the YAML File

Open PowerShell or your terminal in the folder containing `pv-pvc-demo.yaml`.

```bash
kubectl apply -f pv-pvc-demo.yaml
```

Check all three resources:

```bash
kubectl get pv
kubectl get pvc
kubectl get pods
```

### Expected state

| Resource | Expected status |
|---|---|
| `demo-pv` | `Bound` |
| `demo-pvc` | `Bound` |
| `storage-demo-pod` | `Running` |

If the Pod is still starting, wait for it to become ready:

```bash
kubectl wait --for=condition=Ready pod/storage-demo-pod --timeout=120s
```

---

## 3. Write a File into Persistent Storage

Execute a command inside the running Pod to write a file to `/data`:

```bash
kubectl exec storage-demo-pod -- sh -c "echo 'Hello Kubernetes! Persistent data survives Pod replacement.' > /data/message.txt"
```

Read the file back to confirm it was written:

```bash
kubectl exec storage-demo-pod -- cat /data/message.txt
```

**Expected output:**

```
Hello Kubernetes! Persistent data survives Pod replacement.
```

The file now lives at `/data/message.txt` inside the container, backed by the mounted PV at `/mnt/data/demo-pv` on the node.

---

## 4. Delete the Pod

```bash
kubectl delete pod storage-demo-pod
```

Check what remains:

```bash
kubectl get pods
kubectl get pv
kubectl get pvc
```

You should see that `storage-demo-pod` has been removed, while `demo-pv` and `demo-pvc` still exist with status `Bound`.

> **This is the critical distinction:** deleting a Pod does **not** automatically delete its PVC or PV. The storage resources and their data outlive the Pod.

---

## 5. Create the Replacement Pod

Because the Pod definition is still in your YAML file, apply it again:

```bash
kubectl apply -f pv-pvc-demo.yaml
```

Wait for the replacement Pod to become ready:

```bash
kubectl wait --for=condition=Ready pod/storage-demo-pod --timeout=120s
```

Now read the file from the replacement Pod:

```bash
kubectl exec storage-demo-pod -- cat /data/message.txt
```

**Expected output:**

```
Hello Kubernetes! Persistent data survives Pod replacement.
```

✅ **Persistence verified** — the original file remains available even though the original Pod was deleted and a new Pod was created.

---

## 6. What Happened Behind the Scenes

```
Original Pod
    │
    │  writes /data/message.txt
    │
    ▼
  deleted ✗
    │
    │  PVC demo-pvc  ──────────────────► PV demo-pv  (data preserved ✅)
    │  (still bound)                     /mnt/data/demo-pv/message.txt
    │
Replacement Pod
    │
    │  mounts demo-pvc at /data
    │
    ▼
  reads /data/message.txt  ✅
  "Hello Kubernetes! Persistent data survives Pod replacement."
```

The same PVC remained bound to the PV throughout. The replacement Pod simply mounted the same claim and found the data exactly as the original Pod left it.

---

## 7. Important Difference: Pod vs PVC Deletion

| Action | Expected result |
|---|---|
| **Delete the Pod** | PV and PVC remain; data persists |
| **Create a replacement Pod using the same PVC** | It can read the existing data |
| **Delete the PVC** | The `Retain` policy preserves the underlying storage, but the PV becomes `Released` and requires administrative handling before reuse |
| **Delete the PV resource** | The effect on the underlying data depends on the storage type and configuration; do not assume it is safe |

---

## 8. Clean Up

When you have finished the experiment:

```bash
kubectl delete pod storage-demo-pod
kubectl delete pvc demo-pvc
kubectl delete pv demo-pv
```

> Because the reclaim policy is `Retain`, you must delete the PV manually after deleting the PVC. The data directory on the node (`/mnt/data/demo-pv`) will remain until removed manually.

---

## Summary

You have demonstrated the central purpose of Kubernetes persistent storage:

> **The application Pod can be replaced without necessarily losing the data it generated.**

| Component | Lifecycle |
|---|---|
| Pod | Temporary — can be deleted and recreated freely |
| PVC | Independent of the Pod — survives Pod deletion |
| PV | Independent of the Pod and PVC (with `Retain`) — data preserved |
| Data at `/data/message.txt` | Persists across Pod replacements as long as PV and PVC exist |

> **Production note:** This lab uses `hostPath`, so the data is tied to the Kubernetes node's filesystem. The same PVC/PV workflow applies in production clusters using external storage through a suitable StorageClass and CSI driver — for example, AWS EFS via the EFS CSI driver.
