###############################################################################
# PATH 2 — module call
#
# install_mode is ALWAYS "pip": the app is provisioned from PyPI on the first
# (NAT) apply and is not replaced when you flip go_private, so no vendored
# wheels are ever needed on this path. The only thing that changes between
# applies is the agent's egress path (internet -> endpoints) and the network
# plumbing in network.tf / endpoints.tf.
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

  # Internet egress rule on the agent SG only while NOT private. After go_private
  # the agent reaches the interface endpoints via the rule in endpoints.tf.
  agent_internet_egress = !var.go_private

  # Boot ordering: on the first apply the NAT route must exist before the app
  # boots so pip can reach PyPI.
  depends_on = [aws_route_table_association.private]
}
