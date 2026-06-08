terraform {
  backend "s3" {
    bucket = "vprofile-terraform-state-1"
    key    = "emart-eks/terraform.tfstate"
    region = "us-east-1"
  }
}
