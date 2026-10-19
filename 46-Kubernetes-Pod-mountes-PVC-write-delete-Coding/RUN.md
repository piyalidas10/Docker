# RUN.md — How to Run the PV/PVC Persistence Lab

---

## Prerequisites

Before running the lab, confirm the following are in place:

| Requirement | How to check |
|---|---|
| Docker Desktop installed | Open Docker Desktop — it should show "Engine running" |
| Kubernetes enabled in Docker Desktop | Docker Desktop → Settings → Kubernetes → "Enable Kubernetes" must be ticked and the status indicator green |
| `kubectl` available in your terminal | Run `kubectl version --client` — should print a version number |
| Active context points to Docker Desktop | Run `kubectl config current-context` — should return `docker-desktop` |

If the context is wrong, switch it:

```powershell
kubectl config use-context docker-desktop
```

---

## Files in This Folder

| File | Purpose |
|---|---|
| `pv-pvc-demo.yaml` | Kubernetes manifest — defines the PV, PVC, and Pod in a single file |
| `run-lab.ps1` | PowerShell script — runs the full lab sequence automatically |
| `README.md` | Full step-by-step lab guide with explanations |
| `RUN.md` | This file — how to run the lab |

---

## What `pv-pvc-demo.yaml` Creates

The YAML file defines **three Kubernetes resources** separated by `---`:

### Resource 1 — PersistentVolume (`demo-pv`)

```yaml
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
```

| Field | Value | Meaning |
|---|---|---|
| `capacity.storage` | `1Gi` | Total storage capacity offered by this PV |
| `accessModes` | `ReadWriteOnce` | Mountable read-write by a single node at a time |
| `persistentVolumeReclaimPolicy` | `Retain` | When the PVC is deleted, the PV and its data are **kept** — not automatically removed |
| `storageClassName` | `""` | No StorageClass — requires manual binding with a matching PVC |
| `hostPath.path` | `/mnt/data/demo-pv` | Directory on the Kubernetes node's filesystem used as the actual storage location |

---

### Resource 2 — PersistentVolumeClaim (`demo-pvc`)

```yaml
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
```

| Field | Value | Meaning |
|---|---|---|
| `accessModes` | `ReadWriteOnce` | Must match the PV's access mode for binding to succeed |
| `storageClassName` | `""` | Must match the PV's `storageClassName` — both empty, so Kubernetes binds them manually |
| `resources.requests.storage` | `500Mi` | Requests 500 MiB — the PV offers 1Gi, which satisfies this request |

---

### Resource 3 — Pod (`storage-demo-pod`)

```yaml
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

| Field | Value | Meaning |
|---|---|---|
| `image` | `busybox:1.36` | Lightweight Linux image — enough to run shell commands |
| `command` | `sleep 3600` | Keeps the container alive for 1 hour so you can `exec` into it |
| `mountPath` | `/data` | The PVC is accessible inside the container at this path |
| `claimName` | `demo-pvc` | References the PVC defined above — this is how the Pod connects to the PV |

---

## How to Run `run-lab.ps1`

### Step 1 — Open PowerShell

Press `Win + X` → select **Windows PowerShell** or **Terminal**.

### Step 2 — Navigate to this folder

```powershell
cd path\to\46-Kubernetes-Pod-mountes-PVC-write-delete-Coding
```

Replace `path\to\` with the actual path on your machine. For example:

```powershell
cd C:\PIYALI\Github\Docker\46-Kubernetes-Pod-mountes-PVC-write-delete-Coding
```

### Step 3 — Allow script execution (first time only)

PowerShell may block scripts by default. Run this once to allow local scripts:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

When prompted, type `Y` and press Enter.

### Step 4 — Run the script

```powershell
.\run-lab.ps1
```

---

## What the Script Does — Step by Step

```
.\run-lab.ps1
    │
    ├── STEP 1 — kubectl apply -f pv-pvc-demo.yaml
    │            Creates demo-pv, demo-pvc, storage-demo-pod
    │            Waits until storage-demo-pod is Ready
    │            Prints status of PV, PVC, and Pod
    │
    ├── STEP 2 — kubectl exec → writes /data/message.txt
    │            Writes: "Hello Kubernetes! Persistent data survives Pod replacement."
    │            Reads the file back to confirm
    │
    ├── STEP 3 — kubectl delete pod storage-demo-pod
    │            Deletes only the Pod
    │            Confirms demo-pv and demo-pvc still exist
    │
    ├── STEP 4 — kubectl apply -f pv-pvc-demo.yaml
    │            Recreates storage-demo-pod (PV and PVC already exist)
    │            Waits until the replacement Pod is Ready
    │            Reads /data/message.txt from the replacement Pod
    │            ✅ File is still there — persistence verified
    │
    └── STEP 5 — Prompts: "Clean up all resources? [y/N]"
                 y → deletes Pod, PVC, and PV
                 N → leaves resources in the cluster, prints manual delete commands
```

---

## Expected Output

After Step 4, you should see:

```
Reading /data/message.txt from the REPLACEMENT Pod:
Hello Kubernetes! Persistent data survives Pod replacement.
```

And the final banner:

```
============================================================
 Persistence verified.
 The file written by the original Pod is still available
 to the replacement Pod via the same PVC.
============================================================
```

---

## Manual Clean Up

If you chose `N` at the clean-up prompt, or want to clean up later:

```powershell
kubectl delete pod storage-demo-pod --ignore-not-found
kubectl delete pvc demo-pvc          --ignore-not-found
kubectl delete pv  demo-pv           --ignore-not-found
```

> **Important:** Because the reclaim policy is `Retain`, the PV is **not** deleted automatically when you delete the PVC. You must delete the PV separately. The data directory on the node (`/mnt/data/demo-pv`) also remains until manually removed.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `kubectl: command not found` | `kubectl` not installed or not on PATH | Enable Kubernetes in Docker Desktop — it installs `kubectl` automatically |
| Pod stuck in `Pending` | PVC not bound to PV | Run `kubectl describe pod storage-demo-pod` and check Events |
| PVC stuck in `Pending` | `storageClassName` or `accessModes` mismatch | Confirm both PV and PVC have `storageClassName: ""` and the same `accessModes` |
| `cannot be loaded because running scripts is disabled` | PowerShell execution policy | Run `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` |
| Context is not `docker-desktop` | Wrong Kubernetes context active | Run `kubectl config use-context docker-desktop` |
| `ErrImagePull` on busybox | Docker Hub rate limit or no internet | Wait a few minutes and re-apply, or check Docker Hub login |

---

## Notes

- This lab uses `hostPath` storage, which is tied to the **Kubernetes node's local filesystem**. It is suitable for single-node local learning only.
- In a production cluster, the same `PV → PVC → Pod` workflow applies — only the PV definition changes (e.g. using a StorageClass with the AWS EFS CSI driver instead of `hostPath`).
- The `Retain` reclaim policy is intentional here — it ensures you can inspect the PV after deleting the PVC and understand the lifecycle clearly.
