---
name: threat-model
description: Threat-model a Google Cloud architecture from a diagram description, Terraform, or a live project ID using STRIDE per element focused on trust boundaries. Use when the user says things like "threat model this architecture", "what could go wrong with this design", "walk me through the attack surface", or asks for a STRIDE analysis before building or deploying on GCP.
---

# Threat Model

## When to use

Use when the user wants a structured threat model of a GCP architecture — proposed or deployed — from a diagram description, Terraform, a design doc, or a live project ID. Threat modeling enumerates attack paths across trust boundaries; it is not a misconfiguration scan. If the user instead wants existing resources audited against benchmarks or least-privilege rules, defer to the security-review or terraform-least-privilege-review skills.

## Inputs

Ask at most these questions, then proceed with stated assumptions:

1. What is the artifact — diagram description, Terraform (which path), design doc, or a live project ID? If live, which project?
2. Which assets matter most (data classes, availability targets, regulatory drivers)? If unstated, assume the data stores and any internet-facing entry point.
3. Which actors are in scope (external attacker, malicious insider, compromised CI/CD pipeline, compromised third party)? Default: all four.

If the user gives only a project ID, inventory it read-only first and derive the assets from what actually exists.

## Workflow

1. Scope and confirm: restate the system in one paragraph, list the assets worth protecting, and confirm actors and exclusions with the user.
2. Build the inventory: components, data stores, data flows, identities. For a live project, use read-only gcloud MCP tools when available — list enabled services, compute workloads (GCE, GKE, Cloud Run), load balancers, Cloud SQL instances, buckets, service accounts, and IAM bindings. If MCP is unavailable, ask the user to run the equivalent read-only `gcloud` commands. For Terraform, parse resources from the configuration. If neither exists, work from the description and state assumptions.
3. Draw trust boundaries (cheat sheet below) and mark every data flow that crosses one.
4. Enumerate STRIDE threats per element, prioritizing boundary crossings: Spoofing, Tampering, Repudiation, Information disclosure, Denial of service, Elevation of privilege. Skip a category for an element only with a stated reason.
5. Map existing controls per threat from the evidence: Cloud Armor policies, VPC SC perimeters, CMEK, IAM Conditions, audit log configuration, Binary Authorization, WIF vs service account keys.
6. Risk-rank each threat by likelihood x impact using the rubric below; never average a High/High down.
7. Recommend GCP-native mitigations per gap — platform and org-policy controls first, process fixes last.
8. State residual risk and open questions; flag anything you could not verify from evidence.

## GCP trust-boundary cheat sheet

Enumerate threats at each of these boundaries. Flows crossing more than one are the usual high-value attack paths.

- Internet edge: global external Application Load Balancer, Cloud CDN, API gateways. Controls: Cloud Armor security policies (WAF rules, rate limiting), IAP for internal apps, managed certificates.
- VPC Service Controls perimeter: wraps projects and supported services to block exfiltration. Check perimeter bridges, access levels, and ingress/egress policies that punch holes.
- Project boundary: the default blast-radius unit. Every cross-project flow — Shared VPC, VPC peering, cross-project service account impersonation — is a boundary crossing.
- Org/folder org-policy boundary: constraints enforce guardrails, e.g. `constraints/iam.allowedPolicyMemberDomains`, `constraints/iam.disableServiceAccountKeyCreation`, `constraints/storage.uniformBucketLevelAccess`, `constraints/compute.requireShieldedVm` (VERIFY exact constraint names against the current org policy list before citing).
- CI/CD supply chain: Cloud Build worker service accounts, Artifact Registry, deployer identities. Controls: Binary Authorization attestations, build provenance, Workload Identity Federation instead of long-lived SA keys, separation of build and deploy SAs.
- Human/admin access path: Cloud IAM grants and group membership. Controls: IAM Conditions, Privileged Access Manager (VERIFY availability in the target org), IAP TCP forwarding instead of open SSH, Cloud Audit Logs (Admin Activity is always on; check whether Data Access logs are enabled).
- Data layer: Cloud KMS/CMEK vs Google-default encryption, uniform bucket-level access vs object ACLs, IAM database authentication vs static passwords, Secret Manager versioning and rotation.

## Likelihood / impact rubric

Likelihood (probability of exploitation within a year, given current controls):

- High: remotely exploitable path exists today, or the weakness is already observed in evidence; no meaningful control in the way.
- Medium: exploitable but requires a precondition — valid credentials, internal network position, or chaining with another weakness.
- Low: theoretical; requires defeating a working control (e.g. breaking an enforced VPC SC perimeter).

Impact (worst credible outcome for the assets in scope):

- High: loss of regulated or business-critical data, full project or org compromise, prolonged outage of a critical service.
- Medium: limited data exposure, single-service compromise, or recoverable disruption.
- Low: no sensitive data involved; contained to non-production or easily reversible.

Priority = likelihood x impact. High/High and High/Medium are P1; High/Low and Medium/Medium are P2; the rest P3. A high-impact, low-likelihood threat is still P2 minimum — do not let likelihood zero out impact.

## Output format

````markdown
# Threat model: <system name>

## Summary
<3-5 sentences: overall risk posture, top 3 threats, single most important mitigation.>

## Scope and assumptions
- Artifact reviewed: <diagram description / Terraform at <path> / live project <id> (gcloud account: <account>)>
- Assets in scope: <list>
- Actors: <list>
- Assumptions: <explicit list, including anything not verifiable from evidence>

## Components and trust boundaries
| Component | Type | Trust zone / boundary | Data handled | Notes |
|---|---|---|---|---|

## Data-flow diagram
```mermaid
flowchart LR
  <nodes and flows, trust boundaries as subgraphs>
```

## Threats
| ID | Element | STRIDE | Threat | Likelihood | Impact | Existing controls | Gap | Recommended mitigation | Priority |
|---|---|---|---|---|---|---|---|---|---|

## Residual risk and open questions
- <accepted or unmitigated risks, with owner>
- <unanswered questions that would change the ranking if resolved>
````

## Guardrails

- Evidence first: for a live project, inventory via read-only gcloud MCP before enumerating threats, and state explicitly which threats rest on assumptions vs observed configuration. The AGENTS.md read-only rule applies without exception — never touch a resource to "test" an attack path.
- One threat per row; do not merge distinct attack paths to shorten the table, and do not pad it with generic threats that ignore the actual architecture.
- Cite exact product, role, and constraint names; mark anything uncertain `(VERIFY)` — never invent plausible-looking constraint or role names.
- Recommend GCP-native mitigations first (org policy constraints, VPC SC, Cloud Armor, CMEK, Binary Authorization, WIF) before process or third-party fixes.
- Never print secrets, SA keys, or data contents encountered during inventory; reference resources by ID only.
- Every threat must map to an inventoried element and trust boundary; if you cannot place it, it is out of scope, not a finding.
- Keep likelihood and impact honest: a missing control you did not verify is an assumption, not evidence of compromise.
