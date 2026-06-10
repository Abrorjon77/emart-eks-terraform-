# emart-eks-terraform

Terraform configuration to provision an AWS EKS cluster for the emart application.

---

## Prerequisites

Make sure you have these installed and configured before starting:

| Tool | Version | Install |
|---|---|---|
| Terraform | >= 1.3.0 | https://developer.hashicorp.com/terraform/downloads |
| AWS CLI | v2 | https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html |
| kubectl | any recent | https://kubernetes.io/docs/tasks/tools/ |

Configure your AWS credentials:

```bash
aws configure
# Enter: Access Key ID, Secret Access Key, region (us-east-1), output format (json)
```

---

## Step 1 — Create the S3 bucket for Terraform state

The state file is stored remotely in S3. Create the bucket once before anything else:

```bash
aws s3 mb s3://<your-bucket-name> --region us-east-1
```

---

## Step 2 — Create `backend.tf`

This file is gitignored — you must create it manually. Create `backend.tf` in the root of the repo:

```hcl
terraform {
  backend "s3" {
    bucket = "<your-bucket-name>"
    key    = "emart-eks/terraform.tfstate"
    region = "us-east-1"
  }
}
```

---

## Step 3 — (Optional) Override default variables

Default values are already set and will work out of the box:

| Variable | Default | Description |
|---|---|---|
| `region` | `us-east-1` | AWS region |
| `cluster_name` | `emart-eks-cluster` | EKS cluster name |
| `instance_type` | `t3.large` | Worker node instance type |
| `desired_nodes` | `1` | Number of nodes to run |
| `min_nodes` | `1` | Minimum nodes |
| `max_nodes` | `2` | Maximum nodes |

To override, create a `terraform.tfvars` file (also gitignored):

```hcl
cluster_name  = "my-cluster"
instance_type = "t3.medium"
desired_nodes = 2
```

Or pass values inline at apply time:

```bash
terraform apply -var="instance_type=t3.medium"
```

---

## Step 4 — Initialise Terraform

Downloads providers and connects to the S3 backend:

```bash
terraform init
```

---

## Step 5 — Preview the changes

Shows everything that will be created before touching AWS:

```bash
terraform plan
```

---

## Step 6 — Create the cluster

```bash
terraform apply
```

Type `yes` when prompted. Takes **10–15 minutes** to complete.

When done, Terraform prints:

```
cluster_name     = "emart-eks-cluster"
cluster_endpoint = "https://xxxx.gr7.us-east-1.eks.amazonaws.com"
cluster_arn      = "arn:aws:eks:us-east-1:..."
```

---

## Step 7 — Connect kubectl to the cluster

```bash
aws eks update-kubeconfig --region us-east-1 --name emart-eks-cluster
```

Verify the nodes are ready:

```bash
kubectl get nodes
```

Expected output:

```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-x-x.ec2.internal      Ready    <none>   2m    v1.32.x
```

---

## What gets created

- VPC (`10.0.0.0/16`) with 2 public subnets across 2 availability zones
- Internet Gateway and route tables
- EKS control plane (Kubernetes 1.32)
- Managed node group — 1× `t3.large` worker node (scales to 2)
- IAM roles for the cluster and nodes
- OIDC provider (enables pods to assume IAM roles)
- EBS CSI Driver addon (enables Kubernetes persistent volumes on EBS)

---

## Destroy the cluster

Tears down all resources and stops all billing:

```bash
terraform destroy
```

> The EKS control plane costs **$0.10/hr** even when idle. Destroy when not in use.

---

## Estimated cost

| Resource | Rate |
|---|---|
| EKS control plane | $0.10 / hr |
| t3.large node (×1) | $0.0832 / hr |
| **Total** | **~$0.18 / hr (~$134 / month)** |

---

## Related repositories

| Repo | Purpose |
|---|---|
| `emart-eks-terraform` | This repo — AWS infrastructure |
| `emart-k8s-config` | Kubernetes manifests (Deployments, Services, Ingress) |
| `emartapp` | Application source code and GitHub Actions CI/CD |
