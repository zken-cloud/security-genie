---
name: security-review
description: Run a read-only security review of a Terraform codebase, architecture/design doc, app config, or live GCP project and produce severity-rated findings with a prioritized remediation plan. Use when the user asks for a "security review", "security audit", "review this for security issues", or "is this secure" against GCP infrastructure, Terraform, or a design.
---

# Security Review

## When to use

- Reviewing Terraform, app config, or an architecture/design doc for GCP security issues, before or after deployment.
- Auditing a live GCP project/folder/org for misconfigurations (read-only).
- Not for: full threat modelling (use `threat-model`) or IAM-only Terraform audits (use `terraform-least-privilege-review`) — those go deeper on one dimension.

## Inputs

Ask at most these, then proceed with stated assumptions:

1. Target: repo path / doc / config files, or a live GCP project/folder/org ID (and which gcloud profile)?
2. Context: internet-facing components, data sensitivity, compliance drivers (CIS, PCI, HIPAA)?
3. Depth: full checklist, or specific domains only?

Defaults if unanswered: everything in scope, full checklist, assume sensitive data and internet-facing where ambiguous — and say so in the output.

## Workflow

1. Identify target type (terraform | design doc | config | live) and exact scope. For live targets, confirm and record the account, project, and gcloud configuration per the AGENTS.md multi-account rules.
2. Gather evidence first, read-only:
   - Live: inventory via read-only gcloud MCP tools — IAM policy, service accounts and keys, firewall rules, subnets, instances, buckets, SQL instances, org policies, log sinks, enabled APIs. If MCP is unavailable, ask the user to run the gcloud commands below and paste output. If neither is possible, work from provided artifacts and state that assumption.
   - Files: read all in-scope files; grep for checklist patterns (`google_project_iam_member`, `0.0.0.0/0`, `google_service_account_key`, `serial-port-enable`, `authorized_networks`). For code and Terraform targets, run the `sast-scan` skill first as an automated breadth pass and treat its hits as candidates to verify — not as the review itself.
3. Sketch the asset map: public entry points, sensitive data stores, and which identities can reach them.
4. Walk every checklist domain below against the evidence.
5. Record each finding: severity (rubric below), evidence (`file:line` or resource ID), impact, remediation, reference.
6. Re-rate each finding against the rubric; drop or downgrade what you cannot evidence, and label assumptions.
7. Produce the summary, findings table, and prioritized remediation plan in the output format.

Read-only gcloud fallback commands for live reviews (MCP unavailable):

```bash
gcloud projects get-iam-policy PROJECT_ID --format=json
gcloud iam service-accounts list --project PROJECT_ID --format=json
gcloud compute firewall-rules list --project PROJECT_ID --filter="direction=INGRESS AND disabled=false" --format=json
gcloud compute instances list --project PROJECT_ID --format=json
gcloud storage buckets list --project PROJECT_ID --format=json
gcloud sql instances list --project PROJECT_ID --format=json
gcloud org-policies list --project PROJECT_ID --format=json
gcloud logging sinks list --project PROJECT_ID --format=json
gcloud services list --enabled --project PROJECT_ID --filter="name:securitycenter.googleapis.com OR name:binaryauthorization.googleapis.com"
```

## Checklist

### IAM and access

- Primitive roles (`roles/owner`, `roles/editor`, `roles/viewer`) bound at project level or above, in live policy or `google_project_iam_*` resources.
- User-managed SA keys: `google_service_account_key` resources, key JSON files, existing keys on SAs; should be blocked by `constraints/iam.disableServiceAccountKeyCreation` and `constraints/iam.disableServiceAccountKeyUpload`.
- Default Compute Engine SA (`PROJECT_NUMBER-compute@developer.gserviceaccount.com`) or App Engine SA (`PROJECT_ID@appspot.gserviceaccount.com`) used as a workload identity — both carry Editor-level access by default.
- `allUsers` / `allAuthenticatedUsers` in any IAM policy.
- Grants missing IAM Conditions where access should be time-bound or resource-scoped; `roles/iam.serviceAccountUser` or `roles/iam.serviceAccountTokenCreator` granted at project level.
- External/on-prem workloads using SA keys instead of Workload Identity Federation.

### Network and perimeter

- Ingress `0.0.0.0/0` to sensitive ports (22, 3389, 3306, 5432) or wide port ranges; the `default` network and its `default-allow-*` rules still present (`constraints/compute.skipDefaultNetworkCreation` unset).
- VMs with external IPs not fronted by a load balancer (`constraints/compute.vmExternalIpAccess` unset).
- Serial console access enabled (`serial-port-enable=true` in instance/project metadata; `constraints/compute.disableSerialPortAccess` unset).
- No VPC Service Controls perimeter around projects holding sensitive data (Cloud Storage, BigQuery).
- VPC Flow Logs disabled on subnets; Private Google Access off where VMs reach Google APIs.
- Public endpoints (GCLB, GKE Ingress, Cloud Run) without a Cloud Armor security policy.

### Data protection

- Public GCS buckets; uniform bucket-level access disabled; `constraints/storage.uniformBucketLevelAccess` and `constraints/storage.publicAccessPrevention` unset.
- Cloud SQL with public IP or authorized networks `0.0.0.0/0`; `require_ssl`/`ssl_mode` not enforced; `constraints/sql.restrictPublicIp` unset.
- Missing CMEK via Cloud KMS where data classification demands it (buckets, disks, BigQuery, Cloud SQL) — note when Google-managed encryption is a documented, accepted decision instead.
- No deletion protection: `deletion_protection` off on Cloud SQL, backups/PITR (`point_in_time_recovery_enabled`) disabled.

### Secrets

- Secrets in env vars, tfvars, plain files, container images, or Terraform state (`*.tfstate` committed or on a world-readable backend).
- SA keys or other credentials committed to the repo — check git history, not just HEAD.
- Secret Manager absent, or `roles/secretmanager.secretAccessor` granted at project level instead of per-secret.
- No rotation/versioning practice for secrets.

### Logging and detection

- Data Access audit logs off (default is off except BigQuery) on sensitive services: Cloud Storage, Cloud SQL, Secret Manager, Cloud KMS.
- No log sinks/exports to a central log bucket or project; aggregated sink missing at folder/org level; sink filters excluding IAM or org-policy events.
- Security Command Center not enabled at org level (`securitycenter.googleapis.com`).
- No alerting on IAM policy changes, org policy changes, or firewall changes.
- Log buckets without a retention policy or bucket lock where compliance requires.

### Supply chain

- No Binary Authorization policy or enforcement on GKE/Cloud Run (`binaryauthorization.googleapis.com` disabled).
- Unpinned or `:latest` container images; public-registry images without provenance or attestations.
- Cloud Build default SA (`PROJECT_NUMBER@cloudbuild.gserviceaccount.com`) used with broad permissions; triggers building unreviewed code (forks/PRs) with write-capable credentials.
- No Artifact Registry vulnerability scanning; dependencies unpinned (no lockfiles).

### Org posture

- Org-policy starter set missing — spot-check `constraints/iam.allowedPolicyMemberDomains`, `constraints/compute.requireOsLogin`, `constraints/sql.restrictPublicIp`, `constraints/gcp.resourceLocations`, plus the constraints named above.
- Flat resource hierarchy: everything in one project, no folder-level separation of prod/non-prod or of network/security vs. app teams.
- IAM granted to individual users instead of Cloud Identity groups.

## Severity rubric

- Critical: public exploit path to data or credentials (public bucket with sensitive data, SA key in repo, `0.0.0.0/0` to an exposed database).
- High: realistic privilege escalation or exposure (default SA as workload identity, SA key creation allowed, Secret Accessor at project level).
- Medium: hardening gap an attacker would chain (flow logs off, no CMEK, no Cloud Armor, audit logs off).
- Low: hygiene (missing labels, minor retention gaps, unpinned but internal images).

## Output format

```markdown
# Security Review: <target name>
- Scope: <what was reviewed> | Target type: <terraform|design doc|config|live>
- Identity: <gcloud account/project for live reviews, or "from artifacts only — assumptions stated">
- Date: <YYYY-MM-DD>

## Summary
| Critical | High | Medium | Low |
|---|---|---|---|
| <n> | <n> | <n> | <n> |

## Findings
| ID | Severity | Finding | Evidence | Impact | Remediation | Reference |
|---|---|---|---|---|---|---|
| SR-01 | Critical | <one-line title> | <file:line or resource ID> | <attacker outcome> | <specific fix: role, constraint, config> | <CIS GCP Foundation Benchmark x.y or Google Cloud best practice> |

## Prioritized remediation plan
1. <Critical/High fixes first — concrete action per item>
2. <Medium batch>
3. <Low / hygiene>
```

## Guardrails

- Read-only, always: no mutating gcloud commands, no `terraform apply`, no fixing findings unless the user explicitly asks (AGENTS.md global rules apply in full).
- Every finding must cite evidence — `file:line` or a live resource ID. No evidence, no finding; mark unproven suspicions as assumptions.
- Never print secret values, key material, or secret-bearing tfstate contents; reference secrets by resource path only.
- Exact names only: uncertain role, constraint, or product names get `(VERIFY)`; never invent plausible-looking ones.
- For live reviews, state the account and project the findings are based on, and re-confirm after any profile switch before trusting data.
- Stay in scope; record serious out-of-scope observations as one-line notes instead of expanding the review.
- Prefer GCP-native remediations (granular predefined roles, IAM Conditions, org policy constraints, VPC Service Controls, CMEK, Workload Identity Federation) over third-party tooling.
