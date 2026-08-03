---
name: gcmvsp-review
description: Assess a Google Cloud organization, folder, or project against the Google Cloud Minimum Viable Secure Platform (GCMVSP) checklist — 60 Office-of-the-CISO controls across six domains, tiered Basic/Intermediate/Advanced — and produce a per-control conformance table with a tier-aware gap-closure plan. Use when asked for a "GCMVSP review", "MVSP assessment", "Google Cloud security checklist", "minimum viable secure platform", "are we meeting Google's security baseline", "security baseline gap analysis", or a landing-zone/foundation conformance check.
---

# GCMVSP Review

## When to use

- The user asks to assess an org, folder, or project against the Google Cloud
  **Minimum Viable Secure Platform** — Google Cloud Office of the CISO's
  recommended security checklist (60 controls, six domains, three tiers).
- Typical asks: "are we meeting Google's baseline", "GCMVSP gap analysis",
  "check our landing zone against the security checklist", "what does
  Intermediate tier require that we don't have".
- **Not** for open-ended architecture assessment — that is
  `well-architected-review` (five pillars, maturity scores). GCMVSP is a fixed,
  binary checklist: each control is met, partially met, or not met.
- **Not** for finding novel misconfigurations — that is `security-review`. This
  skill answers "do we conform to a named baseline", nothing else. Run
  `security-review` alongside it; conformance and safety are not the same claim.
- Scope is **platform/foundation**, not workload: org policies, IAM, network
  posture, logging. A conformant platform can still host an insecure app.

## Authoritative sources — read them, do not recall them

The control set is versioned by Google and changes. **You do not have the 60
control texts memorized. Do not write a control ID or title from memory.**

| What | Where |
|---|---|
| Checklist docs (canonical) | <https://docs.cloud.google.com/docs/security/gcmvsp> |
| Terraform implementations | <https://github.com/GoogleCloudPlatform/ociso-solutions/tree/main/gcmvsp> |

Domain pages (append to `https://docs.cloud.google.com/docs/security/gcmvsp/`):

| Domain | Slug |
|---|---|
| Authentication and authorization | `authentication-authorization` |
| Organization resource management | `organization` |
| Infrastructure resource management | `infrastructure` |
| Data protection | `data-protection` |
| Network security | `network-security` |
| Monitoring, logging, and alerting | `monitoring-logging-alerting` |

**Step 0 of every run:** fetch the domain pages in scope and build the control
list from them. If you have no web access, say so plainly, ask the user to paste
the checklist (the docs offer a `gcmvsp_checklist.pdf`), and do not proceed on
recall. A GCMVSP report with invented control IDs is worse than no report — the
customer will cite it back to Google.

**Control IDs** run as a single series, `MVSP-CO-1.<n>`, spanning all six
domains (observed: `MVSP-CO-1.21`–`1.23` in Organization, `MVSP-CO-1.47`–`1.52`
in Network security). Reproduce IDs exactly as printed, including the
occasional inconsistent separator in the source (e.g. `MVSP-CO-1-47`). Mark any
mapping to NIST 800-53 / CRI Profile `(VERIFY)` unless it is on the page you
fetched.

## Tiers

Quote the tier definitions as Google states them:

- **Basic** — "recommended for all organizations that use Google Cloud,
  regardless of size or use case. Basic guidelines are aligned with foundational
  security principles."
- **Intermediate** — "recommended for organizations who are ready to move beyond
  foundational security practices and require additional security controls."
- **Advanced** — "recommended for organizations who require more security
  controls."

Agree the **target tier** with the user before scoring. Scoring a startup
sandbox against Advanced produces a meaningless 40-item gap list. Default: score
Basic + Intermediate, report Advanced as informational.

## Inputs

Ask at most 3 questions if missing; otherwise proceed and state assumptions:

1. Scope and target tier: organization ID / folder / project(s), and Basic,
   Intermediate, or Advanced.
2. Regulatory or customer driver, if any (a named regime changes which Advanced
   controls are non-negotiable — e.g. resource-location and VPC-SC controls).
3. Known accepted exceptions: controls the organization has already decided not
   to implement, and why.

## Workflow

1. **Establish context** per AGENTS.md — `gcloud config get-value account`,
   `gcloud config get-value project`, `gcloud organizations list` — and state the
   identity, scope, target tier, and review date in the report.
2. **Fetch the checklist** (Step 0 above). Build the control table before
   touching the environment, so evidence-gathering is driven by the controls
   rather than by what happens to be easy to query.
3. **Gather evidence, read-only**, via gcloud MCP. Useful starting points —
   choose per control, do not run blindly:
   - Org policy: `gcloud org-policies list --organization=ORG_ID`,
     `gcloud org-policies describe <constraint> --effective --project=PROJECT`
   - IAM: `gcloud organizations get-iam-policy ORG_ID`,
     `gcloud projects get-iam-policy PROJECT`,
     `gcloud iam service-accounts list`
   - Inventory: `gcloud asset search-all-resources`,
     `gcloud asset search-all-iam-policies`
   - Network: `gcloud compute networks list`,
     `gcloud compute firewall-rules list`,
     `gcloud access-context-manager perimeters list`
   - Logging: `gcloud logging sinks list`, `gcloud logging buckets list`
   - Detection: where the SecOps MCP server is connected, confirm that logs
     Google requires you to collect are actually *arriving* — a sink that exists
     but delivers nothing fails the control's intent.
   Every control's verdict cites a command output, resource ID, or `file:line`
   in the IaC. **No evidence → `Not verified`, never `Met`.**
4. **Score each control** with one of: `Met` / `Partially met` / `Not met` /
   `Not verified` / `Not applicable` (with justification). Absence of evidence is
   `Not verified`, not a pass.
5. **Check the IaC path.** For each `Not met` control, look for an existing
   module in the `ociso-solutions/gcmvsp` Terraform repo and reference it by path.
   Hand actual code generation to `terraform-secure-generator`.
6. **Build the gap-closure plan**, ordered by tier first (all Basic gaps before
   any Intermediate), then by blast radius. Note controls that must be applied at
   org level and therefore need an org admin the CE may not have.
7. **Report** using the template below.

## Judgment rules

- **Conformance ≠ security.** State this in the summary whenever the score is
  high. A green checklist with an internet-exposed unauthenticated Cloud Run
  service is a passing GCMVSP score and a Critical finding — say both.
- **Inherited controls count, but say so.** A control met by an org policy
  inherited from a parent folder is `Met` at project scope; record *where* it is
  enforced, because the customer may not control that level.
- **Dry-run/audit-mode policies are `Partially met`**, not `Met`.
- **Exceptions are a first-class outcome.** A documented, risk-accepted, owned,
  time-bounded exception is a legitimate end state. An undocumented gap is not.
- Do not renumber, merge, or "improve" Google's controls. If a control is
  ambiguous for the customer's shape, quote it and state your interpretation.

## Output format

```
# GCMVSP Review — <scope>

Identity: <account> | Scope: <org/folder/project IDs> | Target tier: <Basic|Intermediate|Advanced>
Checklist version fetched: <date> from docs.cloud.google.com/docs/security/gcmvsp
Date: <date>

## Conformance summary

| Domain | Met | Partial | Not met | Not verified | N/A |
|---|---|---|---|---|---|
| Authentication and authorization | | | | | |
| Organization resource management | | | | | |
| Infrastructure resource management | | | | | |
| Data protection | | | | | |
| Network security | | | | | |
| Monitoring, logging, and alerting | | | | | |
| **Total** | | | | | |

Target-tier conformance: <n>/<total> (<pct>%)

## Control detail

| Control ID | Title | Tier | Status | Evidence | Gap / action |
|---|---|---|---|---|---|
| MVSP-CO-1.x | <verbatim title> | Basic | Not met | `<command or resource ID>` | <remediation + ociso-solutions module path if one exists> |

## Gap-closure plan

| # | Control(s) | Action | Scope needed | Effort | Owner |
|---|---|---|---|---|---|

## Accepted exceptions

| Control | Rationale | Risk accepted by | Review date |
|---|---|---|---|

## Beyond the checklist

<Findings that GCMVSP does not cover but that materially affect this
environment. Hand off to `security-review` / `threat-model` by name.>

## Not covered by this review

<Controls not verified and why; workload-level security; anything requiring
access the reviewing identity did not have.>
```

## Guardrails

- Read-only. Never apply an org policy or IAM change to close a gap.
- Never invent a control ID, title, tier, or constraint name. Fetch, or mark
  `(VERIFY)`, or omit.
- Never report a percentage without stating the denominator and the target tier.
- Org-policy changes recommended here can break running workloads
  (`gcp.resourceLocations`, `gcp.restrictServiceUsage`, VPC Service Controls
  especially). Every such recommendation must carry a rollout note: dry-run
  first, scope to a test folder, then enforce.
- State the reviewing account and scope in the report. A GCMVSP score is
  meaningless without knowing what the reviewer could actually see.
