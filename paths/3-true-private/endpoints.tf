###############################################################################
# PATH 3 — VPC ENDPOINTS (always on)
#
# With no NAT/IGW, the Security Agent ENI needs only its local route to the
# target: pen test runs completed with full coverage with no securityagent,
# bedrock-runtime or logs endpoint. A logs endpoint is optional
# (enable_cloudwatch_logs_endpoint).
#
# SSM endpoints (ssm/ssmmessages/ec2messages) keep Session Manager working with
# no internet. The S3 gateway endpoint lets the app EC2 (a) dnf-install from the
# regional-S3 AL2023 repos and (b) pull the vendored wheels (wheels.tf).
###############################################################################

locals {
  # The agent ENI needs no VPC endpoints: pen test runs completed with full
  # coverage with no securityagent, bedrock-runtime or logs endpoint. The logs
  # endpoint is optional: turn it on (enable_cloudwatch_logs_endpoint) if you
  # configure CloudWatch logging when you enable penetration testing.
  agent_services = var.enable_cloudwatch_logs_endpoint ? {
    logs = "com.amazonaws.${var.region}.logs"
  } : {}

  ssm_services = {
    ssm         = "com.amazonaws.${var.region}.ssm"
    ssmmessages = "com.amazonaws.${var.region}.ssmmessages"
    ec2messages = "com.amazonaws.${var.region}.ec2messages"
  }

  vpce_services = merge(local.agent_services, local.ssm_services)
}

resource "aws_security_group" "vpce" {
  name        = "${var.name_prefix}-vpce-sg"
  description = "Allow HTTPS from the agent + app ENIs to interface endpoints"
  vpc_id      = aws_vpc.main.id

  # Agent -> endpoints only when the optional logs endpoint exists.
  dynamic "ingress" {
    for_each = var.enable_cloudwatch_logs_endpoint ? [1] : []
    content {
      description     = "HTTPS from agent SG (optional CloudWatch Logs endpoint)"
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      security_groups = [module.pentest_target.agent_security_group_id]
    }
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

# Agent ENI -> endpoint SG on 443, only when the optional logs endpoint is
# enabled. (The module does NOT create an internet-egress rule here.)
resource "aws_vpc_security_group_egress_rule" "agent_to_vpce" {
  count = var.enable_cloudwatch_logs_endpoint ? 1 : 0

  security_group_id            = module.pentest_target.agent_security_group_id
  description                  = "Agent ENI to interface endpoints (443)"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.vpce.id
}

resource "aws_vpc_endpoint" "svc" {
  for_each            = local.vpce_services
  vpc_id              = aws_vpc.main.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "${var.name_prefix}-${each.key}-vpce" }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = { Name = "${var.name_prefix}-s3-gateway-vpce" }
}

