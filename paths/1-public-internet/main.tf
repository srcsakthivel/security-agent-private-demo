###############################################################################
# PATH 1 — module call
#
# install_mode = "pip": the app EC2 installs Flask/pymysql straight from PyPI
# over the NAT. No vendored wheels, no VPC endpoints. The module creates the
# agent SG with a 443-to-internet egress rule (gated on pip mode).
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

  install_mode = "pip"

  # The private route tables (NAT default route) must exist before the instance
  # boots so pip can reach PyPI.
  depends_on = [aws_route_table_association.private]
}
