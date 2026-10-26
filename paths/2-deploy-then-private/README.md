# Path 2 · Deploy, then go private (Medium)

Demonstrates the **transition**: deploy the target with internet egress, confirm the agent
can reach it, then re-apply to tear out the internet and prove the agent keeps working over
**PrivateLink**. This is the story for a customer who starts internet-exposed and wants to
see what "lock it down" actually looks like.

> ⚠️ Intentionally vulnerable. Isolated throwaway POC account only.

## The two-apply flow

Everything hinges on one variable, **`go_private`**:

```bash
cd paths/2-deploy-then-private
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — set db_password, leave go_private = false

terraform init
terraform apply                 # APPLY #1 — with NAT. App installs from PyPI.
# ... verify the app is healthy (see below) ...

# flip the switch:
terraform apply -var=go_private=true   # APPLY #2 — NAT/IGW gone, endpoints in.
# (or set go_private = true in terraform.tfvars and re-apply)
```

### Apply #1 — `go_private = false`
- IGW + NAT + public subnets created; private subnets default-route to NAT.
- App EC2 installs Flask/pymysql from PyPI.
- Agent egresses 443 → NAT → internet.
- Verify with **DNS/HTTP** (internet is up) or jump straight to Private VPC.

### Apply #2 — `go_private = true`
- **IGW, NAT, EIPs, public subnets, public route table are destroyed.**
- The private route tables lose their `0.0.0.0/0` → NAT route.
- **PrivateLink interface endpoints** (`securityagent`, `bedrock-runtime`, `logs`) + the
  **SSM** trio + an **S3 gateway** endpoint are created.
- The agent SG's internet-egress rule is replaced by a 443 rule to the endpoint SG.
- The app EC2 is **not** replaced (it was already provisioned on apply #1), so there are
  **no wheels to vendor on this path** — that's the whole reason it's simpler than Path 3.
- Re-verify the target with **Private VPC** verification.

Check which posture you're in anytime:

```bash
terraform output mode
# "public (NAT egress)"  or  "private (endpoints, no internet)"
```

## Verify the domain

- **After apply #1:** DNS-TXT / HTTP-route (internet available), or Private VPC.
- **After apply #2:** Private VPC. Enter `pentest_target_fqdn` **verbatim** — Private VPC
  verification is exact-match with no subdomain inheritance.

## Wire into Security Agent → Penetration test

| Wizard field | Use output |
|---|---|
| Target URL | `http://` + `pentest_target_fqdn` |
| VPC | `vpc_id` |
| Subnets | `agent_private_subnet_ids` |
| Security group | `agent_security_group_id` |
| Service role | `agent_space_service_role_arn` |

## Smoke-test from inside the VPC

```bash
aws ssm start-session --target $(terraform output -raw app_instance_id)
curl "http://localhost:5000/search?q=' OR '1'='1"
curl "http://localhost:5000/profile?id=2"
```

Session Manager keeps working after go-private because of the SSM interface endpoints.

## Gotchas

- **Run the agent pen-test on the posture you want to demo.** If you want the "private"
  story, do apply #2 *before* kicking off the agent run so its ENI uses the endpoints.
- **Don't skip verifying after the flip.** The FQDN resolves the same, but the agent's
  egress path changed — a bad endpoint set shows up as the agent authenticating then
  stalling.

## Teardown

```bash
terraform destroy
```
