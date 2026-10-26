# Path 1 · Public internet (Simple)

The lowest-friction way to watch the Security Agent find vulnerabilities. Full internet
egress stays in place for the entire test, so you can verify the target domain with
**DNS-TXT or HTTP-route** instead of Private VPC, and the app installs its Python deps
straight from PyPI. **One `terraform apply`, no prerequisites.**

> ⚠️ Intentionally vulnerable. Isolated throwaway POC account only. The target is still
> internal (no public IP on the app/ALB) — "public" here means the VPC has internet
> *egress*, not that the target is exposed.

## What this path builds

- VPC with **public + private** subnets, an **Internet Gateway**, and **NAT Gateways**.
- The shared [`modules/pentest-target`](../../modules/pentest-target/) target: internal
  ALB → EC2 (vulnerable Flask app) → RDS, plus the agent/app security groups, IAM roles,
  and a Route 53 private hosted zone.
- `install_mode = "pip"` — the app pulls Flask/pymysql from PyPI over the NAT.
- No VPC endpoints, no vendored wheels.

### Why there's still a NAT

The agent ENI lands in the **private** subnets and has no public IP, so it can't use the
IGW directly. It egresses 443 → NAT → internet to reach its control plane, Bedrock, and
CloudWatch. The "simple" in this path is the **verification story**, not the dollar cost.

## Deploy

```bash
cd paths/1-public-internet
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — set db_password

terraform init
terraform apply
```

## Verify the domain (DNS / HTTP)

Because internet egress is available, use the simpler verification in the console wizard:

- **HTTP-route:** the console gives you a path/token to serve from the target; the agent
  fetches it over the ALB.
- **DNS-TXT:** add the TXT record the console shows to a zone you control.

(If you'd rather use Private VPC verification here too, you can — the Route 53 private zone
and `pentest_target_fqdn` output exist in every path.)

## Wire into Security Agent → Penetration test

| Wizard field | Use output |
|---|---|
| Target URL | `http://` + `pentest_target_fqdn` |
| VPC | `vpc_id` |
| Subnets | `agent_private_subnet_ids` |
| Security group | `agent_security_group_id` |
| Service role | `agent_space_service_role_arn` |

```bash
terraform output
```

## Smoke-test from inside the VPC

```bash
aws ssm start-session --target $(terraform output -raw app_instance_id)
curl "http://localhost:5000/search?q=' OR '1'='1"
curl "http://localhost:5000/profile?id=2"
```

## Teardown

```bash
terraform destroy
```
