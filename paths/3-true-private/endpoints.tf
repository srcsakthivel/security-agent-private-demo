###############################################################################
# PATH 3 — VPC ENDPOINTS (always on; the agent's ONLY path to AWS services)
#
# With no NAT/IGW, the Security Agent ENI reaches its three required services
# exclusively over PrivateLink:
#   - securityagent   (control plane)
#   - bedrock-runtime (model inference)
#   - logs            (CloudWatch Logs)
# It is all-or-nothing: a control-plane-only endpoint makes the agent
# authenticate but then stall at reasoning/logging.
#
# SSM endpoints (ssm/ssmmessages/ec2messages) keep Session Manager working with
# no internet. The S3 gateway endpoint lets the app EC2 (a) dnf-install from the
# regional-S3 AL2023 repos and (b) pull the vendored wheels (wheels.tf).
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

  vpce_services = merge(local.continuum_services, local.ssm_services)
}

resource "aws_security_group" "vpce" {
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

# Authorize the agent ENI to reach the endpoint SG on 443. (The module does NOT
# create an internet-egress rule here: agent_internet_egress = false.)
resource "aws_vpc_security_group_egress_rule" "agent_to_vpce" {
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

# NOTE: Bedrock cross-region inference may route to sibling regions. If your
# Agent Space uses cross-region inference, add bedrock-runtime endpoints in the
# inference region(s) too. For a single-region POC this set is sufficient.
