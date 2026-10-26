output "mode" {
  description = "Current posture: 'public (NAT)' before go_private, 'private (endpoints)' after."
  value       = var.go_private ? "private (endpoints, no internet)" : "public (NAT egress)"
}

output "pentest_target_fqdn" {
  description = "FQDN of the target. Before go_private you can verify via DNS/HTTP; after, use Private VPC verification."
  value       = module.pentest_target.pentest_target_fqdn
}

output "internal_alb_dns_name" {
  description = "Raw internal ALB DNS name."
  value       = module.pentest_target.internal_alb_dns_name
}

output "vpc_id" {
  description = "VPC ID to select in the Security Agent pen-test VPC configuration."
  value       = aws_vpc.main.id
}

output "agent_private_subnet_ids" {
  description = "Private subnet IDs to hand to Security Agent (agent ENI lands here)."
  value       = aws_subnet.private[*].id
}

output "agent_security_group_id" {
  description = "Security group ID for the agent ENI."
  value       = module.pentest_target.agent_security_group_id
}

output "agent_space_service_role_arn" {
  description = "IAM role ARN to select as the pen-test service role in the Security Agent console."
  value       = module.pentest_target.agent_space_service_role_arn
}

output "app_instance_id" {
  description = "EC2 instance ID of the vulnerable app (reach via SSM Session Manager)."
  value       = module.pentest_target.app_instance_id
}

output "ssm_start_session_hint" {
  description = "Command to open a shell on the private app instance."
  value       = module.pentest_target.ssm_start_session_hint
}

output "private_hosted_zone_id" {
  description = "Route 53 private hosted zone ID."
  value       = module.pentest_target.private_hosted_zone_id
}
