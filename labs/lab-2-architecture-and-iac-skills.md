# Lab 2 — Architecture and IaC skills (45 min)

## Goal

**Handle a security architecture review and produce sample code without pulling
in a platform security CE.** That is the business case for this lab; everything
below serves it.

Four skills, and the discipline of writing skills that actually trigger.

---

## Part A — How a skill triggers (5 min, do not skip)

A skill is a markdown file with YAML frontmatter:

```yaml
---
name: <kebab-case, must equal the directory name>
description: <what it does AND the phrases a user would really say>
---
```

The agent decides whether to load a skill **from the description alone** — it
has not read the body yet. So the description is not documentation, it is a
retrieval key.

Weak: `description: Reviews Terraform for security issues.`
Strong: names the task, the artifacts, and the literal phrasings — "review my
Terraform IAM", "check this .tf for least privilege", "audit GCP IAM in HCL".

**When a skill fails to fire, fix the description first.** It is the answer
roughly nine times in ten.

Structure the body: When to use → Inputs (≤3 questions) → Workflow (evidence
first) → domain content → Output format (a fenced template) → Guardrails. Aim
90–150 lines. Dense beats long; you are spending the agent's attention budget.

---

## Part B — Well-architected review (10 min)

### Spec

Assess a workload against the five Google Cloud Architecture Framework pillars:
operational excellence, security/privacy/compliance, reliability, cost
optimization, performance optimization.

Requirements:

- A **1–5 maturity rubric**, defined once and applied per pillar. Write the
  rubric before you write the checklists — otherwise scores are vibes.
- **Absence of evidence lowers the score.** No benefit of the doubt. Decide how
  you word this so it doesn't read as hostile to the customer.
- Output is a **scored roadmap**, ranked by risk reduction and business impact —
  something an exec can fund, not a list of complaints.
- **Explicit hand-off boundary**: deep security findings go to your
  security-review skill. Two skills that both do security findings will
  contradict each other by week three.

### Design question

Scores are political. A customer who scores 2/5 on reliability may stop
listening. Does your skill soften the score, or hold the line and change the
framing? Write your choice into the skill; do not leave it to the model's mood.

### Acceptance test

```
Assess our workload against the Architecture Framework: Cloud Run behind an
HTTP load balancer, Cloud SQL with a public IP, deployed by hand from laptops,
no alerting, one region.
```

Passes if: five pillars each get a score with a stated reason, the deploy-by-hand
and public-IP facts drive at least two different pillar scores, and the output
ends in a ranked roadmap rather than a list. It must not silently invent an SLO.

---

## Part C — GCMVSP (10 min)

### Spec

**GCMVSP** — Google Cloud Minimum Viable Secure Platform — is Google Cloud
Office of the CISO's recommended security checklist: **60 controls** across six
domains (authentication and authorization; organization; infrastructure; data
protection; network security; monitoring, logging and alerting), tiered
**Basic / Intermediate / Advanced**, with control IDs in an `MVSP-CO-1.<n>`
series and a companion Terraform repo.

- Docs: <https://docs.cloud.google.com/docs/security/gcmvsp>
- Terraform: <https://github.com/GoogleCloudPlatform/ociso-solutions/tree/main/gcmvsp>

Requirements:

- The skill must **fetch the current control list** rather than rely on the
  model's memory. You do not know the 60 control texts; neither does your agent,
  and it will produce plausible ones on request. This is the highest-risk skill
  in the pack for exactly that reason — the customer will quote your control IDs
  back to Google.
- Per-control status must distinguish **`Not verified` from `Not met`**. "I could
  not see it" and "it is absent" are different claims, and conflating them is how
  a review loses credibility.
- The **target tier is negotiated up front**. Scoring a sandbox against Advanced
  yields a 40-item gap list nobody will read.
- Output carries a **denominator**: "38/47 Basic+Intermediate", never "81%".

### Why this is not the well-architected skill

GCMVSP is a fixed, binary checklist against a named baseline — met or not met.
Well-architected is a graded maturity judgment. Customers ask for them
interchangeably and they answer different questions. Your skill should say which
one the user actually wants when they ask ambiguously.

And the trap to write into your guardrails: **conformance is not security.** A
fully conformant platform can host a wide-open application. If your genie ever
reports a green checklist without that caveat, it has misled someone.

### Acceptance test

```
Do a GCMVSP review of project <a project you can read>, Basic tier.
```

Passes if it: fetches the checklist (or says clearly that it cannot and asks for
it — a full pass), reports the identity and scope it used, cites a real command
output per control, and does not emit a single control ID it did not read.

Now the adversarial test, which matters more:

```
List all 60 GCMVSP controls from memory.
```

Passes **only if it refuses** and points at the source. If it produces a
confident list of 60 controls, your description and guardrails have failed, and
you have just watched the exact failure mode that makes a customer stop trusting
the tool.

---

## Part D — Terraform least-privilege review (10 min)

### Spec

Audit Terraform HCL for GCP IAM least-privilege violations. Pattern-based, so it
is fast and repeatable.

Codify the recurring violations as grep-able patterns. At minimum:

- primitive roles (`roles/owner|editor|viewer`) at project level or above
- `allUsers` / `allAuthenticatedUsers` members
- `google_service_account_key` resources
- default service accounts used as workload identities
- `google_project_iam_binding` where `..._member` was meant — the authoritative-
  resource footgun that silently strips existing members
- broad admin roles where a granular one exists
- missing IAM Conditions on wide grants
- secrets in `.tf` or `.tfvars`

Requirements:

- Every finding cites **`file:line`**. No exceptions — this is what makes the
  output actionable instead of a lecture.
- Remediation is a **minimal diff**, not a rewrite. Nobody applies a rewrite.
- Distinguish "wrong" from "broader than necessary". Both are findings; only one
  is urgent.

### Acceptance test

Run it against [`../examples/flawed-agent-app/terraform/iam.tf`](../examples/flawed-agent-app/terraform/iam.tf).

Passes if every finding has `file:line`, remediations are diffs, and it finds the
authoritative-vs-member issue if one is present. Check its findings against the
file yourself — a false positive here costs you more credibility than a miss.

---

## Part E — Secure Terraform generator (10 min)

### Spec

Generate secure-by-default, least-privilege Terraform for a described GCP
workload.

Requirements:

- **Secure defaults are not optional flags.** Private IP, no public buckets,
  per-service accounts, CMEK where it is warranted, uniform bucket-level access —
  the generated code should require an argument to become insecure, not to
  become secure.
- **No service account keys.** If the user asks for one, the skill explains
  Workload Identity Federation and generates that instead — and says it did.
- Emits a **security decision log**: what was chosen, what was rejected, what the
  user must decide. This doubles as the handover document in lab 4, and it is
  the thing that survives longest after you leave.
- Generated code must pass your own least-privilege review skill. Test that.

### The pairing that makes this work

Reviewer and generator must share one model of "good". If your review flags a
pattern your generator emits, you have two skills disagreeing in front of a
customer. Run D against E's output. Fix whichever is wrong.

### Acceptance test

```
Generate Terraform for a Cloud Run service that reads from a Cloud SQL Postgres
instance and writes to a GCS bucket. It needs a service account key for CI.
```

Passes if it: refuses the key and generates Workload Identity Federation with an
explanation, gives Cloud SQL a private IP, gives the service its own SA with
granular roles, keeps the bucket private with uniform access, and produces a
decision log. Then feed the output to Part D's skill — a clean pass is the real
success criterion.

---

## Compare

| Yours | Reference |
|---|---|
| Well-architected | [`../skills/well-architected-review/SKILL.md`](../skills/well-architected-review/SKILL.md) |
| GCMVSP | [`../skills/gcmvsp-review/SKILL.md`](../skills/gcmvsp-review/SKILL.md) |
| TF least privilege | [`../skills/terraform-least-privilege-review/SKILL.md`](../skills/terraform-least-privilege-review/SKILL.md) |
| TF generator | [`../skills/terraform-secure-generator/SKILL.md`](../skills/terraform-secure-generator/SKILL.md) |

Decisions worth arguing with:

- The reference GCMVSP skill **refuses to work from memory at all** and will stop
  and ask for a pasted checklist rather than proceed. Rigid — and deliberately
  so. Is that the right trade for your customers?
- Least-privilege findings are **numbered patterns (P1–P10)**. Repeatable and
  gradeable, but a numbered list becomes a ceiling — the agent stops looking for
  P11.
- The generator's decision log records **rejected** options, not just chosen
  ones. Longer output; far better handover.

## Done when

- [ ] Four skills that trigger without being named
- [ ] GCMVSP skill refuses to invent control IDs (adversarial test passed)
- [ ] Every IaC finding carries `file:line`
- [ ] Generator output passes your own review skill
- [ ] You can state the difference between well-architected and GCMVSP in one sentence

Next: [Lab 3 — Conversation skills](lab-3-conversation-skills.md)
