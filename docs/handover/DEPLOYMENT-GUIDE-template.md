# Deployment Guide — `<workload name>`

> Template. Fill every `<placeholder>`; delete any section that genuinely does
> not apply and say why in *Assumptions*. An unedited placeholder in a customer
> handover is worse than a missing section.
>
> **This guide must have been executed end-to-end by its author** in a
> smoke-test project (see [`../smoke-test-runbook.md`](../smoke-test-runbook.md))
> before it ships. Record the run in *Validation*.

| | |
|---|---|
| Workload | `<name>` |
| Version / commit | `<git sha>` |
| Author | `<name, role>` |
| Date | `<YYYY-MM-DD>` |
| Validated in | `<smoke-test project ID>` on `<date>` |
| Target environments | `<dev / staging / prod project IDs>` |

## 1. What you are deploying

`<Two or three sentences: the workload, the GCP services it uses, and the trust
boundary it sits on. Link the architecture doc.>`

Resources created (from `terraform plan`):

| Resource type | Name | Notes |
|---|---|---|

Estimated steady-state cost: `<$/month, and what drives it>`.

## 2. Prerequisites

**Access.** The deploying identity needs:

| Role | Scope | Why |
|---|---|---|
| `<roles/...>` | `<project/folder/org>` | `<the specific resources it creates>` |

Prefer a dedicated deployment service account with Workload Identity Federation
from CI. If a human runs this, say which human role is sufficient — do not
default to `roles/owner`, and flag it as a finding if the module genuinely needs
it.

**Tooling.**

```bash
terraform -version    # >= <version>, pinned in versions.tf
gcloud --version      # >= <version>
```

**Org policy.** This module requires the following constraints to permit its
resources. Check *before* you plan — these are the most common apply failures:

| Constraint | Required state | If enforced differently |
|---|---|---|
| `constraints/compute.vmExternalIpAccess` | `<...>` | `<workaround>` |
| `constraints/gcp.resourceLocations` | must allow `<region>` | `<workaround>` |
| `<others observed during smoke test>` | | |

**APIs.**

```bash
gcloud services enable <...> --project="$PROJECT_ID"
```

## 3. Inputs

| Variable | Type | Required | Default | Notes |
|---|---|---|---|---|

Secrets: `<how each secret is supplied — Secret Manager resource path, never a
tfvars value. State explicitly that no secret is passed as a Terraform
variable, or explain why one must be.>`

## 4. Deploy

```bash
# 1. State backend (once per environment)
<...>

# 2. Init and review
terraform init
terraform validate
terraform plan -out=tfplan

# 3. Review the plan before applying — required, not optional
terraform show -json tfplan > tfplan.json

# 4. Apply
terraform apply tfplan
```

Order-of-operations notes (things that must exist first, waits, eventual
consistency): `<...>`

Expected duration: `<n> minutes`. `<Name the slow resources — Cloud SQL, managed
certificates, and VPC peering dominate.>`

## 5. Post-deploy verification

Run every check. Paste real output into *Validation*.

| # | Check | Command | Expected |
|---|---|---|---|
| 1 | No public invoker on Cloud Run | `gcloud run services get-iam-policy ...` | no `allUsers` |
| 2 | Database has no public IP | `gcloud sql instances describe ...` | `ipv4Enabled: False` |
| 3 | No user-managed SA keys | `gcloud iam service-accounts keys list --managed-by=user ...` | empty |
| 4 | No primitive roles at project scope | `gcloud projects get-iam-policy ...` | none |
| 5 | `<control specific to this workload>` | | |

## 6. Rollback

```bash
<...>
```

State what rollback does **not** recover: `<data written since deploy, deleted
resources, rotated secrets, DNS TTL>`. If rollback is destructive, say so in
bold and give the backup-restore path instead.

## 7. Operating notes

- **Secret rotation:** `<which secrets, what cadence, what breaks during rotation>`
- **Certificate/domain:** `<managed cert provisioning time, DNS records required>`
- **Scaling limits:** `<min/max instances, connection limits, quota to watch>`
- **Logs and alerts:** `<where logs land, retention, which alert policies exist>`
- **Backups:** `<what is backed up, retention, and when a restore was last tested>`

## 8. Known limitations and accepted risks

| # | Limitation / risk | Severity | Owner | Review date |
|---|---|---|---|---|

Cross-reference the security decision log. Anything the customer must accept
belongs here in plain language — not buried in a Terraform comment.

## 9. Validation

| Check | Result | Evidence | Date |
|---|---|---|---|

`<Redact project numbers, IPs, and any identifier the customer would not want in
a shared doc. Never paste secret values, even redacted-looking ones.>`

## 10. Assumptions

`<Everything you could not verify: org policy state in the target env, quota,
network topology you were told about but did not see, sections deleted from this
template and why.>`
