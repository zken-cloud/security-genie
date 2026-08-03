---
name: security-jargon-translator
description: Translates security and compliance jargon into accurate plain language tailored to a chosen audience (executive, software engineer, auditor/regulator, customer business stakeholder). Use when asked to "explain this to a non-technical audience", "make this executive-ready", "translate this finding for the board", "what does this acronym mean for us", or to rewrite security content for a specific reader.
---
# Security Jargon Translator

## When to use
Use when the task is re-expressing existing security or compliance content for a different audience — a finding, design doc, incident summary, or policy excerpt — without losing accuracy. Also use for ad-hoc "what does X mean for us" questions. Do not use it to perform a security review, threat model, or risk assessment; translating content is not judging it.

## Inputs
Ask at most these questions, then proceed with stated assumptions:

1. **Source text** — required. If missing, ask for the passage, finding, or doc to translate. Nothing else can proceed without it.
2. **Audience** — executive, software engineer, auditor/regulator, or customer business stakeholder. If missing, ask once; if the user can't or won't say, assume customer business stakeholder and state that assumption.
3. **Goal** — inform, persuade, or get a decision. Default: inform. A decision goal means the rewrite must end with an explicit ask.

## Workflow
1. Collect source text, audience, and goal (see Inputs). If the passage asserts facts about a live GCP environment (IAM bindings, key configuration, perimeters) and those facts matter to the translation, check them read-only via the gcloud MCP tools when available; otherwise ask the user to run the read-only `gcloud` command; otherwise translate from the artifact as-is and mark those claims unverified.
2. Extract every jargon term, acronym, framework name, and GCP product name — including terms the target audience will trip on even if the source treats them as obvious.
3. Resolve context-dependent terms (see Guardrails). If a term's meaning is genuinely ambiguous in the passage, ask before translating; otherwise record the interpretation you used.
4. Translate each term: plain-language meaning from the glossary below, then a one-line framing for the chosen audience.
5. Rewrite the passage: same facts, same numbers, same severity — recast in the audience's vocabulary and ordered by what they care about (see Audience lenses). If the goal is a decision, end with the explicit ask and what happens if it's deferred.
6. Self-check against the Guardrails: risk not softened, numbers and commitments unchanged, product names exact, no new claims introduced.
7. Deliver in the Output format below.

## Audience lenses
- **Executive** — money, risk, accountability. Lead with business impact and likelihood in plain terms; name who owns the fix; avoid acronyms entirely unless defined on first use.
- **Software engineer** — mechanism, API, blast radius. Lead with how it works concretely: which service, role, config flag, or code path; quantify blast radius in systems and data touched.
- **Auditor/regulator** — control, evidence, scope. Lead with what the control does, where its evidence lives (e.g. Cloud Audit Logs), and the boundary it covers; never claim framework compliance on the control's behalf.
- **Customer business stakeholder** — outcome, assurance, shared responsibility. Lead with what it means for their data and uptime, what Google handles vs what they must do, and what assurance artifacts exist.

## Glossary
Framing labels: E = executive, Eng = engineer, A = auditor, B = business stakeholder.

| Term | Plain-language meaning | Audience framing |
|---|---|---|
| Zero trust | No user, device, or network location is trusted by default; every request is authenticated and authorized. | E: one stolen credential stops being a master key · Eng: per-request authN/Z, e.g. Identity-Aware Proxy · A: access decisions are logged per request · B: a single phished password can't open everything |
| Defense in depth | Multiple independent layers of control so one failure doesn't equal a breach. | E: no single point of failure between attacker and data · Eng: independent controls at edge, identity, network, data · A: the logic behind compensating controls · B: one mistake doesn't sink us |
| Least privilege | Every identity — human or service — gets only the access it needs, nothing more. | E: limits the blast radius of any compromised account · Eng: granular predefined or custom IAM roles, never primitive roles · A: gives access reviews a defensible baseline · B: people and systems touch only what their job needs |
| Attack surface | Every point where an attacker could try to get in or get data out. | E: fewer doors means fewer ways to lose money · Eng: exposed endpoints, APIs, buckets, service accounts · A: defines the assessment scope · B: what of ours is reachable from outside |
| Exploit chain | Several small weaknesses combined into one working attack. | E: "minor" findings can add up to a breach · Eng: e.g. public bucket + over-privileged service account + no VPC SC · A: findings must be assessed in combination · B: cheap fixes prevent the expensive outcome |
| Lateral movement | After the first foothold, moving between systems toward the valuable target. | E: the break-in isn't the breach — what they reach afterward is · Eng: east-west traffic, service account impersonation paths · A: segmentation and detection evidence · B: what keeps a small incident small |
| CVE vs CVSS | CVE is the catalog ID of a specific vulnerability; CVSS is its 0–10 severity score. | E: the score ranks fix order but isn't the whole story · Eng: CVE-2024-XXXX identifies the flaw, CVSS 9.8 scores it · A: remediation SLAs usually key off CVSS bands · B: a name for the flaw, and a grade for how bad it is |
| CMEK | Customer-managed encryption keys: data at rest is encrypted with keys you hold in Cloud KMS; you control rotation, disable, and destruction. | E: we can cut off access to our own data by disabling a key · Eng: configure the resource's CMEK key; every decrypt calls Cloud KMS · A: key custody and usage evidence in Cloud Audit Logs · B: we hold the keys, Google holds only encrypted data |
| VPC Service Controls | A perimeter around GCP-managed services that blocks data from being copied outside it, even with valid credentials. | E: stolen credentials alone can't exfiltrate data · Eng: service perimeter with ingress/egress rules · A: exfiltration control with audit evidence · B: data stays inside the boundary we drew |
| Workload Identity Federation | External workloads exchange their own identity for short-lived Google credentials — no downloadable service account keys. | E: eliminates the most-leaked credential type · Eng: OIDC/SAML token exchange for short-lived credentials, no key JSON · A: no long-lived keys to inventory and rotate · B: no secret keys sitting in CI systems waiting to be stolen |
| Org policy | Organization-, folder-, or project-level guardrails that forbid risky configurations regardless of who has IAM permission, e.g. `constraints/iam.disableServiceAccountKeyCreation`, `constraints/gcp.resourceLocations`. | E: preventive rules nobody can accidentally override · Eng: enforced at the resource-manager level before config is applied · A: machine-checkable scope restriction · B: corporate guardrails applied automatically everywhere |
| RBAC vs IAM roles | RBAC is the general pattern of permissions grouped by job function; GCP IAM implements it with predefined or custom roles bound to principals on resources. | E: access organized by job, reviewable · Eng: a role is a permission set; a binding attaches it to a principal · A: role definitions and bindings are the evidence · B: people get "job kits" of access, not ad-hoc keys |
| mTLS | Mutual TLS: both sides of a connection present certificates, so services prove their identity to each other, not just the server to the client. | E: systems verify each other, blocking impersonation · Eng: workload certificates, e.g. via Certificate Authority Service (VERIFY naming in your org's docs) · A: strong service-to-service authentication evidence · B: even inside our own network, impostors get rejected |
| SBOM | Software bill of materials: a machine-readable inventory of every component and dependency inside a piece of software. | E: we can answer "are we affected?" in hours instead of weeks · Eng: SPDX or CycloneDX artifact produced by the build · A: composition evidence for supplier reviews · B: the ingredient list for our software |
| SLSA | Supply-chain Levels for Software Artifacts: a framework (levels 1–4) for proving software was built from known sources with tamper-resistant provenance. | E: assurance the software we ship wasn't tampered with · Eng: build provenance, e.g. Cloud Build attestations verified by Binary Authorization · A: provenance attestations as evidence · B: proof of where our software came from |
| SOC 2 / ISO 27001 / PCI DSS | SOC 2: an independent auditor's report on security controls over a period; ISO 27001: a certified information security management system; PCI DSS: a mandatory standard if you store, process, or transmit card data. | E: they unlock deals, but they're attestations, not guarantees · Eng: they map onto concrete controls you already operate · A: different evidence models — report vs certificate vs assessor · B: the independent proof points customers ask for |
| Data residency vs sovereignty | Residency is where data is physically stored; sovereignty is which country's laws can compel access to it. | E: storing data in-region doesn't settle legal exposure · Eng: residency is enforceable via `constraints/gcp.resourceLocations` · A: a scope question — location of data vs jurisdiction over it · B: "kept in Europe" and "governed by European law" are different promises |
| Shared responsibility model | The split of security duties between Google and the customer, which shifts with IaaS, PaaS, and SaaS. | E: we can delegate operations, not accountability · Eng: Google secures the platform; you secure identities, config, and data · A: defines which controls you must evidence yourself · B: what Google guarantees vs what we must still do |
| Penetration test vs vulnerability scan | A scan is an automated sweep for known weaknesses — broad, no exploitation. A pentest is humans actively exploiting weaknesses to prove real impact — scoped, point-in-time. | E: scans are hygiene; a pentest answers "could someone actually get in" · Eng: the scanner finds CVEs; the pentester chains them · A: the two produce different, complementary evidence · B: metal detector vs a rehearsal by a professional burglar |
| RTO vs RPO | RTO: how fast service must be restored after a disaster; RPO: how much data loss, measured in time, is tolerable. | E: they're cost dials the business sets, not IT trivia · Eng: they drive backup cadence and failover design · A: continuity tests are measured against them · B: "how long down" and "how much lost" |

## Rewrite examples

### Before/after: executive
**Before (engineer-speak):** "The GKE cluster's workloads run as the default compute service account with project-level `roles/editor`, and Binary Authorization is not enforced, so a compromised CI credential could deploy unsigned images and pivot to the Cloud SQL instance containing PII."

**After (executive):** "One stolen build credential is enough for an attacker to run unauthorized software in our production cluster and reach the database holding customer personal data. Today nothing independently checks what gets deployed, and the cluster's built-in identity has far more access than it needs. The fix is to require that only signed, approved images can run and to cut that identity's access down to its actual job. Until then, a single phishing success becomes a reportable data breach."

### Before/after: engineer
**Before (executive/auditor-speak):** "Consistent with our zero-trust posture, access to customer data must follow least privilege, and we must maintain an auditable chain of custody over the encryption keys protecting it."

**After (engineer):** "Concretely: give each service its own service account with the minimum predefined roles instead of broad project-level bindings, gate any standing data access with IAM Conditions where you can, and move the data's encryption to CMEK in Cloud KMS with rotation enabled. Key use is then recorded in Cloud Audit Logs, which is the custody evidence the auditors will ask for."

## Output format

```markdown
## Translation for {audience} — goal: {inform | persuade | decide}
**Source:** {document/finding name and date}

### Term-by-term
| Term | What it means here | Framing for {audience} |
|---|---|---|
| {term} | {plain meaning in this passage's context} | {one-line audience framing} |

### Rewritten passage
{full rewrite — same facts, numbers, and severity; audience vocabulary; explicit ask if goal is decide}

### Context-dependent terms
- {term}: interpreted as {meaning}; confirm if the source meant something else.

### Unverified items
- {claim or product name}: {why it couldn't be verified — marked VERIFY in the text above}
```

## Guardrails
- Simplify the vocabulary, never the facts. If a plain-language version would mislead someone making a decision, it is wrong — put the precision back in.
- Never soften a real risk to make it palatable. Severity, likelihood, and impact carry over unchanged; "acceptable risk" framing is the audience's call, not yours.
- Flag terms whose meaning depends on context — "control", "tenant", "agent", "segmentation", "key", "endpoint" — and ask before translating if the passage is ambiguous.
- Keep product, role, constraint, and framework names exact: Cloud KMS, VPC Service Controls, `constraints/iam.disableServiceAccountKeyCreation`, ISO/IEC 27001. Mark anything uncertain `(VERIFY)`; never approximate a name.
- Add no new claims, effort estimates, or remediation advice that isn't in the source. Translating is not reviewing.
- Never say a control "meets" or "is compliant with" SOC 2, ISO 27001, or PCI DSS. Say what the control does and where its evidence lives; mapping to framework requirements is the auditor's job.
- Preserve every number, date, dollar figure, and commitment verbatim. If the source hedges ("approximately", "planned"), keep the hedge.
