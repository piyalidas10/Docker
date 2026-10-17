# Kubernetes: Required Setup & Installation Steps

## Overview

Before you can work with Kubernetes, you need to set up two distinct things:

1. **A Cluster** — the technical infrastructure (master node + worker nodes) with all required software installed
2. **kubectl** — your local communication tool for sending instructions to the cluster

---

## 1. What You Need: The Big Picture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    KUBERNETES REQUIRED SETUP                                 │
│                                                                             │
│   ┌────────────────────────────────────────────────────────────────────┐    │
│   │                        THE CLUSTER                                  │    │
│   │               (Cloud / Data Center / Local VM)                     │    │
│   │                                                                    │    │
│   │   ┌──────────────────────────────┐   ┌────────────────────────┐   │    │
│   │   │        MASTER NODE           │   │     WORKER NODE(S)     │   │    │
│   │   │  (may be distributed for HA) │   │  (one or more)         │   │    │
│   │   │                              │   │                        │   │    │
│   │   │  ✔ API Server                │   │  ✔ Docker              │   │    │
│   │   │  ✔ Scheduler                 │   │  ✔ kubelet             │   │    │
│   │   │  ✔ Controller Manager        │   │  ✔ kube-proxy          │   │    │
│   │   │  ✔ etcd                      │   │  ✔ Container Runtime   │   │    │
│   │   └──────────────────────────────┘   └────────────────────────┘   │    │
│   └────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│                              ▲                                              │
│                              │  sends instructions                         │
│                              │                                              │
│   ┌────────────────────────────────────┐                                    │
│   │         YOUR LOCAL MACHINE         │                                    │
│   │                                    │                                    │
│   │   ✔ kubectl  (kube-control tool)   │                                    │
│   └────────────────────────────────────┘                                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. The Cluster

### Master Node

The master node is the brain of the cluster. It receives your instructions and ensures they are executed correctly across all worker nodes.

> In production, the master node is often **distributed across multiple machines** to ensure high availability — if one master fails, the others keep the cluster running. For local development, a single master node is sufficient.

**Software required on the Master Node:**

| Component              | Role                                                                 |
|------------------------|----------------------------------------------------------------------|
| **API Server**         | Entry point for all cluster commands; exposes the Kubernetes API     |
| **Scheduler**          | Decides which worker node a new Pod should run on                    |
| **Controller Manager** | Runs control loops that reconcile desired state with actual state    |
| **etcd**               | Distributed key-value store; holds the entire cluster configuration  |

### Worker Nodes

Worker nodes are the machines that actually run your application containers inside Pods.

**Software required on each Worker Node:**

| Component             | Role                                                                    |
|-----------------------|-------------------------------------------------------------------------|
| **Docker**            | Container runtime that runs your images                                 |
| **kubelet**           | Agent that communicates with the master node; manages Pods on the node  |
| **kube-proxy**        | Manages networking rules; enables communication between Pods/services   |

---

## 3. kubectl — Your Communication Device

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     HOW kubectl FITS IN                                      │
│                                                                             │
│                                                                             │
│   Developer / Admin                                                         │
│        │                                                                    │
│        │  types a command                                                   │
│        ▼                                                                    │
│   ┌──────────────────┐                                                      │
│   │     kubectl      │  ←── Installed locally on your machine               │
│   │  (kube-control)  │      Works with ANY cluster:                         │
│   │                  │      • minikube (local)                               │
│   └────────┬─────────┘      • AWS EKS                                       │
│            │                • Google GKE                                    │
│            │  sends API     • Azure AKS                                     │
│            │  requests                                                       │
│            ▼                                                                │
│   ┌──────────────────┐                                                      │
│   │   API Server     │  ←── Runs on the Master Node (in the cluster)        │
│   │  (Master Node)   │      Receives instructions and acts on them          │
│   └────────┬─────────┘                                                      │
│            │  coordinates                                                   │
│            ▼                                                                │
│   ┌──────────────────────────────────────────┐                              │
│   │              Worker Nodes                │                              │
│   │   ┌──────────┐   ┌──────────┐            │                              │
│   │   │ Worker 1 │   │ Worker 2 │   ...      │                              │
│   │   │  Pods    │   │  Pods    │            │                              │
│   │   └──────────┘   └──────────┘            │                              │
│   └──────────────────────────────────────────┘                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

> ⚠️ **Do NOT confuse kubectl with the API Server.**
> - `kubectl` is your **local command-line tool** — the thing *with which* you give commands.
> - The **API Server** is the component *inside your cluster* that receives and processes those commands.

### Common kubectl Commands

```bash
# Create or update resources from a YAML file
kubectl apply -f deployment.yaml

# Create a new deployment
kubectl create deployment my-app --image=my-image:v1

# List all running Pods
kubectl get pods

# List all deployments
kubectl get deployments

# Scale a deployment
kubectl scale deployment my-app --replicas=5

# Delete a deployment
kubectl delete deployment my-app

# View logs of a Pod
kubectl logs <pod-name>

# Describe a resource (detailed info)
kubectl describe pod <pod-name>
```

---

## 4. The Analogy: How It All Works Together

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         THE COMMAND CHAIN ANALOGY                            │
│                                                                             │
│   kubectl          ══════►   Master Node    ══════►   Worker Nodes          │
│                                                                             │
│   "The one who                "The General"          "The Soldiers"         │
│    gives the                                                                │
│    order"          Issues the    Ensures the         Execute the            │
│                    command       command is           command               │
│                                  executed                                   │
│                                  correctly                                  │
│                                                                             │
│   You type:        →  API Server decides  →  kubelet on each Worker        │
│   kubectl apply       what needs to happen    Node creates/manages Pods    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Local Setup: minikube

For **local development and testing**, you do not need a real cloud cluster. Instead, use **minikube** — a tool that creates a single-node local cluster using a virtual machine on your computer.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        MINIKUBE: LOCAL CLUSTER                               │
│                                                                             │
│   Your Physical Machine                                                     │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                                                                     │   │
│   │   ┌─────────────────────────────────────────────────────────────┐   │   │
│   │   │             Virtual Machine (managed by minikube)            │   │   │
│   │   │                                                             │   │   │
│   │   │   ┌──────────────────────────────────────────────────────┐  │   │   │
│   │   │   │       Single-Node Kubernetes Cluster                  │  │   │   │
│   │   │   │                                                      │  │   │   │
│   │   │   │   Master Node  +  Worker Node  (combined into one)   │  │   │   │
│   │   │   │                                                      │  │   │   │
│   │   │   │   ✔ API Server   ✔ Scheduler   ✔ etcd               │  │   │   │
│   │   │   │   ✔ kubelet      ✔ Docker      ✔ kube-proxy         │  │   │   │
│   │   │   └──────────────────────────────────────────────────────┘  │   │   │
│   │   └─────────────────────────────────────────────────────────────┘   │   │
│   │                                                                     │   │
│   │   kubectl  (installed directly on your machine)                     │   │
│   │   ──────────────────────────────────────────────────────────────   │   │
│   │   Talks to the minikube cluster exactly as it would talk to a       │   │
│   │   real cloud cluster — same commands, same workflow.               │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

> **Note:** A combined master + worker node is **not recommended for production** but is perfectly fine for local development to keep things simple and resource-friendly.

### minikube Key Facts

| Property           | Value                                                          |
|--------------------|----------------------------------------------------------------|
| **Purpose**        | Local Kubernetes cluster for development & testing            |
| **Supported OS**   | Linux, macOS, Windows                                          |
| **Cluster Type**   | Single-node (master + worker combined in one VM)              |
| **Replaces kubectl?** | ❌ No — kubectl must be installed separately               |
| **Used in production?** | ❌ No — development/testing only                        |

---

## 6. Installation Summary

### What You Need to Install

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       INSTALLATION CHECKLIST                                 │
│                                                                             │
│   Step 1: Install kubectl                                                   │
│   ─────────────────────────────────────────────────────────────────────    │
│   • The CLI tool you use to talk to any Kubernetes cluster                  │
│   • Required regardless of whether you use minikube or a cloud cluster     │
│   • Install on: Linux / macOS / Windows                                     │
│   • Official docs: https://kubernetes.io/docs/tasks/tools/                  │
│                                                                             │
│   Step 2: Install minikube  (for local development)                         │
│   ─────────────────────────────────────────────────────────────────────    │
│   • Creates a local single-node Kubernetes cluster in a VM                  │
│   • Install on: Linux / macOS / Windows                                     │
│   • Official docs: https://minikube.sigs.k8s.io/docs/start/                 │
│                                                                             │
│   Step 3 (Alternative): Use a managed cloud service                         │
│   ─────────────────────────────────────────────────────────────────────    │
│   • AWS EKS, Google GKE, Azure AKS — no local cluster setup needed         │
│   • Still requires kubectl installed locally                                │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Quick Install Commands

**macOS (Homebrew):**
```bash
# Install kubectl
brew install kubectl

# Install minikube
brew install minikube

# Start the local cluster
minikube start

# Verify kubectl can reach the cluster
kubectl get nodes
```

**Windows (Chocolatey):**
```powershell
# Install kubectl
choco install kubernetes-cli

# Install minikube
choco install minikube

# Start the local cluster
minikube start

# Verify kubectl can reach the cluster
kubectl get nodes
```

**Linux:**
```bash
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Install minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Start the local cluster
minikube start

# Verify kubectl can reach the cluster
kubectl get nodes
```

---

## 7. Cloud vs. Local Setup Comparison

```
┌───────────────────────────────┬─────────────────────────────────────────────┐
│        LOCAL (minikube)       │       CLOUD (EKS / GKE / AKS)               │
├───────────────────────────────┼─────────────────────────────────────────────┤
│ minikube + kubectl installed  │ kubectl installed locally only               │
│ locally                       │                                             │
│                               │ Cluster lives in the cloud                  │
│ Cluster lives in a local VM   │                                             │
│                               │ Master + worker nodes are separate,         │
│ Master + worker combined in   │ distributed cloud machines                  │
│ one single VM                 │                                             │
│                               │ High availability by default                │
│ Single node (no HA)           │                                             │
│                               │ Suitable for production                     │
│ Development / testing only    │                                             │
│                               │ Same kubectl commands work                  │
│ Same kubectl commands work    │                                             │
└───────────────────────────────┴─────────────────────────────────────────────┘
```

---

## 8. Full Setup Flow Diagram

```
                        ┌────────────────────────────┐
                        │     Start Here              │
                        └──────────────┬─────────────┘
                                       │
                          ┌────────────▼────────────┐
                          │   Install kubectl        │
                          │   (always required)      │
                          └────────────┬────────────┘
                                       │
                     ┌─────────────────┼──────────────────┐
                     │                                    │
           ┌─────────▼─────────┐              ┌──────────▼──────────┐
           │  Local / Testing   │              │  Cloud / Production  │
           └─────────┬─────────┘              └──────────┬──────────┘
                     │                                   │
           ┌─────────▼─────────┐              ┌──────────▼──────────┐
           │ Install minikube   │              │ Use managed service  │
           └─────────┬─────────┘              │ (EKS / GKE / AKS)   │
                     │                        │ or set up cluster    │
           ┌─────────▼─────────┐              │ manually on VMs      │
           │ minikube start     │              └──────────┬──────────┘
           └─────────┬─────────┘                         │
                     │                                   │
                     └──────────────┬────────────────────┘
                                    │
                         ┌──────────▼──────────┐
                         │  kubectl get nodes   │
                         │  (verify connection) │
                         └──────────┬──────────┘
                                    │
                         ┌──────────▼──────────┐
                         │  Start deploying     │
                         │  applications with   │
                         │  kubectl apply -f    │
                         └─────────────────────┘
```

---

## Key Takeaways

1. **A cluster needs two things:** machines (master + worker nodes) with all required software installed.
2. **Master node software:** API Server, Scheduler, Controller Manager, etcd.
3. **Worker node software:** Docker (container runtime), kubelet, kube-proxy.
4. **kubectl is separate from the cluster** — it is a local CLI tool you use to send commands to the cluster, not part of the cluster itself.
5. **minikube** creates a combined single-node cluster in a local VM — ideal for learning and testing, not for production.
6. **The same kubectl commands work** whether you're talking to a local minikube cluster or a cloud cluster on AWS EKS, Google GKE, or Azure AKS.
7. **Install order:** kubectl first, then minikube (for local) or configure cloud credentials (for cloud).
