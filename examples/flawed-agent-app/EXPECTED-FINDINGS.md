# EXPECTED-FINDINGS.md — facilitator key

Every flaw planted in this example, with the severity a reviewer should
assign and the tool or skill expected to catch it. Use this to score
completeness of a review.

**Severity rubric** (same one used across this repo):

- **Critical** — direct exploit path reachable from the internet
- **High** — privilege escalation or exposure of credentials/data
- **Medium** — hardening gap (defense-in-depth, logging, transport)
- **Low** — hygiene

**Scoring:** 27 planted flaws — **7 Critical, 9 High, 9 Medium, 2 Low.**
Scanners may split one row into several hits or merge several rows into
one; score against the substance, not the row count. Rule IDs are
deliberately omitted: they vary by tool and version.

## Terraform

| # | File | Planted flaw | Why it's bad | Severity | Caught by |
|---|------|--------------|--------------|----------|-----------|
| 1 | `terraform/network.tf` | Firewall allows ingress TCP 22/3389 from `0.0.0.0/0` to the whole VPC | SSH/RDP exposed to the internet on every instance | Critical | checkov/trivy/tfsec-class scanner |
| 2 | `terraform/network.tf` | Subnet has no VPC flow logs and no Private Google Access | No network audit trail; instances need external IPs to reach Google APIs | Medium | checkov/trivy-class scanner |
| 3 | `terraform/cloudsql.tf` | Cloud SQL has a public IP with `authorized_networks` = `0.0.0.0/0` | Database port reachable from anywhere; brute-force/exploit path | Critical | checkov/trivy/tfsec-class scanner |
| 4 | `terraform/cloudsql.tf` | No SSL enforcement; backups disabled; `deletion_protection = false` | Credentials/data cross the internet unencrypted; no PITR; one `destroy` from data loss | Medium | checkov/trivy-class scanner |
| 5 | `terraform/cloudrun.tf` | `roles/run.invoker` granted to `allUsers` | Anyone on the internet can invoke the agent directly, bypassing the LB entirely | Critical | checkov/trivy-class scanner, terraform-least-privilege-review |
| 6 | `terraform/cloudrun.tf` | Service runs as the **default compute service account** | Default SA holds `roles/editor` on the project — compromise of the agent is project-wide compromise | High | terraform-least-privilege-review |
| 7 | `terraform/cloudrun.tf` | DB password passed as a plaintext env var, not Secret Manager | Secret visible in API responses, Terraform state, and to anyone with read access on the service | High | checkov/trivy-class scanner, security-review |
| 8 | `terraform/cloudrun.tf` | `ingress = "INGRESS_TRAFFIC_ALL"` | Service accepts direct internet traffic, so LB-level controls are bypassable | Medium | security-review skill (some scanners) |
| 9 | `terraform/lb.tf` | HTTP-only load balancer — target HTTP proxy, forwarding rule port 80, no HTTPS anywhere | All agent traffic (including credentials and customer data) in cleartext | High | security-review skill |
| 10 | `terraform/lb.tf` | Backend service has no Cloud Armor `security_policy` | No WAF, no rate limiting, no Layer-7 DDoS policy on a public endpoint | Medium | security-review skill |
| 11 | `terraform/storage.tf` | Bucket grants `roles/storage.objectViewer` to `allUsers` | Every export object is world-readable — public data exposure | Critical | checkov/trivy/tfsec-class scanner, terraform-least-privilege-review |
| 12 | `terraform/storage.tf` | No `uniform_bucket_level_access`, no `public_access_prevention` | Object ACLs can make individual objects public; no org-style guardrail against public grants | Medium | checkov/trivy-class scanner |
| 13 | `terraform/storage.tf` | `force_destroy = true`, no versioning | Bucket (and all exports) can be deleted non-empty; no recovery from overwrite/delete | Low | checkov/trivy-class scanner |
| 14 | `terraform/iam.tf` | `google_service_account_key` created for `agent-sa` | Long-lived exportable credential; key material lands in Terraform state | High | checkov/trivy-class scanner, terraform-least-privilege-review |
| 15 | `terraform/iam.tf` | `agent-sa` granted primitive `roles/editor` at project level | Broad read/write over the whole project; primitive role, no conditions | High | terraform-least-privilege-review (some scanners flag primitive roles) |
| 16 | `terraform/bastion.tf` | Bastion has an external IP (`access_config {}`) — reachable through the world-open admin firewall from row 1 | Public SSH target; chains with row 1 into a Critical path | High | checkov/trivy-class scanner, security-review |
| 17 | `terraform/bastion.tf` | Bastion uses the default compute SA with the full `cloud-platform` scope | Whoever lands on the bastion inherits project editor-equivalent API access | High | terraform-least-privilege-review |
| 18 | `terraform/bastion.tf` | `serial-port-enable = "true"`; no `shielded_instance_config` | Interactive serial console enabled; no Secure Boot/vTPM integrity | Medium | checkov/trivy-class scanner |
| 19 | `terraform/variables.tf`, `terraform.tfvars.example` | `db_password` has a weak plaintext default and is **not** marked `sensitive` | Password in state, plan output, and a committed tfvars example | High | security-review skill, secret scanners (trivy et al.) |
| 20 | `terraform/` (as a whole) | No audit log config, no log sinks, no org policies | Nothing records who did what; no guardrails above the project | Medium | security-review skill only — scanners won't flag what's absent |

## Application

| # | File | Planted flaw | Why it's bad | Severity | Caught by |
|---|------|--------------|--------------|----------|-----------|
| 21 | `app/main.py` | Notes lookup built with an f-string: `"... WHERE username = '{user}'"` | SQL injection straight from the request body | Critical | semgrep |
| 22 | `app/main.py` | "Calculator" agent tool runs `eval()` on user-controlled input | Remote code execution as the Cloud Run identity (the default compute SA — see row 6) | Critical | semgrep |
| 23 | `app/main.py` + `app/Dockerfile` | `/admin/run-shell` runs `subprocess.run(cmd, shell=True)` on user input, gated only by env `DEBUG` — and the image bakes in `ENV DEBUG=1` | Unauthenticated remote shell on a public service | Critical | semgrep (the skill/reviewer connects the DEBUG wiring) |
| 24 | `app/main.py` | `os.environ.get("DB_PASSWORD", "sup3rsecret-fallback")` | Hardcoded credential fallback in source | High | semgrep |
| 25 | `app/main.py` | CORS `allow_origins=["*"]`; exceptions returned as full tracebacks | Any site can call the API cross-origin; tracebacks leak internals to callers | Medium | semgrep, security-review |
| 26 | `app/Dockerfile` | No `USER` directive — container runs as root | Container escape / file-permission blast radius | Medium | trivy/checkov-class scanner (Dockerfile) |
| 27 | `app/requirements.txt` | Dependencies unpinned | Non-reproducible builds; silent uptake of vulnerable versions | Low | security-review, dependency scanning |

## Notes for facilitators

- A strong review also connects findings into **attack paths** (the
  threat-model exercise): e.g. `allUsers` invoker (5) → `eval()` RCE
  (22) → default compute SA (6) → `roles/editor` on the project; or
  world-open admin firewall (1) → bastion external IP (16) → default SA
  with `cloud-platform` scope (17).
- Scanners will additionally fire on adjacent resources (e.g. flag the
  firewall's open RDP as its own rule, or the missing SSL on Cloud SQL
  as several rules). That's expected — map them back to the rows above.
- If a participant finds a real issue **not** listed here, that's a win,
  not a scoring error.
