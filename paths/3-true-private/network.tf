###############################################################################
# PATH 3 — TRUE PRIVATE NETWORK (zero internet from the start)
#
# No Internet Gateway. No NAT Gateway. No public subnets. The VPC has only
# private subnets, and their route tables have NO default route — every path
# off-subnet is either a VPC interface/gateway endpoint (endpoints.tf) or the
# local VPC route to the target app. There is no moment at which this stack can
# reach the internet.
###############################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs                  = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  private_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # required so the private hosted zone + endpoint private DNS resolve
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name_prefix}-vpc" }
}

# --- Private subnets only (agent ENI + app tier) ---
resource "aws_subnet" "private" {
  count             = var.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags              = { Name = "${var.name_prefix}-private-${local.azs[count.index]}", Tier = "private-app-and-agent" }
}

# One private route table per AZ, with NO default route. The S3 gateway endpoint
# (endpoints.tf) attaches its prefix-list route here; everything else stays
# local to the VPC.
resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-rt-private-${local.azs[count.index]}" }
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
