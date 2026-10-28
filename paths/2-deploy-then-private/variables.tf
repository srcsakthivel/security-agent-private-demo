variable "region" {
  description = "AWS region. Must be a region where AWS Continuum / Security Agent pen testing is available."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
  default     = "continuum-d2p-pentest"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be a 10.x private range so Private VPC verification passes after going private."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && startswith(var.vpc_cidr, "10.")
    error_message = "vpc_cidr must be a 10.x.x.x private range for Private VPC verification to succeed."
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

###############################################################################
# THE PATH-2 SWITCH
###############################################################################
variable "go_private" {
  description = <<-EOT
    The two-apply switch that defines this path.

      false (FIRST apply): IGW + NAT present, private subnets default-route to
        NAT. The app installs Flask/pymysql from PyPI, and you can verify the
        domain with DNS/HTTP while the internet path is still open. Confirm the
        app is healthy here.

      true  (SECOND apply): the NAT default route is removed from the private
        route tables and a PrivateLink securityagent interface endpoint
        + SSM endpoints + an S3 gateway endpoint are
        created, so the agent and Session Manager keep working with NO internet.
        The IGW/NAT/public subnets are destroyed. Re-verify the target with
        Private VPC verification.

    The app EC2 is NOT replaced between applies (it was already provisioned on
    apply #1), so no wheel vendoring is ever needed on this path.
  EOT
  type        = bool
  default     = false
}

###############################################################################
# OPTIONAL CLOUDWATCH LOGS ENDPOINT
###############################################################################
variable "enable_cloudwatch_logs_endpoint" {
  description = <<-EOT
    Create a com.amazonaws.<region>.logs interface endpoint.
    Not required for a penetration test run. Set to true if you configure
    CloudWatch logging for the Agent Space when you enable penetration testing.
  EOT
  type        = bool
  default     = false
}