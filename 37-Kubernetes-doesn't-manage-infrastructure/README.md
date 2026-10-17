# Kubernetes Does NOT Manage Infrastructure

## Overview

Before getting hands-on with Kubernetes, there is one **critical concept** to understand: the clear split between what **you** are responsible for and what **Kubernetes** handles for you.

> ⚠️ **Key Insight:** Kubernetes is an **application orchestration** tool — not a cloud infrastructure provisioning tool.
> Kubernetes manages your containerized application, but Kubernetes itself does not automatically create all the infrastructure required to run it.

---

## The Fundamental Split

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        KUBERNETES RESPONSIBILITY SPLIT                       │
├─────────────────────────────────────────┬───────────────────────────────────┤
│         YOUR Responsibility             │     KUBERNETES Responsibility      │
│         (You must do this)              │     (Kubernetes does this)         │
├─────────────────────────────────────────┼───────────────────────────────────┤
│  • Create Master & Worker Nodes         │  • Create and manage Pods          │
│    (VMs, EC2 instances, bare metal)     │  • Run containers inside Pods      │
│                                         │                                    │
│  • Install Kubernetes software on nodes │  • Monitor containers & Pods       │
│    - API Server (master)                │  • Replace failing Pods            │
│    - Scheduler (master)                 │  • Scale Pods up/down              │
│    - Controller Manager (master)        │                                    │
│    - etcd (master)                      │  • Move Pods between worker nodes  │
│    - kubelet (each worker)              │  • Ensure app is reachable         │
│    - kube-proxy (each worker)           │    by end users                    │
│                                         │                                    │
│  • Manage OS updates & patches          │  • Keep your application           │
│  • Network security groups / firewall   │    up and running                  │
│  • Keep instances healthy & secure      │  • Utilize the worker node         │
│  • Provision load balancers (if needed) │    resources you created           │
│  • Provision storage (EFS, etc.)        │                                    │
└─────────────────────────────────────────┴───────────────────────────────────┘
```

<img src="./Kubernetes vs Infrastructure Responsibilities.png" width="90%" />

---

## Architecture Diagram

```
                         ┌──────────────────────────────────────────┐
                         │         YOUR INFRASTRUCTURE LAYER         │
                         │        (You create & manage this)         │
                         │                                           │
                         │  ┌─────────────────────────────────────┐  │
                         │  │          Cloud / Data Center         │  │
                         │  │                                     │  │
                         │  │  ┌──────────────┐  ┌─────────────┐ │  │
                         │  │  │  Master Node │  │ Master Node │ │  │
                         │  │  │  (EC2 / VM)  │  │  (EC2 / VM) │ │  │
                         │  │  └──────┬───────┘  └──────┬──────┘ │  │
                         │  │         │                  │        │  │
                         │  │  ┌──────▼──────────────────▼──────┐ │  │
                         │  │  │        Worker Nodes             │ │  │
                         │  │  │  ┌──────────┐  ┌──────────┐   │ │  │
                         │  │  │  │ Worker 1 │  │ Worker 2 │   │ │  │
                         │  │  │  │(EC2 / VM)│  │(EC2 / VM)│   │ │  │
                         │  │  │  └──────────┘  └──────────┘   │ │  │
                         │  │  └─────────────────────────────────┘ │  │
                         │  │                                     │  │
                         │  │  + Load Balancer + Storage (EFS)   │  │
                         │  └─────────────────────────────────────┘  │
                         └──────────────────────────────────────────┘
                                          │
                                          │  Kubernetes runs ON TOP of this
                                          ▼
                         ┌──────────────────────────────────────────┐
                         │          KUBERNETES LAYER                 │
                         │     (Kubernetes manages this for you)     │
                         │                                           │
                         │   Worker 1            Worker 2            │
                         │  ┌──────────────┐   ┌──────────────┐     │
                         │  │  Pod A       │   │  Pod B       │     │
                         │  │ ┌──────────┐ │   │ ┌──────────┐ │     │
                         │  │ │Container1│ │   │ │Container2│ │     │
                         │  │ └──────────┘ │   │ └──────────┘ │     │
                         │  │  Pod C  ←────┼───┼── rescheduled│     │
                         │  │ ┌──────────┐ │   │   (failing   │     │
                         │  │ │Container3│ │   │    pod moved) │     │
                         │  │ └──────────┘ │   └──────────────┘     │
                         │  └──────────────┘                         │
                         │                                           │
                         │  ✔ Monitors  ✔ Replaces  ✔ Scales        │
                         └──────────────────────────────────────────┘
```

---

## What Kubernetes Does NOT Do

| ❌ NOT Kubernetes                              | ✅ YOUR Responsibility                        |
|-----------------------------------------------|----------------------------------------------|
| Create EC2 instances / VMs                    | You create them via AWS Console, CLI, or IaC |
| Install kubelet / API Server on nodes         | You install and configure these manually     |
| Manage OS security patches                    | You keep the OS updated                      |
| Manage network security groups / firewalls    | You configure network access rules           |
| Provision load balancers                      | You create them (e.g., AWS ALB/ELB)          |
| Provision persistent storage (EFS, EBS, etc.) | You create and attach storage                |

---

## What Kubernetes DOES Do

| ✅ Kubernetes Handles This                    | Description                                          |
|----------------------------------------------|------------------------------------------------------|
| Pod creation & management                    | Deploys your containers inside Pods on worker nodes  |
| Container monitoring                         | Watches if containers are healthy and running        |
| Replacing failing Pods                       | Automatically restarts or reschedules failed Pods    |
| Scaling                                      | Scales Pods up/down based on demand                  |
| Load distribution                            | Spreads Pods across worker nodes                     |
| Ensuring reachability                        | Makes sure your app is accessible to end users       |

---

## The "Completing the Picture" Tools

Since Kubernetes doesn't provision infrastructure, you need additional tools to fill the gap:

```
┌─────────────────────────────────────────────────────────────────────┐
│                      COMPLETING THE PICTURE                          │
│                                                                     │
│   ┌──────────────────────┐       ┌──────────────────────────────┐   │
│   │    Manual Approach   │       │    Managed / Automated       │   │
│   │                      │       │         Approach             │   │
│   │  • Create EC2 / VMs  │       │                              │   │
│   │    yourself          │  OR   │  • AWS EKS                   │   │
│   │  • Install kubelets  │       │    (Elastic Kubernetes Svc)  │   │
│   │    & API server      │       │  • Kubermatic                │   │
│   │    manually          │       │  • Google GKE                │   │
│   │  • High maintenance  │       │  • Azure AKS                 │   │
│   │    overhead          │       │                              │   │
│   │                      │       │  These provision infra AND   │   │
│   └──────────────────────┘       │  integrate with Kubernetes   │   │
│                                  └──────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### Tools That Help

| Tool / Service         | Provider   | What It Does                                                                    |
|------------------------|------------|---------------------------------------------------------------------------------|
| **EKS** (Elastic Kubernetes Service) | AWS        | Provisions all infra needed for your Kubernetes config; bring your own K8s YAML |
| **GKE** (Google Kubernetes Engine)   | Google     | Fully managed Kubernetes cluster on Google Cloud                                |
| **AKS** (Azure Kubernetes Service)   | Azure      | Managed Kubernetes on Microsoft Azure                                           |
| **Kubermatic**                       | Open Source| Creates remote machines & installs K8s software; not part of Kubernetes itself  |

> 📝 **Note:** EKS differs from ECS — with EKS you bring your own Kubernetes configuration. You are not locked into AWS-specific orchestration.

---

## Who does what in a real enterprise?

| Responsibility                         | Typical owner or tool                                                |
| -------------------------------------- | -------------------------------------------------------------------- |
| Create cloud VMs and networks          | Cloud / Infrastructure team, Terraform                               |
| Configure server operating systems     | Infrastructure / Platform team                                       |
| Provision Kubernetes cluster           | Platform team, managed Kubernetes service (e.g., AWS EKS)            |
| Define Pods, Deployments and Services  | Application developers / DevOps engineers                            |
| Set CPU and memory requests and limits | Development team, guided by platform standards and capacity planning |
| Schedule Pods onto nodes               | Kubernetes Scheduler                                                 |
| Restart and replace workloads          | Kubernetes controllers and kubelet                                   |
| Monitor health and performance         | Platform and application teams using monitoring tools                |

---

## Summary Flow

```
                ┌─────────────────────────────────────────┐
                │         Full Deployment Picture          │
                └──────────────────┬──────────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
              ▼                    ▼                    ▼
    ┌──────────────────┐  ┌─────────────────┐  ┌─────────────────┐
    │  Infrastructure  │  │   Kubernetes    │  │  Your App Code  │
    │   Provisioning   │  │  Orchestration  │  │  (Containers)   │
    │                  │  │                 │  │                 │
    │ • Nodes (VMs)    │  │ • Pod mgmt      │  │ • Dockerfiles   │
    │ • Load Balancer  │  │ • Monitoring    │  │ • Images        │
    │ • Storage        │  │ • Scaling       │  │ • Deployments   │
    │ • Networking     │  │ • Self-healing  │  │   (YAML)        │
    │                  │  │                 │  │                 │
    │ ➜ YOU or EKS/   │  │ ➜ KUBERNETES   │  │ ➜ YOU          │
    │   Kubermatic     │  │   handles this  │  │   define this   │
    └──────────────────┘  └─────────────────┘  └─────────────────┘
```

---

## Key Takeaways

1. **Kubernetes ≠ Cloud Provider** — It is a framework and set of concepts/tools, not a service that creates machines.
2. **Kubernetes ≠ Infrastructure Tool** — It does not create VMs, EC2 instances, load balancers, or storage.
3. **Kubernetes = Application Orchestrator** — It manages, monitors, scales, and maintains your containerized applications on infrastructure *you provide*.
4. **You must prepare the nodes** — Install the API server, kubelet, kube-proxy, scheduler, etc. on master and worker nodes yourself (or use a managed service).
5. **Managed services complete the picture** — Tools like AWS EKS, GKE, AKS, or Kubermatic bridge the gap by handling infrastructure provisioning alongside Kubernetes orchestration.
6. **For local learning** — Set up a local Kubernetes environment (e.g., with Minikube or Docker Desktop) where both master and worker nodes run on your machine with all required software pre-installed.
7. **Without a managed service or infrastructure automation** - You arrange the machines, networking and Kubernetes installation; Kubernetes manages your workloads afterward.
8. **With a managed service such as AWS EKS** - AWS manages much of the Kubernetes control plane and provides infrastructure integrations. You still have responsibilities for workload configuration, permissions, capacity, networking choices and potentially worker-node management, depending on the setup.
