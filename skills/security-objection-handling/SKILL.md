---
name: security-objection-handling
description: Prepares a customer engineer for customer security objections and tough conversations, producing a conversation prep sheet with responses, product proof points, honest limits, and a next step. Use when a customer pushes back on GCP security — e.g. "public cloud is less secure", "data residency forbids cloud", "the CLOUD Act means no US cloud", "IAM is too complex", "our regulator will not allow it", or ahead of any security Q&A with customer stakeholders.
---

# Security Objection Handling

## When to use

Use when a customer raises a security, compliance, sovereignty, cost, trust, or lock-in objection to adopting or expanding on GCP, or when preparing for a security-focused customer meeting, escalation, or exec Q&A. This skill produces a prep sheet for the conversation — it does not run a security review of an environment (use `security-review` for that).

## Inputs

Ask at most these, then proceed with stated assumptions:

1. The objection, as close to verbatim as possible, and who raised it (role, seniority, security vs. business side).
2. Context: workload or data class at stake, industry, regulator or regulation named, and any prior incident referenced.
3. Stakes and deadline: is this blocking a deal/decision, and when is the conversation?

If the customer already has a GCP footprint and the objection concerns their actual posture, gather evidence before answering — read-only, per the global rules.

## Workflow

1. Capture the objection verbatim and classify it: risk perception / compliance / cost / trust / past incident / lock-in. Classification drives the response angle.
2. Gather evidence. If the objection touches a live environment (e.g. "we will misconfigure IAM" with an existing org), inspect it read-only via the gcloud MCP tools when available; otherwise ask the user to run read-only `gcloud` commands; otherwise work from provided artifacts and state your assumptions explicitly.
3. Identify the root cause using the objection library below — the stated objection is often not the real concern.
4. Build the response: facts and GCP capabilities mapped to the concern, with product names, controls, and documentation the customer can verify.
5. Write the honest limitations: what GCP does not cover, customer-side responsibilities under shared responsibility, real trade-offs (cost, latency, operational burden, exit cost).
6. Propose exactly one concrete next step (workshop, POC, architecture review, documentation deep-dive) with an owner and rough timing.
7. Assemble the prep sheet from the output template. Mark every unverified product name, certification, or claim `(VERIFY)` rather than improvising.

## Conversation framework

1. **Acknowledge the concern.** Repeat it back accurately, without defensiveness or immediate counterattack. The person raising it needs to hear they were understood.
2. **Ask clarifying questions.** Surface the root cause: which regulation, which control, which incident, which prior experience. Most objections compress a specific worry into a general claim.
3. **Respond with facts and GCP capabilities.** Specific products, named controls, published documentation. No adjectives, no "industry-leading".
4. **State honest trade-offs and limits.** Shared responsibility cuts both ways: name what the customer must still configure, operate, and own. Credibility here buys the rest of the conversation.
5. **Propose a concrete next step.** One step, time-bound: a threat-model workshop, a scoped POC, an architecture review, or a doc pack with a follow-up date.

## Objection library

### "Public cloud is less secure than our data center"
- Root cause: perimeter-era mental model; physical control equated with risk control; hyperscaler investment underestimated.
- Response angle: shift from building ownership to control comparison. Ask which specific on-prem control they believe they lose.
- Proof points: Titan hardware root of trust; encryption at rest by default; global DDoS absorption; BeyondCorp-origin zero-trust design; 24/7 SRE operations. Note on-prem environments fail audits too.

### "Data residency rules forbid GCP"
- Root cause: conflates residency with sovereignty; assumption that region pinning is not enforceable.
- Response angle: ask which regulation and which data classes; show residency as an enforceable control, not a promise.
- Proof points: Assured Workloads for residency control sets; org policy `constraints/gcp.resourceLocations` to pin resource creation to regions; in-region CMEK; sovereign cloud partnerships where required (VERIFY per country).

### "The CLOUD Act / government access means we cannot use US cloud"
- Root cause: belief the CLOUD Act reaches only US-cloud-hosted data; it applies to US-headquartered providers regardless of where data sits — including customer datacenters run by US vendors.
- Response angle: reframe from geography to plaintext exposure; control key custody and access transparency.
- Proof points: CMEK, Cloud EKM, Key Access Justifications (VERIFY availability per service/Assured Workloads bundle); Google transparency reports and published practice of challenging overbroad requests; Google's government-access whitepaper (VERIFY current link). Honest limit: no provider can promise zero lawful access.

### "IAM is too complex, we will misconfigure something"
- Root cause: prior exposure to primitive roles and flat IAM; fear of blast radius.
- Response angle: complexity is managed with tooling and guardrails, and misconfiguration risk exists on-prem too — AD misconfiguration is a leading breach vector.
- Proof points: granular predefined roles; IAM Conditions (time-bound, attribute-based); Policy Simulator and Policy Analyzer; role recommendations via Recommender; org policy guardrails such as `constraints/iam.allowedPolicyMemberDomains`; secure-by-default Terraform patterns.

### "We were breached before, cloud adds risk"
- Root cause: recency bias; change equated with risk. Often the original vector — unpatched systems, flat network, weak IAM — is exactly what cloud-native controls address.
- Response angle: ask what the actual root cause was, then map it to controls. Acknowledge that a badly run migration does add risk — hence a landing-zone review first.
- Proof points: provider-patched infrastructure layers; VPC segmentation; Event Threat Detection and Security Command Center findings; Cloud Audit Logs with Admin Activity enabled by default.

### "We must hold our own keys"
- Root cause: genuine compliance requirement, desire for a provider kill switch, or provider distrust.
- Response angle: present the full key-custody spectrum and let them pick the point that matches the requirement — then price the trade-offs honestly.
- Proof points: Google-managed encryption → CMEK in Cloud KMS → Cloud HSM (FIPS 140-2 Level 3) → Cloud EKM with an external key manager under customer control → Key Access Justifications to approve or deny key use (VERIFY service coverage). Trade-offs: EKM adds latency, cost, and an availability dependency; losing the key means losing the data.

### "Logging and SCC cost too much"
- Root cause: everything enabled at full retention, compared against an on-prem baseline that logs far less.
- Response angle: tier the spend instead of cutting visibility; frame cost against incident and audit-preparation cost.
- Proof points: Cloud Logging exclusion filters and per-bucket retention; export to Cloud Storage or BigQuery for cheap long-term retention; SCC tiering — enable higher tiers selectively per org/folder (VERIFY current tier names and pricing).

### "Our regulator will not allow it"
- Root cause: frequently an internal interpretation, not the rule text; occasionally a genuinely prescriptive regime.
- Response angle: ask for the specific regulation and clause; map requirements control-by-control; offer a compliance workshop. Never claim "the regulator approves GCP".
- Proof points: Google Cloud compliance offerings page for current certifications and attestations (ISO/IEC 27001, SOC 1/2/3, PCI DSS, FedRAMP — VERIFY against the live page); regulator outsourcing/cloud guidance that Google publishes mappings for (VERIFY per regulator).

### "GCP will lock us in"
- Root cause: prior proprietary lock-in experience; managed-service convenience conflated with lock-in.
- Response angle: agree lock-in is a spectrum and choose deliberately; architect the exit cost into the design.
- Proof points: open foundations — GKE/Kubernetes, Terraform as IaC, open APIs, standard data formats, documented export paths. Honest gravity: BigQuery, Cloud Spanner, Vertex AI create switching cost; egress charges are real. Keep data portable and decouple where exit matters.

## Tone

- No FUD — about competitors, about on-prem, or in favor of GCP. Fear-based selling destroys credibility with security audiences.
- No overselling. Never say or imply GCP "handles security for you". State customer-side responsibilities explicitly: IAM configuration, data classification, workload patching, key custody choices, detection response.
- Correct the premise, respect the person. Objections are risk signals, not ignorance; the goal is precision, not winning.
- Every proof point needs a source the customer can check. Anything unverified is marked `(VERIFY)`, never improvised.
- Match the register: a CISO wants assurance and accountability mechanics; an engineer wants control details and failure modes.
- If you do not know, say so and commit to a dated follow-up. A credible "I will confirm" beats a confident guess.

## Output format

```markdown
# Conversation Prep: <customer> — <date>

## Objection (verbatim)
> <exact words, who said it, role>

## Classification
<risk perception | compliance | cost | trust | past incident | lock-in> — <one-line root cause>

## Questions to ask them
- <clarifying question 1: regulation / control / incident specifics>
- <clarifying question 2>
- <clarifying question 3>

## Key points and proof points
- <point> — <GCP capability, exact product/control name> (<doc or console reference>)
- <point> — <capability> (VERIFY: <what to confirm>)
- <point>

## Honest limitations
- <what GCP does not cover / customer-side responsibility under shared responsibility>
- <real trade-off: cost, latency, operational burden, exit cost>

## Suggested next step
<workshop | POC | architecture review | doc deep-dive> — <owner, rough timing>

## Follow-up materials
- <doc/page to send, with URL — VERIFY any link not personally confirmed>
- <internal artifact to produce: control mapping, reference architecture, cost estimate>
```

## Guardrails

- Never fabricate certifications, attestations, regulator positions, or case studies. If a proof point is needed but unverified, mark it `(VERIFY)` and point to the Google Cloud compliance offerings page: https://cloud.google.com/security/compliance/offerings.
- Shared responsibility cuts both ways: every prep sheet names the customer-side obligations. Never present GCP as secure-by-default with nothing left to do.
- No disparagement of the customer's on-prem environment, their prior incident, or competitors — and no FUD in either direction.
- Legal topics (CLOUD Act, GDPR, residency, sovereignty): give architectural mitigations and point to Google's published papers; never give legal advice or promise regulatory outcomes.
- When inspecting a live customer environment to ground the conversation, stay read-only per the global rules and state which account and project findings are based on.
- Keep the prep sheet to what the CE can actually defend in the room: verify every product, role, and constraint name before it goes in.
