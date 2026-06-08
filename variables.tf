variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  default     = "emart-eks-cluster"
}

variable "instance_type" {
  description = "EC2 instance type for worker nodes"
  default     = "t3.large"
}

variable "desired_nodes" {
  description = "Desired number of worker nodes"
  default     = 1
}

variable "min_nodes" {
  description = "Minimum number of worker nodes"
  default     = 1
}

variable "max_nodes" {
  description = "Maximum number of worker nodes"
  default     = 2
}
