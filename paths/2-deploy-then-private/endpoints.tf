###############################################################################
# PATH 2 — VPC ENDPOINTS (created on the SECOND apply, go_private = true)
#
# Once the NAT is gone the agent ENI can no longer reach its control plane,
# Bedrock, or CloudWatch over the internet. These interface endpoints carry that
# traffic inside the VPC. SSM endpoints keep Session Manager working, and an S3
# gateway endpoint keeps the private posture self-contained.
#
# All gated on var.go_private, so they do not exist on the first (NAT) apply.
###############################################################################

locals {
  continuum_services = {
    securityagent   = "com.amazonaws.${var.region}.securityagent"
    bedrock_runtime = "com.amazonaws.${var.region}.bedrock-runtime"
    logs            = "com.amazonaws.${var.region}.logs"
  }

  ssm_services = {
    ssm         = "com.amazonaws.${var.region}.ssm"
    ssmmessages = "com.amazonaws.${var.region}.ssmmessages"
    ec2messages = "com.amazonaws.${var.region}.ec2messages"
  }

  vpce_services = var.go_private ? merge(local.continuum_services, local.ssm_services) : {}
}

resource "aws_security_group" "vpce" {
  count       = var.go_private ? 1 : 0
  name        = "${var.name_prefix}-vpce-sg"
  description = "Allow HTTPS from the agent + app ENIs to interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS from agent SG (Continuum services)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [module.pentest_target.agent_security_group_id]
  }

  ingress {
    description     = "HTTPS from app SG (SSM Session Manager)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [module.pentest_target.app_security_group_id]
  }

  egress {
    description = "Return traffic within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${var.name_prefix}-vpce-sg" }
}

# When private, authorize the agent ENI to reach the endpoint SG on 443 (the
# module's internet-egress rule is off because agent_internet_egress=false).
resource "aws_vpc_security_group_egress_rule" "agent_to_vpce" {
  count = var.go_private ? 1 : 0

  security_group_id            = module.pentest_target.agent_security_group_id
  description                  = "Agent ENI to interface endpoints (443)"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.vpce[0].id
}

resource "aws_vpc_endpoint" "svc" {
  for_each            = local.vpce_services
  vpc_id              = aws_vpc.main.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpce[0].id]
  private_dns_enabled = true

  tags = { Name = "${var.name_prefix}-${each.key}-vpce" }
}

resource "aws_vpc_endpoint" "s3" {
  count             = var.go_private ? 1 : 0
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = { Name = "${var.name_prefix}-s3-gateway-vpce" }
}
