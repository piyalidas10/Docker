# Kubernetes Limitations: It Does Not Provision the Machines for You

Kubernetes manages your applications and cluster resources, but it does **not** automatically create and prepare all the underlying machines in a self-managed environment.

The examples below use an enterprise banking application.

## 1. What is the problem ?

Imagine you want to deploy a banking frontend, backend API, and payment service using Kubernetes. Before Kubernetes can schedule your Pods, you need infrastructure on which Kubernetes can run.

### Diagram 1

```mermaid
flowchart LR
    A["<b>1. Infrastructure provisioning</b><br/>Create physical machines or virtual machines (VMs)"]
    B["<b>2. Network and security setup</b><br/>Create networks, subnets, firewall rules, and access permissions"]
    C["<b>3. Prepare every machine</b><br/>Install the operating system, container runtime, and Kubernetes packages"]
    D["<b>4. Bootstrap the control plane</b><br/>Initialise the API server, etcd, scheduler, and controller manager"]
    E["<b>5. Join the worker nodes</b><br/>Register each worker node with the control plane"]
    F["<b>6. Install cluster add-ons</b><br/>Pod networking, DNS, ingress, storage, and metrics"]
    G["<b>7. Configure access and policies</b><br/>RBAC, kubeconfig, namespaces, and resource policies"]
    H["<b>8. Deploy the banking application</b><br/>Kubernetes schedules Pods and manages their desired state"]
    I["<b>9. Operate and maintain</b><br/>Monitor, scale, patch, back up, and upgrade the cluster"]
    A --> B --> C --> D --> E --> F --> G --> H --> I
```

### Diagram 2

```mermaid
flowchart TB
    subgraph P1["Phase 1: Prepare the infrastructure"]
        direction LR
        A["<b>1. Infrastructure provisioning</b><br/>Create physical machines<br/>or virtual machines (VMs)"]
        B["<b>2. Network and security setup</b><br/>Networks, subnets, firewall rules,<br/>and access permissions"]
        C["<b>3. Prepare every machine</b><br/>OS, container runtime,<br/>and Kubernetes packages"]
        A --> B --> C
    end

    subgraph P2["Phase 2: Build the Kubernetes cluster"]
        direction LR
        D["<b>4. Bootstrap the control plane</b><br/>API server, etcd, scheduler,<br/>and controller manager"]
        E["<b>5. Join the worker nodes</b><br/>Register each worker node<br/>with the control plane"]
        F["<b>6. Install cluster add-ons</b><br/>Pod networking, DNS, ingress,<br/>storage, and metrics"]
        G["<b>7. Configure access and policies</b><br/>RBAC, kubeconfig, namespaces,<br/>and resource policies"]
        D --> E --> F --> G
    end

    subgraph P3["Phase 3: Run the banking application"]
        direction LR
        H["<b>8. Deploy the banking application</b><br/>Kubernetes schedules Pods and<br/>manages their desired state"]
        I["<b>9. Operate and maintain</b><br/>Monitor, scale, patch,<br/>back up, and upgrade the cluster"]
        H --> I
    end

    P1 --> P2 --> P3
```

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

```mermaid
flowchart TB
    subgraph A["Option A: Self-managed Kubernetes"]
        direction LR
        AT["<b>Your team must manage</b>"]
        A1["EC2 instances for<br/>control-plane nodes"]
        A2["EC2 instances for<br/>worker nodes"]
        A3["Kubernetes installation<br/>and upgrades"]
        A4["Load balancers<br/>and storage"]
        A5["Cluster security<br/>and maintenance"]
        AT --> A1 --> A2 --> A3 --> A4 --> A5
    end

    subgraph B["Option B: Amazon EKS"]
        direction LR
        BT["<b>AWS manages the<br/>Kubernetes control plane</b>"]
        B1["API server"]
        B2["Control-plane<br/>availability"]
        B3["Control-plane<br/>infrastructure"]
        BY["<b>Your team still manages</b><br/>Worker capacity, applications,<br/>access policies, and<br/>workload configuration"]
        BT --> B1 --> B2 --> B3 --> BY
    end

    A ~~~ B
```

<img src="./imgs/AWS Kubernetes_ Self-Managed vs. EKS.png" width="100%" />

<img src="./imgs/self-managed vs. managed Kubernetes.png" width="100%" />

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

```mermaid
flowchart LR
    T["<b>Terraform</b><br/>Infrastructure provisioning<br/>EC2 instances, networks, IAM permissions,<br/>EKS clusters, load balancers, storage as code"]
    E["<b>Amazon EKS</b><br/>Managed Kubernetes<br/>AWS manages the control plane"]
    H["<b>Helm / Kubernetes manifests</b><br/>Application deployment<br/>Deployments, Services, resource requests,<br/>limits, and scaling rules"]
    C["<b>CI/CD pipeline</b><br/>Automated delivery<br/>Build, test, publish image,<br/>deploy to Kubernetes"]
    T --> E --> H --> C
```

| Tool / approach | Role | What it does |
|---|---|---|
| <img src="https://images.openai.com/static-rsc-4/OucbJVc5Wo3qkMjQpVLN8cyoIzDg_fzgQhKKnyHAtxsnLxmFoh-07NJ7FNrSE8L-Gc7cqdWocCFyXEkOGNEPDbLJmNgfYnoCn2PO5n9Lc4bqmhw56ZfvqCZUFdGMTVHmUznMotvubtPIrJUJ7hZ1kBF5LIPiZ73Mifpnt24fObw?purpose=inline" width="75px" /> <br/> **Terraform** | Infrastructure provisioning | Define EC2 instances, networks, IAM permissions, EKS clusters, load balancers, and storage as code instead of creating them manually. |
| <img src="https://images.openai.com/static-rsc-4/Or04aWW_S6Y8QP12Tpysowjs5H9xNIfIoUsmXmvXwhfdlDyIWS0alY3VTsThAXaJg4qtUdzLyz94i6YfXPubs3qOLgJhm-TK30A0cOWV6iHv3QfWUkel7f0UY90cm-3f1HjL8goBOgC4_6of--688sUXF4gstLAhGxNnzVWd7Tk?purpose=inline" width="75px" /> <br/> **Amazon EKS** | Managed Kubernetes | AWS manages the Kubernetes control plane, reducing the operational work required to run a cluster. |
| <img src="https://images.openai.com/static-rsc-4/TiS5laVIQvXOAr0K_9Y0qJhrF0ca-SmLHDHWhHgMf9tMxs7ASPshNahLE-LIPqyOBgffGIhWZFXuNrJOhfrBwd3j_Zkaoj_E-xqWCN5QWFuOYfJqjZvAfxSXeCC4iNGR1acOJyts-vIskAbIapKq0U99MlcJsTNjL8E2fh0qe_g?purpose=inline" width="75px" /> <br/> **Helm / Kubernetes manifests** | Application deployment | Define Deployments, Services, resource requests, limits, and scaling rules declaratively. |
| <img src="https://images.openai.com/static-rsc-4/sePLPBbLKTTDogXXdhHYIZwXrS0oAzLVMDOla8Evt2VCbBeqb5TY_hC2VLa05QCUim_e1eZraJzxzXm_-MSaaPmnoc1u5RLtouaA96v3rvn_HE_XPMoS8KLyvdySVER7a1fpgCKSw0op0ShXc0Ve-udY8QxrSvIPPAh3-JXza2s?purpose=inline" width="75px" /> <br/> **CI/CD pipeline** | Automated delivery | Build and test the application, publish the container image, and deploy the updated version to Kubernetes. |

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
