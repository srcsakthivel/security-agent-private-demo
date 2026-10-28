# AWS Continuum — Pen-Test Target (POC): pick your network path

This repo stands up an **intentionally-vulnerable** Flask app (internal ALB → EC2 → RDS)
as a target for AWS Continuum / Security Agent penetration testing, in one of **three
network postures**. The *target itself is identical* in all three — only the network
around it (internet egress, VPC endpoints, how Python deps are installed) changes.

> ⚠️ **Intentionally vulnerable.** Deploy only in an isolated POC account you intend to
> throw away. Never attach a public IP or a public ALB to the target. Destroy / nuke the
> account after the demo.

---

## Pick your path

| | Path | Internet egress | Domain verification | Extra setup | Complexity |
|---|---|---|---|---|---|
| 🟢 | **[1 · Public internet](paths/1-public-internet/)** | Yes (IGW + NAT), whole test | DNS-TXT / HTTP-route | none | **Simple** |
| 🟡 | **[2 · Deploy, then go private](paths/2-deploy-then-private/)** | Yes at first apply → removed on second | Private VPC (after flip) | two `terraform apply`s | **Medium** |
| 🔴 | **[3 · True private from the start](paths/3-true-private/)** | **None, ever** | Private VPC | vendor wheels first (`vendor-wheels.sh`) | **Complex** |

**How to choose:**

- **Just want to see the agent find vulns with the least friction?** → **Path 1.** Full
  internet, simplest verification, no prerequisites. One `terraform apply`.
- **Want to demonstrate the transition** from an internet-exposed deploy to a locked-down
  private VPC, and show the agent still works via PrivateLink? → **Path 2.** Deploy with
  NAT, confirm the app, then re-apply with `go_private = true` to tear out the internet
  and swap in VPC endpoints.
- **Need to prove zero internet egress from the very first second** (security-conscious
  customer, air-gapped posture)? → **Path 3.** No IGW/NAT ever; the agent reaches its
  control plane only over a PrivateLink interface endpoint, and the app installs
  Python deps from wheels you vendor into S3. The most moving parts, but the strongest story.

Each path is a **self-contained Terraform root module** with its own README, variables,
and state. They all call the shared module in [`modules/pentest-target/`](modules/pentest-target/).

---

## The one fact that surprises everyone

**The agent needs outbound to AWS even when the target is private.** The Security Agent
injects an ENI into your private subnets to reach the target over local VPC routing — but
that ENI also has to reach the Security Agent **control plane**. It has no public IP, so it can't use an Internet Gateway directly. Each path solves
the agent's own egress differently:

- **Path 1 & 2 (before go-private):** agent egresses 443 → **NAT Gateway** → internet.
- **Path 2 (after go-private) & Path 3:** agent egresses 443 → a **PrivateLink
  `securityagent` interface endpoint** inside the VPC. `bedrock-runtime` is not
  required; a `logs` endpoint is optional, for when you configure CloudWatch logging.

---

## Repo layout

```
security-agent-private/
├── README.md                       ← you are here (path selector)
├── modules/
│   └── pentest-target/             ← SHARED target: vuln Flask app, EC2+SSM, RDS,
│                                     internal ALB, IAM (agent ENI role + EC2 SSM role),
│                                     SGs, Route 53 private zone. No network inside.
├── paths/
│   ├── 1-public-internet/          ← VPC + public/private subnets + IGW + NAT; pip install
│   ├── 2-deploy-then-private/      ← same, plus go_private switch → endpoints, drop NAT
│   └── 3-true-private/             ← private subnets only; endpoints + S3 gateway; wheels
├── iam/
│   └── agent-space-eni-policy.json ← standalone copy of the ENI policy (reference)
└── demo/                           ← blog draft / transcript / architecture assets
```

---

## Common steps (all paths)

```bash
cd paths/<chosen-path>
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — set db_password (required)

terraform init
terraform apply          # path 3: run ./vendor-wheels.sh FIRST
```

Then read that path's `README.md` for its verification method and the exact outputs to
paste into the **AWS Security Agent → Penetration test** console wizard. The outputs you'll
use are the same four everywhere: `pentest_target_fqdn`, `vpc_id`,
`agent_private_subnet_ids`, `agent_security_group_id`, plus `agent_space_service_role_arn`
for the service role.

Smoke-test the app from inside the VPC (no SSH key, no bastion — Session Manager):

```bash
aws ssm start-session --target $(terraform output -raw app_instance_id)
# on the instance:
curl "http://localhost:5000/search?q=' OR '1'='1"
curl "http://localhost:5000/profile?id=2"
```

## Security notes (demo-only — not for production)

This repo is a **throwaway POC** that deploys an intentionally-vulnerable app. It makes
demo-grade trade-offs that are deliberately *not* production patterns:

- **RDS password** is passed as a Terraform variable and rendered into EC2 user-data and
  the systemd unit. For anything real, use **AWS Secrets Manager** (or SSM Parameter Store)
  with **RDS IAM authentication** instead of a static password.
- **Terraform state** contains the DB password and all resource IDs. State and
  `terraform.tfvars` are git-ignored; keep them out of version control and use a remote
  encrypted backend (e.g. S3 + DynamoDB lock) for shared work.
- **The target is intentionally vulnerable.** Deploy only in an isolated account you will
  destroy. Never attach a public IP or public ALB.

Before committing, run `terraform fmt -recursive` and `terraform validate` in each path.

## Teardown

```bash
cd paths/<chosen-path>
terraform destroy
```

(Or just nuke the isolated POC account.)
