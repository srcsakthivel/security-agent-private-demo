###############################################################################
# PATH 3 — module call
#
# install_mode = "wheels": the app EC2 installs Flask/pymysql from the vendored
# wheels in S3 (wheels.tf), pulled over the S3 gateway endpoint. There is no
# internet egress at any point, so agent_internet_egress = false — the agent
# reaches AWS services only through the interface endpoints (endpoints.tf).
###############################################################################

module "pentest_target" {
  source = "../../modules/pentest-target"

  name_prefix        = var.name_prefix
  region             = var.region
  vpc_id             = aws_vpc.main.id
  vpc_cidr           = var.vpc_cidr
  private_subnet_ids = aws_subnet.private[*].id
  private_domain     = var.private_domain
  app_hostname       = var.app_hostname
  db_password        = var.db_password
  instance_type      = var.instance_type

  install_mode          = "wheels"
  agent_internet_egress = false
  wheels_bucket         = aws_s3_bucket.wheels.id
  wheels_bucket_arn     = aws_s3_bucket.wheels.arn

  # The instance pulls wheels from S3 and dnf-installs over the S3 gateway at
  # boot, so the uploaded objects, the gateway endpoint, and the presence check
  # must all exist first.
  depends_on = [
    aws_s3_object.wheel,
    aws_vpc_endpoint.s3,
    terraform_data.wheels_present_check,
  ]
}
