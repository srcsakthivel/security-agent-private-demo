###############################################################################
# PATH 2 — DEPLOY-THEN-PRIVATE NETWORK
#
# Everything that provides internet egress is gated on !var.go_private, so the
# SECOND apply (go_private = true) tears it down:
#   - IGW, NAT Gateways, EIPs, public subnets, public route table  -> destroyed
#   - the private subnets' 0.0.0.0/0 -> NAT route                  -> removed
# After that the private subnets have no default route; the agent reaches AWS
# services over the interface endpoints in endpoints.tf (also gated on
# go_private), and the target app is reached over local VPC routing.
###############################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs                  = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  public_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name_prefix}-vpc" }
}

# --- Internet egress plumbing (removed on the second apply) ---
resource "aws_internet_gateway" "igw" {
  count  = var.go_private ? 0 : 1
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  count                   = var.go_private ? 0 : var.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name_prefix}-public-${local.azs[count.index]}", Tier = "public-nat" }
}

resource "aws_eip" "nat" {
  count  = var.go_private ? 0 : var.az_count
  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-nat-eip-${local.azs[count.index]}" }
}

resource "aws_nat_gateway" "nat" {
  count         = var.go_private ? 0 : var.az_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.name_prefix}-nat-${local.azs[count.index]}" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  count  = var.go_private ? 0 : 1
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw[0].id
  }
  tags = { Name = "${var.name_prefix}-rt-public" }
}

resource "aws_route_table_association" "public" {
  count          = var.go_private ? 0 : var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# --- Private subnets (persist across both applies) ---
resource "aws_subnet" "private" {
  count             = var.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags              = { Name = "${var.name_prefix}-private-${local.azs[count.index]}", Tier = "private-app-and-agent" }
}

# One private route table per AZ. The default route to NAT is present only
# before go_private; after, there is no default route (endpoints carry agent
# traffic, local route carries app traffic).
resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.go_private ? [] : [1]
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.nat[count.index].id
    }
  }

  tags = { Name = "${var.name_prefix}-rt-private-${local.azs[count.index]}" }
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
