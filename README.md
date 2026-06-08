# emart-eks-terraform

Terraform configuration to provision a minimal AWS EKS cluster for the emart application.

---

## Repository Structure

```
emart-eks-terraform/
├── main.tf         # All AWS resources
├── variables.tf    # Configurable input parameters
├── outputs.tf      # Values printed after apply
├── backend.tf      # Remote state configuration
└── README.md
```

---

## File Breakdown

### `main.tf`

The core infrastructure file. Contains every AWS resource in a flat structure (no modules).

**Providers**
- `aws` (~> 5.0) — creates all AWS resources
- `tls` (~> 4.0) — reads the OIDC certificate thumbprint from the EKS issuer URL

**Networking**

| Resource | What it does |
|---|---|
| `aws_vpc.main` | Creates a VPC with CIDR `10.0.0.0/16`, DNS enabled |
| `aws_internet_gateway.main` | Attaches an internet gateway so public subnets can reach the internet |
| `aws_subnet.public` (×2) | Two public subnets in different AZs (`10.0.0.0/24`, `10.0.1.0/24`). Tagged for EKS load balancer discovery |
| `aws_route_table.public` | Route table with a default route (`0.0.0.0/0`) to the internet gateway |
| `aws_route_table_association.public` | Associates both public subnets with the route table |

No private subnets or NAT gateways — cost-optimised for non-production use.

**EKS Cluster IAM**

| Resource | What it does |
|---|---|
| `aws_iam_role.cluster` | IAM role the EKS control plane assumes (`eks.amazonaws.com`) |
| `aws_iam_role_policy_attachment.cluster_policy` | Attaches `AmazonEKSClusterPolicy` — minimum permissions for the control plane |

**EKS Cluster**

| Resource | What it does |
|---|---|
| `aws_eks_cluster.main` | The EKS control plane (version 1.32). Endpoint is public so `kubectl` works from your machine |

**Node Group IAM**

| Resource | What it does |
|---|---|
| `aws_iam_role.nodes` | IAM role EC2 worker nodes assume (`ec2.amazonaws.com`) |
| `aws_iam_role_policy_attachment.node_policy` | `AmazonEKSWorkerNodePolicy` — lets nodes register with the cluster |
| `aws_iam_role_policy_attachment.cni_policy` | `AmazonEKS_CNI_Policy` — lets the VPC CNI plugin manage pod networking |
| `aws_iam_role_policy_attachment.ecr_policy` | `AmazonEC2ContainerRegistryReadOnly` — lets nodes pull images from ECR |

**Node Group**

| Resource | What it does |
|---|---|
| `aws_eks_node_group.main` | Managed node group of `t3.large` EC2 instances in the public subnets. Desired: 1, Min: 1, Max: 2 |

**OIDC Provider (for IRSA)**

| Resource | What it does |
|---|---|
| `data.tls_certificate.eks` | Fetches the TLS certificate from the EKS OIDC issuer URL to extract the thumbprint |
| `aws_iam_openid_connect_provider.eks` | Registers the EKS OIDC provider with IAM — required for pods to assume IAM roles |

IRSA (IAM Roles for Service Accounts) lets pods authenticate to AWS services without long-lived credentials on the node.

**EBS CSI Driver**

| Resource | What it does |
|---|---|
| `data.aws_iam_policy_document.ebs_csi_assume` | Trust policy scoped to the `ebs-csi-controller-sa` service account in `kube-system` |
| `aws_iam_role.ebs_csi` | `AmazonEKS_EBS_CSI_DriverRole` — the IAM role the EBS CSI controller pod assumes via IRSA |
| `aws_iam_role_policy_attachment.ebs_csi` | Attaches `AmazonEBSCSIDriverPolicy` — allows creating/attaching/detaching EBS volumes |
| `aws_eks_addon.ebs_csi` | Installs the `aws-ebs-csi-driver` EKS managed addon. AWS creates the service account automatically |

The EBS CSI driver is required to use `PersistentVolumeClaims` backed by EBS in Kubernetes.

---

### `variables.tf`

| Variable | Default | Description |
|---|---|---|
| `region` | `us-east-1` | AWS region to deploy into |
| `cluster_name` | `emart-eks-cluster` | Name prefix used on all resources |
| `instance_type` | `t3.large` | EC2 instance type for worker nodes |
| `desired_nodes` | `1` | Number of nodes to run normally |
| `min_nodes` | `1` | Minimum nodes (auto-scaling lower bound) |
| `max_nodes` | `2` | Maximum nodes (auto-scaling upper bound) |

Override any variable at apply time:
```bash
terraform apply -var="instance_type=t3.medium" -var="desired_nodes=2"
```

---

### `outputs.tf`

Values printed to the terminal after `terraform apply`:

| Output | Description |
|---|---|
| `cluster_name` | Name of the EKS cluster |
| `cluster_endpoint` | HTTPS endpoint of the Kubernetes API server |
| `cluster_arn` | Full ARN of the EKS cluster |

---

### `backend.tf`

Stores Terraform state in an S3 bucket so the state is shared and not lost if you delete your local directory.

> `backend.tf` is **gitignored** — you must create it manually before running `terraform init`.

Create the file with your own S3 bucket:

```hcl
terraform {
  backend "s3" {
    bucket = "<your-s3-bucket-name>"
    key    = "emart-eks/terraform.tfstate"
    region = "us-east-1"
  }
}
```

Create the S3 bucket if you don't have one:

```bash
aws s3 mb s3://<your-s3-bucket-name> --region us-east-1
```

> No DynamoDB state locking is used (cost optimisation for solo/dev use). If multiple people run `terraform apply` simultaneously it could corrupt state — add a `dynamodb_table` entry if working in a team.

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.3.0
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with credentials
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- An S3 bucket for remote state (see `backend.tf`)

Configure AWS credentials:
```bash
aws configure
```

---

## Usage

```bash
# 1. Initialise providers and backend
terraform init

# 2. Preview changes
terraform plan

# 3. Create the cluster (~10-15 minutes)
terraform apply

# 4. Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name emart-eks-cluster

# 5. Verify nodes are ready
kubectl get nodes
```

To destroy all resources and stop billing:
```bash
terraform destroy
```

---

## Estimated Cost (us-east-1)

| Resource | Rate |
|---|---|
| EKS control plane | $0.10 / hr |
| t3.large node (×1) | $0.0832 / hr |
| Internet Gateway | Free |
| **Total** | **~$0.18 / hr (~$134 / month)** |

> Destroy the cluster when not in use — the control plane charges even when idle.

---

## Security Notes

- Worker nodes are in **public subnets** — acceptable for dev/staging, not recommended for production
- The Kubernetes API endpoint is **publicly accessible** — restrict `public_access_cidrs` in `vpc_config` for production
- No credentials or account IDs are stored in this repository
- Add `terraform.tfvars`, `*.tfstate`, and `.terraform/` to `.gitignore`

---

## Related Repositories

| Repo | Purpose |
|---|---|
| `emart-eks-terraform` | This repo — AWS infrastructure |
| `emart-k8s-config` | Kubernetes manifests (Deployments, Services, Ingress) |
| `emartapp` | Application source code and CI/CD workflows |
