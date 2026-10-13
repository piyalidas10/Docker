# Kubernetes Limitations: It Does Not Provision the Machines for You

Kubernetes manages your applications and cluster resources, but it does **not** automatically create and prepare all the underlying machines in a self-managed environment.

The examples below use an enterprise banking application.

## 1. What problem is the instructor describing?

Imagine you want to deploy a banking frontend, backend API, and payment service using Kubernetes. Before Kubernetes can schedule your Pods, you need infrastructure on which Kubernetes can run.

| Step | What happens |
|---|---|
| **1. Infrastructure provisioning** | Create physical machines or virtual machines (VMs). |
| **2. Kubernetes installation and configuration** | Configure the control plane and Worker Nodes in a self-managed cluster. |
| **3. Deploy the banking application** | Kubernetes schedules Pods and manages their desired state. |

In a self-managed environment, someone must provision the machines and install or configure the necessary Kubernetes components before the cluster can run workloads.

## 2. Who manages what?

| Responsibility | Self-managed Kubernetes | Managed Kubernetes |
|---|---|---|
| Create physical machines or VMs | Infrastructure / platform team | Cloud provider for the control plane; customer provisions or configures worker capacity, depending on the service |
| Install and manage the control plane | Your team | Cloud provider |
| Install and maintain worker-node components | Your team | Provider tooling or managed node service, depending on configuration |
| Deploy application Pods | Application / DevOps team | Application / DevOps team |
| Configure application scaling | Platform / DevOps team | Platform / DevOps team |
| Configure storage and networking | Shared responsibility | Shared responsibility |

## 3. AWS example: self-managed vs. managed Kubernetes

### Option A: Self-managed Kubernetes

Your team must manage:

- EC2 instances for control-plane nodes
- EC2 instances for worker nodes
- Kubernetes installation and upgrades
- Load balancers and storage
- Cluster security and maintenance

### Option B: Amazon EKS

AWS manages the Kubernetes control plane:

- API server
- Control-plane availability
- Control-plane infrastructure

Your team still manages worker capacity, applications, access policies, and workload configuration according to the chosen EKS setup.

> For AWS, the managed service is **Amazon EKS**. You generally do not need to create and maintain your own Kubernetes control-plane EC2 instances when using EKS.

## 4. How do we avoid all this manual work?

The key point of the lecture: **Infrastructure as Code (IaC)** and **managed Kubernetes services**.

| Tool / approach | Role | What it does |
|---|---|---|
| <img src="https://images.openai.com/static-rsc-4/OucbJVc5Wo3qkMjQpVLN8cyoIzDg_fzgQhKKnyHAtxsnLxmFoh-07NJ7FNrSE8L-Gc7cqdWocCFyXEkOGNEPDbLJmNgfYnoCn2PO5n9Lc4bqmhw56ZfvqCZUFdGMTVHmUznMotvubtPIrJUJ7hZ1kBF5LIPiZ73Mifpnt24fObw?purpose=inline" width="75px" /> **Terraform** | Infrastructure provisioning | Define EC2 instances, networks, IAM permissions, EKS clusters, load balancers, and storage as code instead of creating them manually. |
| **Amazon EKS** | Managed Kubernetes | AWS manages the Kubernetes control plane, reducing the operational work required to run a cluster. |
| **Helm / Kubernetes manifests** | Application deployment | Define Deployments, Services, resource requests, limits, and scaling rules declaratively. |
| **CI/CD pipeline** | Automated delivery | Build and test the application, publish the container image, and deploy the updated version to Kubernetes. |

## 5. The enterprise banking workflow

```mermaid
flowchart TD
    IaC["Terraform / IaC"] --> Infra["Cloud infrastructure"]
    Infra --> EKS["Amazon EKS control plane"]
    Infra --> Workers["Worker nodes"]
    EKS --> API["Kubernetes API"]
    CICD["CI/CD pipeline"] --> Registry["Container registry"]
    CICD --> API
    API --> Deploy["Deployments and Services"]
    Deploy --> Pods["Banking application Pods"]
    Workers -.->|run| Pods
    Registry -.->|image pull| Pods
    Users["Users access banking application"] --> Pods
```

The important distinction is that Kubernetes automation and infrastructure automation solve different problems:

- Kubernetes automates workload scheduling, recovery, service discovery, and application scaling.
- Terraform or similar tools automate the creation and configuration of infrastructure.
- Managed Kubernetes reduces the amount of cluster infrastructure you must operate.
- CI/CD automates the process of delivering application changes.

> **Remember:** Kubernetes does not automatically mean zero infrastructure management. In a modern enterprise, teams combine managed Kubernetes, Infrastructure as Code, and CI/CD to avoid manually creating and configuring every resource for every deployment.
