---
name: security-faq
description: Answers commonly asked Google Cloud security questions (encryption, IAM, networking, secrets, SCC, org policy) in a short-answer/why/verify/references format that corrects misconceptions. Use when the user asks things like "is my data encrypted at rest?", "VPC SC vs Private Google Access?", "are service account keys OK?", "do we need CMEK?", or compares two GCP security controls.
---

# Security FAQ

## When to use

Use when the user asks a conceptual or comparative GCP security question — "is encryption at rest on by default?", "VPC Service Controls or Private Google Access?", "Standard vs Enterprise SCC?", "do we still need a bastion host?" — and wants a direct, defensible answer rather than an audit. For auditing a live project or Terraform, defer to the security-review or terraform-least-privilege-review skills. If the question touches a live environment, evidence comes first (AGENTS.md): inspect before answering.

## Inputs

Ask at most these, then proceed with stated assumptions:

1. The exact question or decision ("should we enable CMEK?", not "tell me about KMS"). If only implied, restate it in one sentence and continue.
2. Scope: a live project/org (which one?) or hypothetical? Default: hypothetical — answer from product behavior, not environment state.
3. Audience: engineer or manager/compliance? Default: engineer.

## Workflow

1. Classify the question: conceptual ("how does X work?"), comparative ("X or Y?"), or live-environment ("is X enabled in our project?").
2. Check the position cheat sheet below; if the topic is covered, start from that position and tailor it to the user's context.
3. For live-environment questions, gather evidence first with read-only gcloud MCP tools when available (describe the resource, get the IAM policy, describe the org policy). If MCP is unavailable, ask the user to run the equivalent read-only `gcloud` commands and paste the output. If neither is possible, answer from stated assumptions and label them as such.
4. Verify names before writing them: role names, org policy constraint IDs, command flags, and product tiers must be real; mark anything uncertain `(VERIFY)`.
5. Identify any misconception embedded in the question (see Guardrails) and correct it explicitly before answering.
6. Compose the answer in the Output format: short answer, why, how to verify, references. Prefer GCP-native controls and cite exact product and role names.

## Position cheat sheet

Default positions, one line each. Expand into the full Output format when answering; do not paste the line alone.

- **Encryption at rest.** Always on for GCP storage services with Google-managed keys (AES-256); there is no checkbox and no way to disable it. CMEK only when you need rotation/destruction control, key-use audit, or a regulatory mandate; CSEK or Cloud EKM only when keys must live outside Google (limited service support — verify per service).
- **VPC Service Controls vs Private Google Access.** VPC SC is an API-perimeter control against data exfiltration from Google-managed services, based on identity and context — it is not a firewall. PGA only gives VMs without external IPs a route to Google APIs. Complementary, not alternatives.
- **IAP TCP forwarding vs bastion hosts.** Prefer IAP TCP forwarding (`gcloud compute ssh --tunnel-through-iap`, `roles/iap.tunnelResourceAccessor`): identity-authenticated, logged, no external IP, no extra VM to patch. Bastion hosts are public attack surface; keep one only where IAP cannot reach.
- **Workload Identity Federation vs service account keys.** WIF issues short-lived tokens to external workloads (AWS, Azure, GitHub Actions, on-prem) via service account impersonation — nothing to download or leak. SA keys are long-lived secrets; treat any key creation as an exception.
- **Secret Manager vs env vars / instance metadata.** Secret Manager gives per-secret IAM (`roles/secretmanager.secretAccessor`), versioning, access audit logs, and rotation. Env vars leak into CI logs and process listings; instance metadata is readable by any process on the VM. Reference secrets by resource path; never print payloads.
- **Security Command Center Standard vs Enterprise.** Standard (free) covers asset inventory and basic findings; Enterprise adds Google SecOps (SIEM/SOAR), attack path simulation, and the full detection stack, with Premium as the middle tier. (VERIFY current tier contents — SCC packaging changed in 2024.)
- **Org-policy starter set.** Enforce at the org root: `constraints/storage.uniformBucketLevelAccess`, `constraints/iam.disableServiceAccountKeyCreation`, `constraints/compute.vmExternalIpAccess` (deny all), `constraints/storage.publicAccessPrevention`. (VERIFY exact constraint IDs against the current org policy list before applying.)
- **Binary Authorization for GKE.** Deploy-time admission control: only images carrying required attestations (e.g., from your Cloud Build pipeline) may run on the cluster. Supply-chain control, not runtime protection; pair with Artifact Registry vulnerability scanning.
- **Cloud SQL public IP vs connectors.** Prefer private IP plus Cloud SQL connectors or the Auth Proxy: IAM-authenticated, automatic TLS, no authorized-networks CIDR management. Public IP is acceptable only with tight authorized networks and enforced SSL.
- **Shared VPC security model.** The host project owns subnets and firewall rules; service projects get subnet-scoped `roles/compute.networkUser`. Project owners cannot open firewall rules — use it to separate network admin from workload admin.
- **Cloud Armor.** Edge WAF and L3-L7 DDoS protection on the global external Application Load Balancer: preconfigured OWASP rules, rate limiting, geo blocking. It covers only traffic through that load balancer — other entry points are unprotected.
- **Cloud Audit Logs.** Admin Activity logs are always on, no charge, retained 400 days. Data Access logs are off by default (BigQuery excepted), enabled per service, billed, retained 30 days by default — export via log sinks for longer retention.
- **Assured Workloads.** Folder-level control packages enforce data residency (e.g., EU data boundary) and compliance regimes (FedRAMP, IL4, CJIS) via org policy. Residency applies only to supported services in selected regions — check the supported-services list.
- **GCS public access prevention.** Bucket- or org-level setting that rejects IAM grants to `allUsers` and `allAuthenticatedUsers`; enforce org-wide with the constraint above and audit existing buckets' IAM policies for legacy public grants.

## Verification command cheat sheet

Read-only commands for the "How to verify" section. Prefer gcloud MCP tools when available; otherwise hand the user the command. Replace placeholders; state account and project per AGENTS.md.

- Org policy: `gcloud resource-manager org-policies describe <constraint-id> --organization=<org-id>` (works for project/folder with `--project` / `--folder`).
- Uniform bucket-level access / public access prevention: `gcloud storage buckets describe gs://<bucket> --format="value(iamConfiguration)"`.
- Legacy public bucket grants: `gcloud storage buckets get-iam-policy gs://<bucket>` — look for `allUsers` / `allAuthenticatedUsers`.
- Service account keys: `gcloud iam service-accounts keys list --iam-account=<sa-email>` — any user-managed key is a finding candidate.
- Secret access scope: `gcloud secrets get-iam-policy <secret-id> --project=<project-id>` — accessor roles should be per-secret, not project-wide.
- Audit log configuration: `gcloud projects get-iam-policy <project-id> --format="yaml(auditConfigs)"` — empty means no Data Access logs enabled.
- VM external IPs (bastion check): `gcloud compute instances list --format="value(name, networkInterfaces[].accessConfigs[].natIP)"`.
- Binary Authorization on GKE: `gcloud container clusters describe <cluster> --location=<location> --format="value(binaryAuthorization)"`.
- Cloud SQL network posture: `gcloud sql instances describe <instance> --format="value(settings.ipConfiguration)"` — check `ipv4Enabled`, `authorizedNetworks`, `sslMode`.
- VPC SC perimeters: `gcloud access-context-manager perimeters list --policy=<policy-id>` (get the policy ID via `gcloud access-context-manager policies list --organization=<org-id>`).
- Cloud Armor: `gcloud compute security-policies list` and `gcloud compute backend-services list --global --format="value(name, edgeSecurityPolicy, securityPolicy)"` (VERIFY flag name for the edge policy field).
- SCC tier: console path `Security > Security Command Center > Settings`; tier and enabled services are also visible in the console overview.

## Output format

```markdown
**Short answer.** <1-3 sentences: the fact or recommendation, stated plainly.>

**Why it works that way.** <The mechanism: what the control actually enforces and what it does not cover. Put the misconception correction here when the question contained one, e.g. "There is no encryption-at-rest checkbox because...".>

**How to verify.** <One read-only gcloud command or a console path the user can use to confirm the setting; for purely conceptual questions, the command that would show it.>

**References.** <Google Cloud documentation titles, e.g. "Encryption at rest in Google Cloud", "VPC Service Controls overview".>
```

Keep the short answer under three sentences. If the honest answer is "it depends", list the 2-3 deciding factors in the Why section instead of hedging.

## Example answer

Question: "Is it fine to use a service account key for our GitHub Actions deploy to GCP?"

**Short answer.** No — use Workload Identity Federation. GitHub's OIDC provider exchanges a short-lived token for GCP credentials; no downloadable key exists to leak.

**Why it works that way.** An SA key is a long-lived bearer credential: whoever holds the JSON file is the service account, from anywhere, until the key is revoked. Keys routinely end up in repos, CI logs, and laptops. WIF maps an external identity (repo, branch, workflow) to service account impersonation with conditions, so exfiltrated tokens expire in minutes and only match your intended workload. "The SA key is the standard way" is a misconception — it is the legacy way.

**How to verify.** List existing keys with `gcloud iam service-accounts keys list --iam-account=<sa-email>`; check whether key creation is blocked org-wide with `gcloud resource-manager org-policies describe constraints/iam.disableServiceAccountKeyCreation --organization=<org-id>` (VERIFY constraint ID).

**References.** "Workload Identity Federation", "Best practices for using service accounts", "Manage service account keys".

## Guardrails

- Correct misconceptions explicitly and early: there is no "encryption at rest checkbox"; VPC SC is not a firewall; Private Google Access creates no perimeter; "the service account key is the standard way" is false — Workload Identity Federation or attached service accounts are.
- Never invent role names, constraint IDs, command flags, or product tiers. If not certain, write the best-known form with `(VERIFY)` and tell the user to confirm against current docs.
- Live-environment claims require read-only evidence per AGENTS.md; label assumption-based answers as assumptions and state which account and project the evidence came from.
- Never print or request secret payloads, SA key material, or tokens — reference secrets by resource path only, even when the user offers to paste them.
- Stay product-accurate, not marketing-accurate: name what a control does not cover (Cloud Armor off the load-balancer path, Binary Authorization at runtime, Data Access logs left disabled).
- Use the four-part format even for trivial questions; a cheat-sheet line alone is not an answer.
- No emojis, no "great question" openers, no marketing language.
