---
name: well-architected-review
description: Assess a GCP workload against the Google Cloud Architecture Framework pillars (operational excellence, security/privacy/compliance, reliability, cost optimization, performance optimization) and produce a scored, prioritized improvement roadmap. Use when someone asks for a "well-architected review", "architecture framework assessment", "WAF review", a production-readiness check, or a periodic architecture health check of a GCP workload.
---

# Well-Architected Review

## When to use

- The user asks to assess a workload, landing zone, or application against the Google Cloud Architecture Framework, or asks "is this production-ready", "review my architecture", "well-architected assessment", "architecture health check".
- Not for deep security audits — that is the `security-review` skill; this review flags security findings at checklist depth and hands off. Not for Terraform-only IAM audits — that is `terraform-least-privilege-review`.

## Inputs

Ask at most 3 questions if missing; otherwise proceed and state assumptions in the output:

1. Business context and compliance regime: what the workload does, data classification (public / internal / confidential / restricted), applicable regimes (PCI DSS, HIPAA, SOC 2, ISO 27001, none).
2. SLOs and scale: availability and latency targets, RTO/RPO, traffic and data volume, single-region or multi-region ambition.
3. Team and delivery maturity: who operates it (SRE / platform / dev), on-call model, deployment frequency, IaC coverage.

If unanswered, default to: business-critical internal workload, 99.9% availability, internal data, unknown IaC coverage — and mark every such assumption in the report.

## Workflow

1. Scope: record workload name, environments, GCP project/folder IDs, regions, and review date. Before any live inspection, establish context per AGENTS.md (`gcloud config get-value account && gcloud config get-value project`) and state it in the report.
2. Gather evidence — always before scoring:
   - Artifacts: architecture diagrams, Terraform/IaC, CI/CD configs, SLO docs, runbooks, incident history, BigQuery billing export.
   - Live project: use read-only gcloud MCP tools when available (`gcloud projects get-iam-policy`, `gcloud services list`, `gcloud asset search-all-resources`, `gcloud compute instances list`, `gcloud logging logs list`, `gcloud monitoring policies list`, `gcloud org-policies list`). If MCP is unavailable, ask the user to run these read-only commands and paste output. If neither is possible, work from provided artifacts and mark all live-state claims as assumptions.
3. Build a resource inventory (projects, networks, workloads, data stores, service accounts, integrations) and map it to the five pillars.
4. Score each pillar 1–5 against the maturity rubric below. Every score cites observed evidence; absence of evidence lowers the score — no benefit of the doubt.
5. Cross-pillar trade-off analysis: surface where recommendations conflict and resolve against the stated SLOs and compliance regime, not preference.
6. Build the roadmap: top-10 recommendations ranked by risk reduction and business impact, each with effort and suggested owner.
7. Report using the output template. Deep security findings get a severity note and a hand-off reference to `security-review`; do not duplicate that audit here.

## Maturity rubric (apply per pillar)

- 1 – Ad hoc: manual changes (ClickOps), no IaC, no SLOs, default-only or no monitoring, no DR.
- 2 – Basic: partial IaC, some alerting, backups exist but restores untested, single-zone, perimeter-only controls.
- 3 – Defined: infra fully described in IaC with code review, CI/CD with rollback, SLOs defined and measured, restores tested, baseline guardrails in place (org policy, least privilege started).
- 4 – Managed: drift detection, progressive delivery (canary/blue-green), error budgets gate releases, multi-zone HA, policy as code, continuous compliance scanning, full cost attribution.
- 5 – Optimizing: self-healing and chaos testing, multi-region where SLOs justify it, continuous optimization loops (rightsizing, autoscaling, commitment coverage), blameless postmortems feed the backlog.

## Per-pillar checklist

### Operational excellence

- IaC coverage (Terraform / Config Connector), no unmanaged drift; environment separation via projects and folders.
- CI/CD: Cloud Build / Cloud Deploy, automated tests, rollback path, prod approval gates.
- Observability: Cloud Monitoring dashboards and alert policies tied to SLOs, structured Cloud Logging, uptime checks, Cloud Trace and Profiler where relevant.
- Ops readiness: runbooks, on-call rotation, incident process, postmortems.

### Security, privacy, and compliance (checklist depth — hand findings to `security-review`)

- No primitive roles at project level and above; granular predefined or custom roles, groups over individuals, IAM Conditions where temporal/attribute scoping is needed.
- No user-managed service account keys; Workload Identity Federation for external workloads; no default compute service account as workload identity.
- Org policy guardrails, e.g. `constraints/iam.disableServiceAccountKeyCreation`, `constraints/iam.allowedPolicyMemberDomains`, `constraints/compute.requireShieldedVm`, `constraints/storage.uniformBucketLevelAccess` — mark any others `(VERIFY)` before citing.
- VPC Service Controls perimeters against exfiltration; Private Google Access; no public IPs without justification.
- CMEK via Cloud KMS where the regime requires; secrets in Secret Manager; Cloud Audit Logs coverage (Admin Activity plus Data Access for sensitive services).
- Security Command Center enabled, Cloud Armor on internet-facing load balancers, Binary Authorization on GKE deploy paths.
- Data classification mapped to controls; residency requirements via Assured Workloads where applicable `(VERIFY regime-specific folders)`.

### Reliability

- SLOs with error budgets; architecture actually meets them: multi-zone MIGs or regional clusters, health-checked load balancing.
- DR: RTO/RPO defined; backups (Persistent Disk snapshots, Cloud SQL automated backups, Backup and DR Service) with tested restores.
- Failure handling: retries with backoff, graceful degradation; capacity headroom and autoscaling limits reviewed.
- Change safety: progressive rollouts with automated canary analysis.

### Cost optimization

- Budgets with alerts, BigQuery billing export, label-based cost allocation, no orphaned resources.
- Efficiency: rightsizing via Recommender, Spot VMs where fault-tolerant, committed use discounts for steady-state load, autoscaling over static headroom.
- Storage lifecycle policies and classes; egress reviewed (inter-region and internet).

### Performance optimization

- Right service and sizing choices (GKE node pools, machine families, Cloud SQL tiers); recent load-test evidence.
- Latency: regions near users, global load balancing, Cloud CDN, caching (Memorystore) where it pays.
- Bottleneck visibility: Cloud Trace, Cloud Profiler, Cloud SQL Insights; database query and index review.
- Scalability: quotas reviewed, stateless horizontally-scalable front-ends.

### Sustainability lens (optional — not a pillar)

Only when the user asks or policy requires: low-carbon region selection where latency allows, idle resource cleanup, and the Cloud Carbon Footprint report.

## Cross-pillar trade-offs

Address at least two per review. Typical conflicts:

- Reliability vs cost: multi-region spend vs budget — resolve from RTO/RPO and SLO math.
- Security vs operational excellence: VPC SC perimeters and CMEK add operational friction — phase in with dry-run perimeters and scoped key rings.
- Performance vs cost: static headroom vs autoscaling — prefer autoscaling plus scheduled load tests.

## Output format

```markdown
# Well-Architected Review: <workload> — <date>
Reviewed by <account> against project <project-id>. Scope: <environments/regions>. Assumptions: <list>.

## Executive summary
<max 5 lines: overall maturity, biggest risk, top 3 moves>

## Pillar scores
| Pillar | Score (1-5) | Justification (one line, evidence-based) |
|---|---|---|
| Operational excellence | | |
| Security, privacy, and compliance | | |
| Reliability | | |
| Cost optimization | | |
| Performance optimization | | |

## Strengths (top 3)
1. <strength — evidence>
2. <strength — evidence>
3. <strength — evidence>

## Top-10 prioritized recommendations
| # | Recommendation | Pillar | Impact | Effort | Suggested owner |
|---|---|---|---|---|---|

## Per-pillar detail
### Operational excellence
Score: N — evidence: <resource IDs, file:line, command output>
Findings and recommendations...
### Security, privacy, and compliance
Score: N — evidence: <...>. Findings above checklist depth handed off to `security-review`: <list with severity>.
### Reliability
### Cost optimization
### Performance optimization
### Cross-pillar trade-offs
<conflicts and chosen resolution>
```

## Guardrails

- Every score cites observed evidence (resource IDs, `file:line`, command output). Never infer maturity from diagrams alone — undocumented claims score as unimplemented.
- Read-only: inspect and report only, per AGENTS.md; never change resources, IAM, or code during a review.
- Security findings get severity and a hand-off reference to `security-review`; do not re-run that audit inline.
- Mark any role, constraint, or product name you cannot verify `(VERIFY)`; never invent plausible names.
- No single averaged score — report per pillar; averages hide the pillar that will cause the incident.
- Cost figures come from observed billing export or Recommender output with the source stated — never from guesswork.
- Do not print secrets, key material, or secret payloads; reference by resource path only (per AGENTS.md).
