---
name: terraform-secure-generator
description: Generate secure-by-default, least-privilege Terraform (HCL) for GCP workloads, with a security decision log and deployment notes. Use when the user asks to "write Terraform for ...", "scaffold a GCP project/module", or "generate infra for <workload>" and expects code that passes a security review.
---

# Terraform Secure Generator

Writes new Terraform for GCP workloads that is secure by default: dedicated identities, least-privilege IAM, private networking, CMEK for sensitive data, and an auditable record of every security decision. For auditing existing Terraform, use `terraform-least-privilege-review` instead.

## When to use

- "Write / generate / scaffold Terraform for <workload> on GCP", "create a module for <service>", "I need infra for <app>".
- Greenfield GCP project, or a new module inside an existing Terraform repo.
- Output is code plus a decision log, ready for review and `terraform plan` — this skill never applies anything.

## Inputs

Ask at most these three questions, then proceed:

1. **Workload shape** — which GCP services (Cloud Run, GKE, GCE, Cloud SQL, GCS, Pub/Sub, BigQuery, ...), single project or multi-project?
2. **Data classification** — does it store or process sensitive data (PII, PHI, financial)? Drives CMEK, Data Access audit logs, and stricter exposure defaults.
3. **Network exposure** — internal-only, or is a public endpoint required (then: HTTPS-only, Cloud Armor in scope)?

If the user does not answer, proceed with stated assumptions — single project, sensitive data (CMEK on), internal-only — and record each assumption in the decision log.

## Workflow

1. **Gather evidence first.** Generating into an existing repo: read its `.tf` files before writing anything — naming conventions, module boundaries, provider/version pinning, backend and state strategy, variable and locals style. Match them; do not impose a new structure.
2. Targeting a live project: inspect it read-only via the gcloud MCP tools (org policies, enabled APIs, existing KMS rings and service accounts). If MCP is unavailable, ask the user to run the equivalent `gcloud` commands; otherwise work from provided artifacts and mark unverified facts as assumptions.
3. Confirm intake answers or defaults, then pick the smallest file/module layout consistent with the discovered conventions.
4. Generate the HCL. Every security-relevant argument carries an inline `#` comment naming the control and the reason.
5. Emit the security decision log (decision / control / why).
6. Emit deployment notes: IAM roles the applying identity needs, bootstrap order, manual steps.
7. If the user asked for anything that weakens a default, do not weaken it silently — report it as a finding with severity and require explicit confirmation (see Guardrails).

## Non-negotiable rules

- **Dedicated service accounts.** One `google_service_account` per workload. No default SAs (compute/appengine), no SA shared across workloads. Never emit `google_service_account_key` — user-managed keys do not exist in generated code.
- **Least-privilege bindings.** Granular predefined roles (e.g. `roles/storage.objectAdmin`, `roles/cloudsql.client`, `roles/secretmanager.secretAccessor`) or a `google_project_iam_custom_role`; bind at the most specific resource level (`google_storage_bucket_iam_member`, `google_secret_manager_secret_iam_member`, `google_kms_crypto_key_iam_member`) before falling back to project level. Never primitive roles (`roles/owner`, `roles/editor`, `roles/viewer` at project scope).
- **IAM Conditions** for time-bound or scoped grants: a `condition` block on the IAM member resource, e.g. `expression = "request.time < timestamp(\"2026-12-31T00:00:00Z\")"`.
- **Workload Identity Federation** for CI/CD and off-GCP workloads: `google_iam_workload_identity_pool` + `google_iam_workload_identity_pool_provider`, then `google_service_account_iam_member` granting `roles/iam.workloadIdentityUser` to the pool `principalSet`. On-GCP workloads attach the SA directly to the resource.
- **Hardened GCS.** `uniform_bucket_level_access = true`, `public_access_prevention = "enforced"`, `versioning { enabled = true }`, and never `allUsers` or `allAuthenticatedUsers` in any binding.
- **CMEK for sensitive data.** `google_kms_key_ring` + `google_kms_crypto_key` with `rotation_period = "7776000s"` (90 days); wire via `encryption { default_kms_key_name = ... }` on GCS, `kms_key_name` on Pub/Sub topics, `default_encryption_configuration` on BigQuery datasets. Grant the service agent (e.g. `data "google_storage_project_service_account"`) `roles/cloudkms.cryptoKeyEncrypterDecrypter` on the key.
- **Private networking.** No external IPs: no `access_config` on instances/templates, no public `google_compute_address` for workloads. Subnets set `private_ip_google_access = true`. Cloud SQL: `ip_configuration { ipv4_enabled = false; private_network = ... }`. A public endpoint exists only if the user confirmed it, and then only behind an HTTPS load balancer with a Cloud Armor policy.
- **Audit logging.** `google_project_iam_audit_config` enabling `DATA_READ` and `DATA_WRITE` for every service holding sensitive data (at minimum GCS, BigQuery, Secret Manager). `ADMIN_READ` is on by default — do not redeclare it.
- **Labels.** Every labelable resource gets `env` and `data-classification`, values valid per GCP label syntax (lowercase, `-`/`_`).
- **Minimal APIs.** `google_project_service` for exactly the APIs the workload uses, nothing "just in case".
- **Service-specific hardening.** GKE: shielded nodes and Binary Authorization. Public HTTPS endpoints: Cloud Armor policy. Note in deployment notes that org-level controls — VPC Service Controls perimeters, org policy constraints — are applied outside this code (see Guardrails).

## Output format

Deliver in this order, no extra prose between sections:

````markdown
## File tree
<directory tree of every file generated>

## Files

### `<path>/<file>.tf`
```hcl
<complete file contents — no placeholders, no "... rest unchanged">
```

### `<path>/<file>.tf`
```hcl
<complete file contents>
```

## Security decisions

| Decision | Control | Why |
|---|---|---|
| Dedicated SA `sa-<workload>` per workload | Least privilege | Blast radius limited to one workload; no default SA in use |
| <decision> | <control, e.g. CIS GCP Foundations x.y> | <reason> |

## Deployment notes

- **Applying identity needs:** <roles, e.g. roles/iam.serviceAccountAdmin, roles/cloudkms.admin, roles/storage.admin, roles/resourcemanager.projectIamAdmin>
- **Bootstrap order:** 1) `google_project_service` APIs → 2) KMS ring/key → 3) service-agent grant on the key → 4) workload SA + IAM bindings → 5) data resources.
- **Manual / out-of-band steps:** org policy constraints to confirm (`constraints/iam.disableServiceAccountKeyCreation`, `constraints/compute.vmExternalIpAccess`, `constraints/storage.uniformBucketLevelAccess`), WIF provider attribute mapping for the specific CI system, VPC SC perimeter membership if applicable, `terraform plan` review before apply.
````

## Guardrails

- Generating into an existing repo: read the existing Terraform first and match its naming, module layout, provider pinning, and backend/state conventions. Do not impose a new structure.
- Never emit `google_service_account_key`, plaintext secret values, or secret payloads in HCL. Provision `google_secret_manager_secret` plus IAM and let the workload read secrets at runtime.
- Generation is not deployment: produce code, decision log, and notes only. Never run `terraform apply` or mutate cloud resources — global read-only rules apply.
- A request to weaken a default (public bucket, primitive role, external IP, shared SA) is a finding, not a config change: flag it with severity, require explicit confirmation, and record the accepted risk in the decision log.
- Mark any resource, role, or org-policy constraint name you are not certain of as `(VERIFY)`. Never invent plausible-looking names.
- Keep scope to the stated workload: no speculative modules, wrappers, or "future-proof" frameworks.
