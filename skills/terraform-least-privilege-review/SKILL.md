---
name: terraform-least-privilege-review
description: Audit Terraform (HCL) for GCP IAM least-privilege violations — primitive roles, service account keys, public members, missing IAM Conditions — and propose minimal diff-style fixes. Use when asked to "review my Terraform IAM", "check this .tf for least privilege", or "audit GCP IAM in HCL".
---
# Terraform Least-Privilege Review

## When to use
The user provides Terraform files (or a repo path) and asks for a least-privilege / IAM audit of GCP resources, or any Terraform review where IAM bindings appear. For runtime IAM state, do a live review with read-only `gcloud` MCP tools instead; combining both is stronger.

## Inputs
Ask at most these, then proceed with stated assumptions:
1. Path to the Terraform (file, directory, or pasted HCL). If none given, search the working directory for `*.tf`.
2. Scope: full audit, or specific resources/projects only?
3. Environment (prod vs dev) if it changes severity — otherwise assume prod and say so.

## Workflow
1. **Enumerate.** Locate all `*.tf`; grep for `google_*_iam_member` / `_binding` / `_policy`, `google_service_account`, `google_service_account_key`, `google_iam_workload_identity_pool`, `google_project_iam_audit_config`, custom roles, `condition` blocks. Record `file:line` for every hit. If Checkov/Trivy/tfsec is available, run it first (see the `sast-scan` skill) for breadth — your grep-driven enumeration remains the source of `file:line` evidence.
2. **Inventory guardrails.** Note presence/absence of `uniform_bucket_level_access`, `public_access_prevention`, audit config (`DATA_READ`/`DATA_WRITE` on sensitive services), org policy constraints if the module manages them.
3. **Map identity to need.** For each grant, identify the member and infer the workload's need from adjacent resources. A grant you cannot map to a need is a finding candidate.
4. **Flag violations.** Apply patterns P1–P10 below to every hit; capture exact line numbers.
5. **Cross-check scope.** For each project/folder/org-level grant, check whether a resource-level equivalent exists (bucket vs project storage); flag the broader scope.
6. **Report and optionally verify live.** Emit the findings table plus per-finding patches (Output format), ordered by severity. If read-only `gcloud` MCP tools are available and the user wants ground truth, compare with `gcloud projects get-iam-policy <project>`; otherwise state findings are static-analysis only.

## Detection patterns
Severity by context: public exposure and primitive roles at org level are Critical; a dev-only project viewer may be Low.

### P1 — Primitive roles at project/folder/org level
- **Pattern:** `role\s*=\s*"roles/(owner|editor|viewer)"` in `google_project_iam_member` / `_binding` / `_policy`, `google_folder_iam_*`, `google_organization_iam_*`.
- **Risk:** `roles/editor` is near-total read+write on the project; `roles/owner` adds IAM and billing control. Folder/org level multiplies blast radius.
- **Fix:** granular predefined role for the actual need, or a custom role:
```hcl
resource "google_project_iam_member" "app" {
  role   = "roles/run.invoker" # was roles/editor
  member = "serviceAccount:${google_service_account.app.email}"
}
```
### P2 — Service account keys
- **Pattern:** `resource\s+"google_service_account_key"`.
- **Risk:** long-lived downloadable credential; a leak bypasses all identity controls.
- **Fix:** delete the resource. Off-GCP workloads: Workload Identity Federation (`google_iam_workload_identity_pool` + provider); user-to-SA: impersonation (`roles/iam.serviceAccountTokenCreator`); GKE: Workload Identity Federation for GKE. Then bind the external identity:
```hcl
member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/attribute.repository/my-org/my-repo" # on google_service_account_iam_member with role = "roles/iam.workloadIdentityUser"
```
### P3 — Public members
- **Pattern:** `member\s*=\s*"(allUsers|allAuthenticatedUsers)"` or either inside `members = [...]` in any IAM resource.
- **Risk:** unauthenticated (or any-Google-account) access. Org-wide defense: `constraints/iam.allowedPolicyMemberDomains`.
- **Fix:** delete the grant; for genuinely public content use a global external ALB + Cloud CDN fronting a private bucket, or signed URLs:
```hcl
# delete the *_iam_member/_binding block for allUsers/allAuthenticatedUsers — no replacement resource
```
### P4 — Default service accounts as workload identity
- **Pattern:** `<project-number>-compute@developer.gserviceaccount.com`, `<project-id>@appspot.gserviceaccount.com`, or a `google_service_account` named `default`.
- **Risk:** default compute/App Engine SAs hold `roles/editor` on the project and are shared by every default-attached workload; one compromised VM owns the project.
- **Fix:** per-workload SA with a granular role, attached via `service_account { email = ... }` on the compute resource; org policy `constraints/iam.automaticIamGrantsForDefaultServiceAccounts` disables the auto editor grant:
```hcl
resource "google_service_account" "app" { account_id = "app-workload" } # one per workload
```
### P5 — Wildcard or bloated custom roles
- **Pattern:** `resource\s+"google_(project|organization)_iam_custom_role"` with `"*"` in `permissions`, or a permission list over ~20 entries.
- **Risk:** re-creates editor under a custom name; `*` silently grows as GCP adds permissions.
- **Fix:** enumerate only the permissions the workload calls; split unrelated duties into separate roles:
```hcl
permissions = ["storage.objects.get", "storage.objects.list"] # never "*"
```
### P6 — Sensitive grants without IAM Conditions
- **Pattern:** powerful roles (`roles/iam.*`, `*.admin`, primitives) on `*_iam_member` / `_binding` with no `condition {` block.
- **Risk:** standing permanent privilege where a time-boxed or name-scoped grant suffices; lateral-movement value.
- **Fix:** add an IAM Condition — time-bound, or resource-name-scoped e.g. `resource.name.startsWith("projects/_/buckets/my-bucket")` (VERIFY resource.name format per service):
```hcl
condition {
  title      = "expiring-grant"
  expression = "request.time < timestamp(\"2026-08-01T00:00:00Z\")"
}
```
### P7 — Authoritative IAM resources
- **Pattern:** `resource\s+"google_project_iam_(policy|binding)"`.
- **Risk:** authoritative for the whole policy (policy) or entire role (binding); `apply` deletes out-of-band grants — other teams' bindings, break-glass access. Common cause of lockouts.
- **Fix:** prefer additive member resources; use authoritative only when Terraform genuinely owns the whole policy, commented as such:
```hcl
resource "google_project_iam_member" "app" { role = "roles/storage.objectViewer" } # + member attr; one per member/role pair
```
### P8 — Project-level grant where resource-level exists
- **Pattern:** `google_project_iam_member` with `roles/storage.*`, `roles/bigquery.*`, `roles/pubsub.*`, `roles/secretmanager.*` where the module manages the target resource.
- **Risk:** covers every current and future bucket/dataset/topic/secret in the project.
- **Fix:** move to the resource-level binding:
```hcl
resource "google_storage_bucket_iam_member" "app" {
  bucket = google_storage_bucket.data.name
  role   = "roles/storage.objectViewer" # was project-level roles/storage.admin
  member = "serviceAccount:${google_service_account.app.email}"
}
```
### P9 — Public bucket via IAM + missing bucket guardrails
- **Pattern:** `google_storage_bucket_iam_member` / `_binding` with `allUsers` / `allAuthenticatedUsers` (P3 subset, called out for its guardrail pairing); companion check: `google_storage_bucket` without `uniform_bucket_level_access = true` (ACLs bypass IAM review) or `public_access_prevention = "enforced"`.
- **Risk:** the classic public-bucket data exposure, often undetected because ACLs sit outside IAM review.
- **Fix:** remove the public grant and set both guardrails:
```hcl
uniform_bucket_level_access = true   # on google_storage_bucket
public_access_prevention    = "enforced"
```
### P10 — Missing audit config
- **Pattern:** no `google_project_iam_audit_config` anywhere for projects handling sensitive data.
- **Risk:** DATA_READ/DATA_WRITE not logged; Cloud Audit Logs can't support forensics or Security Command Center investigation. Cost note: scope `service` if volume is a concern.
- **Fix:**
```hcl
resource "google_project_iam_audit_config" "data" {
  project = var.project_id
  service = "allServices"
  audit_log_config { log_type = "DATA_READ" } # add DATA_WRITE too
}
```

## Output format
Findings first, patches second; follow the repo's global findings convention (severity / evidence / impact / remediation / CIS or best-practice reference). Append short "Guardrail gaps" (P2/P9/P10 absences) and "Assumptions" lists when applicable.

````markdown
## Terraform Least-Privilege Review — <path>

Scope: <files audited> | Mode: static analysis (HCL only) — live policy not compared

### Findings

| ID | Location | Identity | Role | Issue | Severity | Remediation |
|----|----------|----------|------|-------|----------|-------------|
| F1 | iam.tf:12 | sa-app@... | roles/editor | Primitive role, project level (P1) | High | roles/run.invoker |

### Proposed patches

Minimal unified-diff-style HCL per finding; author's structure preserved.

#### F1 — iam.tf

```diff
 resource "google_project_iam_member" "app" {
-  role    = "roles/editor"
+  role    = "roles/run.invoker"
   member  = "serviceAccount:${google_service_account.app.email}"
 }
```
````

## Guardrails
- Propose minimal diffs only: never rewrite the whole file, reorder blocks, or reformat unrelated HCL; preserve names, comments, structure.
- Static review: no `terraform apply`/`plan` against real state, no mutations; read-only `gcloud` MCP lookups are fine for verification.
- Every finding needs real `file:line` evidence from your grep, not paraphrase; say so if line numbers are approximate.
- Don't call a grant over-privileged without naming the narrower role that satisfies the workload — "too broad" with no alternative is noise.
- Distinguish additive (`_member`) from authoritative (`_binding`/`_policy`) before flagging: a binding's full `members` list may be legitimate.
- Mark any role, permission, or constraint name you are not certain of as `(VERIFY)`; never invent plausible-looking names.
- Never print secret payloads or key material found near IAM resources; reference by path only.
