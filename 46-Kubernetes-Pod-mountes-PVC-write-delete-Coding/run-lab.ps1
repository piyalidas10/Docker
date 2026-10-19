# ============================================================
# Kubernetes Hands-on Lab: Verify PV/PVC Data Persistence
# Run this script from the folder containing pv-pvc-demo.yaml
# Requirements: Docker Desktop with Kubernetes enabled
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Kubernetes PV/PVC Data Persistence Lab" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# STEP 1 — Apply PV, PVC, and Pod
# ------------------------------------------------------------
Write-Host "STEP 1: Applying PV, PVC, and Pod..." -ForegroundColor Yellow
kubectl apply -f pv-pvc-demo.yaml
Write-Host ""

# Wait for the Pod to be ready
Write-Host "Waiting for storage-demo-pod to become Ready..." -ForegroundColor Yellow
kubectl wait --for=condition=Ready pod/storage-demo-pod --timeout=120s
Write-Host ""

# Show resource status
Write-Host "--- PersistentVolume ---" -ForegroundColor Green
kubectl get pv demo-pv
Write-Host ""
Write-Host "--- PersistentVolumeClaim ---" -ForegroundColor Green
kubectl get pvc demo-pvc
Write-Host ""
Write-Host "--- Pod ---" -ForegroundColor Green
kubectl get pod storage-demo-pod
Write-Host ""

# ------------------------------------------------------------
# STEP 2 — Write a file into persistent storage
# ------------------------------------------------------------
Write-Host "STEP 2: Writing file to /data/message.txt inside the Pod..." -ForegroundColor Yellow
kubectl exec storage-demo-pod -- sh -c "echo 'Hello Kubernetes! Persistent data survives Pod replacement.' > /data/message.txt"

Write-Host "Reading the file back from the original Pod:" -ForegroundColor Green
kubectl exec storage-demo-pod -- cat /data/message.txt
Write-Host ""

# ------------------------------------------------------------
# STEP 3 — Delete the Pod
# ------------------------------------------------------------
Write-Host "STEP 3: Deleting the Pod..." -ForegroundColor Yellow
kubectl delete pod storage-demo-pod
Write-Host ""

Write-Host "Checking remaining resources (PV and PVC should still exist):" -ForegroundColor Green
kubectl get pv demo-pv
kubectl get pvc demo-pvc
Write-Host ""

# ------------------------------------------------------------
# STEP 4 — Create the replacement Pod and verify the file
# ------------------------------------------------------------
Write-Host "STEP 4: Creating the replacement Pod..." -ForegroundColor Yellow
kubectl apply -f pv-pvc-demo.yaml

Write-Host "Waiting for replacement storage-demo-pod to become Ready..." -ForegroundColor Yellow
kubectl wait --for=condition=Ready pod/storage-demo-pod --timeout=120s
Write-Host ""

Write-Host "Reading /data/message.txt from the REPLACEMENT Pod:" -ForegroundColor Green
kubectl exec storage-demo-pod -- cat /data/message.txt
Write-Host ""

# ------------------------------------------------------------
# RESULT
# ------------------------------------------------------------
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Persistence verified." -ForegroundColor Cyan
Write-Host " The file written by the original Pod is still available" -ForegroundColor Cyan
Write-Host " to the replacement Pod via the same PVC." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# STEP 5 — Clean up (optional — prompts before deleting)
# ------------------------------------------------------------
$cleanup = Read-Host "Clean up all resources? (PV, PVC, Pod) [y/N]"
if ($cleanup -eq "y" -or $cleanup -eq "Y") {
    Write-Host "Deleting Pod, PVC, and PV..." -ForegroundColor Yellow
    kubectl delete pod storage-demo-pod --ignore-not-found
    kubectl delete pvc demo-pvc --ignore-not-found
    kubectl delete pv  demo-pv  --ignore-not-found
    Write-Host "Clean up complete." -ForegroundColor Green
} else {
    Write-Host "Skipping clean up. Resources remain in the cluster." -ForegroundColor Gray
    Write-Host "To clean up manually:" -ForegroundColor Gray
    Write-Host "  kubectl delete pod storage-demo-pod" -ForegroundColor Gray
    Write-Host "  kubectl delete pvc demo-pvc" -ForegroundColor Gray
    Write-Host "  kubectl delete pv  demo-pv" -ForegroundColor Gray
}

Write-Host ""
