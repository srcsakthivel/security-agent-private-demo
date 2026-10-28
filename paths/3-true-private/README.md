# Path 3 · True private from the start (Complex)

Proves **zero internet egress from the very first second**. There is no Internet Gateway
and no NAT Gateway at any point. The agent reaches its control plane
only over a PrivateLink interface endpoint, and the app installs its Python deps from
**wheels you vendor into S3** — because PyPI is unreachable. This is the strongest story
for an air-gapped / security-conscious customer, and it has the most moving parts.

> ⚠️ Intentionally vulnerable. Isolated throwaway POC account only.

## What this path builds

- VPC with **private subnets only** — no public subnets, no IGW, no NAT. The private route
  tables have **no default route**.
- **PrivateLink interface endpoints** (always on): `securityagent` (agent control plane)
  + `ssm`, `ssmmessages`, `ec2messages` (Session Manager). `bedrock-runtime` is not
  required. Set `enable_cloudwatch_logs_endpoint = true` to add a `logs` endpoint if you
  configure CloudWatch logging for the Agent Space.
- An **S3 gateway endpoint** so the app EC2 can dnf-install from the regional-S3 AL2023
  repos and pull the vendored wheels.
- The shared [`modules/pentest-target`](../../modules/pentest-target/) target with
  `install_mode = "wheels"` and `agent_internet_egress = false`.
- A private **wheels S3 bucket** (`wheels.tf`) that Terraform populates from `./wheels/`.

## Deploy (vendor wheels FIRST)

```bash
cd paths/3-true-private
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — set db_password

./vendor-wheels.sh          # needs internet ON YOUR MACHINE; the VPC never gets any
terraform init
terraform apply
```

`terraform apply` will **fail fast with a clear message** if you forget `vendor-wheels.sh`
— the `wheels_present_check` precondition refuses to boot an instance that would then fail
its offline `pip install`.

### Why wheels, and why the vendor step

With no NAT/IGW the instance cannot reach PyPI. `vendor-wheels.sh` downloads the Flask +
pymysql wheel set **targeted at the instance** (Python 3.9, `manylinux2014_x86_64`), not
your laptop — macOS/arm64 wheels wouldn't install on AL2023. Terraform uploads them under
`s3://<bucket>/wheels/`, and user-data pulls them over the S3 gateway endpoint with
`pip install --no-index --find-links`.

## Two gotchas baked into this path

1. **AL2023 dnf + IPv6 over the S3 gateway.** AL2023's dnf resolves the dual-stack S3
   hostname to IPv6-only, which the gateway endpoint's IPv4 prefix list can't route, so
   dnf hangs. User-data sets `ip_resolve=4` in `/etc/dnf/dnf.conf` *before* the first dnf
   call to force IPv4. (Already handled in the module's `user_data.sh.tftpl`.)
2. **Only the control-plane endpoint is needed for the agent.** Pen test runs completed
   with full coverage without a `bedrock-runtime` endpoint, so `endpoints.tf` creates
   `securityagent` for the agent, plus `logs` only when `enable_cloudwatch_logs_endpoint = true`.

## Verify the domain (Private VPC)

Use **Private VPC** verification. Enter `pentest_target_fqdn` **verbatim** — exact-match,
no subdomain inheritance. The FQDN resolves to the internal ALB via the Route 53 private
zone from inside the VPC only.

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

Session Manager works with no internet thanks to the SSM interface endpoints.

## Teardown

```bash
terraform destroy      # force_destroy on the wheels bucket lets it empty itself
```
