# Lab 4 — Genie at work (60 min)

## Goal

Run the whole thing end-to-end on a flawed architecture "the customer sent you",
and finish with a **handover pack**: reviewed findings, fixed IaC that has been
proven to deploy, a deployment guide, and architecture documentation.

This is the deliverable a CE actually ships. Labs 1–3 built the tools; this is
the engagement.

## The target

[`../examples/flawed-agent-app/`](../examples/flawed-agent-app/) — an "Acme
support agent": Cloud Run, Cloud SQL, HTTP load balancer, a public bucket, a
bastion host. It contains **27 planted flaws** (7 Critical, 9 High, 9 Medium,
2 Low).

**Never deploy the flawed version.** It is genuinely exploitable — public
bucket, open bastion, SQL-injectable app. You deploy only the fixed Terraform,
and only into a project you created for the purpose.

Do not read [`../examples/flawed-agent-app/EXPECTED-FINDINGS.md`](../examples/flawed-agent-app/EXPECTED-FINDINGS.md)
until step 6. It is the answer key.

## Time budget

| Step | Minutes |
|---|---|
| 1. SAST breadth pass | 5 |
| 2. IAM review | 5 |
| 3. Security review | 10 |
| 4. Threat model | 10 |
| 5. Generate the fix | 10 |
| 6. Score against the answer key | 5 |
| 7. Smoke test | 10 |
| 8. Handover pack | 5 |

Running long is normal. Steps 7 and 8 are the ones people skip and the ones that
carry the deliverable — protect them by cutting depth in 3 and 4 if you must.

---

## Step 1 — SAST breadth pass (5 min)

```
Run a SAST scan over examples/flawed-agent-app and triage the results.
```

Scanners give you breadth in seconds. Then look at what came back and, more
importantly, what did not.

The planted lesson: semgrep catches the `eval` and `shell=True` in the app, but
**misses the SQL injection and the environment-variable password fallback**.
Both are Critical. Both are invisible to pattern matching because they look like
ordinary string handling.

Your triage output must have a **"not covered"** section. If your genie reports
scanner results as a review, that is a finding about your genie.

> Say this to customers: SAST is breadth, not depth. A clean scan is not a clean
> system. This example is a five-second proof.

## Step 2 — IAM review (5 min)

```
Audit the Terraform IAM in examples/flawed-agent-app for least privilege.
```

Expect primitive roles, over-broad service accounts, possibly a service account
key and public members.

Verify two findings yourself against the source. Open the file, check the line.
You are grading your genie's precision, and a false positive in an IAM review is
expensive — it sends a customer's platform team chasing a change that breaks
something for no security gain.

## Step 3 — Security review (10 min)

```
Do a full security review of examples/flawed-agent-app — Terraform, app code
and architecture.
```

Requirements for the output:

- Severity per finding, and severities that are **defensible**. Everything is
  not Critical; if seven things are Critical, ranking has stopped working.
- `file:line` on every finding.
- A **prioritized remediation plan**, not just a list. What does the customer do
  on Monday?

Sanity-check the ordering: a public GCS bucket with customer data outranks a
missing security header, every time. If your genie's ordering does not survive
you reading it aloud, the severity rubric needs work.

## Step 4 — Threat model (10 min)

```
Threat model this architecture with STRIDE, focused on trust boundaries.
```

Boundaries that matter here: internet → load balancer, LB → Cloud Run, Cloud Run
→ Cloud SQL, bastion → VPC, CI/CD → project, and the agent's own tool access.

The point of doing this **after** the review: the review finds what is wrong with
what exists; the threat model finds what is missing entirely. Compare the two
outputs and note anything the threat model surfaced that the review did not.
That delta is the argument for doing both, and it is worth showing a customer.

If your SecOps MCP server is connected, ask what detection coverage would exist
for each attack path. "We would never know" is a finding.

## Step 5 — Generate the fix (10 min)

```
Generate secure replacement Terraform for this architecture, with a security
decision log.
```

Then verify the fix with your own tools — this is the loop that matters:

```
Run the least-privilege review and the SAST scan against the generated
Terraform.
```

Your generator's output must pass your reviewer. If they disagree, one of them
is wrong and you now know which pair to fix. Resolve it before you continue;
shipping two skills that contradict each other is the failure this step exists
to catch.

## Step 6 — Score against the answer key (5 min)

Now open [`../examples/flawed-agent-app/EXPECTED-FINDINGS.md`](../examples/flawed-agent-app/EXPECTED-FINDINGS.md).

| Metric | Target |
|---|---|
| Critical found (of 7) | 7 |
| High found (of 9) | ≥ 7 |
| Overall (of 27) | ≥ 20 |
| False positives | 0 material |

Score **substance, not row matches** — skills and scanners overlap, and one
well-stated finding can cover two rows. Two questions worth more than the score:

- **What did you miss, and why?** Usually a skill's checklist has a gap, or a
  description meant the right skill never loaded.
- **What did you find that is not on the list?** The answer key is not exhaustive.
  Genuine extra findings are the strongest signal your build is good.

## Step 7 — Smoke test the fixed IaC (10 min)

Full procedure: [`../docs/smoke-test-runbook.md`](../docs/smoke-test-runbook.md).

Short version:

1. Create a **disposable** project. Not a customer project. Not a shared demo
   project. Link billing, set a budget alert.
2. Remote state in GCS, versioned. Terraform state holds generated passwords in
   plaintext — a local `terraform.tfstate` in a workshop repo is a leak waiting
   for `git add -A`.
3. `fmt` → `init` → `validate` → SAST → `plan`. Have the genie review
   `tfplan.json` before you apply; module defaults become real resources at plan
   time and that is where a public IP appears.
4. `terraform apply` — **this is guard-blocked, by design.** Consent explicitly
   for the named command in the named project, or run it yourself. Do not
   disable the hook. Watching it fire is part of the lab.
5. **Verify the security properties, not just `Apply complete`.** No `allUsers`
   invoker, no public DB IP, no user-managed SA keys, no primitive roles. The
   runbook has the commands. Save the outputs.
6. **Destroy and delete the project in this session.** Not later. Later does not
   happen.

Expect the first apply to fail — missing APIs, VPC peering ordering, connector
CIDR overlap, org policy on external IPs. **Every failure is handover content.**
The customer will hit the same ones, and a deployment guide that lists the real
error modes is worth more than one that pretends the path is clean.

## Step 8 — Assemble the handover pack (5 min)

Four artifacts. Templates in [`../docs/handover/`](../docs/handover/).

| Artifact | From | The test |
|---|---|---|
| Findings report | Steps 1–4 | Severities defensible, every finding has evidence |
| Fixed IaC | Step 5, proven in step 7 | Passes your own review skill |
| [Deployment guide](../docs/handover/DEPLOYMENT-GUIDE-template.md) | Step 7 | **You executed it.** Real prerequisites, real error modes, real order |
| [Architecture doc](../docs/handover/ARCHITECTURE-template.md) | Steps 4–5, updated as-built | Trust boundaries drawn, residual risks listed |

Plus the security decision log from step 5, **amended with whatever the smoke
test forced you to change**. The delta between what you designed and what
actually deployed is the most useful page in the pack.

Final checks before you would send this to a customer:

- [ ] No secrets, keys, or real project identifiers anywhere in the pack
- [ ] No unfilled `<placeholder>` left in either template
- [ ] Every claim traceable to a command output or `file:line`
- [ ] Residual risks named and owned, not quietly dropped
- [ ] Smoke-test project deleted

---

## Compare

There is no reference handover pack in this repo, deliberately — the pack is
shaped by the engagement, and a model answer would just get copied. Compare
process instead:

| Yours | Reference |
|---|---|
| Review order and skills | [`../docs/facilitator-guide.md`](../docs/facilitator-guide.md), "Running the flawed-architecture exercise" |
| Smoke-test procedure | [`../docs/smoke-test-runbook.md`](../docs/smoke-test-runbook.md) |
| Handover structure | [`../docs/handover/`](../docs/handover/) |

Decisions worth arguing with:

- **SAST runs first**, even though it is the weakest signal. It is fast, it
  frames the "breadth vs depth" lesson, and it stops the deep review from
  spending attention on what a scanner already found.
- **Security review before threat model.** Findings first, then gaps. Reversing
  it produces a threat model full of things you were about to find anyway.
- The runbook **requires deleting the project**, not just `terraform destroy` —
  destroy misses everything created outside Terraform, which in practice is the
  state bucket, a stray API enablement, and a console click.

## Done when

- [ ] ≥ 20 of 27 findings, all 7 Critical, no material false positives
- [ ] Generated Terraform passes your own review skill
- [ ] Fixed IaC applied cleanly in a disposable project
- [ ] Security properties verified with saved command output
- [ ] Project destroyed and deleted
- [ ] Four-artifact handover pack complete, no placeholders

Back to [labs overview](README.md) for the self-assessment.
