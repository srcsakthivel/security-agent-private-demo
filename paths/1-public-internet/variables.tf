variable "region" {
  description = "AWS region. Must be a region where AWS Continuum / Security Agent pen testing is available."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
  default     = "continuum-pub-pentest"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. A 10.x range keeps the target resolvable to a private CIDR if you ever switch to Private VPC verification."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && startswith(var.vpc_cidr, "10.")
    error_message = "vpc_cidr must be a 10.x.x.x private range."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across (>=2 recommended)."
  type        = number
  default     = 2
}

variable "private_domain" {
  description = "Private hosted-zone apex. The app FQDN becomes app.<private_domain>."
  type        = string
  default     = "internal.pentest-demo.local"
}

variable "app_hostname" {
  description = "Left-most label of the app FQDN. Final FQDN = <app_hostname>.<private_domain>."
  type        = string
  default     = "app"
}

variable "db_password" {
  description = "Password for the demo RDS instance. REQUIRED — set in terraform.tfvars."
  type        = string
  sensitive   = true
}

variable "instance_type" {
  description = "App EC2 instance type."
  type        = string
  default     = "t3.small"
}
